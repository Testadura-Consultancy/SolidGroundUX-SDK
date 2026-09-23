#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX SDK - Create Workspace
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626612
#   Checksum    : ddf78268928b795fa45051d32b603dfb6c831cc8b9ceeb0a2327b699579d9462
#   Source      : create-workspace.sh
#   Type        : script
#   Group       : SDK
#   Purpose     : Create a new development workspace from templates
#
# Description:
#   Provides a developer utility that scaffolds a new project workspace
#   into a target directory using the framework's standard template layout.
#
#   The script:
#     - Resolves project name and target folder
#     - Creates a repository-shaped target-root structure
#     - Lists installed convenience templates and lets the user choose which to copy
#     - Copies the selected convenience templates into the new project workspace
#     - Creates project-namespaced definitions in the SolidGroundUX globals folder
#     - Optionally creates a simple 95-<project> MOTD identity entry
#     - Generates a VS Code workspace file and standard .gitignore and .release-ignore
#     - Optionally initializes Git and creates/pushes a GitHub repository using gh
#
# Design principles:
#   - Workspace creation is deterministic and repeatable
#   - Follows SolidGroundUX project conventions
#   - Supports dry-run for all filesystem operations
#
# Role in framework:
#   - Entry point for initializing new development workspaces
#   - Ensures consistent project structure across environments
#
# Non-goals:
#   - Deployment or installation of runtime environments
#   - Managing existing workspaces beyond initial scaffolding
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# =====================================================================================
set -uo pipefail
# --- Bootstrap ----------------------------------------------------------------------
    # fn$ _framework_locator - Resolve and load the active SolidGroundUX framework
        # . Purpose
        #   Determine the filesystem root of the currently executing SolidGroundUX tree
        #   from the script's physical path, then load the executable runtime library.
        #
        # . Behavior
        #   - Resolves the physical path of the executing script.
        #   - Treats usr, etc, and var as the canonical top-level SolidGroundUX tree roots.
        #   - Uses the last occurrence of one of those path components to determine the
        #     active filesystem root.
        #   - Resolves production scripts beneath /usr, /etc, or /var to root (/).
        #   - Resolves staged/development trees to the path prefix preceding the detected
        #     usr, etc, or var component.
        #   - Loads sgnd-exe-common.sh from the resolved framework root when available.
        #   - For staged/development trees where the executable common library is not
        #     present, falls back to the installed framework copy without changing
        #     SGND_FRAMEWORK_ROOT.
        #
        # . Globals (write)
        #   SGND_FRAMEWORK_ROOT
        #
        # . Output
        #   Writes fatal bootstrap errors to stderr using printf because framework UI
        #   helpers are not available until sgnd-exe-common.sh has been loaded.
        #
        # . Returns
        #   0 when the framework root was resolved and executable common library loaded.
        #   126 when the script path cannot be resolved, no canonical root component can
        #   be found, or the executable common library is unreadable.
        #
        # . Usage
        #   _framework_locator || return $?
    _framework_locator() {
        local script_file=""
        local path_without_root=""
        local component=""
        local framework_root=""
        local exe_common=""
        local index=0
        local root_index=-1
        local -a path_parts=()

        script_file="$(readlink -f "${BASH_SOURCE[0]}")" || {
            printf 'FATAL: Cannot resolve executable path: %s\n' "${BASH_SOURCE[0]}" >&2
            return 126
        }

        path_without_root="${script_file#/}"
        IFS='/' read -r -a path_parts <<< "$path_without_root"

        for index in "${!path_parts[@]}"; do
            component="${path_parts[$index]}"
            case "$component" in
                usr|etc|var)
                    root_index=$index
                    ;;
            esac
        done

        if (( root_index < 0 )); then
            printf 'FATAL: Cannot determine SolidGroundUX framework root from: %s\n' "$script_file" >&2
            return 126
        fi

        if (( root_index == 0 )); then
            framework_root="/"
        else
            framework_root=""
            for (( index=0; index<root_index; index++ )); do
                framework_root+="/${path_parts[$index]}"
            done
        fi

        SGND_FRAMEWORK_ROOT="$framework_root"

        if [[ "$SGND_FRAMEWORK_ROOT" == "/" ]]; then
            exe_common="/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"
        else
            exe_common="${SGND_FRAMEWORK_ROOT%/}/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"

            if [[ ! -r "$exe_common" ]]; then
                exe_common="/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"
            fi
        fi

        [[ -r "$exe_common" ]] || {
            printf 'FATAL: Cannot read executable common library: %s\n' "$exe_common" >&2
            return 126
        }

        # shellcheck source=/dev/null
        source "$exe_common"
    }
# - Script metadata -----------------------------------------------------------------
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"
    SGND_SCRIPT_TITLE="Create workspace"
   
    # -- Script metadata (framework integration) -----------------------------------------
        # SGND_USING
            # Libraries to source from SGND_COMMON_LIB.
            # These are loaded automatically by sgnd_bootstrap AFTER core libraries.
            #
            # Example:
            #   SGND_USING=( net.sh fs.sh )
            #
            # Leave empty if no extra libs are needed.
        SGND_USING=(
        )

        # SGND_ARGS_SPEC
            # Optional: script-specific argument definitions.
            #
            # Each entry:
            #   "name|short|type|var|help|choices"
            #
            # Fields:
            #   name    Long option name without leading --
            #   short   Short option name without leading -
            #   type    flag | value | enum
            # var: Shell variable to receive the parsed value
            #   help    Help text for auto-generated --help output
            #   choices Comma-separated values for enum; empty otherwise
            #
            # Notes:
            #   - -h / --help is built in and does not need to be defined here.
            #   - Parsed values become available in the configured target variables.
        SGND_ARGS_SPEC=(
            "project|p|value|PROJECT_NAME|Project name|"
            "prefix||value|PROJECT_PREFIX|Project prefix|"
            "description||value|PROJECT_DESCRIPTION|Project description|"
            "product||value|PRODUCT_NAME|Product name|"
            "group||value|PROJECT_GROUP|Generated script group|"
            "subgroup||value|PROJECT_SUBGROUP|Generated script subgroup|"
            "root||value|PROJECT_ROOT|Project root folder|"
            "folder|f|value|PROJECT_FOLDER|Set project folder|"
            "gitinit|g|flag|FLAG_GIT_INIT|Initialize a local Git repository|0|"
            "github||flag|FLAG_GITHUB_INIT|Create and push a GitHub repository using gh|0|"
            "github-repo||value|GITHUB_REPO_NAME|GitHub repository name|"
            "github-visibility||enum|GITHUB_VISIBILITY|GitHub repository visibility|private,public"
            "uncreate|u|flag|FLAG_UNCREATE|Remove items listed in workspace manifest|0|"
        )
        # SGND_SCRIPT_EXAMPLES
            # Optional: examples for --help output.
            # Each entry is a string that will be printed verbatim.
            #
            # Example:
            #   SGND_SCRIPT_EXAMPLES=(
            #       "Example usage:"
            #       "  script.sh --verbose --mode fast"
            #       "  script.sh -v -m slow"
            #   )
            #
            # Leave empty if no examples are needed.
        SGND_SCRIPT_EXAMPLES=(
            "Show help"
            "  $SGND_SCRIPT_NAME --help"
            ""
            "Perform a dry run:"
            "  $SGND_SCRIPT_NAME --dryrun"
        )

        # SGND_SCRIPT_GLOBALS
            # Explicit declaration of global variables intentionally used by this script.
            #
            # . Purpose
            #   - Declares which globals are part of the script’s public/config contract.
            #   - Enables optional configuration loading when non-empty.
            #
            # . Behavior
            #   - If this array is non-empty, sgnd_bootstrap enables config integration.
            #   - Variables listed here may be populated from configuration files.
            #   - Unlisted globals will NOT be auto-populated.
            #
            # Use this to:
            #   - Document intentional globals
            #   - Prevent accidental namespace leakage
            #   - Make configuration behavior explicit and predictable
            #
            # Only list:
            #   - Variables that must be globally accessible
            #   - Variables that may be defined in config files
            #
            # Leave empty if:
            #   - The script does not use configuration-driven globals
        SGND_SCRIPT_GLOBALS=(
        )

        # SGND_STATE_VARIABLES
            # List of variables participating in persistent state.
            #
            # . Purpose
            #   - Declares which variables should be saved/restored when state is enabled.
            #
            # . Behavior
            #   - Only used when sgnd_bootstrap is invoked with --state.
            #   - Variables listed here are serialized on exit (if SGND_STATE_SAVE=1).
            #   - On startup, previously saved values are restored before main logic runs.
            #
            # Contract:
            #   - Variables must be simple scalars (no arrays/associatives unless explicitly supported).
            #   - Script remains fully functional when state is disabled.
            #
            # Leave empty if:
            #   - The script does not use persistent state.
        SGND_STATE_VARIABLES=(
            PRODUCT_NAME
            PROJECT_GROUP
            PROJECT_SUBGROUP
            PROJECT_ROOT
            PROJECT_DESCRIPTION
            PROJECT_PREFIX
        )

        # SGND_ON_EXIT_HANDLERS
            # List of functions to be invoked on script termination.
            #
            # . Purpose
            #   - Allows scripts to register cleanup or finalization hooks.
            #
            # . Behavior
            #   - Functions listed here are executed during framework exit handling.
            #   - Execution order follows array order.
            #   - Handlers run regardless of normal exit or controlled termination.
            #
            # Contract:
            #   - Functions must exist before exit occurs.
            #   - Handlers must not call exit directly.
            #   - Handlers should be idempotent (safe if executed once).
            #
            # Typical uses:
            #   - Cleanup temporary files
            #   - Persist additional state
            #   - Release locks
            #
            # Leave empty if:
            #   - No custom exit behavior is required.
        SGND_ON_EXIT_HANDLERS=(
        )
        
        # State persistence is opt-in.
            # Scripts that want persistent state must:
            #   1) set SGND_STATE_SAVE=1
            #   2) call sgnd_bootstrap --state
        SGND_STATE_SAVE=1


# - Workspace template selection ----------------------------------------------------
    WORKSPACE_SELECTED_TEMPLATES=()
    FLAG_CREATE_STARTERS=0
    STARTER_TEMPLATE_NAMES=()
    STARTER_SCRIPT_NAMES=()
    STARTER_GROUPS=()
    STARTER_SUBGROUPS=()

# - Local script functions ----------------------------------------------------------
 # -- General helpers
    # fn: _copy_template_file - Copy one template file into the workspace
        # . Purpose
        #   Copy a single template file to a target location.
        #
        # . Behavior
        #   - Verifies the source template exists.
        #   - Creates the destination parent directory when needed.
        #   - Honors dry-run mode by reporting the intended action only.
        #   - Records the destination file in the manifest only when it did not exist before.
        #
        # . Arguments
        #   $1  Source template file
        #   $2  Destination file
        #
        # . Returns
        #   0 on success
        #   1 on failure
        #
        # . Usage
        #   _copy_template_file "/tmp/sgnd-example.txt" "/tmp/sgnd-example.txt" "/tmp/sgnd-example.txt"
    _copy_template_file() {
        local src="$1"
        local dst="$2"
        local existed=0

        [[ -f "$src" ]] || {
            sayfail "Template file not found: $src"
            return 1
        }

        [[ -e "$dst" ]] && existed=1

        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have copied template $src -> $dst"
            return 0
        fi

        mkdir -p "$(dirname "$dst")" || return 1
        cp "$src" "$dst" || return 1

        if [[ "$dst" == */target-root/usr/local/lib/solidgroundux/templates/* ]]; then
            local temp_file=""
            temp_file="$(mktemp)" || return 1

            {
                IFS= read -r first_line || true
                if [[ "$first_line" == '#!'* ]]; then
                    printf '%s\n' "$first_line"
                    printf '%s\n' '# Caveat: Canonical template placed as a template by create-workspace.sh; change at your own peril.'
                    cat
                else
                    printf '%s\n' '# Caveat: Canonical template placed as a template by create-workspace.sh; change at your own peril.'
                    [[ -n "$first_line" ]] && printf '%s\n' "$first_line"
                    cat
                fi
            } < "$dst" > "$temp_file" || { rm -f -- "$temp_file"; return 1; }

            mv -f -- "$temp_file" "$dst" || { rm -f -- "$temp_file"; return 1; }
        fi

        if (( ! existed )); then
            _manifest_record_file "$dst"
        fi

        sayinfo "Copied template $src -> $dst"
    }

    # fn: _template_metadata_value - Read one Metadata field from a template
    _template_metadata_value() {
        local file="${1:?missing template file}" field="${2:?missing field}"
        awk -v field="$field" '
            $0 ~ "^#[[:space:]]+" field "[[:space:]]*:" {
                line=$0; sub("^#[[:space:]]+" field "[[:space:]]*:[[:space:]]*", "", line); print line; exit
            }
        ' "$file"
    }

    # fn: _specialize_workspace_template - Make a copied canonical template product-aware
    _specialize_workspace_template() {
        local file="${1:?missing template file}" tmp=""
        [[ -f "$file" ]] || return 1
        (( ${FLAG_DRYRUN:-0} )) && return 0
        tmp="$(mktemp)" || return 1
        awk -v product="${PRODUCT_NAME:-$PROJECT_NAME}" '
            NR==3 && /^# / {
                line=$0; sub(/^# [^-]+ - /, "", line); print "# " product " - " line; next
            }
            { print }
        ' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
        mv -f "$tmp" "$file"
    }

    # fn: _specialize_generated_file - Apply selected metadata to a generated starter file
    _specialize_generated_file() {
        local file="${1:?missing generated file}"
        local script_name="${2:?missing script name}"
        local group="${3:-}"
        local subgroup="${4:-}"
        local tmp="" title="${script_name%.sh}"
        [[ -f "$file" ]] || return 1
        (( ${FLAG_DRYRUN:-0} )) && return 0
        tmp="$(mktemp)" || return 1
        awk -v product="${PRODUCT_NAME:-$PROJECT_NAME}" -v title="$title" -v source="$script_name" -v group="$group" -v subgroup="$subgroup" '
            NR==3 && /^# / { print "# " product " - " title; next }
            /^#[[:space:]]+Source[[:space:]]*:/ { print "#   Source      : " source; next }
            /^#[[:space:]]+Version[[:space:]]*:/ { print "#   Version     : 1.0"; next }
            /^#[[:space:]]+Build[[:space:]]*:/ { print "#   Build       : -"; next }
            /^#[[:space:]]+Checksum[[:space:]]*:/ { print "#   Checksum    : -"; next }
            /^#[[:space:]]+Product[[:space:]]*:/ { print "#   Product     : " product; next }
            /^#[[:space:]]+Group[[:space:]]*:/ { print "#   Group       : " group; next }
            /^#[[:space:]]+Subgroup[[:space:]]*:/ { print "#   Subgroup    : " subgroup; next }
            { print }
        ' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
        mv -f "$tmp" "$file"
    }

    # fn: _workspace_convenience_template_dir - Resolve the installed shared template library
    _workspace_convenience_template_dir() {
        if [[ "${SGND_FRAMEWORK_ROOT:-/}" == "/" ]]; then
            printf '%s\n' "/usr/local/share/solidgroundux/convenience-templates"
        else
            printf '%s\n' "${SGND_FRAMEWORK_ROOT%/}/usr/local/share/solidgroundux/convenience-templates"
        fi
    }

    # fn: _resolve_convenience_template_selection - Select convenience templates for the workspace
        # . Purpose
        #   Discover installed convenience templates and let the user choose which copies
        #   should be placed in the new workspace.
        #
        # . Behavior
        #   - Lists all top-level convenience-template files except templates_preface.sh.
        #   - Defaults to all discovered templates.
        #   - Accepts "all", "none", or a comma-separated list of template numbers.
        #   - In automatic mode, selects all discovered templates without prompting.
        #
        # . Outputs (globals)
        #   WORKSPACE_SELECTED_TEMPLATES
        #
        # . Returns
        #   0 on success, including when no convenience templates are installed.
        #   1 on invalid interactive selection.
    _resolve_convenience_template_selection() {
        local source_dir="" template="" answer="all" item="" index=0
        local -a available=() selected=()

        source_dir="$(_workspace_convenience_template_dir)"
        WORKSPACE_SELECTED_TEMPLATES=()

        if [[ ! -d "$source_dir" ]]; then
            saywarning "Convenience template directory not found: $source_dir"
            return 0
        fi

        while IFS= read -r -d '' template; do
            [[ "$(basename -- "$template")" == "templates_preface.sh" ]] && continue
            available+=( "$(basename -- "$template")" )
        done < <(find "$source_dir" -mindepth 1 -maxdepth 1 -type f -print0 2>/dev/null | sort -z)

        if (( ${#available[@]} == 0 )); then
            saywarning "No convenience templates found in: $source_dir"
            return 0
        fi

        if (( ! ${FLAG_AUTO:-0} )); then
            sgnd_print
            sgnd_print_sectionheader "Convenience templates"
            for index in "${!available[@]}"; do
                sgnd_print "  $((index + 1))) ${available[index]}"
            done
            sgnd_print
            ask --label "Templates to copy (all/none/numbers)" --var answer --default "all"
            answer="${answer,,}"
        fi

        case "$answer" in
            all|"")
                selected=( "${available[@]}" )
                ;;
            none)
                selected=()
                ;;
            *)
                IFS=',' read -r -a choices <<< "$answer"
                for item in "${choices[@]}"; do
                    item="${item//[[:space:]]/}"
                    [[ "$item" =~ ^[0-9]+$ ]] || {
                        sayfail "Invalid template selection: $item"
                        return 1
                    }
                    (( item >= 1 && item <= ${#available[@]} )) || {
                        sayfail "Template selection out of range: $item"
                        return 1
                    }
                    selected+=( "${available[item-1]}" )
                done
                ;;
        esac

        WORKSPACE_SELECTED_TEMPLATES=( "${selected[@]}" )
        return 0
    }

    # fn: _resolve_starter_scripts - Configure optional starter files for selected templates
    _resolve_starter_scripts() {
        local resp="N" template="" default_name="" name="" group="" subgroup="" slug=""
        STARTER_TEMPLATE_NAMES=()
        STARTER_SCRIPT_NAMES=()
        STARTER_GROUPS=()
        STARTER_SUBGROUPS=()
        FLAG_CREATE_STARTERS=0

        (( ${#WORKSPACE_SELECTED_TEMPLATES[@]} > 0 )) || return 0
        (( ${FLAG_AUTO:-0} )) && return 0

        slug="$(_project_slug)"
        for template in "${WORKSPACE_SELECTED_TEMPLATES[@]}"; do
            sgnd_print
            sgnd_print_sectionheader "$template"
            resp="N"
            ask --label "Add starter script (Y/N)" --var resp --default "N" --choices "Y,Yes,N,No" --labelwidth 25
            resp="${resp^^}"
            [[ "$resp" == "Y" || "$resp" == "YES" ]] || continue

            FLAG_CREATE_STARTERS=1
            case "$template" in
                wrapper-template) default_name="$slug" ;;
                doc-template.sh) default_name="${slug}-doc.sh" ;;
                *) default_name="${slug}.sh" ;;
            esac
            name="$default_name"
            group="${PROJECT_GROUP:-}"
            subgroup="${PROJECT_SUBGROUP:-}"
            ask --label "Script name " --var name --default "$name" --labelwidth 25
            ask --label "Group " --var group --default "$group" --labelwidth 25
            ask --label "Subgroup " --var subgroup --default "$subgroup" --labelwidth 25
            STARTER_TEMPLATE_NAMES+=("$template")
            STARTER_SCRIPT_NAMES+=("$name")
            STARTER_GROUPS+=("$group")
            STARTER_SUBGROUPS+=("$subgroup")
        done
    }

    # fn: _starter_target_path - Resolve conventional target path for a starter template
    _starter_target_path() {
        local template="${1:?missing template}" name="${2:?missing script name}"
        case "$template" in
            exe-template.sh) printf '%s\n' "${PROJECT_FOLDER}/target-root/usr/local/libexec/solidgroundux/${name}" ;;
            lib-template.sh) printf '%s\n' "${PROJECT_FOLDER}/target-root/usr/local/lib/solidgroundux/common/${name}" ;;
            mod-template.sh) printf '%s\n' "${PROJECT_FOLDER}/target-root/usr/local/libexec/solidgroundux/console-modules/${name}" ;;
            doc-template.sh) printf '%s\n' "${PROJECT_FOLDER}/target-root/usr/local/share/doc/${PRODUCT_NAME}/${name}" ;;
            wrapper-template) printf '%s\n' "${PROJECT_FOLDER}/target-root/usr/local/bin/${name}" ;;
            *) printf '%s\n' "${PROJECT_FOLDER}/target-root/usr/local/libexec/solidgroundux/${name}" ;;
        esac
    }

    # fn: _create_starter_scripts - Instantiate configured starter files from workspace templates
    _create_starter_scripts() {
        local i=0 template="" source="" target="" name=""
        (( ${FLAG_CREATE_STARTERS:-0} )) || return 0
        for i in "${!STARTER_TEMPLATE_NAMES[@]}"; do
            template="${STARTER_TEMPLATE_NAMES[i]}"
            name="${STARTER_SCRIPT_NAMES[i]}"
            source="${PROJECT_FOLDER}/target-root/usr/local/lib/solidgroundux/templates/${template}"
            target="$(_starter_target_path "$template" "$name")" || return 1
            if (( ${FLAG_DRYRUN:-0} )); then
                sayinfo "Would have created starter: $target"
                continue
            fi
            mkdir -p -- "$(dirname -- "$target")" || return 1
            _copy_template_file "$source" "$target" || return 1
            _specialize_generated_file "$target" "$name" "${STARTER_GROUPS[i]}" "${STARTER_SUBGROUPS[i]}" || return 1
            if [[ "$template" == "exe-template.sh" || "$template" == "mod-template.sh" || "$template" == "wrapper-template" || "$template" == "doc-template.sh" ]]; then
                chmod +x -- "$target" || return 1
            fi
        done

        return 0
    }

    # fn: _copy_workspace_templates - Copy shared convenience templates into the workspace
        # . Purpose
        #   Seed the repository-shaped workspace with the installed SolidGroundUX templates.
        #
        # . Behavior
        #   - Resolves the installed shared convenience-template directory.
        #   - Copies only the convenience templates selected for this workspace.
        #   - Records newly created template files in the workspace manifest.
        #   - Honors dry-run mode through _copy_template_file().
        #
        # Inputs (globals):
        #   SGND_COMMON_LIB
        #   PROJECT_FOLDER
        #
        # . Returns
        #   0 on success.
        #   1 when a selected template is missing or a copy fails.
        #
        # . Usage
        #   _copy_workspace_templates
    _copy_workspace_templates() {
        local source_dir=""
        local target_dir="${PROJECT_FOLDER}/target-root/usr/local/lib/solidgroundux/templates"
        local template_name=""

        source_dir="$(_workspace_convenience_template_dir)"

        if (( ${#WORKSPACE_SELECTED_TEMPLATES[@]} == 0 )); then
            sayinfo "No convenience templates selected for copying."
            return 0
        fi

        for template_name in "${WORKSPACE_SELECTED_TEMPLATES[@]}"; do
            [[ -f "$source_dir/$template_name" ]] || {
                sayfail "Selected convenience template not found: $source_dir/$template_name"
                return 1
            }
            _copy_template_file "$source_dir/$template_name" "$target_dir/$template_name" || return 1
            _specialize_workspace_template "$target_dir/$template_name" || return 1
        done

        return 0
    }

    # fn: _workspace_layout_file - Resolve the SDK-owned workspace layout configuration
    _workspace_layout_file() {
        local candidate=""
        local -a candidates=(
            "${SGND_FRAMEWORK_ROOT%/}/usr/local/share/solidgroundux/workspace-layout.cfg"
            "/usr/local/share/solidgroundux/workspace-layout.cfg"
        )
        for candidate in "${candidates[@]}"; do
            [[ -r "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
        done
        return 1
    }

    # fn: _get_project_directories - Resolve the standard project directory layout
    _get_project_directories() {
        local -n out_ref=$1
        local layout_file="" line="" slug=""
        layout_file="$(_workspace_layout_file)" || { sayfail "Workspace layout configuration not found: workspace-layout.cfg"; return 1; }
        slug="$(_project_slug)"; out_ref=()
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%%#*}"; line="${line%${line##*[![:space:]]}}"; line="${line#${line%%[![:space:]]*}}"
            [[ -n "$line" ]] || continue
            line="${line//\{PROJECT_NAME\}/$PROJECT_NAME}"; line="${line//\{PROJECT_SLUG\}/$slug}"
            out_ref+=( "$line" )
        done < "$layout_file"
    }

 # -- Manifest helpers
    # fn: _manifest_init - Initialize the workspace creation manifest
        # . Purpose
        #   Initialize the workspace creation manifest.
        #
        # . Behavior
        #   - Sets WORKSPACE_MANIFEST under the project root.
        #   - Writes a small manifest header with project name and timestamp.
        #   - Honors dry-run mode by reporting the intended action without writing the file.
        #
        # Inputs (globals):
        #   PROJECT_FOLDER
        #   PROJECT_NAME
        #   FLAG_DRYRUN
        #
        # Outputs (globals):
        #   WORKSPACE_MANIFEST
        #
        # . Returns
        #   0 on success
        #   Non-zero on failure
        #
        # . Usage
        #   _manifest_init "example"
    _manifest_init() {
        WORKSPACE_MANIFEST="${PROJECT_FOLDER}/.create-workspace.manifest"

        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have initialized manifest ${WORKSPACE_MANIFEST}"
            return 0
        fi

        mkdir -p "$PROJECT_FOLDER" || return 1

        {
            printf '%s\n' "# create-workspace manifest"
            printf '# project: %s\n' "$PROJECT_NAME"
            printf '# created: %(%F %T)T\n' -1
        } > "$WORKSPACE_MANIFEST" || return 1
    }

    # fn: _manifest_record_file - Record a created file in the manifest
        # . Purpose
        #   Append a file entry to the workspace manifest.
        #
        # . Arguments
        #   $1  Absolute file path
        #
        # . Behavior
        #   - Does nothing when WORKSPACE_MANIFEST is unset.
        #   - Does nothing in dry-run mode.
        #   - Appends a FILE record to the manifest.
        #
        # . Returns
        #   0 always
        #
        # . Usage
        #   _manifest_record_file "/tmp/sgnd-example"
    _manifest_record_file() {
        local path="$1"

        [[ -n "${WORKSPACE_MANIFEST:-}" ]] || return 0
        [[ "$FLAG_DRYRUN" -eq 1 ]] && return 0

        printf 'FILE|%s\n' "$path" >> "$WORKSPACE_MANIFEST"
    }

    # fn: _manifest_record_dir - Record a created directory in the manifest
        # . Purpose
        #   Append a directory entry to the workspace manifest.
        #
        # . Arguments
        #   $1  Absolute directory path
        #
        # . Behavior
        #   - Does nothing when WORKSPACE_MANIFEST is unset.
        #   - Does nothing in dry-run mode.
        #   - Appends a DIR record to the manifest.
        #
        # . Returns
        #   0 always
        #
        # . Usage
        #   _manifest_record_dir "/tmp/sgnd-example"
    _manifest_record_dir() {
        local path="$1"

        [[ -n "${WORKSPACE_MANIFEST:-}" ]] || return 0
        [[ "$FLAG_DRYRUN" -eq 1 ]] && return 0

        printf 'DIR|%s\n' "$path" >> "$WORKSPACE_MANIFEST"
    }

    # fn: _uncreate_from_manifest - Remove artifacts recorded in the create manifest
        # . Purpose
        #   Remove files and directories listed in a workspace manifest.
        #
        # . Behavior
        #   - Validates that the manifest exists.
        #   - Reads FILE and DIR entries from the manifest.
        #   - Removes files first.
        #   - Removes directories afterwards in reverse order.
        #   - Removes only empty directories by using rmdir.
        #   - Removes the manifest itself last.
        #   - Honors dry-run mode by reporting intended actions without modifying the filesystem.
        #
        # . Arguments
        #   $1  Manifest file path
        #
        # . Returns
        #   0 on success
        #   1 when the manifest does not exist
        #
        # . Usage
        #   _uncreate_from_manifest "example"
    _uncreate_from_manifest() {
        local manifest="$1"
        local line=""
        local kind=""
        local path=""
        local -a files=()
        local -a dirs=()
        local i=0

        [[ -f "$manifest" ]] || {
            sayfail "Manifest not found: $manifest"
            return 1
        }

        # Read manifest entries
        while IFS= read -r line; do
            [[ -z "$line" || "${line:0:1}" == "#" ]] && continue

            kind="${line%%|*}"
            path="${line#*|}"

            case "$kind" in
                FILE) files+=( "$path" ) ;;
                DIR)  dirs+=( "$path" ) ;;
            esac
        done < "$manifest"

        # Remove files first
        for path in "${files[@]}"; do
            if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
                sayinfo "Would have removed file $path"
            else
                if [[ -f "$path" ]]; then
                    rm -f "$path" || return 1
                    sayinfo "Removed file $path"
                fi
            fi
        done

        # Remove directories last, deepest first
        for (( i=${#dirs[@]}-1; i>=0; i-- )); do
            path="${dirs[i]}"

            if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
                sayinfo "Would have removed directory $path"
            else
                if [[ -d "$path" ]]; then
                    rmdir "$path" 2>/dev/null || true
                    sayinfo "Removed directory (if empty) $path"
                fi
            fi
        done

        # Remove manifest itself last
        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have removed manifest $manifest"
        else
            rm -f "$manifest" || return 1
            sayinfo "Removed manifest $manifest"
        fi
    }

 # -- Main sequence
    # _resolve_project_settings
        # . Purpose
        #   Resolve and confirm the project name and target folder for a new workspace.
        #
        # . Behavior
        #   - Prompts for the project name.
        #   - Prompts whether to include executable, library, and console-module components.
                #   - Derives a filesystem-safe slug from the project name.
        #   - Uses the selected components to determine a default project folder.
        #   - Prompts for the project folder.
        #   - Normalizes relative folder paths to absolute paths.
        #   - Displays a summary and asks the user to confirm, redo, or abort.
        #   - Repeats until the settings are confirmed or the user cancels.
        #
        # Outputs (globals):
        #   PROJECT_NAME
        #   PROJECT_FOLDER
        #
        # . Returns
        #   0  settings confirmed
        #   1  user aborted or an unexpected response occurred
        #
        # . Usage
        #   _resolve_project_settings
        # . Purpose
        #   Resolve project creation settings.
        #
        # . Behavior
        #
        # . Returns
        #   Returns the underlying command or workflow status.
        #
        # . Usage
        #   _resolve_project_settings
    _resolve_project_settings(){
        local slug=""
        local default_folder=""
        local default_projectname="Project"
        local lw=25
        local mxw=60
        FLAG_CREATE_MOTD="${FLAG_CREATE_MOTD:-1}"
        FLAG_GIT_INIT="${FLAG_GIT_INIT:-0}"
        FLAG_GITHUB_INIT="${FLAG_GITHUB_INIT:-0}"
        GITHUB_VISIBILITY="${GITHUB_VISIBILITY:-private}"

        while true; do
            sgnd_print
            sgnd_print_sectionheader "Project name and location" --maxwidth "$mxw"
            ask --label "Project name " --var PROJECT_NAME --default "$default_projectname" --labelwidth "$lw"
            PRODUCT_NAME="${PRODUCT_NAME:-$PROJECT_NAME}"
            PROJECT_PREFIX="${PROJECT_PREFIX:-$(_project_slug)}"
            PROJECT_GROUP="${PROJECT_GROUP:-}"
            PROJECT_SUBGROUP="${PROJECT_SUBGROUP:-}"
            ask --label "Product name " --var PRODUCT_NAME --default "$PRODUCT_NAME" --labelwidth "$lw"
            ask --label "Project prefix " --var PROJECT_PREFIX --default "$PROJECT_PREFIX" --labelwidth "$lw"
            PROJECT_DESCRIPTION="${PROJECT_DESCRIPTION:-}"
            ask --label "Description " --var PROJECT_DESCRIPTION --default "$PROJECT_DESCRIPTION" --labelwidth "$lw"
            ask --label "Group " --var PROJECT_GROUP --default "$PROJECT_GROUP" --labelwidth "$lw"
            ask --label "Subgroup " --var PROJECT_SUBGROUP --default "$PROJECT_SUBGROUP" --labelwidth "$lw"

            slug="${PROJECT_NAME// /-}"
            slug="${slug,,}"

            local resp
            local default

            PROJECT_ROOT="${PROJECT_ROOT:-$SGND_USER_HOME/dev}"
            ask --label "Project root " --var PROJECT_ROOT --default "$PROJECT_ROOT" --labelwidth "$lw"
            if [[ "$PROJECT_ROOT" != /* ]]; then
                PROJECT_ROOT="$(pwd)/$PROJECT_ROOT"
            fi

            # Project folder defaults to the stateful project root plus normalized project name.
            default_folder="${PROJECT_ROOT%/}/${slug}"
            ask --label "Project folder " --var PROJECT_FOLDER --default "$default_folder" --labelwidth "$lw"
            if [[ "$PROJECT_FOLDER" != /* ]]; then
               PROJECT_FOLDER="$(pwd)/$PROJECT_FOLDER"
            fi

            default="Y"
            (( FLAG_CREATE_MOTD )) || default="N"
            ask --label "Create project MOTD entry (Y/N)" --var resp --default "$default" --choices "Y,Yes,N,No" --labelwidth "$lw"
            resp="${resp^^}"
            [[ "$resp" == "Y" || "$resp" == "YES" ]] && FLAG_CREATE_MOTD=1 || FLAG_CREATE_MOTD=0

            # Select the installed convenience templates as part of the interactive
            # workspace settings, so the selection is visible before confirmation.
            _resolve_convenience_template_selection || return 1
            _resolve_starter_scripts || return 1

            saydebug "${slug}"

            sgnd_print
            sgnd_print_sectionheader "Version control" --maxwidth "$mxw"
            lw=35

            default="N"
            (( FLAG_GIT_INIT )) && default="Y"
            ask --label "Initialize local Git repository (Y/N)" --var resp --default "$default" --choices "Y,Yes,N,No" --labelwidth "$lw"
            resp="${resp^^}"
            [[ "$resp" == "Y" || "$resp" == "YES" ]] && FLAG_GIT_INIT=1 || FLAG_GIT_INIT=0

            default="N"
            (( FLAG_GITHUB_INIT )) && default="Y"
            ask --label "Create GitHub repository (Y/N)" --var resp --default "$default" --choices "Y,Yes,N,No" --labelwidth "$lw"
            resp="${resp^^}"
            [[ "$resp" == "Y" || "$resp" == "YES" ]] && FLAG_GITHUB_INIT=1 || FLAG_GITHUB_INIT=0

            if (( FLAG_GITHUB_INIT )); then
                FLAG_GIT_INIT=1
                GITHUB_REPO_NAME="${GITHUB_REPO_NAME:-$slug}"

                ask --label "GitHub repository name"                     --var GITHUB_REPO_NAME                     --default "$GITHUB_REPO_NAME"                     --labelwidth "$lw"

                ask_decision --label "GitHub visibility"                     --choices "private,public"                     --default "$GITHUB_VISIBILITY"                     --var GITHUB_VISIBILITY                     --displaychoices 1                     --labelwidth "$lw"
            fi

            sgnd_print 
            sgnd_print_sectionheader "Summary" --maxwidth "$mxw"

            sgnd_print_labeledvalue --label "Project name"   --value "$PROJECT_NAME"
            sgnd_print_labeledvalue --label "Product name"   --value "$PRODUCT_NAME"
            sgnd_print_labeledvalue --label "Project prefix" --value "$PROJECT_PREFIX"
            sgnd_print_labeledvalue --label "Description"    --value "${PROJECT_DESCRIPTION:--}"
            sgnd_print_labeledvalue --label "Group"          --value "$PROJECT_GROUP"
            sgnd_print_labeledvalue --label "Subgroup"       --value "${PROJECT_SUBGROUP:--}"
            sgnd_print_labeledvalue --label "Project root"   --value "$PROJECT_ROOT"
            sgnd_print_labeledvalue --label "Project folder" --value "$PROJECT_FOLDER"
            sgnd_print_labeledvalue --label "Project MOTD"    --value "$([[ ${FLAG_CREATE_MOTD:-1} -eq 1 ]] && printf yes || printf no)"
            local template_text="none"
            if (( ${#WORKSPACE_SELECTED_TEMPLATES[@]} > 0 )); then
                template_text="$(IFS=', '; printf '%s' "${WORKSPACE_SELECTED_TEMPLATES[*]}")"
            fi
            sgnd_print_labeledvalue --label "Templates"       --value "$template_text"
            sgnd_print_labeledvalue --label "Starter scripts" --value "$([[ ${FLAG_CREATE_STARTERS:-0} -eq 1 ]] && printf yes || printf no)"
            sgnd_print_labeledvalue --label "Initialize Git"  --value "$([[ ${FLAG_GIT_INIT:-0} -eq 1 ]] && printf yes || printf no)"
            sgnd_print_labeledvalue --label "Create GitHub"   --value "$([[ ${FLAG_GITHUB_INIT:-0} -eq 1 ]] && printf yes || printf no)"
            if (( ${FLAG_GITHUB_INIT:-0} )); then
                sgnd_print_labeledvalue --label "GitHub repo"       --value "$GITHUB_REPO_NAME"
                sgnd_print_labeledvalue --label "GitHub visibility" --value "$GITHUB_VISIBILITY"
            fi

            sgnd_print 
            sgnd_print_sectionheader --maxwidth "$mxw"

            ask_dlg_autocontinue \
                --seconds 15 \
                --message "Continue with these settings?" \
                --redo \
                --cancel

            case $? in
                0|1) break ;;
                2) saycancel "Aborting as per user request."; return 1 ;;
                3) PROJECT_NAME=""; PROJECT_FOLDER=""; continue ;;
                *) sayfail "Aborting (unexpected response)."; return 1 ;;
            esac
        done
    }
    
    # fn: _create_repository - Create the repository directory structure
        # . Purpose
        #   Create the project repository structure and copy template files.
        #
        # . Behavior
        #   - Creates the project root folder when needed.
        #   - Builds the standard repository-shaped workspace directory structure.
        #   - Copies only the convenience templates selected for the workspace.
        #   - Honors dry-run mode by reporting intended actions without modifying the filesystem.
        #
        # Inputs (globals):
        #   PROJECT_FOLDER
        #   PROJECT_NAME
        #   SGND_COMMON_LIB
        #   FLAG_DRYRUN
        #
        # . Returns
        #   0 on success
        #   Non-zero if required filesystem operations fail
        #
        # . Usage
        #   _create_repository
    _create_repository(){
        local d=""
        local -a dirs=()

        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have created folder ${PROJECT_FOLDER}"
        else
            if [[ ! -d "$PROJECT_FOLDER" ]]; then
                saydebug "Creating folder ${PROJECT_FOLDER}"
                mkdir -p "$PROJECT_FOLDER" || return 1
                _manifest_record_dir "${PROJECT_FOLDER}"
            fi
        fi

        _get_project_directories dirs || return 1

        for d in "${dirs[@]}"; do
            if [[ "$d" == "." ]]; then
                continue
            fi

            if [[ "$FLAG_DRYRUN" -eq 0 ]]; then
                if [[ ! -d "${PROJECT_FOLDER}/${d}" ]]; then
                    mkdir -p "${PROJECT_FOLDER}/${d}" || return 1
                    sayinfo "Created folder ${PROJECT_FOLDER}/${d}"
                    _manifest_record_dir "${PROJECT_FOLDER}/${d}"
                fi
            else
                sayinfo "Would have created folder ${PROJECT_FOLDER}/${d}"
            fi
        done

        _copy_workspace_templates || return 1
        _create_starter_scripts || return 1
    }

    # fn: _workspace_default_logo - Resolve the default logo copied into new workspaces
    _workspace_default_logo() {
        local candidate=""
        local -a candidates=(
            "${SGND_FRAMEWORK_ROOT%/}/usr/local/assets/SolidGround UX.png"
            "/usr/local/assets/SolidGround UX.png"
        )

        for candidate in "${candidates[@]}"; do
            [[ -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
        done
        return 1
    }

    # fn: _definition_value - Read one generated project definition value
    _definition_value() {
        local file="${1:?missing definitions file}" variable="${2:?missing variable}"
        bash -c 'source "$1"; printf "%s\n" "${!2-}"' _ "$file" "$variable"
    }

    # fn: _definition_description - Read the canonical Description section
    _definition_description() {
        local file="${1:?missing definitions file}"
        awk '/^# Description:/{f=1;next} f && /^# ===/{exit} f && /^#   /{sub(/^#   /,""); if ($0!="-") print}' "$file"
    }

    # fn: _create_workspace_project_files - Create README, CHANGELOG, LICENSE, and project logo
    _create_workspace_project_files() {
        local readme_file="${PROJECT_FOLDER}/README.md" changelog_file="${PROJECT_FOLDER}/CHANGELOG.md" license_file="${PROJECT_FOLDER}/LICENSE"
        local asset_dir="${PROJECT_FOLDER}/target-root/usr/local/assets" slug="" key="" definitions_file="" logo_source="" logo_name="" logo_target=""
        local title="" version="" build="" copyright="" description="" documentation_path=""
        local existed_readme=0 existed_changelog=0 existed_license=0 existed_logo=0
        slug="$(_project_slug)"; key="$(_project_key)"; definitions_file="${PROJECT_FOLDER}/target-root/usr/local/lib/solidgroundux/globals/${slug}-definitions.sh"
        logo_name="${PROJECT_PREFIX}-readmelogo.png"; logo_target="${asset_dir}/${logo_name}"; documentation_path="target-root/usr/local/share/doc/${PROJECT_NAME}/index.html"
        [[ -r "$definitions_file" ]] || { sayfail "Project definitions not found: $definitions_file"; return 1; }
        title="$(_definition_value "$definitions_file" "SGND_${key}_TITLE")" || return 1; version="$(_definition_value "$definitions_file" "SGND_${key}_VERSION")" || return 1
        build="$(_definition_value "$definitions_file" "SGND_${key}_BUILD")" || return 1; copyright="$(_definition_value "$definitions_file" "SGND_${key}_COPYRIGHT")" || return 1
        description="$(_definition_description "$definitions_file")" || return 1
        [[ -e "$readme_file" ]] && existed_readme=1; [[ -e "$changelog_file" ]] && existed_changelog=1; [[ -e "$license_file" ]] && existed_license=1; [[ -e "$logo_target" ]] && existed_logo=1
        if (( ${FLAG_DRYRUN:-0} )); then sayinfo "Would have created $readme_file"; sayinfo "Would have created $changelog_file"; sayinfo "Would have created $license_file"; return 0; fi
        mkdir -p -- "$asset_dir" || return 1
        if logo_source="$(_workspace_default_logo 2>/dev/null)"; then cp -- "$logo_source" "$logo_target" || return 1; (( existed_logo )) || _manifest_record_file "$logo_target"; else logo_name=""; saywarning "Default workspace logo not found; README created without a logo."; fi
        {
            printf '<table>\n<tr>\n'; [[ -n "$logo_name" ]] && printf '<td width="170" align="center" valign="middle">\n  <img width="96" height="96" alt="%s logo" src="target-root/usr/local/assets/%s" />\n</td>\n' "$title" "$logo_name"
            printf '<td valign="middle">\n<h1>%s</h1>\n<strong>Version %s.%s</strong>' "$title" "$version" "$build"; [[ -n "$copyright" ]] && printf ' &middot; %s' "$copyright"; printf '\n</td>\n</tr>\n</table>\n\n'
            printf '<table>\n<tr>\n<td width="33%%" align="center">\n  <a href="%s"><strong>Documentation</strong></a><br>\n  Project reference and guides\n</td>\n' "$documentation_path"
            printf '<td width="33%%" align="center">\n  <a href="CHANGELOG.md"><strong>Changelog</strong></a><br>\n  Releases and development history\n</td>\n'
            printf '<td width="33%%" align="center">\n  <a href="LICENSE"><strong>License</strong></a><br>\n  Terms of use and redistribution\n</td>\n</tr>\n</table>\n\n---\n\n'
            [[ -n "$description" ]] && printf '## About %s\n\n%s\n' "$PROJECT_NAME" "$description"
        } > "$readme_file" || return 1
        { printf '# Changelog\n\nAll notable changes to %s are documented in this file.\n\n## Unreleased\n\n### Added\n\n### Changed\n\n### Deleted\n' "${PRODUCT_NAME:-$PROJECT_NAME}"; } > "$changelog_file" || return 1
        if (( ! existed_license )); then printf 'LICENSE\n-------\n\nReplace this file with the license terms that apply to this project.\n' > "$license_file" || return 1; fi
        (( existed_readme )) || _manifest_record_file "$readme_file"; (( existed_changelog )) || _manifest_record_file "$changelog_file"; (( existed_license )) || _manifest_record_file "$license_file"
    }

    # _create_workspace_file
        # . Purpose
        #   Generate a VS Code workspace file for the new project.
        #
        # . Behavior
        #   - Creates a .code-workspace file in the project root.
        #   - Configures the project root as the workspace folder.
        #   - Adds a minimal set of editor settings and file exclusions.
        #   - Honors dry-run mode by reporting the intended action without writing the file.
        #
        # Inputs (globals):
        #   PROJECT_FOLDER
        #   PROJECT_NAME
        #   FLAG_DRYRUN
        #
        # . Side effects
        #   - Creates or overwrites:
        #       ${PROJECT_FOLDER}/${PROJECT_NAME}.code-workspace
        #
        # . Returns
        #   0 on success
        #   Non-zero if file creation fails
        #
        # . Usage
        #   _create_workspace_file
        #
        # Examples:
        #   _create_workspace_file || return 1
        #
        # Notes:
        #   - The generated workspace assumes the project root as the workspace folder.
    # fn: _create_workspace_file - Create the VS Code workspace file
        # . Purpose
        #   Create the VS Code workspace file.
        #
        # . Behavior
        #
        # . Returns
        #   Returns the underlying command or workflow status.
        #
        # . Usage
        #   _create_workspace_file
    _create_workspace_file(){
        local workspace_file="${PROJECT_FOLDER}/${PROJECT_NAME}.code-workspace"
        local existed=0

        [[ -e "$workspace_file" ]] && existed=1

        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have created workspace file ${workspace_file}" 
            return 0
        fi

        {
            printf '{\n'
            printf '  "folders": [\n'
            printf '    { "name": "%s", "path": "." }\n' "$PROJECT_NAME"
            printf '  ],\n'
            printf '  "settings": {\n'
            printf '    "files.exclude": {\n'
            printf '      "**/.git": true,\n'
            printf '      "**/.DS_Store": true\n'
            printf '    },\n'
            printf '    "terminal.integrated.cwd": "${workspaceFolder}"\n'
            printf '  }\n'
            printf '}\n'
        } > "$workspace_file" || return 1

        if (( ! existed )); then
            _manifest_record_file "$workspace_file"
        fi

        sayinfo "Created VS Code workspace file ${workspace_file}"
    }

    # _create_gitignore_file
        # . Purpose
        #   Create a standard .gitignore file in the project workspace root.
        #
        # . Behavior
        #   - Writes a predefined .gitignore containing common exclusions for
        #     Testadura / SolidGround development environments.
        #   - Covers OS artifacts, IDE metadata, logs, runtime state, build output,
        #     archives, environment files, and common backup/swap files.
        #   - Honors dry-run mode by reporting the intended action without creating the file.
        #
        # Inputs (globals):
        #   PROJECT_FOLDER
        #   FLAG_DRYRUN
        #
        # . Side effects
        #   - Creates or overwrites:
        #       ${PROJECT_FOLDER}/.gitignore
        #
        # . Returns
        #   0 on success
        #
        # . Usage
        #   _create_gitignore_file
        #
        # Examples:
        #   _create_gitignore_file
        #
        # Notes:
        #   - The ignore rules are intentionally generic and safe for most script-based projects.
    # fn: _create_gitignore_file - Create the workspace .gitignore file
        # . Purpose
        #   Create the workspace .gitignore file.
        #
        # . Behavior
        #
        # . Returns
        #   Returns the underlying command or workflow status.
        #
        # . Usage
        #   _create_gitignore_file
    _create_gitignore_file(){
        local gitignore_file="${PROJECT_FOLDER}/.gitignore"
        local existed=0

        [[ -e "$gitignore_file" ]] && existed=1

        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have created .gitignore" 
            return 0
        fi

        sayinfo "Creating .gitignore"
        saydebug "$gitignore_file"

        printf '%s\n' \
        '# --------------------------------------------------' \
        '# OS junk' \
        '# --------------------------------------------------' \
        '.DS_Store' \
        'Thumbs.db' \
        '*~' \
        '' \
        '# --------------------------------------------------' \
        '# Editors / IDE' \
        '# --------------------------------------------------' \
        '.vscode/*' \
        '!.vscode/settings.json' \
        '!.vscode/extensions.json' \
        '.idea/' \
        '' \
        '# --------------------------------------------------' \
        '# Logs' \
        '# --------------------------------------------------' \
        '*.log' \
        'logs/' \
        '' \
        '# --------------------------------------------------' \
        '# Runtime / state' \
        '# --------------------------------------------------' \
        '*.state' \
        '*.pid' \
        '*.lock' \
        'tmp/' \
        'temp/' \
        '' \
        '# --------------------------------------------------' \
        '# Build / packaging' \
        '# --------------------------------------------------' \
        'build/' \
        'dist/' \
        'release/' \
        '' \
        '# --------------------------------------------------' \
        '# Archives' \
        '# --------------------------------------------------' \
        '*.zip' \
        '*.tar' \
        '*.tar.gz' \
        '*.tgz' \
        '' \
        '# --------------------------------------------------' \
        '# Environment / secrets' \
        '# --------------------------------------------------' \
        '.env' \
        '.env.*' \
        '' \
        '# --------------------------------------------------' \
        '# Misc' \
        '# --------------------------------------------------' \
        '*.bak' \
        '*.swp' \
        '*.swo' \
        > "$gitignore_file" || return 1

        if (( ! existed )); then
            _manifest_record_file "$gitignore_file"
        fi
    }

    # fn: _create_releaseignore_file - Create the workspace .release-ignore file
    _create_releaseignore_file(){
        local releaseignore_file="${PROJECT_FOLDER}/.release-ignore"
        local existed=0

        [[ -e "$releaseignore_file" ]] && existed=1

        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have created .release-ignore"
            return 0
        fi

        sayinfo "Creating .release-ignore"
        saydebug "$releaseignore_file"

        printf '%s\n' \
        '# SolidGroundUX release exclusions' \
        '' \
        '# Local/editor/runtime metadata' \
        '.*' \
        '*.state' \
        '*.cfg' \
        '*.code-workspace' \
        '' \
        '# Runtime data that must not be packaged' \
        '/var/log/solidgroundux.log*' \
        '/var/lib/solidgroundux/archive/' \
        '/var/lib/solidgroundux/releases/' \
        '/var/lib/solidgroundux/projects/' \
        > "$releaseignore_file" || return 1

        if (( ! existed )); then
            _manifest_record_file "$releaseignore_file"
        fi
    }

    # fn: _project_slug - Return the filesystem-safe project slug
        # . Usage
        #   _project_slug
    _project_slug() {
        local slug="${PROJECT_NAME// /-}"
        slug="${slug,,}"
        slug="$(printf '%s' "$slug" | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//')"
        printf '%s\n' "$slug"
    }

    # fn: _project_key - Return the variable-safe project key
        # . Usage
        #   _project_key
    _project_key() {
        local key="${PROJECT_NAME^^}"
        key="$(printf '%s' "$key" | sed -E 's/[^A-Z0-9]+/_/g; s/^_+//; s/_+$//')"
        printf '%s\n' "$key"
    }

    # fn: _create_project_definitions - Create project-wide definition globals
        # . Purpose
        #   Create <project>-definitions.sh in the deployable SolidGroundUX globals folder.
        # . Usage
        #   _create_project_definitions
    _create_project_definitions() {
        local slug="" key="" definitions_file="" build="" existed=0
        slug="$(_project_slug)"
        key="$(_project_key)"
        build="$(date +%y%j%H)"
        definitions_file="${PROJECT_FOLDER}/target-root/usr/local/lib/solidgroundux/globals/${slug}-definitions.sh"
        [[ -e "$definitions_file" ]] && existed=1

        if (( ${FLAG_DRYRUN:-0} )); then
            sayinfo "Would have created project definitions: $definitions_file"
            return 0
        fi

        mkdir -p -- "$(dirname -- "$definitions_file")" || return 1
        {
            printf '%s\n' '#!/usr/bin/env bash'
            printf '# =====================================================================================\n'
            printf '# %s - Project Definitions\n' "${PRODUCT_NAME:-$PROJECT_NAME}"
            printf '# -------------------------------------------------------------------------------------\n'
            printf '# Metadata:\n'
            printf '#   Version     : 1.0\n'
            printf '#   Build       : %s\n' "$build"
            printf '#   Checksum    : -\n'
            printf '#   Source      : %s-definitions.sh\n' "$slug"
            printf '#   Type        : library\n'
            printf '#   Group       : Globals\n'
            printf '#   Purpose     : Project-wide identity and release globals\n'
            printf '# Description:\n'
            if [[ -n "${PROJECT_DESCRIPTION:-}" ]]; then printf '#   %s\n' "$PROJECT_DESCRIPTION"; else printf '#   -\n'; fi
            printf '# =====================================================================================\n'
            printf 'SGND_%s_PRODUCT=%q\n' "$key" "${PRODUCT_NAME:-$PROJECT_NAME}"
            printf 'SGND_%s_TITLE=%q\n' "$key" "${PRODUCT_NAME:-$PROJECT_NAME}"
            printf 'SGND_%s_VERSION=%q\n' "$key" "1.0"
            printf 'SGND_%s_BUILD=%q\n' "$key" "$build"
            printf 'SGND_%s_COMPANY=%q\n' "$key" "${SGND_COMPANY:-Testadura Consultancy}"
            printf 'SGND_%s_COPYRIGHT=%q\n' "$key" "${SGND_COPYRIGHT:-}"
            printf 'SGND_%s_LICENSE=%q\n' "$key" "${SGND_LICENSE:-}"
            printf 'SGND_%s_DOCUMENTATION=%q\n' "$key" ""
            printf 'SGND_%s_APPENDICES=%q\n' "$key" "attribution,license,changelog"
            printf 'SGND_%s_RELEASE_EXCLUDES=%q\n' "$key" "usr/local/lib/solidgroundux/templates"
        } > "$definitions_file" || return 1

        (( existed )) || _manifest_record_file "$definitions_file"
        sayinfo "Created project definitions: $definitions_file"
    }

    # fn: _create_project_motd - Create a minimal project MOTD identity entry
        # . Usage
        #   _create_project_motd
    _create_project_motd() {
        local slug="" key="" motd_file="" definitions_installed=""
        (( ${FLAG_CREATE_MOTD:-1} )) || return 0
        slug="$(_project_slug)"
        key="$(_project_key)"
        motd_file="${PROJECT_FOLDER}/target-root/etc/update-motd.d/95-${slug}"
        definitions_installed="/usr/local/lib/solidgroundux/globals/${slug}-definitions.sh"

        if (( ${FLAG_DRYRUN:-0} )); then
            sayinfo "Would have created project MOTD: $motd_file"
            return 0
        fi

        mkdir -p -- "$(dirname -- "$motd_file")" || return 1
        {
            printf '%s\n' '#!/usr/bin/env bash'
            printf 'definitions=%q\n' "$definitions_installed"
            printf '[[ -r "$definitions" ]] || exit 0\n'
            printf '# shellcheck source=/dev/null\n'
            printf 'source "$definitions"\n'
            printf 'printf '\''%%s %%s.%%s\\n'\'' "$SGND_%s_PRODUCT" "$SGND_%s_VERSION" "$SGND_%s_BUILD"\n' "$key" "$key" "$key"
        } > "$motd_file" || return 1

        chmod 0755 -- "$motd_file" || return 1
        _manifest_record_file "$motd_file"
        sayinfo "Created project MOTD: $motd_file"
    }

    # fn: _create_empty_directory_placeholders - Preserve the canonical workspace tree in Git
    _create_empty_directory_placeholders() {
        local dir="" keep=""
        if (( ${FLAG_DRYRUN:-0} )); then sayinfo "Would have created .gitkeep files in empty workspace directories."; return 0; fi
        while IFS= read -r -d '' dir; do
            if [[ -z "$(find "$dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then keep="$dir/.gitkeep"; : > "$keep" || return 1; _manifest_record_file "$keep"; fi
        done < <(find "$PROJECT_FOLDER/target-root" "$PROJECT_FOLDER/user-root" -type d -print0 2>/dev/null)
    }

    # fn: _initialize_git_repository - Initialize and commit the new workspace
        # . Purpose
        #   Initialize a local Git repository using main as the primary branch.
        #
        # . Behavior
        #   - Does nothing unless FLAG_GIT_INIT=1.
        #   - Leaves an existing .git repository intact.
        #   - Creates an initial commit containing the generated workspace when possible.
        #   - Reports missing Git identity as a failure rather than silently creating
        #     an uncommitted repository.
        # . Usage
        #   _initialize_git_repository
    _initialize_git_repository() {
        (( ${FLAG_GIT_INIT:-0} )) || return 0

        command -v git >/dev/null 2>&1 || {
            sayfail "Git is required to initialize the repository."
            return 1
        }

        if (( ${FLAG_DRYRUN:-0} )); then
            sayinfo "Would initialize Git repository in $PROJECT_FOLDER with branch main."
            sayinfo "Would stage generated files and create the initial commit."
            return 0
        fi

        if [[ ! -d "$PROJECT_FOLDER/.git" ]]; then
            if git -C "$PROJECT_FOLDER" init -b main >/dev/null 2>&1; then
                :
            else
                git -C "$PROJECT_FOLDER" init >/dev/null || return 1
                git -C "$PROJECT_FOLDER" branch -M main || return 1
            fi
            sayinfo "Initialized Git repository: $PROJECT_FOLDER"
        else
            sayinfo "Git repository already exists: $PROJECT_FOLDER"
            git -C "$PROJECT_FOLDER" branch -M main >/dev/null 2>&1 || true
        fi

        git -C "$PROJECT_FOLDER" add -A || return 1

        if git -C "$PROJECT_FOLDER" diff --cached --quiet; then
            sayinfo "No Git changes require an initial commit."
            return 0
        fi

        if ! git -C "$PROJECT_FOLDER" commit -m "Initial project scaffold" >/dev/null; then
            sayfail "Could not create the initial Git commit. Check git user.name and user.email."
            return 1
        fi

        sayinfo "Created initial Git commit."
        return 0
    }

    # fn: _initialize_github_repository - Create and push the workspace repository
        # . Purpose
        #   Create a GitHub repository using the authenticated gh CLI account.
        #
        # . Behavior
        #   - Does nothing unless FLAG_GITHUB_INIT=1.
        #   - Requires a successfully initialized local Git repository.
        #   - Requires gh to be installed and authenticated.
        #   - Creates origin for a new repository, then explicitly pushes main.
        #   - If origin already exists, does not recreate the remote and only pushes main.
        # . Usage
        #   _initialize_github_repository
    _initialize_github_repository() {
        local visibility_flag="--private"
        local github_account=""
        local confirm="Y"

        (( ${FLAG_GITHUB_INIT:-0} )) || return 0

        command -v gh >/dev/null 2>&1 || {
            sayfail "GitHub CLI (gh) is required to create a GitHub repository."
            return 1
        }

        gh auth status >/dev/null 2>&1 || {
            sayfail "GitHub CLI is not authenticated. Run: gh auth login"
            return 1
        }

        github_account="$(gh api user --jq '.login' 2>/dev/null || true)"
        [[ -n "$github_account" ]] || {
            sayfail "Could not determine the authenticated GitHub account."
            return 1
        }

        GITHUB_VISIBILITY="${GITHUB_VISIBILITY:-private}"
        GITHUB_VISIBILITY="${GITHUB_VISIBILITY,,}"

        case "$GITHUB_VISIBILITY" in
            public)  visibility_flag="--public" ;;
            private) visibility_flag="--private" ;;
            *)
                sayfail "Invalid GitHub visibility: ${GITHUB_VISIBILITY:-}"
                return 1
                ;;
        esac

        sgnd_print
        sgnd_print_sectionheader "GitHub repository" --padend 60
        sgnd_print_labeledvalue --label "GitHub account" --value "$github_account"
        sgnd_print_labeledvalue --label "Repository"     --value "$GITHUB_REPO_NAME"
        sgnd_print_labeledvalue --label "Visibility"     --value "$GITHUB_VISIBILITY"
        sgnd_print_labeledvalue --label "Branch"         --value "main"
        sgnd_print

        if (( ${FLAG_DRYRUN:-0} )); then
            sayinfo "Would create GitHub repository ${github_account}/${GITHUB_REPO_NAME} and push main."
            return 0
        fi

        if (( ! ${FLAG_AUTO:-0} )); then
            sgnd_print_sectionheader --padend 60
            ask --label "Create repository and push to GitHub (Y/N)" \
                --var confirm \
                --default "Y" \
                --choices "Y,Yes,N,No"
            sgnd_print

            case "${confirm^^}" in
                Y|YES) ;;
                *)
                    saycancel "GitHub repository creation cancelled."
                    return 0
                    ;;
            esac
        fi

        if git -C "$PROJECT_FOLDER" remote get-url origin >/dev/null 2>&1; then
            sayinfo "Git remote origin already exists; skipping GitHub repository creation."
            git -C "$PROJECT_FOLDER" push -u origin main || return 1
            sayinfo "Pushed main to existing origin."
            return 0
        fi

        gh repo create "$GITHUB_REPO_NAME" \
            --source "$PROJECT_FOLDER" \
            "$visibility_flag" \
            --remote origin || {
                sayfail "GitHub repository creation failed."
                return 1
            }

        git -C "$PROJECT_FOLDER" push -u origin main || {
            sayfail "GitHub repository was created, but pushing main failed."
            return 1
        }

        sayok "Created GitHub repository and pushed main: ${github_account}/${GITHUB_REPO_NAME}"
        return 0
    }

# - Main ----------------------------------------------------------------------------
    # main
        # . Purpose
        #   Execute the workspace creation or uncreation workflow.
        #
        # . Behavior
        #   - Loads the framework bootstrapper.
        #   - Initializes the framework runtime via sgnd_bootstrap.
        #   - Executes builtin framework argument handling.
        #   - Normalizes project selection flags.
        #   - Prepares the standard UI state and title bar.
        #   - In uncreate mode:
        #       - validates the workspace manifest
        #       - confirms removal with the user
        #       - removes files and directories listed in the manifest
        #   - In normal mode:
        #       - resolves project settings interactively
        #       - initializes the workspace manifest
        #       - creates the repository structure, workspace file, .gitignore, and .release-ignore
        #       - creates project definitions and optionally a project MOTD entry
#       - optionally initializes Git and creates/pushes a GitHub repository
        #       - applies final ownership and permission fixes when not in dry-run mode.
        #
        # . Arguments
        #   $@  Framework and script-specific command-line arguments
        #
        # . Returns
        #   Exits with the resulting status produced by bootstrap or script logic
        #
        # . Usage
        #   main "$@"
        #
        # Examples:
        #   main "$@"
        #
        # Notes:
        #   - sgnd_bootstrap splits framework arguments from script arguments automatically.
    # fn: main - Run the executable main sequence
        # . Purpose
        #   Run the executable main sequence.
        #
        # . Behavior
        #
        # . Returns
        #   Returns the underlying command or workflow status.
        #
        # . Usage
        #   main
    main() {
        # -- Startup
            _framework_locator || exit $?
            sgnd_exe_start --autostate -- "$@"

        # -- Main script logic
          # -- Uncreate mode
            if (( ${FLAG_UNCREATE:-0} )); then
                if [[ -z "${PROJECT_FOLDER:-}" ]]; then
                    sayfail "Uncreate requires --folder <workspace>"
                    exit 1
                fi

                if [[ "$PROJECT_FOLDER" != /* ]]; then
                    PROJECT_FOLDER="$(pwd)/$PROJECT_FOLDER"
                fi

                local manifest="${PROJECT_FOLDER}/.create-workspace.manifest"

                [[ -f "$manifest" ]] || {
                    sayfail "Manifest not found: $manifest"
                    exit 1
                }

                saywarning "About to remove workspace items listed in manifest:"
                saywarning "$manifest"

                ask_ok_redo_quit "Proceed with uncreate?" 10
                case $? in
                    0) ;;
                    1) exit 0 ;;
                    2) saycancel "Aborted."; exit 0 ;;
                esac

                _uncreate_from_manifest "$manifest" || exit $?

                sayok "Uncreate completed"
                exit 0
            fi
          # -- 'Normal' operation
            # Resolve settings (0=OK, 1=abort, 2=skip template)
            if _resolve_project_settings; then
                proceed=0
            else
                proceed=$?
            fi    

            # User aborted
            if [[ "$proceed" -eq 1 ]]; then
                exit 0
            fi

            # For 0 (OK) and 2 (skip template) we still create repo + workspace
            _manifest_init || exit $?
            _create_repository || exit $?
            _create_workspace_file || exit $?
            _create_gitignore_file || exit $?
            _create_releaseignore_file || exit $?
            _create_project_definitions || exit $?
            _create_workspace_project_files || exit $?
            _create_project_motd || exit $?
            _create_empty_directory_placeholders || exit $?

            if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
                sayinfo "Would have fixed ownership and permissions"
            else 
                saydebug "Fixing ownership and permissions $PROJECT_FOLDER"
                sgnd_fix_ownership "${PROJECT_FOLDER}"
                sgnd_fix_permissions "${PROJECT_FOLDER}"
            fi

            _initialize_git_repository || exit $?
            _initialize_github_repository || exit $?

            if (( ! ${FLAG_AUTO:-0} )); then
                sgnd_print
                sgnd_print_sectionheader "Workspace creation complete" --padend 60
                sgnd_print
                if command -v tree >/dev/null 2>&1; then
                    tree "$PROJECT_FOLDER"
                else
                    find "$PROJECT_FOLDER" -print
                fi
                sgnd_print
                sgnd_print_sectionheader "" --padend 60
                ask_dlg_autocontinue \
                    --seconds 10 \
                    --message "Press Enter to end." \
                    --hidelegend || true
            fi
    }

    # Entrypoint: sgnd_bootstrap will split framework args from script args.
    main "$@"

