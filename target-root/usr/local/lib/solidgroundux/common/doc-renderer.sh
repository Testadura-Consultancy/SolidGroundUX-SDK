# ==================================================================================
# SolidGroundUX SDK - Documentation Renderer
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626501
#   Checksum    : eea836588eeb28a5146abe4d95414b273cdcc8b5a1b03644dbb589dd70907372
#   Source      : doc-renderer.sh
#   Type        : library
#   Group       : SDK
#   Subgroup    : Documentation Generator
#   Purpose     : Prepare normalized parser data and invoke the documentation renderer
#
# Description:
#   Converts parser-owned documentation tables into renderer input files and delegates
#   final HTML generation to the Python documentation renderer.
#
# Design principles:
#   - Keep parsing, export preparation, and final rendering separate.
#   - Use explicit table-shaped arrays and PSV files as intermediate models.
#   - Preserve deterministic ordering and stable content references.
#   - Avoid hidden relational behavior or synthetic database-like machinery.
#
# Role in framework:
#   - Post-processing and hand-off layer between doc-processor and concrete renderers.
#   - Exports parser tables as the canonical input set for renderer implementations.
#   - Invokes the Python HTML renderer for the current documentation output.
#
# Non-goals:
#   - Parsing source files.
#   - Owning source comment grammar.
#   - Performing final format-specific rendering directly in Bash.
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
# - Local definitions -------------------------------------------------------------
    # var: DOC_RENDER_CACHE_DIR - Persistent renderer input cache directory
        # . Purpose
        #   Hold the complete exported renderer input set for fast HTML-only rebuilds.
        #
        # . Behavior
        #   - Defaults to a hidden directory beneath VAL_OUTDIR.
        #   - Is refreshed after Full, Selected, and Changed generation.
        #   - Is consumed directly by Render mode without reparsing source files.
        #   - May be overridden by callers before rendering.
        DOC_RENDER_CACHE_DIR=""

    # var: Postprocess datamodel - Renderer-side documentation indexes
        # . Purpose
        #   Define renderer-owned index tables derived from parser output.
        #
        # . Behavior
        #   - Stores attribution and function lookup data for documentation indexes.
        #   - Keeps post-processing output separate from parser-owned tables.
        #   - Uses schema strings as explicit table contracts for sgnd-datatable helpers.
        #
        # Tables:
        #   DOC_ATTRIBUTION_INDEX
        #     Groups attribution metadata by company, developer, license, module, product, and group.
        #
        #   DOC_FUNCTION_INDEX
        #     Lists documented functions by product, group, module, visibility, name, purpose, and anchor.
        #
        # Notes:
        #   - These tables are renderer indexes, not parser input contracts.
        #   - Concrete renderers may consume these indexes together with exported parser tables.
        DOC_ATTRIBUTION_INDEX_SCHEMA="company|developer|license|modulename|moduletitle|product|group"
        DOC_ATTRIBUTION_INDEX=()

        DOC_FUNCTION_INDEX_SCHEMA="product|group|modulename|itemvisibility|functionname|purpose|anchor"
        DOC_FUNCTION_INDEX=()

        DOC_LICENSE_LINES_SCHEMA="linenr|content"
        DOC_LICENSE_LINES=()

    # -- Arguments ------------------------------------------------------------------
        # doc: render_options - Documentation output selection and ordering defaults
            # . Purpose
            #   Define default renderer options used by documentation generation.
            #
            # . Behavior
            #   - Controls whether internal items and empty sections are included.
            #   - Defines default grouping and sort expressions for indexes, sections, and items.
            #
            # Notes:
            #   - These values are configuration defaults, not parser-owned data.
            #   - Concrete renderers may interpret only the options they support.
        FLAG_INCLUDE_INTERNAL=0
        FLAG_INCLUDE_EMPTY_SECTIONS=1
        
        VAL_INDEX_GROUPBY="product,group,type"
        VAL_SECTION_SORTBY="modulename,parent,section,level"
        VAL_ITEM_SORTBY="modulename,section,itemvisibility,type,name"

    # -- Helpers --------------------------------------------------------------------
        # fn: _init_metadata - Initialize document-level render metadata
            # . Purpose
            #   Populate renderer metadata from document configuration values.
            #
            # . Behavior
            #   - Copies configured title, subtitle, version, and product values into DOC_* variables.
            #   - Records the render timestamp in UTC ISO-like format.
            #
            # Inputs (globals):
            #   VAL_DOCUMENT_TITLE, VAL_DOCUMENT_SUBTITLE, VAL_DOCUMENT_VERSION, VAL_DOCUMENT_PRODUCT
            #
            # Outputs (globals):
            #   DOC_TITLE, DOC_SUBTITLE, DOC_VERSION, DOC_PRODUCT, DOC_RENDER_DATE
            #
            # . Returns
            #   0 on successful initialization.
            #
            # . Usage
            #   _init_metadata
        _init_metadata() {
            DOC_TITLE="${VAL_DOCUMENT_TITLE:-}"
            DOC_SUBTITLE="${VAL_DOCUMENT_SUBTITLE:-}"
            DOC_VERSION="${VAL_DOCUMENT_VERSION:-}"
            DOC_PRODUCT="${VAL_DOCUMENT_PRODUCT:-}"
            DOC_RENDER_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        }

        # fn: _prepare_output_directory - Create and optionally clean the documentation output directory
            # . Purpose
            #   Ensure the configured output directory exists and is ready for rendering.
            #
            # . Behavior
            #   - Creates VAL_OUTDIR when it does not exist.
            #   - Cleans existing output when FLAG_CLEAN_OUTPUT is enabled.
            #   - Preserves an existing assets/theme.css file across clean output runs.
            #
            # . Inputs (globals):
            #   VAL_OUTDIR, FLAG_CLEAN_OUTPUT
            #
            # . Outputs
            #   Creates or modifies files under VAL_OUTDIR.
            #
            # . Returns
            #   0 when the directory is ready.
            #   1 when creation, cleanup, or theme preservation fails.
            #
            # . Usage
            #   _prepare_output_directory
        _prepare_output_directory() {
            if [[ -d "$VAL_OUTDIR" ]]; then
                sayinfo "Output directory already exists: $VAL_OUTDIR"
            else
                mkdir -p "$VAL_OUTDIR" && sayinfo "Created output directory: $VAL_OUTDIR" || {
                    sayfail "Failed to create output directory: $VAL_OUTDIR"
                    return 1
                }
            fi

           if (( FLAG_CLEAN_OUTPUT == 1 )); then
                sayinfo "Cleaning output directory: $VAL_OUTDIR"

                local preserved_theme=""
                local preserved_images=""

                if [[ -f "$VAL_OUTDIR/assets/theme.css" ]]; then
                    preserved_theme="$(mktemp /tmp/sgnd-doc-theme.XXXXXX.css)" || return 1
                    cp "$VAL_OUTDIR/assets/theme.css" "$preserved_theme" || return 1
                fi

                if [[ -d "$VAL_OUTDIR/assets/images" ]]; then
                    preserved_images="$(mktemp -d /tmp/sgnd-doc-images.XXXXXX)" || return 1
                    cp -a "$VAL_OUTDIR/assets/images/." "$preserved_images/" || return 1
                fi

                rm -rf "${VAL_OUTDIR:?}/"* && sayinfo "Cleaned output directory: $VAL_OUTDIR" || {
                    sayfail "Failed to clean output directory: $VAL_OUTDIR"
                    return 1
                }

                if [[ -n "$preserved_theme" && -f "$preserved_theme" ]]; then
                    mkdir -p "$VAL_OUTDIR/assets" || return 1
                    cp "$preserved_theme" "$VAL_OUTDIR/assets/theme.css" || return 1
                    rm -f "$preserved_theme"
                    sayinfo "Preserved existing theme.css"
                fi

                if [[ -n "$preserved_images" && -d "$preserved_images" ]]; then
                    mkdir -p "$VAL_OUTDIR/assets/images" || return 1
                    cp -a "$preserved_images/." "$VAL_OUTDIR/assets/images/" || return 1
                    rm -rf "$preserved_images"
                    sayinfo "Preserved documentation images"
                fi
            fi

            local image_source_dir="${VAL_SRCDIR}/usr/local/lib/solidgroundux/assets"
            local image_target_dir="${VAL_OUTDIR}/assets/images"
            
            if [[ -d "$image_source_dir" ]]; then
                mkdir -p "$image_target_dir" || {
                    sayfail "Failed to create documentation image directory: $image_target_dir"
                    return 1
                }

                cp -a "$image_source_dir/." "$image_target_dir/" || {
                    sayfail "Failed to copy documentation images from: $image_source_dir"
                    return 1
                }

                sayinfo "Copied documentation images from: $image_source_dir"
            fi
        }

        # fn: _export_render_config - Export renderer configuration to a PSV file
            # . Purpose
            #   Write document-level render settings in the same table format used by exported parser data.
            #
            # . Behavior
            #   - Writes a key|value header.
            #   - Exports title, subtitle, version, product, clean-output behavior, and navigation width.
            #   - Forces FLAG_CLEAN_OUTPUT to 0 for the Python renderer hand-off to avoid recursive cleanup.
            #
            # . Arguments
            #   $1  Target render_config.psv file.
            #
            # . Returns
            #   0 when the file is written.
            #   Non-zero when the target file cannot be written.
            #
            # . Usage
            #   _export_render_config "/tmp/sgnd-example.txt"
        _export_render_config() {

            local config_file="${1:?missing config file}"

            {
                printf '%s\n' 'key|value'
                printf 'VAL_DOCUMENT_TITLE|%s\n' "${VAL_DOCUMENT_TITLE:-}"
                printf 'VAL_DOCUMENT_SUBTITLE|%s\n' "${VAL_DOCUMENT_SUBTITLE:-}"
                printf 'VAL_DOCUMENT_VERSION|%s\n' "${VAL_DOCUMENT_VERSION:-}"
                printf 'VAL_DOCUMENT_PRODUCT|%s\n' "${VAL_DOCUMENT_PRODUCT:-}"
                printf 'VAL_COLLECTION_NAME|%s\n' "${VAL_COLLECTION_NAME:-}"
                printf 'VAL_DOCUMENT_PRODUCTS|%s\n' "${VAL_DOCUMENT_PRODUCTS:-ALL}"
                printf 'FLAG_CLEAN_OUTPUT|0\n'
                printf 'VAL_NAV_WIDTH|%s\n' "${VAL_NAV_WIDTH:-320px}"

            } > "$config_file"
        }

        # fn: _collect_license_lines - Collect active license text for appendix rendering
            # . Purpose
            #   Load the active framework license file into the renderer license table.
            #
            # . Behavior
            #   - Uses SGND_LICENSE_FILE as the active license source.
            #   - Skips gracefully when the license path is empty, missing, or unreadable.
            #   - Stores one row per source line with the original line order.
            #   - Replaces pipe characters because renderer hand-off tables are PSV based.
            #
            # Inputs (globals):
            #   SGND_LICENSE_FILE
            #
            # Outputs (globals):
            #   DOC_LICENSE_LINES
            #
            # . Returns
            #   0 always; missing license text is represented as an empty export table.
            #
            # . Usage
            #   _collect_license_lines
        _collect_license_lines() {
            local license_file="${SGND_LICENSE_FILE:-}"
            local line=""
            local safe_line=""
            local line_nr=0

            DOC_LICENSE_LINES=()

            [[ -n "$license_file" ]] || {
                saydebug "No SGND_LICENSE_FILE configured; license appendix will be empty"
                return 0
            }

            [[ -r "$license_file" ]] || {
                saydebug "License file not readable; license appendix will be empty: $license_file"
                return 0
            }

            while IFS= read -r line || [[ -n "$line" ]]; do
                (( line_nr++ ))
                safe_line="${line//|/¦}"
                DOC_LICENSE_LINES+=("$line_nr|$safe_line")
            done < "$license_file"

            saydebug "Exported $line_nr license lines from: $license_file"
            return 0
        }

        # fn: _export_product_manifests - Export discovered product metadata for product-owned appendices
        _export_product_manifests() {
            local export_dir="${1:?missing export dir}" index=0 definition="" record=""
            local product="" version="" build="" company="" copyright="" license="" documentation="" appendices="" project_root=""
            local file="$export_dir/product_manifests.psv"
            printf '%s\n' 'product|version|build|company|copyright|license|documentation|appendices|project_root' > "$file"
            for index in "${!SGND_DOC_DISCOVERED_DEFINITIONS[@]}"; do
                definition="${SGND_DOC_DISCOVERED_DEFINITIONS[$index]}"
                project_root="${SGND_DOC_DISCOVERED_ROOTS[$index]:-${definition%%/target-root/*}}"
                record="$(bash -c '
                    source "$1"
                    for var in $(compgen -A variable SGND_); do
                        case "$var" in
                            SGND_PRODUCT) p=SGND ;;
                            *_PRODUCT) p="${var%_PRODUCT}" ;;
                            *) continue ;;
                        esac
                        eval "product=\${${p}_PRODUCT-}"; eval "version=\${${p}_VERSION-}"; eval "build=\${${p}_BUILD-}";
                        eval "company=\${${p}_COMPANY-}"; eval "copyright=\${${p}_COPYRIGHT-}"; eval "license=\${${p}_LICENSE-}";
                        eval "documentation=\${${p}_DOCUMENTATION-}"; eval "appendices=\${${p}_APPENDICES-}";
                        printf "%s|%s|%s|%s|%s|%s|%s|%s\\n" "$product" "$version" "$build" "$company" "$copyright" "$license" "$documentation" "$appendices"; exit
                    done
                ' bash "$definition" 2>/dev/null || true)"
                [[ -n "$record" ]] || continue
                printf '%s|%s\n' "$record" "$project_root" >> "$file"
            done
        }

        # fn: _export_render_tables - Export parser tables for the Python renderer
            # . Purpose
            #   Persist normalized documentation tables into a renderer hand-off directory.
            #
            # . Behavior
            #   - Creates the export directory when needed.
            #   - Exports module, section, item, attribution, global, and content-line tables as PSV files.
            #   - Exports renderer configuration alongside parser data.
            #
            # . Arguments
            #   $1  Directory that receives the exported PSV files.
            #
            # Inputs (globals):
            #   MOD_TABLE, MOD_SECTIONS, MOD_ITEMS, MOD_ATTRIBUTION, MOD_GLOBALS, DOC_CONTENT_LINES
            #   and their corresponding schema variables.
            #
            # . Returns
            #   0 when all tables and config are exported.
            #   1 when directory creation or any export step fails.
            #
            # . Usage
            #   _export_render_tables "/tmp/sgnd-example"
        _export_render_tables() {
            local export_dir="${1:?missing export dir}"

            mkdir -p "$export_dir" || return 1
            _export_product_manifests "$export_dir" || return 1

            sgnd_dt_export_psv \
                "$MOD_TABLE_SCHEMA" \
                MOD_TABLE \
                "$export_dir/mod_table.psv" \
                || return 1

            sgnd_dt_export_psv \
                "$MOD_SECTIONS_SCHEMA" \
                MOD_SECTIONS \
                "$export_dir/mod_sections.psv" \
                || return 1

            sgnd_dt_export_psv \
                "$MOD_ITEMS_SCHEMA" \
                MOD_ITEMS \
                "$export_dir/mod_items.psv" \
                || return 1

            sgnd_dt_export_psv \
                "$MOD_ATTRIBUTION_SCHEMA" \
                MOD_ATTRIBUTION \
                "$export_dir/mod_attribution.psv" \
                || return 1

            sgnd_dt_export_psv \
                "$MOD_GLOBALS_SCHEMA" \
                MOD_GLOBALS \
                "$export_dir/mod_globals.psv" \
                || return 1

            sgnd_dt_export_psv \
                "$DOC_CONTENT_LINES_SCHEMA" \
                DOC_CONTENT_LINES \
                "$export_dir/doc_content_lines.psv" \
                || return 1

            _collect_license_lines

            sgnd_dt_export_psv \
                "$DOC_LICENSE_LINES_SCHEMA" \
                DOC_LICENSE_LINES \
                "$export_dir/doc_license_lines.psv" \
                || return 1

            project_root="${VAL_SRCDIR%/target-root}"

            if [[ -f "$project_root/SolidGroundUX-Canonical.md" ]]; then
                cp "$project_root/SolidGroundUX-Canonical.md" \
                    "$export_dir/SolidGroundUX-Canonical.md" \
                    || return 1
            elif [[ -f "$project_root/SolidGroundUX-Cannonical.md" ]]; then
                cp "$project_root/SolidGroundUX-Cannonical.md" \
                    "$export_dir/SolidGroundUX-Cannonical.md" \
                    || return 1
            fi

            if [[ -f "$project_root/CHANGELOG.md" ]]; then
                cp "$project_root/CHANGELOG.md" \
                    "$export_dir/CHANGELOG.md" \
                    || return 1
            fi

            if [[ -f "$project_root/INSTALL.md" ]]; then
                cp "$project_root/INSTALL.md" \
                    "$export_dir/INSTALL.md" \
                    || return 1
            fi


            _export_render_config \
                "$export_dir/render_config.psv" \
                || return 1
        }

        # fn: _doc_render_cache_dir - Resolve the persistent renderer cache directory
            # . Purpose
            #   Return the active renderer cache directory for the current output tree.
            #
            # . Output
            #   Writes the resolved path to stdout.
            # . Usage
            #   _doc_render_cache_dir
        _doc_render_cache_dir() {
            printf '%s\n' "${DOC_RENDER_CACHE_DIR:-$VAL_OUTDIR/.sgnd-render-cache}"
        }

        # fn: _clear_render_cache - Remove cached renderer input data
            # . Purpose
            #   Delete the persistent renderer cache when explicitly requested.
            #
            # . Returns
            #   0 when the cache is absent or removed successfully.
            # . Usage
            #   _clear_render_cache
        _clear_render_cache() {
            local cache_dir=""
            cache_dir="$(_doc_render_cache_dir)"

            [[ -n "$cache_dir" ]] || return 1
            [[ -d "$cache_dir" ]] || return 0

            rm -rf -- "$cache_dir" || {
                sayfail "Failed to clear renderer cache: $cache_dir"
                return 1
            }

            sayinfo "Cleared renderer cache: $cache_dir"
            return 0
        }

        # fn: _persist_render_cache - Persist a complete renderer export set
            # . Purpose
            #   Replace the persistent renderer cache with a validated export directory.
            #
            # . Arguments
            #   $1  Source export directory.
            #
            # . Returns
            #   0 when the cache is replaced successfully.
            # . Usage
            #   _persist_render_cache "<source_dir>"
        _persist_render_cache() {
            local source_dir="${1:?missing source render directory}"
            local cache_dir=""
            local staging_dir=""

            cache_dir="$(_doc_render_cache_dir)"
            staging_dir="${cache_dir}.new"

            rm -rf -- "$staging_dir" || return 1
            mkdir -p "$staging_dir" || return 1
            cp -a "$source_dir/." "$staging_dir/" || return 1

            rm -rf -- "$cache_dir" || return 1
            mv "$staging_dir" "$cache_dir" || return 1

            sayinfo "Renderer cache updated: $cache_dir"
            return 0
        }

        # fn: _validate_render_cache - Validate cached renderer input
            # . Purpose
            #   Verify that Render mode has the complete minimum PSV input set.
            #
            # . Arguments
            #   $1  Renderer cache directory.
            #
            # . Returns
            #   0 when all required files exist and are readable.
            #   1 otherwise.
            # . Usage
            #   _validate_render_cache "<cache_dir>"
        _validate_render_cache() {
            local cache_dir="${1:?missing renderer cache directory}"
            local required_file=""
            local -a required_files=(
                mod_table.psv
                mod_sections.psv
                mod_items.psv
                mod_attribution.psv
                mod_globals.psv
                doc_content_lines.psv
                render_config.psv
            )

            [[ -d "$cache_dir" ]] || return 1

            for required_file in "${required_files[@]}"; do
                [[ -r "$cache_dir/$required_file" ]] || return 1
            done

            return 0
        }

        # fn: _cleanup_old_render_exports - Clean old renderer export folders
            # . Purpose
            # > Remove stale temporary documentation renderer export folders from /tmp.
            #
            # . Behavior
            # > - Finds directories matching /tmp/sgnd-doc-render.*.
            # > - Sorts them by modification time, newest first.
            # > - Keeps the two newest render export folders.
            # > - Deletes older render export folders.
            # > - Ignores missing matches without raising an error.
            #
            # . Notes
            # > This cleanup only affects temporary renderer input exports.
            # > It does not touch generated documentation output.
            #
            # . Returns
            # > 0 after cleanup completes.
            #
            # . Usage
            # > _cleanup_old_render_exports
        _cleanup_old_render_exports() {
            find /tmp \
                -maxdepth 1 \
                -type d \
                -name 'sgnd-doc-render.*' \
                -printf '%T@ %p\n' |
            sort -nr |
            tail -n +3 |
            cut -d' ' -f2- |
            xargs -r rm -rf
        }

# - Main sequence ----------------------------------------------------------
    # fn: _render_site - Render collected documentation data
        # . Purpose
        #   Provide the renderer hand-off point for collected documentation tables.
        #
        # . Behavior
        #   - Validates the output folder argument.
        #   - Prepares and optionally cleans the output directory.
        #   - Initializes document-level metadata.
        #   - Exports parser tables and renderer configuration to a temporary hand-off directory.
        #   - Persists the complete hand-off set for future Render-mode runs.
        #   - Invokes the Python HTML renderer.
        #   - Verifies that index.html was created.
        #
        # . Arguments
        #   $1  Output folder for generated documentation.
        #
        # . Returns
        #   0 when rendering completes and index.html exists.
        #   1 when validation, preparation, export, rendering, or output verification fails.
        #
        # . Usage
        #   _render_site "example"
    _render_site(){
        local output_folder="${1:-}"
        [[ -z "$output_folder" ]] && {
            sayfail "No outputfolder was passed"
            return 1
        }
        saydebug "Rendering site to $output_folder"

        _prepare_output_directory || {
            sayfail "Failed to prepare output directory"
            return 1
        }

        _init_metadata || {
            sayfail "Failed to initialize documentation metadata"
            return 1
        }

        _cleanup_old_render_exports

        local export_dir=""
        export_dir="$(mktemp -d "/tmp/sgnd-doc-render.XXXXXX")" || {
            sayfail "Failed to create temporary export directory"
            return 1
        }

        _export_render_tables "$export_dir" || {
            sayfail "Failed to export render tables for Python renderer"
            return 1
        }

        # Parser cache remains the source for Selected/Changed generation.
        local parser_cache_dir="$VAL_OUTDIR/.sgnd-doc-cache"
        mkdir -p "$parser_cache_dir" || {
            sayfail "Failed to create documentation cache directory: $parser_cache_dir"
            return 1
        }

        cp -f "$export_dir"/*.psv "$parser_cache_dir/" || {
            sayfail "Failed to update documentation cache: $parser_cache_dir"
            return 1
        }
        sayinfo "Documentation cache updated: $parser_cache_dir"

        if (( ${FLAG_CLEAR_RENDER_CACHE:-0} )); then
            _clear_render_cache || return 1
        fi

        _persist_render_cache "$export_dir" || {
            sayfail "Failed to update persistent renderer cache"
            return 1
        }

        sayinfo "Python renderer input : $export_dir"
        sayinfo "Python renderer output: $output_folder"
        sayinfo "Python renderer script: $SGND_PYTHON_DIR/sgnd_doc_renderer.py"

        python3 "$SGND_PYTHON_DIR/sgnd_doc_renderer.py" \
            "$export_dir" \
            "$output_folder" || {
                sayfail "Python documentation renderer failed"
                return 1
        }



        if [[ ! -f "$output_folder/index.html" ]]; then
            sayfail "Python renderer completed, but index.html was not created in: $output_folder"
            return 1
        fi
        sayinfo "Documentation rendering complete. Output available at: $output_folder"

        return 0
    } 

    # fn: _render_cached_site - Render HTML from the persistent renderer cache
        # . Purpose
        #   Rebuild the generated site without rescanning or reparsing source files.
        #
        # . Behavior
        #   - Uses the complete renderer input set saved by a previous generation.
        #   - Preserves the parser cache and source tables unchanged.
        #   - Prepares the output directory without cleaning it.
        #   - Fails explicitly when no valid renderer cache exists.
        #
        # . Arguments
        #   $1  Output folder for generated documentation.
        #
        # . Returns
        #   0 when rendering completes and index.html exists.
        #   1 when the cache is missing/invalid or rendering fails.
        # . Usage
        #   _render_cached_site "<output_folder>"
    _render_cached_site() {
        local output_folder="${1:-}"
        local cache_dir=""

        [[ -n "$output_folder" ]] || {
            sayfail "No output folder was passed"
            return 1
        }

        cache_dir="$(_doc_render_cache_dir)"
        _validate_render_cache "$cache_dir" || {
            sayfail "No valid renderer cache is available: $cache_dir"
            sayinfo "Run Full, Selected, or Changed generation before using Render mode"
            return 1
        }

        FLAG_CLEAN_OUTPUT=0
        _prepare_output_directory || {
            sayfail "Failed to prepare output directory"
            return 1
        }

        sayinfo "Python renderer input : $cache_dir"
        sayinfo "Python renderer output: $output_folder"
        sayinfo "Python renderer script: $SGND_PYTHON_DIR/sgnd_doc_renderer.py"

        python3 "$SGND_PYTHON_DIR/sgnd_doc_renderer.py" \
            "$cache_dir" \
            "$output_folder" || {
                sayfail "Python documentation renderer failed"
                return 1
            }

        [[ -f "$output_folder/index.html" ]] || {
            sayfail "Python renderer completed, but index.html was not created in: $output_folder"
            return 1
        }

        sayinfo "Documentation rendering complete. Output available at: $output_folder"
        return 0
    }
    


    
