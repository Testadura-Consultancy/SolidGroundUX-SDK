#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX SDK - Canonical Structure Normalizer
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626414
#   Checksum    : 7ed0ee2c1b287a207a6bf3fc3e3bba3257eb8105468610f9fe05e30feaf6b01c
#   Source      : normalize-canon.sh
#   Type        : script
#   Group       : SDK
#   Subgroup    : Development
#   Purpose     : Replace canonical bootstrap and library-guard structures in shell files.
#
# Description:
#   Applies canonical SolidGroundUX structural fragments to one or more shell files.
#   Files are classified from their contents: _framework_locator() identifies an
#   executable bootstrap target, while _sgnd_lib_guard() identifies a source-only
#   library or console module. Files containing neither target are skipped; files
#   containing both are rejected.
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# =====================================================================================
set -uo pipefail

# - Bootstrap -----------------------------------------------------------------------
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
        #   - Loads sgnd-exe-common.sh from the resolved framework root.
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
        fi

        [[ -r "$exe_common" ]] || {
            printf 'FATAL: Cannot read executable common library: %s\n' "$exe_common" >&2
            return 126
        }

        # shellcheck source=/dev/null
        source "$exe_common"
    }

# - Script identity -----------------------------------------------------------------
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"
    SGND_SCRIPT_TITLE="Canonical Structure Normalizer"

# - Framework integration -----------------------------------------------------------
    SGND_USING=()
    SGND_ARGS_SPEC=(
        "auto|a|flag|FLAG_AUTO|Run using command-line inputs or saved parameters|0|"
    )
    SGND_SCRIPT_EXAMPLES=(
        "  $SGND_SCRIPT_NAME /path/to/file.sh"
        "  $SGND_SCRIPT_NAME '/path/to/project/**/*.sh'"
        "  $SGND_SCRIPT_NAME '/path/to/project/usr/local/lib/**/*.sh'"
    )
    SGND_SCRIPT_GLOBALS=()
    SGND_STATE_VARIABLES=(
        SGND_CANON_INPUT
    )
    SGND_ON_EXIT_HANDLERS=()
    SGND_STATE_SAVE=0

# - Local script declarations -------------------------------------------------------
    SGND_CANON_DIRECTORY=""
    SGND_CANON_LOCATOR=""
    SGND_CANON_LIB_GUARD=""
    SGND_CANON_INPUT=""
    SGND_CANON_CLI_INPUTS=()

# - Parameter collection ------------------------------------------------------------
    # fn$ _collect_cli_inputs - Collect positional file and mask arguments
        # . Purpose
        #   Preserve positional file and mask arguments as explicit runtime inputs while
        #   excluding the script-specific --auto switch from the collected values.
        #
        # . Arguments
        #   $@  Original executable arguments.
        #
        # . Outputs (globals)
        #   SGND_CANON_CLI_INPUTS
        #
        # . Returns
        #   0 after command-line inputs have been collected.
        #
        # . Usage
        #   _collect_cli_inputs "$@"
    _collect_cli_inputs() {
        local arg=""

        SGND_CANON_CLI_INPUTS=()
        for arg in "$@"; do
            case "$arg" in
                --auto|-a)
                    ;;
                --*)
                    # Framework built-ins are handled by sgnd_exe_start. They are not
                    # file/mask defaults for this script.
                    ;;
                -*)
                    ;;
                *)
                    SGND_CANON_CLI_INPUTS+=("$arg")
                    ;;
            esac
        done
        return 0
    }

    # fn$ _get_parameters - Resolve interactive or automatic normalization inputs
        # . Purpose
        #   Resolve the file or mask used for canonical normalization, using explicit
        #   command-line inputs as the highest-priority values and saved state as the
        #   fallback for --auto execution.
        #
        # . Behavior
        #   - Loads SGND_CANON_INPUT from script state when available.
        #   - Uses positional command-line inputs as defaults in interactive mode.
        #   - In --auto mode, uses positional command-line inputs when supplied.
        #   - In --auto mode without positional inputs, uses the saved SGND_CANON_INPUT.
        #   - In interactive mode, prompts with ask and saves the confirmed value.
        #
        # . Outputs (globals)
        #   SGND_CANON_INPUT
        #   SGND_CANON_CLI_INPUTS
        #
        # . Returns
        #   0 when usable input has been resolved; 2 when auto mode has no usable input.
        #
        # . Usage
        #   _get_parameters
    _get_parameters() {
        local cli_default=""

        if (( ${#SGND_CANON_CLI_INPUTS[@]} > 0 )); then
            cli_default="${SGND_CANON_CLI_INPUTS[0]}"
        fi

        sgnd_state_load_keys --array SGND_STATE_VARIABLES || return $?

        if [[ -n "$cli_default" ]]; then
            SGND_CANON_INPUT="$cli_default"
        fi

        if (( ${FLAG_AUTO:-0} )); then
            if (( ${#SGND_CANON_CLI_INPUTS[@]} > 0 )); then
                sayinfo "Auto mode: using command-line file or mask input(s)."
                sgnd_state_save_keys --array SGND_STATE_VARIABLES || return $?
                return 0
            fi

            if [[ -n "$SGND_CANON_INPUT" ]]; then
                sayinfo "Auto mode: using saved file or mask input."
                return 0
            fi

            sayfail "Auto mode requires a command-line file/mask or saved parameters."
            return 2
        fi

        # An explicit positional input is already a complete answer. Do not force the
        # caller to confirm it through ask a second time.
        if (( ${#SGND_CANON_CLI_INPUTS[@]} > 0 )); then
            sgnd_state_save_keys --array SGND_STATE_VARIABLES || return $?
            return 0
        fi

        ask \
            --label "File or mask" \
            --var SGND_CANON_INPUT \
            --default "$SGND_CANON_INPUT" || return $?

        [[ -n "$SGND_CANON_INPUT" ]] || {
            sayfail "Specify a shell file or file mask."
            return 2
        }

        sgnd_state_save_keys --array SGND_STATE_VARIABLES || return $?
        return 0
    }

# - Local script functions ----------------------------------------------------------
    # fn$ _resolve_canon_files - Resolve and validate canonical fragment files
        # . Returns
        #   0 when both canonical fragments are readable; 1 otherwise.
        #
        # . Usage
        #   _resolve_canon_files
    _resolve_canon_files() {
        if [[ "$SGND_FRAMEWORK_ROOT" == "/" ]]; then
            SGND_CANON_DIRECTORY="/usr/local/lib/solidgroundux/templates/canon"
        else
            SGND_CANON_DIRECTORY="${SGND_FRAMEWORK_ROOT%/}/usr/local/lib/solidgroundux/templates/canon"
        fi

        SGND_CANON_LOCATOR="$SGND_CANON_DIRECTORY/framework-locator.sh"
        SGND_CANON_LIB_GUARD="$SGND_CANON_DIRECTORY/lib-guard.sh"

        [[ -r "$SGND_CANON_LOCATOR" ]] || {
            sayfail "Canonical framework locator not found: $SGND_CANON_LOCATOR"
            return 1
        }
        [[ -r "$SGND_CANON_LIB_GUARD" ]] || {
            sayfail "Canonical library guard not found: $SGND_CANON_LIB_GUARD"
            return 1
        }
        return 0
    }

    # fn$ _detect_canonical_target - Determine which canonical structure a file contains
        # . Arguments
        #   $1 FILE
        #   $2 OUTPUT_VAR
        #
        # . Returns
        #   0 with OUTPUT_VAR set to locator, libguard, or skip.
        #   1 when both mutually exclusive target functions are present.
        #
        # . Usage
        #   _detect_canonical_target "$file" target
    _detect_canonical_target() {
        local file="${1:?missing file}"
        local output_var="${2:?missing output variable}"
        local has_locator=0
        local has_lib_guard=0
        local detected="skip"

        grep -Eq '^[[:space:]]*_framework_locator[[:space:]]*\(.*\)[[:space:]]*\{' "$file" && has_locator=1
        grep -Eq '^[[:space:]]*_sgnd_lib_guard[[:space:]]*\(.*\)[[:space:]]*\{' "$file" && has_lib_guard=1

        if (( has_locator && has_lib_guard )); then
            sayfail "Both _framework_locator() and _sgnd_lib_guard() found: $file"
            return 1
        elif (( has_locator )); then
            detected="locator"
        elif (( has_lib_guard )); then
            detected="libguard"
        fi

        printf -v "$output_var" '%s' "$detected"
        return 0
    }

    # fn$ _replace_framework_locator - Replace one locator function and its canonical header
        # . Arguments
        #   $1 FILE
        #
        # . Behavior
        #   - Starts replacement at the fn$ locator header when present immediately
        #     before the function; otherwise starts at the function declaration.
        #   - Ends at the function's closing brace at the same indentation level.
        #   - Preserves all other content in the Bootstrap section.
        #
        # . Returns
        #   0 when replacement succeeds; non-zero on malformed input or write failure.
        #
        # . Usage
        #   _replace_framework_locator "$file"
    _replace_framework_locator() {
        local file="${1:?missing file}"
        local temp_file=""

        temp_file="$(mktemp)" || return 1

        awk -v canon="$SGND_CANON_LOCATOR" '
            function emit_canon(   line) {
                while ((getline line < canon) > 0) print line
                close(canon)
            }
            BEGIN {
                in_header=0
                in_function=0
                found=0
                emitted=0
                indent=""
                buffered_count=0
            }
            {
                line=$0

                if (!in_function && line ~ /^[[:space:]]*#[[:space:]]*fn\$[[:space:]]+_framework_locator([[:space:]]|$)/) {
                    in_header=1
                    buffered_count=0
                    buffer[++buffered_count]=line
                    next
                }

                if (in_header && !in_function) {
                    if (line ~ /^[[:space:]]*_framework_locator[[:space:]]*\(.*\)[[:space:]]*\{[[:space:]]*$/) {
                        found++
                        if (found > 1) exit 42
                        indent=line
                        sub(/_framework_locator.*/, "", indent)
                        emit_canon()
                        emitted=1
                        in_header=0
                        in_function=1
                        next
                    }
                    buffer[++buffered_count]=line
                    next
                }

                if (!in_function && line ~ /^[[:space:]]*_framework_locator[[:space:]]*\(.*\)[[:space:]]*\{[[:space:]]*$/) {
                    found++
                    if (found > 1) exit 42
                    indent=line
                    sub(/_framework_locator.*/, "", indent)
                    emit_canon()
                    emitted=1
                    in_function=1
                    next
                }

                if (in_function) {
                    if (line == indent "}") {
                        in_function=0
                    }
                    next
                }

                print line
            }
            END {
                if (in_header && !emitted) {
                    for (i=1; i<=buffered_count; i++) print buffer[i]
                }
                if (found == 0) exit 40
                if (in_function) exit 41
            }
        ' "$file" > "$temp_file"
        local awk_rc=$?

        if (( awk_rc != 0 )); then
            rm -f "$temp_file"
            case "$awk_rc" in
                40) sayfail "Could not locate _framework_locator() in: $file" ;;
                41) sayfail "Could not determine end of _framework_locator() in: $file" ;;
                42) sayfail "Multiple _framework_locator() functions found in: $file" ;;
                *)  sayfail "Could not replace _framework_locator() in: $file" ;;
            esac
            return 1
        fi

        cat "$temp_file" > "$file" || { rm -f "$temp_file"; return 1; }
        rm -f "$temp_file"
        return 0
    }

    # fn$ _replace_library_guard - Replace the complete Library guard section
        # . Arguments
        #   $1 FILE
        #
        # . Behavior
        #   Uses _sgnd_lib_guard() only to identify the file type. Once identified,
        #   replaces the complete Library guard section through the next top-level
        #   section marker. A top-level section is identified structurally by
        #   `# - <Section title>`; trailing separator dashes are cosmetic and optional.
        #
        # . Returns
        #   0 when replacement succeeds; non-zero when the section is malformed.
        #
        # . Usage
        #   _replace_library_guard "$file"
    _replace_library_guard() {
        local file="${1:?missing file}"
        local temp_file=""

        temp_file="$(mktemp)" || return 1

        awk -v canon="$SGND_CANON_LIB_GUARD" '
            function emit_canon(   line) {
                while ((getline line < canon) > 0) print line
                close(canon)
            }
            BEGIN {
                in_guard=0
                found=0
            }
            # Canonical top-level section marker: `# - <Section title>`.
            # Exactly one whitespace character separates `#` from `-`, so ordinary
            # documentation bullets such as `#   - item` are not section markers.
            /^[[:space:]]*#[[:space:]]-[[:space:]]+Library guard([[:space:]]+-+)?[[:space:]]*$/ {
                found++
                if (found > 1) exit 42
                emit_canon()
                in_guard=1
                next
            }
            in_guard && /^[[:space:]]*#[[:space:]]-[[:space:]]+[^[:space:]-].*$/ {
                in_guard=0
                print
                next
            }
            in_guard { next }
            { print }
            END {
                if (found == 0) exit 40
                if (in_guard) exit 41
            }
        ' "$file" > "$temp_file"
        local awk_rc=$?

        if (( awk_rc != 0 )); then
            rm -f "$temp_file"
            case "$awk_rc" in
                40) sayfail "_sgnd_lib_guard() found but Library guard section is missing: $file" ;;
                41) sayfail "Library guard section has no following section marker: $file" ;;
                42) sayfail "Multiple Library guard sections found in: $file" ;;
                *)  sayfail "Could not replace Library guard section in: $file" ;;
            esac
            return 1
        fi

        cat "$temp_file" > "$file" || { rm -f "$temp_file"; return 1; }
        rm -f "$temp_file"
        return 0
    }

    # fn$ _expand_input - Expand one file path or glob mask
        # . Arguments
        #   $1 INPUT
        #
        # . Output
        #   Writes matching regular files, one per line.
        #
        # . Returns
        #   0 when at least one file matches; 1 otherwise.
        #
        # . Usage
        #   _expand_input "$input"
    _expand_input() {
        local input="${1:?missing input}"
        local match=""
        local matched=0

        if [[ -f "$input" ]]; then
            printf '%s\n' "$input"
            return 0
        fi

        while IFS= read -r match; do
            [[ -f "$match" ]] || continue
            printf '%s\n' "$match"
            matched=1
        done < <(compgen -G "$input" || true)

        (( matched ))
    }

    # fn$ _normalize_file - Apply the appropriate canonical replacement to one file
        # . Arguments
        #   $1 FILE
        #
        # . Returns
        #   0 for replaced or skipped files; non-zero on structural failure.
        #
        # . Usage
        #   _normalize_file "$file"
    _normalize_file() {
        local file="${1:?missing file}"
        local target=""
        local before_checksum=""
        local after_checksum=""

        case "$file" in
            */usr/local/lib/solidgroundux/templates/canon/*)
                saydebug "Skipped canonical source fragment: $file"
                return 0
                ;;
        esac

        _detect_canonical_target "$file" target || return 1

        case "$target" in
            locator)
                before_checksum="$(sha256sum "$file" | awk '{print $1}')"
                _replace_framework_locator "$file" || return 1
                ;;
            libguard)
                before_checksum="$(sha256sum "$file" | awk '{print $1}')"
                _replace_library_guard "$file" || return 1
                ;;
            skip)
                saydebug "Skipped; no canonical target function: $file"
                return 0
                ;;
            *)
                sayfail "Unknown canonical target '$target' for: $file"
                return 1
                ;;
        esac

        if ! bash -n "$file"; then
            sayfail "Shell syntax validation failed after canonical replacement: $file"
            return 1
        fi

        after_checksum="$(sha256sum "$file" | awk '{print $1}')"
        if [[ "$before_checksum" == "$after_checksum" ]]; then
            saydebug "Already canonical: $file"
        else
            sayok "Canonicalized $target: $file"
        fi
        return 0
    }

# - Main ----------------------------------------------------------------------------
    # fn$ main - Normalize canonical structures in selected shell files
        # . Arguments
        #   $@  One or more file paths or shell glob masks.
        #
        # . Returns
        #   0 when all matching files were processed successfully; non-zero otherwise.
        #
        # . Usage
        #   main "$@"
    main() {
        local input=""
        local file=""
        local failures=0
        local matched=0
        local -a inputs=()
        local -A seen=()

        _collect_cli_inputs "$@"
        _framework_locator || exit $?
        sgnd_exe_start "$@" || exit $?
        _resolve_canon_files || exit $?
        _get_parameters || return $?

        if (( ${FLAG_AUTO:-0} )) && (( ${#SGND_CANON_CLI_INPUTS[@]} > 0 )); then
            inputs=("${SGND_CANON_CLI_INPUTS[@]}")
        else
            inputs=("$SGND_CANON_INPUT")
        fi

        shopt -s globstar

        for input in "${inputs[@]}"; do
            local input_matched=0
            while IFS= read -r file; do
                [[ -n "$file" ]] || continue
                file="$(readlink -f "$file")"
                [[ -n "${seen[$file]-}" ]] && continue
                seen["$file"]=1
                matched=$((matched + 1))
                input_matched=1
                _normalize_file "$file" || failures=$((failures + 1))
            done < <(_expand_input "$input" || true)

            (( input_matched )) || saywarning "No files matched: $input"
        done

        if (( matched == 0 )); then
            sayfail "No files matched the supplied paths or masks."
            return 2
        fi

        if (( failures > 0 )); then
            sayfail "$failures file(s) could not be normalized."
            return 1
        fi

        sayok "Canonical normalization complete for $matched file(s)."

        if (( ! ${FLAG_AUTO:-0} )); then
            ask_dlg_autocontinue \
                --seconds 5 \
                --message "Press Enter to finish." || true
        fi

        return 0
    }

    main "$@"
