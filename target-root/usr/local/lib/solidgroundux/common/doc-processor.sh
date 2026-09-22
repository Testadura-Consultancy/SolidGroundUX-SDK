# ==================================================================================
# SolidGroundUX SDK - Document processor
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626501
#   Checksum    : 460b41e36c9256efaf2c245e6940ea6af9149f484a5ede9f0693a298af27783a
#   Source      : doc-processor.sh
#   Type        : library
#   Group       : SDK
#   Subgroup    : Documentation Generator
#   Purpose     : Parse source files for structured comments and assemble normalized
#                 documentation data
#
# Description:
#   Provides the core parsing engine for the SolidGroundUX documentation system.
#
#   The processor:
#     - Iterates source files line-by-line
#     - Interprets structured comment conventions (headers, metadata, sections, items)
#     - Maintains parsing state (header, section hierarchy, current item, etc.)
#     - Normalizes detected elements into a flat render stream (DOC_CONTENT_LINES)
#
#   Parsing is convention-based and deterministic. Each recognized line contributes
#   either state transitions or a normalized documentation record.
#
# Design principles:
#   - Single-pass parsing (no backtracking or multi-phase analysis)
#   - Separation of concerns:
#       * Detection/state mutation
#       * Content normalization
#       * Rendering (handled elsewhere)
#   - Convention over configuration (strict comment grammar)
#   - Minimal side effects outside controlled doc_* and mod_* variables
#   - Transparent state transitions for debuggability
#
# Role in framework:
#   - Core documentation data collector
#   - Produces the canonical DOC_CONTENT_LINES dataset consumed by renderers
#   - Bridges raw source code and higher-level documentation output (HTML, etc.)
#   - Shared parsing engine for all documentation-related tooling
#
# Non-goals:
#   - Rendering output formats (HTML, Markdown, PDF, etc.)
#   - Parsing arbitrary or free-form comments
#   - Semantic analysis of code (only structured comment interpretation)
#   - Cross-file linking or indexing logic
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# ==================================================================================
set -uo pipefail
# - Library guard ------------------------------------------------------------------
    # fn$ _sgnd_lib_guard - Enforce source-only, single-load library initialization
        # . Purpose
        #   Ensure the file is sourced as a library and initialized only once.
        #
        # . Behavior
        #   - Derives a unique guard variable name from the current filename.
        #   - Aborts execution when the file is run directly instead of sourced.
        #   - Sets the guard variable on first load.
        #   - Returns immediately when the library was already loaded.
        #
        # Inputs
        #   BASH_SOURCE[0]
        #   $0
        #
        # Outputs (globals)
        #   SGND_<MODULE>_LOADED
        #
        # . Returns
        #   0 when already loaded or successfully initialized.
        #   Exits with code 2 when executed instead of sourced.
        #
        # . Usage
        #   _sgnd_lib_guard
    _sgnd_lib_guard() {
        local lib_base=""
        local guard=""

        lib_base="$(basename "${BASH_SOURCE[0]}" .sh)"
        lib_base="${lib_base//-/_}"
        guard="SGND_${lib_base^^}_LOADED"

        [[ "${BASH_SOURCE[0]}" != "$0" ]] || {
            printf 'This is a library; source it, do not execute it: %s\n' "${BASH_SOURCE[0]}" >&2
            exit 2
        }

        [[ -n "${!guard-}" ]] && return 0
        printf -v "$guard" '1'
    }

    _sgnd_lib_guard
    unset -f _sgnd_lib_guard

    if declare -F sgnd_module_init_metadata >/dev/null 2>&1 \
        && declare -F sgnd_header_buffer_load >/dev/null 2>&1; then
        sgnd_module_init_metadata "${BASH_SOURCE[0]}"
    fi
# - Local definitions
    # var: Datamodel - Content tables for parsed documentation data
        # . Purpose
        #   Define the parser-owned documentation tables.
        #
        # . Behavior
        #   - Stores collected module metadata, attribution, sections, documented items,
        #     and normalized content lines.
        #   - Keeps parsing output independent from rendering output.
        #   - Uses schema strings as explicit table contracts for sgnd-datatable helpers.
        #
        # Tables:
        #   MOD_TABLE
        #     One row per parsed source module.
        #     Holds module identity, title, type, purpose, version, build, group, subgroup, and product.
        #
        #   MOD_ATTRIBUTION
        #     One row per parsed source module.
        #     Holds developer, company, client, copyright, and license information.
        #
        #   MOD_GLOBALS
        #     One row per detected framework or script global declaration.
        #     Holds module, scope, audience, variable name, description, and extra metadata.
        #
        #   MOD_SECTIONS
        #     One row per detected documentation section.
        #     Holds module, section, parent, grandparent, display title, and hierarchy level.
        #
        #   MOD_ITEMS
        #     One row per detected documented item.
        #     Holds module, section context, item type (including fn/cls/var/doc), visibility, role, name, and title.
        #
        #   DOC_CONTENT_LINES
        #     One row per normalized emitted documentation line.
        #     Holds source position, section context, style-hint context, item context,
        #     content type, content text, and canonical content reference.
        #
        # Notes:
        #   - These tables are collection/output contracts, not class definitions.
        #   - Rendering code should consume these tables instead of reparsing source files.
        MOD_TABLE_SCHEMA="file|name|title|type|purpose|version|build|checksum|group|subgroup|product"
        MOD_TABLE=()

        MOD_ATTRIBUTION_SCHEMA="modulename|developers|company|client|copyright|license"
        MOD_ATTRIBUTION=()

        MOD_GLOBALS_SCHEMA="modulename|scope|audience|name|description|extra|currentvalue"
        MOD_GLOBALS=()

        MOD_SECTIONS_SCHEMA="modulename|section|parent|grandparent|title|level"
        MOD_SECTIONS=()

        MOD_ITEMS_SCHEMA="modulename|section|parentsection|typecode|type|itemvisibility|itemrole|name|title"
        MOD_ITEMS=()
        
        DOC_CONTENT_LINES_SCHEMA="file|source_linenr|doc_linenr|section|parentsection|grandparentsection|stylehint|item|title|contenttype|content|contentref"
        DOC_CONTENT_LINES=()

        SGND_DOC_STYLEHINTS=(
            "normal"
            "label"
            "emphasis"
            "highlight"
            "underline"
            "quote"
            "listitem"
            "indent"
        )

    # fn: _init_localvars - Initialize parser state variables
        # . Purpose
        #   Reset source, module, item, section, and emission state before parsing a file.
        #
        # . Behavior
        #   - Clears source-line tracking values.
        #   - Clears module metadata values populated from the file header.
        #   - Resets current section, parent section, item, and style-hint context.
        #   - Resets documentation line counters and emission flags.
        #
        # Outputs (globals):
        #   src_line, src_linenr, src_linetype, src_haltlineprocessing
        #   doc_globalblock, doc_globalscope
        #   mod_product, mod_title, mod_name
        #   doc_section, doc_sectionlevel, doc_parentsection, doc_grandparentsection
        #   doc_item, doc_itemtitle, doc_itemtype, doc_itemmarker
        #   doc_itemvisibility, doc_itemrole
        #   doc_headersection, doc_stylehint, doc_linenr, doc_contenttype
        #   doc_content, doc_inheader, doc_started, doc_titleextracted, doc_emitline
        #
        # . Returns
        #   0 on successful initialization.
        #
        # . Usage
        #   _init_localvars
    _init_localvars(){
        src_line=""
        src_linenr=0
        src_linetype=""
        src_haltlineprocessing=0

        doc_globalblock=0
        doc_globalscope=""

        mod_product=""
        mod_title=""
        mod_name=""
        mod_group=""
        mod_subgroup=""
        
        doc_section=""
        doc_sectionlevel=0
        doc_parentsection=""
        doc_sectiontitle=""
        doc_grandparentsection=""

        doc_item=""
        doc_itemtitle=""
        doc_itemtype=""
        doc_itemmarker=""
        doc_itemvisibility=""
        doc_itemrole=""

        doc_headersection=""
        doc_stylehint="normal"
        doc_linenr=0
        doc_contenttype="" 
        doc_content=""


        doc_inheader=0
        doc_started=0
        doc_titleextracted=0
        doc_emitline=0


    }

    # -- Parser expressions ------------------------------------------------------------
        # Defines the regular expressions used by the source parser.
        #
        # Expressions:
        #   _rgx_header
        #     Matches header boundary lines, for example:
        #       # ==================================================================================
        #
        #   _rgx_moduletitle
        #     Matches the module title line and captures:
        #       1. Product name
        #       2. Module title
        #
        #     Example:
        #       # SolidGroundUX - Library Template
        #
        #   _rgx_headersectionheader
        #     Matches comment section headers and captures the section name.
        #
        #     Example:
        #       # Metadata:
        #       # Attribution:
        #
        #   _rgx_headerfield
        #     Matches metadata/attribution fields and captures:
        #       1. Field name
        #       2. Field value
        #
        #     Example:
        #       #   Version     : 1.1
        #
        #   _rgx_section
        #     Matches documentation section markers and captures:
        #       1. Section marker depth (-, --, ---)
        #       2. Section title
        #
        #     Example:
        #       # - Chapter ----------------------------------------------------------------
        #       # -- Paragraph -------------------------------------------------------------
        #       # --- Subparagraph ---------------------------------------------------------
    _rgx_header='^# =+[[:space:]]*$'
    _rgx_moduletitle='^#[[:space:]]+([^-]+)[[:space:]]+-[[:space:]]+(.+)[[:space:]]*$'
    _rgx_headersectionheader='^[[:space:]]*#[[:space:]]+([^:]+):[[:space:]]*$'
    _rgx_headerfield='^#[[:space:]]+([[:alnum:]_]+)[[:space:]]*:[[:space:]]*(.*)[[:space:]]*$'
    _rgx_section='^[[:space:]]*#[[:space:]](-{1,3})[[:space:]]+(.+)[[:space:]]*-*[[:space:]]*$'
    _rgx_docitem='^[[:space:]]*#[[:space:]]+([a-z]{2,3})([:$])[[:space:]]+([^[:space:]]+)([[:space:]]+-[[:space:]]+(.+))?[[:space:]]*$'
    _rgx_commentseparator='^[[:space:]]*#[[:space:]]+-{3,}[[:space:]]*$'
    _rgx_globalarray_start='^[[:space:]]*(SGND_FRAMEWORK_GLOBALS|SGND_RUNTIME_GLOBALS|SGND_SCRIPT_GLOBALS)[[:space:]]*=\([[:space:]]*$'
    _rgx_globalarray_entry='^[[:space:]]*["'"'"']([^"'"'"']*)["'"'"'][[:space:]]*(#.*)?$'

    # -- Semantic registries ----------------------------------------------------------
        # fn: _sgnd_doc_list_contains - Test whether a value exists in a named array
            # . Purpose
            #   Provide a small membership helper for semantic registries.
            #
            # . Behavior
            #   - Uses a nameref to inspect the array named by the first argument.
            #   - Compares each array element with the requested value.
            #   - Returns success on the first exact match.
            #
            # . Arguments
            #   $1  Name of the array to inspect.
            #   $2  Value to find.
            #
            # . Returns
            #   0 when the value exists in the named array.
            #   1 when the array name/value is missing or no match is found.
            #
            # . Usage
            #   _sgnd_doc_list_contains SGND_DOC_STYLEHINTS "normal"
        _sgnd_doc_list_contains() {
            local array_name="${1:-}"
            local value="${2:-}"
            local item=""

            [[ -z "$array_name" || -z "$value" ]] && return 1

            local -n list_ref="$array_name"
            for item in "${list_ref[@]}"; do
                [[ "$item" == "$value" ]] && return 0
            done

            return 1
        }

        # fn: _sgnd_doc_is_valid_stylehint - Validate documentation style hint
            # . Purpose
            #   Check whether a style hint is part of the supported documentation style registry.
            #
            # . Behavior
            #   - Delegates membership testing to _sgnd_doc_list_contains.
            #   - Does not mutate parser state.
            #
            # . Arguments
            #   $1  Style hint to validate.
            #
            # . Returns
            #   0 when the style hint is valid.
            #   1 when the style hint is unknown or missing.
            #
            # . Usage
            #   _sgnd_doc_is_valid_stylehint "tip" && printf 'Valid style hint\n'
        _sgnd_doc_is_valid_stylehint() {
            _sgnd_doc_list_contains SGND_DOC_STYLEHINTS "${1:-}"
        }


    # -- Detectors -------------------------------------------------------------------
        # fn: _detect_noncommentline - Detect non-comment source lines
            # . Purpose
            #   Stop documentation parsing for source lines that are not structured comments.
            #
            # . Behavior
            #   - Ignores the line when another detector already handled it.
            #   - Returns without action for comment lines.
            #   - Clears the current source/content type for executable or ordinary source lines.
            #   - Prevents later detectors from processing the same line.
            #
            # Inputs (globals):
            #   src_line, src_haltlineprocessing
            #
            # Outputs (globals):
            #   src_linetype, doc_contenttype, doc_headersection, doc_emitline, src_haltlineprocessing
            #
            # . Returns
            #   0 always.
            #
            # . Usage
            #   _detect_noncommentline
        _detect_noncommentline() {
            (( src_haltlineprocessing )) && return 0

            [[ "$src_line" =~ ^[[:space:]]*# ]] && return 0

            # doc: Some extra documentation
                # line 1
                # line 2
            src_linetype=""
            doc_contenttype=""
            doc_headersection=""
        doc_stylehint="normal"
            doc_emitline=0
            src_haltlineprocessing=1

            saydebug "Non-comment line detected; source/content type reset"
        }

        # fn: _detect_headermarker - Detect module header boundary lines
            # . Purpose
            #   Detect the opening and closing marker of the file-level documentation header.
            #
            # . Behavior
            #   - Matches header separator lines using _rgx_header.
            #   - Marks the parser as started on the first header marker.
            #   - Ends header mode and emits module metadata on the closing header marker.
            #   - Prevents later detectors from processing the same line.
            #
            # Inputs (globals):
            #   src_line, src_haltlineprocessing, doc_started
            #
            # Outputs (globals):
            #   src_linetype, doc_inheader, doc_started, doc_emitline, doc_headersection, src_haltlineprocessing
            #
            # . Returns
            #   0 always.
            #
            # . Usage
            #   _detect_headermarker
        _detect_headermarker() {
            (( src_haltlineprocessing )) && return 0

            saydebug "Detecting header marker"
            [[ "$src_line" =~ $_rgx_header ]] || return 0

            if (( ! doc_started )); then
                src_linetype="moduleheader"
                doc_inheader=1
                doc_started=1
                doc_emitline=0
            else
                src_linetype=""
                doc_inheader=0
                doc_headersection=""
        doc_stylehint="normal"
                _action_headerend
            fi

            src_haltlineprocessing=1

            saydebug "Header marker detected"
        }

        # fn: _detect_moduletitle - Detect the module title line
            # . Purpose
            #   Extract product and title information from the first title line in the file header.
            #
            # . Behavior
            #   - Runs only while inside the module header and before a title was extracted.
            #   - Matches the title line using _rgx_moduletitle.
            #   - Stores product and module title metadata.
            #   - Emits a module-header content line.
            #
            # Inputs (globals):
            #   src_line, doc_inheader, doc_titleextracted
            #
            # Outputs (globals):
            #   mod_product, mod_title, doc_contenttype, doc_content, doc_emitline, doc_titleextracted, src_haltlineprocessing
            #
            # . Returns
            #   0 always.
            #
            # . Usage
            #   _detect_moduletitle
        _detect_moduletitle() {
            (( doc_inheader == 1 && doc_titleextracted == 0 )) || return 0

            saydebug "Detecting module title"

            [[ "$src_line" =~ $_rgx_moduletitle ]] || return 0

            mod_product="${BASH_REMATCH[1]}"
            mod_title="${BASH_REMATCH[2]}"

            doc_contenttype="moduleheader"
            doc_stylehint="normal"
            doc_content="$mod_product - $mod_title"
            doc_emitline=1

            doc_titleextracted=1
            src_haltlineprocessing=1

            saydebug "Module title detected: Product $mod_product, Title $mod_title"
        }

        # fn: _detect_headerfields - Detect metadata and attribution fields
            # . Purpose
            #   Extract named header fields and map them to mod_* variables.
            #
            # . Behavior
            #   - Runs only while inside the file header.
            #   - Accepts fields only under Metadata or Attribution header sections.
            #   - Normalizes field names to lowercase shell variable names.
            #   - Assigns values dynamically to mod_<field> variables.
            #
            # Inputs (globals):
            #   src_line, doc_inheader, doc_headersection, src_haltlineprocessing
            #
            # Outputs (globals):
            #   mod_* variables derived from header field names, src_haltlineprocessing
            #
            # . Returns
            #   0 always.
            #
            # . Usage
            #   _detect_headerfields
        _detect_headerfields() {       
            (( src_haltlineprocessing )) && return 0

            saydebug "Detecting header fields"

            # Only applies inside the header.
            (( doc_inheader )) || return 0

            # Only applies to Metadata and Attribution sections.
            [[ "$doc_headersection" == "Metadata" || "$doc_headersection" == "Attribution" ]] || return 0

            [[ "$src_line" =~ $_rgx_headerfield ]] || return 0

            local field_name
            local field_value
            local var_name

            field_name="${BASH_REMATCH[1]}"
            field_value="${BASH_REMATCH[2]}"

            # Normalize field name for variable use.
            field_name="${field_name,,}"
            field_name="${field_name//-/_}"

            var_name="mod_${field_name}"

            printf -v "$var_name" '%s' "$field_value"
            src_haltlineprocessing=1

            saydebug "Header field detected: $var_name=$field_value"
        }

        # fn: _detect_section - Detect documentation section headers
            # . Purpose
            #   Detect structured level 1, 2, and 3 documentation section headers.
            #
            # . Behavior
            #   - Matches section marker lines using _rgx_section.
            #   - Determines section level from marker depth.
            #   - Maintains current section, parent section, and grandparent section context.
            #   - Emits a section record and prepares a section-header content line.
            #
            # Inputs (globals):
            #   src_line, src_haltlineprocessing, doc_sectionlevel, doc_section, doc_parentsection, doc_grandparentsection
            #
            # Outputs (globals):
            #   src_linetype, doc_headersection, doc_section, doc_parentsection, doc_grandparentsection
            #   doc_sectionlevel, doc_content, doc_contenttype, doc_emitline, src_haltlineprocessing
            #
            # . Returns
            #   0 always.
            #
            # . Usage
            #   _detect_section
        _detect_section() {       
            (( src_haltlineprocessing )) && return 0

            saydebug "Detecting sections"

            [[ "$src_line" =~ $_rgx_section ]] || return 0

            local marker
            local section_name

            marker="${BASH_REMATCH[1]}"
            section_name="${BASH_REMATCH[2]}"
            section_name="$(sed -E 's/[[:space:]-]+$//' <<< "$section_name")"

            local section_title=""

            if [[ "$section_name" == *":"* ]]; then
                section_title="${section_name#*:}"
                section_name="${section_name%%:*}"

                section_name="${section_name%"${section_name##*[![:space:]]}"}"
                section_title="${section_title#"${section_title%%[![:space:]]*}"}"
            else
                section_title="$section_name"
            fi

            src_linetype="sectionheader"
            doc_headersection=""
            doc_stylehint="normal"
            doc_sectiontitle="$section_title"
   
            # New section owns its own body; do not inherit previous item context.
            doc_item=""
            doc_itemtitle=""
            doc_itemtype=""
            doc_itemmarker=""
            doc_itemvisibility=""
            doc_itemrole=""
            
            local foundlevel="${#marker}"

            case "$foundlevel" in
                1)  
                    doc_section="$section_name"              
                    doc_parentsection=""
                    doc_grandparentsection=""

                    doc_content="$section_name"
                    doc_contenttype="L1Sectionheader"
                    doc_stylehint="normal"
                    doc_emitline=1
                    ;;

                2)
                    if [[ "$doc_sectionlevel" == 3 ]]; then
                        doc_parentsection="$doc_grandparentsection"
                        doc_grandparentsection=""
                    elif [[ "$doc_sectionlevel" == 1 ]]; then
                        doc_parentsection="$doc_section"
                    fi
                    doc_section="$section_name"
                    doc_content="$section_name"
                    doc_contenttype="L2Sectionheader"
                    doc_stylehint="normal"
                    doc_emitline=1   
                    ;;

                3)
                    if [[ "$doc_sectionlevel" == 2 ]]; then
                        doc_grandparentsection="$doc_parentsection"
                        doc_parentsection="$doc_section"
                        doc_section="$section_name"
                    fi
                    doc_contenttype="L3Sectionheader"
                    doc_stylehint="normal"
                    doc_content="$section_name"
                    doc_section="$section_name"
                    doc_emitline=1
                    ;;
            esac
                    
            doc_sectionlevel="$foundlevel"

            _emit_sectionrecord

            src_haltlineprocessing=1        

            saydebug "Section detected: level $doc_sectionlevel, section $doc_section, parentsection $doc_parentsection, grandparent $doc_grandparentsection"
        }

        # fn: _detect_items - Detect documented items
            # . Purpose
            #   Detect structured item markers such as functions, classes, variables, and general documentation blocks.
            #
            # . Behavior
            #   - Matches item declaration lines using _rgx_docitem.
            #   - Extracts item type, marker, name, and optional title.
            #   - Marks template items when the item marker is '$'.
            #   - Derives access level from a leading underscore in the item name.
            #   - Emits an item record and prepares an item-header content line.
            #
            # Inputs (globals):
            #   src_line, src_haltlineprocessing
            #
            # Outputs (globals):
            #   doc_item, src_linetype, doc_contenttype, doc_itemtype, doc_content
            #   doc_itemvisibility, doc_itemrole, doc_itemmarker, doc_itemtitle
            #   doc_emitline, src_haltlineprocessing
            #
            # . Returns
            #   0 always.
            #
            # . Usage
            #   _detect_items
        _detect_items(){
            (( src_haltlineprocessing )) && return 0

            saydebug "Detecting items"
            if [[ "$src_line" =~ $_rgx_docitem ]]; then
                local item_type="${BASH_REMATCH[1]}"      # fn, cls, var, doc
                local item_marker="${BASH_REMATCH[2]}"    # : or $
                local item_name="${BASH_REMATCH[3]}"
                local item_title="${BASH_REMATCH[5]}"

                if [[ "$item_marker" == '$' ]]; then
                    doc_itemrole="template"
                else
                    doc_itemrole="normal"
                fi

                
                if [[ "$item_name" == _* ]]; then
                    doc_itemvisibility="internal"
                else
                    doc_itemvisibility="public"
                fi
                
                saydebug "Item detected $item_type. $item_marker, $item_name, $item_title"
                
                doc_item="$item_name"
                src_linetype="$item_type"

                case "$item_type" in
                    fn)
                        doc_contenttype="functionheader"
                        doc_itemtype="function"
                        ;;
                    cls)
                        doc_contenttype="classheader"
                        doc_itemtype="class"
                        ;;
                    var)
                        doc_contenttype="variableheader"
                        doc_itemtype="variable"
                        ;;
                    doc)
                        doc_contenttype="gendocheader"
                        doc_itemtype="general documentation"
                        ;;
                    *)
                        doc_contenttype="itemheader"
                        doc_itemtype="unknown"
                        ;;
                esac
                doc_stylehint="normal"
                doc_content="$item_name"
                [[ -n "$item_title" ]] && doc_content+=" - $item_title"

                doc_item="$item_name"
                doc_itemmarker="$item_type$item_marker"
                doc_itemtitle="$item_title"

                _emit_itemrecord

                doc_emitline=1
                src_haltlineprocessing=1
            fi
        }

        # fn: _detect_headersectionheader - Detect named header sections
            # . Purpose
            #   Detect named sections inside the module header, such as Metadata and
            #   Attribution, without emitting render content.
            #
            # . Behavior
            #   - Runs only while inside the file header.
            #   - Matches lines such as '# Metadata:' and '# Attribution:'.
            #   - Stores the active header section for field extraction.
            #
            # Inputs (globals):
            #   src_line, src_haltlineprocessing, doc_inheader
            #
            # Outputs (globals):
            #   doc_headersection, src_linetype, src_haltlineprocessing
            #
            # . Returns
            #   0 always.
            #
            # . Usage
            #   _detect_headersectionheader
        _detect_headersectionheader() {
            (( src_haltlineprocessing )) && return 0
            (( doc_inheader )) || return 0

            saydebug "Detecting header section"
            [[ "$src_line" =~ $_rgx_headersectionheader ]] || return 0

            doc_headersection="${BASH_REMATCH[1]}"
            src_linetype="headersection"

            # Metadata and Attribution are control sections used for field extraction.
            # Other header sections are rendered as module body labels, allowing the
            # module header to contribute visible body content without reintroducing
            # documentation-paragraph state.
            if [[ "$doc_headersection" == "Metadata" || "$doc_headersection" == "Attribution" ]]; then
                # Metadata and attribution are captured in MOD_TABLE/MOD_ATTRIBUTION.
                # They are intentionally not emitted as module body content.
                doc_contenttype=""
                doc_content=""
                doc_emitline=0
            else
                doc_contenttype="modulebody"
                doc_stylehint="label"
                doc_content="$doc_headersection"
                doc_emitline=1
            fi

            src_haltlineprocessing=1

            saydebug "Header section detected: $doc_headersection"
        }
        # fn: _detect_default - Detect default
            # . Purpose
            #   Internal helper for detect default.
            #
            # . Behavior
            #   - Supports the module implementation; not intended as a public framework API.
            #   - Extracts the optional leading documentation style hint from normal content.
            #   - Leaves the remaining content intact, including :: table separators and the renderer-owned <> alignment token.
            #   - This keeps table syntax renderer-owned: `. Table` starts a table, the first row may
            #     use `!` as its style hint, and a blank documentation line ends the table.
            #   - Uses framework UI/output conventions for terminal or dialog interaction.
            #
            # . Arguments
            #   $1  ARG1 - Positional value used by this function.
            #   $2  ARG2 - Positional value used by this function.
            #   $3  ARG3 - Positional value used by this function.
            #   $4  ARG4 - Positional value used by this function.
            #   $5  ARG5 - Positional value used by this function.
            #   $6  ARG6 - Positional value used by this function.
            #
            # . Side effects
            #   May read, write, create, update, or remove files/directories required by the workflow.
            #
            # . Returns
            #   0 on success unless the called command returns a different status.
            #
            # . Usage
            #   _detect_default "string" "" "" "" "SolidGroundUX"
        _detect_default(){
            (( src_haltlineprocessing )) && return 0

            if (( doc_inheader )) && [[ "$doc_headersection" == "Metadata" || "$doc_headersection" == "Attribution" ]]; then
                doc_emitline=0
                return 0
            fi

            [[ -z "$doc_contenttype" ]] && return 0

            # Remove only indentation before the comment marker and the marker itself.
            # Preserve the author's layout after "# " so diagrams, workflows, trees,
            # and aligned examples render as written.
            doc_content="${src_line#"${src_line%%[![:space:]]*}"}"
            doc_content="${doc_content#\#}"
            doc_content="${doc_content# }"

            doc_stylehint="normal"

            # Style hints are presentation hints layered on top of the structural
            # content type. They must be the first token after "# ". Do not strip
            # leading whitespace before checking for hints; indented content is
            # author layout and must be preserved.
            case "$doc_content" in
                '> '*)
                    doc_content="${doc_content#> }"
                    ;;
                '>')
                    doc_content=""
                    ;;
                ': '*)
                    doc_stylehint="label"
                    doc_content="${doc_content#: }"
                    ;;
                '. '*)
                    doc_stylehint="highlight"
                    doc_content="${doc_content#. }"
                    ;;
                '! '*)
                    doc_stylehint="emphasis"
                    doc_content="${doc_content#! }"
                    ;;
                '_ '*)
                    doc_stylehint="underline"
                    doc_content="${doc_content#_ }"
                    ;;
                '~ '*)
                    doc_stylehint="quote"
                    doc_content="${doc_content#~ }"
                    ;;
                '- '*)
                    doc_stylehint="listitem"
                    doc_content="${doc_content#- }"
                    ;;
            esac

            doc_emitline=1

        }
        # fn: _get_section_comments - Get section comments
            # . Purpose
            #   Internal helper for get section comments.
            #
            # . Behavior
            #   - Supports the module implementation; not intended as a public framework API.
            #   - Reads or updates SolidGroundUX runtime, metadata, configuration, or UI globals as needed.
            #   - Uses SolidGroundUX datatable rows and schemas for structured state.
            #   - Uses framework UI/output conventions for terminal or dialog interaction.
            #
            # . Arguments
            #   $1  MODULE_NAME - Variable, field, or item name.
            #   $2  GRANDPARENT_SECTION - Header section name.
            #   $3  PARENT_SECTION - Header section name.
            #   $4  SECTION_NAME - Variable, field, or item name.
            #   $5  ITEM_NAME - Variable, field, or item name.
            #   $6  CURRENTVALUE - Value to read, validate, render, or store.
            #
            # . Output
            #   Writes computed or formatted text to stdout/stderr as appropriate for the function.
            #
            # . Returns
            #   0 on success.
            #   Non-zero when validation, resolution, user cancellation, or execution fails.
            #
            # . Usage
            #   _get_section_comments
        _get_section_comments() {
            (( src_haltlineprocessing )) && return 0

            [[ "$src_linetype" == "sectioncomment" ]] || return 0

            doc_contenttype="sectionbody"
            doc_stylehint="normal"
            doc_content="$src_line"

            # Strip only leading indentation before the comment marker and the marker
            # itself. Preserve the author's layout after "# ".
            doc_content="${doc_content#"${doc_content%%[![:space:]]*}"}"
            doc_content="${doc_content#\#}"
            doc_content="${doc_content# }"

            doc_emitline=1

            saydebug "Section comment detected: $doc_contenttype, $doc_linenr, $doc_content, $doc_section, $doc_sectionlevel, $doc_headersection"
        }

        # fn: _detect_global_array_start - Detect framework/runtime/script globals array declarations
            # . Purpose
            #   Detect SGND_FRAMEWORK_GLOBALS, SGND_RUNTIME_GLOBALS, and SGND_SCRIPT_GLOBALS array blocks.
            #
            # . Behavior
            #   - Recognizes the start of strict-format global declaration arrays.
            #   - Records whether following entries belong to framework or script scope.
            #   - Prevents normal documentation detectors from processing the array start line.
            #
            # Outputs (globals):
            #   doc_globalblock, doc_globalscope, src_haltlineprocessing
            #
            # . Returns
            #   0 always.
            #
            # . Usage
            #   _detect_global_array_start
        _detect_global_array_start() {
            (( src_haltlineprocessing )) && return 0

            [[ "$src_line" =~ $_rgx_globalarray_start ]] || return 0

            case "${BASH_REMATCH[1]}" in
                SGND_FRAMEWORK_GLOBALS) doc_globalscope="framework" ;;
                SGND_RUNTIME_GLOBALS)   doc_globalscope="runtime" ;;
                SGND_SCRIPT_GLOBALS)    doc_globalscope="script" ;;
                *)                      doc_globalscope="" ;;
            esac

            doc_globalblock=1
            src_haltlineprocessing=1

            saydebug "Global declaration block detected: $doc_globalscope"
        }

        # fn: _detect_global_array_entry - Detect global declaration array entries
            # . Purpose
            #   Parse entries inside SGND_FRAMEWORK_GLOBALS, SGND_RUNTIME_GLOBALS, and SGND_SCRIPT_GLOBALS.
            #
            # . Behavior
            #   - Runs only while inside a global declaration array block.
            #   - Ends the block when a closing parenthesis is encountered.
            #   - Parses strict pipe-delimited entries:
            #       audience|VARNAME|Description|extra
            #   - Emits one global declaration record per valid entry.
            #
            # Outputs (globals):
            #   MOD_GLOBALS, doc_globalblock, doc_globalscope, src_haltlineprocessing
            #
            # . Returns
            #   0 always.
            #
            # . Usage
            #   _detect_global_array_entry
        _detect_global_array_entry() {
            (( src_haltlineprocessing )) && return 0
            (( doc_globalblock )) || return 0

            local trimmed="$src_line"
            trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
            trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"

            if [[ "$trimmed" == ')' ]]; then
                doc_globalblock=0
                doc_globalscope=""
                src_haltlineprocessing=1
                saydebug "Global declaration block ended"
                return 0
            fi

            [[ "$trimmed" =~ $_rgx_globalarray_entry ]] || {
                src_haltlineprocessing=1
                return 0
            }

            local spec="${BASH_REMATCH[1]}"
            local audience=""
            local name=""
            local description=""
            local extra=""

            IFS='|' read -r audience name description extra <<< "$spec"

            [[ -n "$name" ]] || {
                src_haltlineprocessing=1
                return 0
            }

            _emit_globalrecord "$doc_globalscope" "$audience" "$name" "$description" "$extra"
            src_haltlineprocessing=1
        }

        # fn: _detect_commentseparator - Ignore visual comment separators
            # . Purpose
            #   Detect separator-only comment lines and prevent them from becoming content.
            #
            # . Behavior
            #   - Matches separator lines using _rgx_commentseparator.
            #   - Clears pending content state.
            #   - Prevents later detectors from processing the same line.
            #
            # Inputs (globals):
            #   src_line, src_haltlineprocessing
            #
            # Outputs (globals):
            #   src_haltlineprocessing, doc_contenttype, doc_content
            #
            # . Returns
            #   0 always.
            #
            # . Usage
            #   _detect_commentseparator
        _detect_commentseparator() {
            (( src_haltlineprocessing )) && return 0

            [[ "$src_line" =~ $_rgx_commentseparator ]] || return 0

            src_haltlineprocessing=1
            doc_content=""
            doc_emitline=0

            saydebug "Comment separator ignored"
        }

    # -- Action -------------------------------------------------------------------
        # fn: _action_headerend - Emit module-level header data
            # . Purpose
            #   Store collected file header metadata in module-level data tables.
            #
            # . Behavior
            #   - Appends module identity and metadata to MOD_TABLE.
            #   - Appends attribution information to MOD_ATTRIBUTION.
            #   - Clears pending content emission for the header marker line.
            #
            # Inputs (globals):
            #   src_file, mod_name, mod_title, mod_type, mod_purpose, mod_version, mod_build, mod_group, mod_subgroup, mod_product
            #   mod_developers, mod_company, mod_client, mod_copyright, mod_license
            #
            # Outputs (globals):
            #   MOD_TABLE, MOD_ATTRIBUTION, doc_emitline
            #
            # . Returns
            #   0 if table append calls succeed.
            #
            # . Usage
            #   _action_headerend
        _action_headerend() {

            saydebug "Adding module: ${src_file:-}, ${mod_name:-}, ${mod_title:-}, ${mod_type:-}, ${mod_purpose:-}, ${mod_version:-}, ${mod_build:-}, ${mod_group:-}, ${mod_subgroup:-}, ${mod_product:-}"

            sgnd_dt_append \
                "$MOD_TABLE_SCHEMA" \
                MOD_TABLE \
                "${src_file:-}" \
                "${mod_name:-}" \
                "${mod_title:-}" \
                "${mod_type:-}" \
                "${mod_purpose:-}" \
                "${mod_version:-}" \
                "${mod_build:-}" \
                "${mod_checksum:-}" \
                "${mod_group:-}" \
                "${mod_subgroup:-}" \
                "${mod_product:-}"

            saydebug "Adding module attribution: ${MOD_ATTRIBUTION_SCHEMA:-}, ${mod_name:-}, ${mod_developers:-}, ${mod_company:-}, ${mod_client:-}, ${mod_copyright:-}, ${mod_license:-}"

            sgnd_dt_append \
                "$MOD_ATTRIBUTION_SCHEMA" \
                MOD_ATTRIBUTION \
                "${mod_name:-}" \
                "${mod_developers:-}" \
                "${mod_company:-}" \
                "${mod_client:-}" \
                "${mod_copyright:-}" \
                "${mod_license:-}"

            doc_emitline=0

        }

        # fn: _guess_nextcontenttype - Advance content type after emitted headers
            # . Purpose
            #   Prepare the parser for body content following a recognized header line.
            #
            # . Behavior
            #   - Maps module, section, item, and recognized headers to their body content types.
            #   - Leaves unknown or body content types unchanged.
            #
            # Inputs (globals):
            #   doc_contenttype
            #
            # Outputs (globals):
            #   doc_contenttype
            #
            # . Returns
            #   0 always.
            #
            # . Usage
            #   _guess_nextcontenttype
        _guess_nextcontenttype(){
            case "$doc_contenttype" in
                "moduleheader" ) doc_contenttype="modulebody";;
                "L1Sectionheader" ) doc_contenttype="L1Sectionbody";;
                "L2Sectionheader" ) doc_contenttype="L2Sectionbody";;
                "L3Sectionheader" ) doc_contenttype="L3Sectionbody";;
                "functionheader" ) doc_contenttype="functionbody";;
                "classheader" ) doc_contenttype="classbody";;
                "variableheader" ) doc_contenttype="variablebody";;
                "gendocheader" ) doc_contenttype="gendocbody";;
            esac
        }

    # -- Emitters -------------------------------------------------------------------
        # fn: _emit_globalrecord - Append a framework/runtime/script global declaration record
            # . Purpose
            #   Store a detected global variable declaration in the module globals table.
            #
            # . Behavior
            #   - Appends module name, scope, audience, variable name, description, extra metadata, and current value.
            #   - Preserves the array source through the scope field.
            #
            # . Arguments
            #   $1  Scope, normally framework or script.
            #   $2  Audience, normally system, user, or both.
            #   $3  Global variable name.
            #   $4  Human-readable description.
            #   $5  Extra metadata, reserved for future use.
            #   $6  Current shell value captured during documentation generation.
            #
            # Outputs (globals):
            #   MOD_GLOBALS
            #
            # . Returns
            #   0 if the table append succeeds.
            #
            # . Usage
            #   _emit_globalrecord "framework" "both" "SGND_ROOT" "Framework root" ""
        _emit_globalrecord() {
            local scope="${1:-}"
            local audience="${2:-}"
            local name="${3:-}"
            local description="${4:-}"
            local extra="${5:-}"
            local currentvalue="${6-}"

            if [[ $# -lt 6 && -n "$name" ]]; then
                currentvalue="${!name-}"
            fi

            [[ -n "$scope" && -n "$name" ]] || return 0

            sgnd_dt_append \
                "$MOD_GLOBALS_SCHEMA" \
                MOD_GLOBALS \
                "$mod_name" \
                "$scope" \
                "$audience" \
                "$name" \
                "$description" \
                "$extra" \
                "$currentvalue"
        }

        # fn: _emit_contentline - Append a normalized documentation content line
            # . Purpose
            #   Emit the current normalized content state into DOC_CONTENT_LINES.
            #
            # . Behavior
            #   - Skips emission when content type or emit flag is missing.
            #   - Increments the documentation line counter.
            #   - Appends the normalized content line with current section and item context.
            #   - Clears the emit flag after successful emission.
            #
            # Inputs (globals):
            #   doc_contenttype, doc_content, doc_emitline, mod_name, src_linenr, doc_linenr
            #   doc_section, doc_parentsection, doc_grandparentsection, doc_headersection, doc_item, doc_itemtitle
            #
            # Outputs (globals):
            #   DOC_CONTENT_LINES, doc_linenr, doc_emitline
            #
            # . Returns
            #   0 when skipped or appended successfully.
            #
            # . Usage
            #   _emit_contentline
        _emit_contentline() {
            [[ -z "$doc_contenttype" ]] && return 0
            (( ! doc_emitline )) && return 0

            _sgnd_doc_is_valid_stylehint "$doc_stylehint" || {
                saywarning "Invalid documentation style hint: $doc_stylehint"
                doc_stylehint="normal"
            }

            ((doc_linenr++))
            contentref="$(_build_content_ref "$mod_name" "$doc_grandparentsection" "$doc_parentsection" "$doc_section" "$doc_item")"

            sgnd_dt_append \
                "$DOC_CONTENT_LINES_SCHEMA" \
                DOC_CONTENT_LINES \
                "$mod_name" \
                "$src_linenr" \
                "$doc_linenr" \
                "$doc_section" \
                "$doc_parentsection" \
                "$doc_grandparentsection" \
                "$doc_stylehint" \
                "$doc_item" \
                "$doc_itemtitle" \
                "$doc_contenttype" \
                "$doc_content" \
                "$contentref"

            doc_emitline=0
        }

        # fn: _emit_itemrecord - Append a documented item record
            # . Purpose
            #   Store the current documented item in the module item index.
            #
            # . Behavior
            #   - Appends module, section, item type, visibility, role, name, and title to MOD_ITEMS.
            #   - Preserves the item role so template-origin items can be distinguished from normal items.
            #
            # Inputs (globals):
            #   mod_name, doc_section, doc_parentsection, src_linetype, doc_itemtype
            #   doc_itemvisibility, doc_itemrole, doc_item, doc_itemtitle
            #
            # Outputs (globals):
            #   MOD_ITEMS
            #
            # . Returns
            #   0 if the table append succeeds.
            #
            # . Usage
            #   _emit_itemrecord
        _emit_itemrecord(){
    
            saydebug "Adding item: Module ${mod_name:-}, Section ${doc_section:-}, Parent ${doc_parentsection:-}, SrcLinetype ${src_linetype:-}, DocLinetype ${doc_linetype:-} /
                    , Visibility: ${doc_itemvisibility:-}, Role: ${doc_itemrole:-}, ItemType ${doc_itemtype:-}, ItemTitle ${doc_item:-}, ${doc_itemtitle:-}"

            
            sgnd_dt_append \
                "$MOD_ITEMS_SCHEMA" \
                MOD_ITEMS \
                "$mod_name" \
                "$doc_section" \
                "$doc_parentsection" \
                "$src_linetype" \
                "$doc_itemtype" \
                "$doc_itemvisibility" \
                "$doc_itemrole" \
                "$doc_item" \
                "$doc_itemtitle"
        }

        # fn: _emit_sectionrecord - Append a documentation section record
            # . Purpose
            #   Store the current section context in the module section index.
            #
            # . Behavior
            #   - Appends module name, section name, parent section, grandparent section, title, and level.
            #   - Preserves hierarchy context for later renderer-side navigation construction.
            #
            # Inputs (globals):
            #   mod_name, doc_section, doc_parentsection, doc_grandparentsection
            #   doc_sectiontitle, doc_sectionlevel
            #
            # Outputs (globals):
            #   MOD_SECTIONS
            #
            # . Returns
            #   0 if the table append succeeds.
            #
            # . Usage
            #   _emit_sectionrecord
        _emit_sectionrecord(){
            sgnd_dt_append \
                "$MOD_SECTIONS_SCHEMA" \
                MOD_SECTIONS \
                "$mod_name" \
                "$doc_section" \
                "$doc_parentsection" \
                "$doc_grandparentsection" \
                "$doc_sectiontitle" \
                "$doc_sectionlevel" 
        }


# - Internal API ----------------------------------------------------------------
    # fn: _parse_module_file - Parse one module source file
        # . Purpose
        #   Parse a source file and collect normalized documentation tables.
        #
        # . Behavior
        #   - Validates the source filename argument.
        #   - Resets parser state for the file.
        #   - Reads the file line-by-line in source order.
        #   - Runs detectors in deterministic order.
        #   - Emits normalized content, section, item, metadata, and attribution records.
        #
        # . Arguments
        #   $1  Source file to parse.
        #
        # Outputs (globals):
        #   MOD_TABLE, MOD_ATTRIBUTION, MOD_SECTIONS, MOD_ITEMS, DOC_CONTENT_LINES
        #
        # . Returns
        #   0 on successful parsing.
        #   1 when no source filename is supplied.
        #
        # . Usage
        #   _parse_module_file "/usr/local/lib/solidgroundux/common/sgnd-core.sh"
    _parse_module_file(){
        src_file="${1:-}"
        [[ -z "$src_file" ]] && {
            sayerror "No filename was passed"
            return 1
        }

        _init_localvars
        local total_lines
        total_lines=$(wc -l < "$src_file")

        mod_name="$(basename "$src_file")"
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Line counters, src_linenr tracks current line number in source file, doc_linenr starts counting
            # when a header marker is found
            ((src_linenr++))
            src_line="$line"

            if declare -F _doc_progress_line >/dev/null; then
                _doc_progress_line "$src_linenr" "$total_lines" "$(basename "$src_file")"
            else
                sayprogress \
                    --slot 0 \
                    --current "$src_linenr" \
                    --total "$total_lines" \
                    --label "Parsing $(basename "$src_file")" \
                    --type 5
            fi

            src_haltlineprocessing=0
            
            # Source-level declarations
            _detect_global_array_entry
            _detect_global_array_start

            # Early filter
            _detect_commentseparator
            
            # Start conditions
            _detect_headermarker
            saydebug "after header marker: $src_linetype, $src_linenr, $doc_linenr, $src_line"

            # Stop conditions
            _detect_noncommentline
            (( !doc_started )) && continue

            # Contenttype detection
            _detect_moduletitle

            saydebug "Pre headerfield detection, headersection $doc_headersection, InHeader? $doc_inheader, $doc_linenr, $src_line"
            _detect_headersectionheader
            _detect_headerfields

            _detect_section
            _get_section_comments

            _detect_items

            _detect_default
            
            _emit_contentline

            _guess_nextcontenttype

        done < "$src_file"
        
        return 0
    } 

    # fn: _build_content_ref - Build a stable documentation content reference
        # . Purpose
        #   Create the canonical reference key used to link content to a module, section, and item context.
        #
        # . Behavior
        #   - Joins module, grandparent section, parent section, section, and item values.
        #   - Preserves empty hierarchy parts so the reference shape remains stable.
        #   - Writes the generated reference to stdout.
        #
        # . Arguments
        #   $1  Module name.
        #   $2  Grandparent section name.
        #   $3  Parent section name.
        #   $4  Current section name.
        #   $5  Current item name.
        #
        # . Returns
        #   0 after writing the content reference.
        #
        # . Usage
        #   _build_content_ref "sgnd-core" "Core" "Strings" "Formatting" "sgnd_sgr"
    _build_content_ref() {
        local module_name="${1-}"
        local grandparent_section="${2-}"
        local parent_section="${3-}"
        local section_name="${4-}"
        local item_name="${5-}"

        printf '%s:%s:%s:%s:%s\n' \
            "$module_name" \
            "$grandparent_section" \
            "$parent_section" \
            "$section_name" \
            "$item_name"
    }  




