#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX SDK - Create Wrappers
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626710
#   Checksum    : 528a6c64c08ba8cac6d5fb949ea330579e7d362cb1c588c54139d2843150ec3d
#   Source      : create-wrappers.sh
#   Type        : script
#   Group       : SDK
#   Purpose     : Create framework-relative command wrappers for SolidGroundUX scripts.
#
# Description:
#   Creates one or more command wrappers from SolidGroundUX scripts. Source files are
#   selected from a source directory using a filename or shell mask. Generated wrappers
#   are rendered from the canonical wrapper-template and resolve the active SolidGroundUX
#   framework tree from the wrapper path before launching their configured target.
#
#   Wrapper names:
#     - Optional Metadata/Wrapper overrides the generated command name.
#     - Otherwise script.sh -> sgnd-script and sgnd-script.sh -> sgnd-script.
#
#   Wrapper target directories:
#     - <selected-framework-root>/usr/local/bin  (default)
#     - <selected-framework-root>/usr/local/sbin
#
# Design principles:
#   - Generated wrappers remain environment-independent.
#   - The source directory determines the framework tree that owns the wrappers.
#   - Wrapper targets are stored relative to that selected framework root.
#   - Wrapper execution follows the active self-locating framework tree.
#   - Existing wrappers are not overwritten without confirmation.
#   - A filename or mask may select one or multiple source scripts.
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# =====================================================================================

set -uo pipefail

# - Bootstrap ------------------------------------------------------------------------
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
# - Script identity ------------------------------------------------------------------
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"

# - Framework integration ------------------------------------------------------------
    SGND_USING=(
    )

    SGND_ARGS_SPEC=(
        "auto|a|flag|FLAG_AUTO|Repeat with last settings|0|"
        "source|s|value|SOURCE_DIR|Source directory containing scripts|"
        "mask|m|value|SOURCE_MASK|Filename or shell mask to select scripts|*.sh"
        "target|t|enum|TARGET_KIND|Wrapper target directory: bin or sbin|bin,sbin"
        "overwrite|o|flag|FLAG_OVERWRITE|Overwrite existing wrappers without confirmation|0|"
    )

    SGND_SCRIPT_EXAMPLES=(
        "Create wrappers interactively:"
        "  $SGND_SCRIPT_NAME"
        ""
        "Create wrappers for all shell scripts in one directory:"
        "  $SGND_SCRIPT_NAME --source /path/to/scripts --mask '*.sh' --target bin"
        ""
        "Create one wrapper:"
        "  $SGND_SCRIPT_NAME --source /path/to/scripts --mask prepare-release.sh"
    )

    SGND_SCRIPT_GLOBALS=(
    )

    SGND_STATE_VARIABLES=(
        SOURCE_DIR
        SOURCE_MASK
        TARGET_KIND
        FLAG_OVERWRITE
    )

    SGND_ON_EXIT_HANDLERS=(
    )

    SGND_STATE_SAVE=1

# - Helpers --------------------------------------------------------------------------
    # fn: _framework_path - Resolve a path beneath a framework root
        # . Purpose
        #   Convert a framework-relative path to an absolute path beneath the supplied
        #   framework root. Defaults to the active SGND_FRAMEWORK_ROOT.
        # . Arguments
        #   $1 Relative path.
        #   $2 Framework root (optional).
        # . Returns
        #   0 always.
        # . Usage
        #   path="$(_framework_path "usr/local/bin" "$root")"
    _framework_path() {
        local relative="${1#/}"
        local root="${2:-$SGND_FRAMEWORK_ROOT}"

        if [[ "$root" == "/" ]]; then
            printf '/%s\n' "$relative"
        else
            printf '%s/%s\n' "${root%/}" "$relative"
        fi
    }

    # fn: _framework_root_from_path - Resolve the framework root owning a selected path
        # . Purpose
        #   Derive the canonical SolidGroundUX framework root from an absolute source path,
        #   using the same last usr/etc/var component rule as _framework_locator().
        # . Returns
        #   0 with the resolved root on stdout; 1 when the path cannot be resolved.
        # . Usage
        #   _framework_root_from_path "<path>" "<framework_root>"
    _framework_root_from_path() {
        local path="${1:-}"
        local absolute=""
        local path_without_root=""
        local component=""
        local root=""
        local index=0
        local root_index=-1
        local -a path_parts=()

        [[ -n "$path" ]] || return 1
        absolute="$(readlink -f "$path")" || return 1
        path_without_root="${absolute#/}"
        IFS='/' read -r -a path_parts <<< "$path_without_root"

        for index in "${!path_parts[@]}"; do
            component="${path_parts[$index]}"
            case "$component" in
                usr|etc|var) root_index=$index ;;
            esac
        done

        (( root_index >= 0 )) || return 1

        if (( root_index == 0 )); then
            printf '/\n'
            return 0
        fi

        for (( index=0; index<root_index; index++ )); do
            root+="/${path_parts[$index]}"
        done
        printf '%s\n' "$root"
    }

    # fn: _wrapper_template_path - Resolve the canonical wrapper template path
        # . Purpose
        #   Resolve the wrapper template beneath SGND_FRAMEWORK_ROOT.
        # . Returns
        #   0 with the template path on stdout.
        # . Usage
        #   template="$(_wrapper_template_path)"
    _wrapper_template_path() {
        local relative="usr/local/lib/solidgroundux/templates/wrapper-template"

        if [[ "$SGND_FRAMEWORK_ROOT" == "/" ]]; then
            printf '/%s\n' "$relative"
        else
            printf '%s/%s\n' "${SGND_FRAMEWORK_ROOT%/}" "$relative"
        fi
    }

    # fn: _relative_to_framework_root - Convert an absolute source path to framework-relative
        # . Purpose
        #   Ensure a selected source belongs to the supplied framework root and return its
        #   normalized path relative to that root.
        # . Returns
        #   0 when source is beneath the framework root; 1 otherwise.
        # . Usage
        #   rel="$(_relative_to_framework_root "$file")"
    _relative_to_framework_root() {
        local file="${1:-}"
        local framework_root="${2:-$SGND_FRAMEWORK_ROOT}"
        local root="${framework_root%/}"
        local absolute=""

        [[ -n "$file" ]] || return 1
        absolute="$(readlink -f "$file")" || return 1

        if [[ "$SGND_FRAMEWORK_ROOT" == "/" ]]; then
            printf '%s\n' "${absolute#/}"
            return 0
        fi

        case "$absolute" in
            "$root"/*)
                printf '%s\n' "${absolute#"$root"/}"
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    }

    # fn: _wrapper_name_for_script - Return the public wrapper command name
        # . Purpose
        #   Resolve an optional Metadata/Wrapper override, falling back to the current
        #   sgnd-<script> naming convention when no override is present.
        #
        # . Returns
        #   0 with the wrapper name on stdout.
        #
        # . Usage
        #   name="$(_wrapper_name_for_script "$file")"
    _wrapper_name_for_script() {
        local file="${1:-}"
        local base=""
        local wrapper_name=""

        if [[ -n "$file" ]] && sgnd_header_get_field "$file" "Metadata" "Wrapper" wrapper_name 2>/dev/null; then
            wrapper_name="${wrapper_name#"${wrapper_name%%[![:space:]]*}"}"
            wrapper_name="${wrapper_name%"${wrapper_name##*[![:space:]]}"}"
            if [[ -n "$wrapper_name" ]]; then
                printf '%s\n' "$wrapper_name"
                return 0
            fi
        fi

        base="$(basename -- "$file")"
        base="${base%.sh}"
        if [[ "$base" == sgnd-* ]]; then
            printf '%s\n' "$base"
        else
            printf 'sgnd-%s\n' "$base"
        fi
    }

    # fn: _write_wrapper - Create one framework-relative wrapper
        # . Purpose
        #   Generate a wrapper from the canonical wrapper template.
        # . Behavior
        #   - Resolves the source path relative to SGND_FRAMEWORK_ROOT.
        #   - Loads the canonical wrapper template from SGND_FRAMEWORK_ROOT.
        #   - Replaces the <target> placeholder with the framework-relative target.
        #   - Preserves overwrite and dry-run behavior.
        # . Returns
        #   0 on success; 1 on failure or declined overwrite.
        # . Usage
        #   _write_wrapper "$source" "$wrapper"
    _write_wrapper() {
        local source="${1:-}"
        local wrapper="${2:-}"
        local framework_root="${3:-$SGND_FRAMEWORK_ROOT}"
        local relative_target=""
        local template=""
        local line=""

        relative_target="$(_relative_to_framework_root "$source" "$framework_root")" || {
            sayfail "Source is outside selected framework root ($framework_root): $source"
            return 1
        }

        template="$(_wrapper_template_path)"
        [[ -r "$template" ]] || {
            sayfail "Wrapper template is not readable: $template"
            return 1
        }

        if [[ -e "$wrapper" || -L "$wrapper" ]]; then
            if (( ! ${FLAG_OVERWRITE:-0} )); then
                saywarning "Skipped existing wrapper: $wrapper"
                return 0
            fi
        fi

        if (( ${FLAG_DRYRUN:-0} )); then
            sayinfo "[DRYRUN] Would create wrapper from $template: $wrapper -> $relative_target"
            return 0
        fi

        mkdir -p -- "$(dirname -- "$wrapper")" || return 1

        : > "$wrapper" || return 1
        while IFS= read -r line || [[ -n "$line" ]]; do
            printf '%s\n' "${line//<target>/$relative_target}" >> "$wrapper" || return 1
        done < "$template"

        chmod 0755 -- "$wrapper" || return 1
        sayok "Created wrapper: $wrapper -> $relative_target"
        return 0
    }

    # fn: _get_parameters - Collect wrapper-generation parameters
        # . Purpose
        #   Resolve source selection and wrapper target directory.
        # . Returns
        #   0 on success; 1 on cancellation/invalid input.
        # . Usage
        #   _get_parameters
    _get_parameters() {
        local lw=22
        local lp=4

        if [[ "$SGND_FRAMEWORK_ROOT" == "/" ]]; then
            SOURCE_DIR="${SOURCE_DIR:-/usr/local/libexec/solidgroundux}"
        else
            SOURCE_DIR="${SOURCE_DIR:-${SGND_FRAMEWORK_ROOT%/}/usr/local/libexec/solidgroundux}"
        fi
        SOURCE_MASK="${SOURCE_MASK:-*.sh}"
        TARGET_KIND="${TARGET_KIND:-bin}"
        FLAG_OVERWRITE="${FLAG_OVERWRITE:-0}"

        sgnd_state_load_keys --array SGND_STATE_VARIABLES || return $?

        if (( ${FLAG_AUTO:-0} )); then
            return 0
        fi

        sgnd_print
        sgnd_print_sectionheader "Wrapper source" --padend 0

        ask --label "Source directory" \
            --var SOURCE_DIR \
            --default "$SOURCE_DIR" \
            --validate sgnd_validate_dir_exists \
            --colorize both \
            --labelclr "${CYAN}" \
            --pad "$lp" \
            --labelwidth "$lw"

        ask --label "Filename or mask" \
            --var SOURCE_MASK \
            --default "$SOURCE_MASK" \
            --colorize both \
            --labelclr "${CYAN}" \
            --pad "$lp" \
            --labelwidth "$lw"

        ask_decision --label "Target directory" \
            --choices "bin,sbin" \
            --default "$TARGET_KIND" \
            --var TARGET_KIND \
            --displaychoices 1 \
            --colorize both \
            --labelclr "${CYAN}" \
            --pad "$lp" \
            --labelwidth "$lw"

        local overwrite="N"
        (( FLAG_OVERWRITE )) && overwrite="Y"

        ask --label "Overwrite existing wrappers (Y/N)" \
            --var overwrite \
            --default "$overwrite" \
            --choices "Y,Yes,N,No" \
            --colorize both \
            --labelclr "${CYAN}" \
            --pad "$lp" \
            --labelwidth "$lw"

        case "${overwrite^^}" in
            Y|YES) FLAG_OVERWRITE=1 ;;
            *)     FLAG_OVERWRITE=0 ;;
        esac

        return 0
    }

    # fn: _create_wrappers - Create wrappers for selected scripts
        # . Purpose
        #   Match selected scripts and create canonical sgnd-* wrappers.
        # . Returns
        #   0 when all matching wrappers are handled successfully; 1 otherwise.
        # . Usage
        #   _create_wrappers
    _create_wrappers() {
        local target_root=""
        local selected_framework_root=""
        local source=""
        local wrapper_name=""
        local wrapper=""
        local matched=0
        local failed=0

        selected_framework_root="$(_framework_root_from_path "$SOURCE_DIR")" || {
            sayfail "Cannot determine framework root from source directory: $SOURCE_DIR"
            return 1
        }

        case "${TARGET_KIND,,}" in
            bin)
                target_root="$(_framework_path "usr/local/bin" "$selected_framework_root")"
                ;;
            sbin)
                target_root="$(_framework_path "usr/local/sbin" "$selected_framework_root")"
                ;;
            *)
                sayfail "Invalid wrapper target directory: $TARGET_KIND"
                return 1
                ;;
        esac

        while IFS= read -r -d '' source; do
            (( matched++ ))

            wrapper_name="$(_wrapper_name_for_script "$source")"
            wrapper="${target_root%/}/$wrapper_name"

            _write_wrapper "$source" "$wrapper" "$selected_framework_root" || failed=1
        done < <(
            find "$SOURCE_DIR" \
                -mindepth 1 \
                -maxdepth 1 \
                -type f \
                -name "$SOURCE_MASK" \
                -print0 2>/dev/null
        )

        if (( matched == 0 )); then
            saywarning "No files matched: ${SOURCE_DIR%/}/$SOURCE_MASK"
            return 1
        fi

        if (( failed )); then
            sayfail "One or more wrappers could not be created."
            return 1
        fi

        sayok "Wrapper generation complete: $matched source file(s) processed."
        return 0
    }

# - Main -----------------------------------------------------------------------------
    # fn: main - Run wrapper generation
        # . Purpose
        #   Initialize SolidGroundUX and create selected command wrappers.
        # . Usage
        #   main "$@"
    main() {
        _framework_locator || exit $?
        sgnd_exe_start --state -- "$@"

        _get_parameters || exit $?
        _create_wrappers || exit $?
    }

    main "$@"
