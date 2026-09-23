#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX SDK - Deploy Workspace
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626612
#   Checksum    : a0290e0b28c1d96ba1cd0f5dbb9ff6569e60e8ecc13e636488e3a7cd63648ee8
#   Source      : deploy-workspace.sh
#   Type        : script
#   Group       : SDK
#   Purpose     : Select workspace files and deploy them through receive-files.sh
#
# Description:
#   Collects deployment settings from command-line arguments and interactive prompts,
#   resolves the requested workspace files into a concrete relative path list, creates
#   a tar stream, and passes that stream to receive-files.sh locally or over SSH.
#
# Design principles:
#   - Selection and transport remain separate from destination-side installation policy
#   - Local and remote deployment use the same receive-files.sh contract
#   - Command-line values override saved defaults
#   - Confirmed deployment settings are always saved; the success timestamp changes only after a successful receive operation
#   - Changed-after defaults to the last successful deployment timestamp when available
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
# --- Script metadata (identity) ------------------------------------------------------
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"
    SGND_SCRIPT_TITLE="Deploy workspace"
    : "${SGND_SCRIPT_DESC:=Select and stream development workspace files to a SolidGroundUX receiver.}"
    : "${SGND_SCRIPT_VERSION:=1.8}"
    : "${SGND_SCRIPT_BUILD:=2621602}"
    : "${SGND_SCRIPT_DEVELOPERS:=Mark Fieten}"
    : "${SGND_SCRIPT_COMPANY:=Testadura Consultancy}"
    : "${SGND_SCRIPT_COPYRIGHT:=© 2025 - 2026 Testadura Consultancy}"
    : "${SGND_SCRIPT_LICENSE:=Testadura Non-Commercial License (TD-NC) v1.1.}"

# --- Script metadata (framework integration) -----------------------------------------
    SGND_USING=(
    )

    SGND_ARGS_SPEC=(
        "auto|a|flag|FLAG_AUTO|Deploy immediately using saved settings|0|"
        "local|l|flag|FLAG_LOCAL|Deploy to the local system|0|"
        "remote|r|value|REMOTE_TARGET|Deploy through SSH to user@host|"
        "product-root||value|PRODUCT_ROOT|Development root containing product repositories|"
        "products||value|PRODUCT_SELECTION|Product selection (A, comma list, or range)|"
        "source|s|value|SRC_ROOT|Explicit single workspace source root (compatibility)|"
        "target|t|value|DEST_ROOT|Destination filesystem root|"
        "directory|d|value|SELECT_DIRECTORY|Optional directory below the workspace root|"
        "match|m|value|SELECT_MATCH|Comma-separated filenames or shell-style file masks|"
        "changed-after|c|value|CHANGED_AFTER|Only include files modified after this date, timestamp, or datetime shortcut|"
        "since-last||flag|FLAG_SINCE_LAST|Only include files changed since the last successful deployment|0|"
        "receiver||value|RECEIVER_PATH|Path to receive-files.sh on the destination|"
    )

    SGND_SCRIPT_EXAMPLES=(
        "Deploy all shell files beneath one directory locally:"
        "  $SGND_SCRIPT_NAME --local --source /srv/solidgroundux/target-root --directory usr/local/lib/solidgroundux --match '*.sh'"
        ""
        "Deploy one named file remotely:"
        "  $SGND_SCRIPT_NAME --remote sysadmin@192.168.0.253 --match management-console.sh"
        ""
        "Deploy files changed since the last successful deployment:"
        "  $SGND_SCRIPT_NAME --remote sysadmin@192.168.0.253 --since-last"
    )

    SGND_SCRIPT_GLOBALS=(
    )

    SGND_STATE_VARIABLES=(
        DEPLOY_TRANSPORT
        REMOTE_TARGET
        PRODUCT_ROOT
        PRODUCT_SELECTION
        SRC_ROOT
        DEST_ROOT
        SELECT_DIRECTORY
        SELECT_MATCH
        CHANGED_AFTER
        FLAG_SINCE_LAST
        RECEIVER_PATH
        LAST_DEPLOY_SUCCESS
    )

    SGND_ON_EXIT_HANDLERS=(
    )

    SGND_STATE_SAVE=1

# --- Local declarations ---------------------------------------------------------------
    DEPLOY_TRANSPORT="${DEPLOY_TRANSPORT:-}"
    REMOTE_TARGET="${REMOTE_TARGET:-}"
    PRODUCT_ROOT="${PRODUCT_ROOT:-}"
    PRODUCT_SELECTION="${PRODUCT_SELECTION:-A}"
    SRC_ROOT="${SRC_ROOT:-}"
    DEST_ROOT="${DEST_ROOT:-}"
    SELECT_DIRECTORY="${SELECT_DIRECTORY:-}"
    SELECT_MATCH="${SELECT_MATCH:-}"
    CHANGED_AFTER="${CHANGED_AFTER:-}"
    RECEIVER_PATH="${RECEIVER_PATH:-}"
    LAST_DEPLOY_SUCCESS="${LAST_DEPLOY_SUCCESS:-}"

    CLI_DEPLOY_TRANSPORT=0
    CLI_REMOTE_TARGET=0
    CLI_PRODUCT_ROOT=0
    CLI_PRODUCT_SELECTION=0
    CLI_SRC_ROOT=0
    CLI_DEST_ROOT=0
    CLI_SELECT_DIRECTORY=0
    CLI_SELECT_MATCH=0
    CLI_CHANGED_AFTER=0
    CLI_SINCE_LAST=0
    CLI_RECEIVER_PATH=0

    SELECTED_PATHS=()
    SELECTED_PRODUCT_ROOTS=()
    SELECTED_PRODUCT_NAMES=()
    DEPLOYED_PATHS=()
    DEPLOY_STARTED_AT=""
    DEPLOY_FINISHED_AT=""

# --- Product discovery ---------------------------------------------------------------
    # fn$ _deploy_product_record - Read product metadata from one target-root
    _deploy_product_record() {
        local root="${1:?missing target root}"
        local globals_dir="${root%/}/usr/local/lib/solidgroundux/globals" file="" record=""
        [[ -d "$globals_dir" ]] || return 1

        while IFS= read -r -d '' file; do
            record="$(bash -c '
                source "$1"
                for var in $(compgen -A variable SGND_); do
                    case "$var" in
                        SGND_PRODUCT) printf "%s|%s|%s|%s\\n" "${SGND_PRODUCT-}" "${SGND_VERSION-}" "${SGND_BUILD-}" "$1"; exit ;;
                        *_PRODUCT) prefix="${var%_PRODUCT}"; vv="${prefix}_VERSION"; bv="${prefix}_BUILD"; printf "%s|%s|%s|%s\\n" "${!var-}" "${!vv-}" "${!bv-}" "$1"; exit ;;
                    esac
                done
            ' bash "$file" 2>/dev/null || true)"
            [[ -n "$record" ]] && { printf '%s\n' "$record"; return 0; }
        done < <(find "$globals_dir" -maxdepth 1 -type f \( -name 'sgnd-definitions.sh' -o -name '*-definitions.sh' \) -print0 2>/dev/null | sort -z)
        return 1
    }

    # fn$ _deploy_parse_product_selection - Parse A/comma/range product selection
    _deploy_parse_product_selection() {
        local spec="${1:-}" max="${2:-0}" token="" begin="" finish="" i=0 idx=0
        local -n out_ref=$3
        local -A seen=()
        local -a tokens=()

        out_ref=()
        spec="${spec//[[:space:]]/}"
        [[ -n "$spec" ]] || return 1

        if [[ "${spec^^}" == "A" ]]; then
            for (( i=1; i<=max; i++ )); do out_ref+=("$i"); done
            return 0
        fi

        IFS=',' read -r -a tokens <<< "$spec"
        for token in "${tokens[@]}"; do
            if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                begin="${BASH_REMATCH[1]}"; finish="${BASH_REMATCH[2]}"
                (( begin >= 1 && finish >= begin && finish <= max )) || return 1
                for (( i=begin; i<=finish; i++ )); do
                    [[ -n "${seen[$i]-}" ]] || { out_ref+=("$i"); seen[$i]=1; }
                done
            elif [[ "$token" =~ ^[0-9]+$ ]]; then
                idx="$token"
                (( idx >= 1 && idx <= max )) || return 1
                [[ -n "${seen[$idx]-}" ]] || { out_ref+=("$idx"); seen[$idx]=1; }
            else
                return 1
            fi
        done
        (( ${#out_ref[@]} > 0 ))
    }

    # fn$ _select_products - Discover and select deployable product repositories
    _select_products() {
        local repo="" root="" record="" product="" version="" build="" defs=""
        local selection="" i=0 index=0
        local current_repo="" current_root="$SGND_FRAMEWORK_ROOT"
        local -a roots=() products=() versions=() builds=() selected_indexes=()

        # An explicit --source retains the old single-tree behavior.
        if (( CLI_SRC_ROOT )); then
            [[ -d "$SRC_ROOT" ]] || { sayfail "Workspace root not found: $SRC_ROOT"; return 1; }
            SELECTED_PRODUCT_ROOTS=("${SRC_ROOT%/}")
            SELECTED_PRODUCT_NAMES=("Explicit source")
            return 0
        fi

        [[ "$(basename -- "$current_root")" == "target-root" ]] && current_repo="$(dirname -- "$current_root")"
        : "${PRODUCT_ROOT:=$(dirname -- "${current_repo:-$current_root}")}"

        if (( ! CLI_PRODUCT_ROOT && ! ${FLAG_AUTO:-0} )); then
            sgnd_print
            sgnd_print_sectionheader "Product discovery" --padend 0
            ask --label "Product root" --var PRODUCT_ROOT --default "$PRODUCT_ROOT" \
                --validate sgnd_validate_dir_exists --colorize both --labelclr "${CYAN}" --labelwidth 30
            sgnd_save_state || return $?
        fi

        PRODUCT_ROOT="${PRODUCT_ROOT%/}"
        [[ -d "$PRODUCT_ROOT" ]] || { sayfail "Product root not found: $PRODUCT_ROOT"; return 1; }

        while IFS= read -r -d '' repo; do
            root="$repo/target-root"
            [[ -d "$root" ]] || continue
            record="$(_deploy_product_record "$root" 2>/dev/null || true)"
            [[ -n "$record" ]] || continue
            IFS='|' read -r product version build defs <<< "$record"
            roots+=("$root"); products+=("$product"); versions+=("$version"); builds+=("$build")
        done < <(find "$PRODUCT_ROOT" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

        (( ${#roots[@]} > 0 )) || { sayfail "No SolidGroundUX products found below: $PRODUCT_ROOT"; return 1; }

        sgnd_print
        sgnd_print_sectionheader "Deploy products" --padend 0
        for i in "${!roots[@]}"; do
            sgnd_print "$((i+1)) : ${products[$i]}  v${versions[$i]}.${builds[$i]}"
        done
        (( ${#roots[@]} > 1 )) && sgnd_print "A : All products"
        sgnd_print

        while true; do
            selection="${PRODUCT_SELECTION:-A}"
            (( ${#roots[@]} == 1 )) && selection="1"

            if (( CLI_PRODUCT_SELECTION || ${FLAG_AUTO:-0} )); then
                _deploy_parse_product_selection "$selection" "${#roots[@]}" selected_indexes || {
                    sayfail "Invalid product selection: $selection"
                    return 1
                }
                break
            fi

            ask --label "Products (comma/range or A)" --var selection --default "$selection" \
                --colorize both --labelclr "${CYAN}" --labelwidth 30
            if _deploy_parse_product_selection "$selection" "${#roots[@]}" selected_indexes; then
                break
            fi
            saywarning "Invalid product selection: $selection"
        done

        PRODUCT_SELECTION="$selection"
        SELECTED_PRODUCT_ROOTS=()
        SELECTED_PRODUCT_NAMES=()
        for index in "${selected_indexes[@]}"; do
            i=$((index-1))
            SELECTED_PRODUCT_ROOTS+=("${roots[$i]}")
            SELECTED_PRODUCT_NAMES+=("${products[$i]}")
        done
        sgnd_save_state || return $?
        return 0
    }

# --- Selection helpers ---------------------------------------------------------------
    # fn: _is_deployable_path - Test whether a relative workspace path is deployable
        # . Arguments
        #   $1  Relative path beneath SRC_ROOT.
        #
        # . Returns
        #   0 when the path is deployable.
        #   1 when the path is top-level, hidden, private, or marked .old.
        #
        # . Usage
        #   _is_deployable_path "usr/local/bin/sgnd-console"
    _is_deployable_path() {
        local rel="$1"
        local name=""

        name="$(basename -- "$rel")"

        [[ "$rel" == */* ]] || return 1
        [[ "$name" != _* ]] || return 1
        [[ "$name" != *.old ]] || return 1
        [[ "$rel" != .*/* ]] || return 1
        [[ "$rel" != _*/* ]] || return 1
        [[ "$rel" != */.*/* ]] || return 1
        [[ "$rel" != */_*/* ]] || return 1
        return 0
    }

    # fn: _normalize_relative_path - Normalize and validate a workspace-relative path
        # . Arguments
        #   $1  User-provided path.
        #
        # . Output
        #   Writes the normalized relative path to stdout.
        #
        # . Returns
        #   0 when the path is safe and remains beneath SRC_ROOT.
        #   1 for absolute paths, empty paths, or parent traversal.
        #
        # . Usage
        #   rel="$(_normalize_relative_path "usr/local/bin")"
    _normalize_relative_path() {
        local rel="${1#./}"

        rel="${rel%/}"
        [[ -n "$rel" && "$rel" != /* ]] || return 1
        [[ "$rel" != ".." && "$rel" != ../* && "$rel" != */../* && "$rel" != */.. ]] || return 1
        printf '%s\n' "$rel"
    }

    # fn: _add_selected_file - Add one deployable file to the normalized selection
        # . Arguments
        #   $1  Absolute filename beneath SRC_ROOT.
        #
        # . Side effects
        #   Appends a relative path to SELECTED_PATHS when eligible.
        #
        # . Returns
        #   0 always.
        #
        # . Usage
        #   _add_selected_file "$SRC_ROOT/usr/local/bin/sgnd-console"
    _add_selected_file() {
        local file="$1"
        local rel=""

        [[ -f "$file" ]] || return 0
        rel="${file#"$SRC_ROOT"/}"
        [[ "$rel" != "$file" ]] || return 0
        _is_deployable_path "$rel" || return 0
        SELECTED_PATHS+=("$rel")
    }

    # fn: _select_files - Resolve the combined workspace filters into a concrete file list
        # . Purpose
        #   Select deployable files by optional directory, filename or mask, and modification time.
        #
        # . Inputs (globals)
        #   SRC_ROOT, SELECT_DIRECTORY, SELECT_MATCH, CHANGED_AFTER,
        #   FLAG_SINCE_LAST, LAST_DEPLOY_SUCCESS
        #
        # . Outputs (globals)
        #   SELECTED_PATHS
        #
        # . Returns
        #   0 when at least one deployable file was selected.
        #   1 when a filter is invalid or no files match.
        #
        # . Usage
        #   _select_files || return $?
    _select_files() {
        local search_root="$SRC_ROOT"
        local directory=""
        local match_list="${SELECT_MATCH:-*}"
        local changed_after="${CHANGED_AFTER:-1900-01-01}"
        local candidate=""
        local pattern=""
        local -a patterns=()

        SELECTED_PATHS=()

        if [[ -n "${SELECT_DIRECTORY:-}" ]]; then
            directory="$(_normalize_relative_path "$SELECT_DIRECTORY")" || {
                sayfail "Invalid relative directory path: $SELECT_DIRECTORY"
                return 1
            }
            search_root="$SRC_ROOT/$directory"
        fi

        [[ -d "$search_root" ]] || {
            sayfail "Selection directory not found: $search_root"
            return 1
        }

        if [[ "${FLAG_SINCE_LAST:-0}" -eq 1 ]]; then
            [[ -n "${LAST_DEPLOY_SUCCESS:-}" ]] || {
                sayfail "No successful deployment timestamp is available for --since-last."
                return 1
            }
            changed_after="$LAST_DEPLOY_SUCCESS"
        fi

        IFS=',' read -r -a patterns <<< "$match_list"

        for pattern in "${patterns[@]}"; do
            pattern="${pattern#"${pattern%%[![:space:]]*}"}"
            pattern="${pattern%"${pattern##*[![:space:]]}"}"
            [[ -n "$pattern" ]] || continue

            while IFS= read -r -d '' candidate; do
                _add_selected_file "$candidate"
            done < <(find "$search_root" -type f -name "$pattern" -newermt "$changed_after" -print0)
        done

        if (( ${#SELECTED_PATHS[@]} == 0 )); then
            saywarning "No deployable files matched the filters."
            return 1
        fi

        mapfile -d '' -t SELECTED_PATHS < <(printf '%s\0' "${SELECTED_PATHS[@]}" | sort -zu)
        sayinfo "Selected ${#SELECTED_PATHS[@]} file(s)."
        return 0
    }

# --- Parameter collection ------------------------------------------------------------
    # fn: _capture_cli_parameters - Record which deployment settings were supplied explicitly
        # . Purpose
        #   Distinguish command-line values from state/default values so explicit settings
        #   are not prompted again.
        #
        # . Arguments
        #   $@  Original executable arguments.
        #
        # Outputs (globals)
        #   CLI_DEPLOY_TRANSPORT, CLI_REMOTE_TARGET, CLI_SRC_ROOT, CLI_DEST_ROOT,
        #   CLI_SELECT_DIRECTORY, CLI_SELECT_MATCH, CLI_CHANGED_AFTER,
        #   CLI_SINCE_LAST, CLI_RECEIVER_PATH
        #
        # . Returns
        #   0 always.
        #
        # . Usage
        #   _capture_cli_parameters "$@"
    _capture_cli_parameters() {
        local arg=""

        while (( $# > 0 )); do
            arg="$1"
            shift

            case "$arg" in
                --local|-l)
                    CLI_DEPLOY_TRANSPORT=1
                    ;;
                --remote|-r)
                    CLI_DEPLOY_TRANSPORT=1
                    CLI_REMOTE_TARGET=1
                    (( $# > 0 )) && shift
                    ;;
                --remote=*)
                    CLI_DEPLOY_TRANSPORT=1
                    CLI_REMOTE_TARGET=1
                    ;;
                --product-root)
                    CLI_PRODUCT_ROOT=1
                    (( $# > 0 )) && shift
                    ;;
                --product-root=*)
                    CLI_PRODUCT_ROOT=1
                    ;;
                --products)
                    CLI_PRODUCT_SELECTION=1
                    (( $# > 0 )) && shift
                    ;;
                --products=*)
                    CLI_PRODUCT_SELECTION=1
                    ;;
                --source|-s)
                    CLI_SRC_ROOT=1
                    (( $# > 0 )) && shift
                    ;;
                --source=*)
                    CLI_SRC_ROOT=1
                    ;;
                --target|-t)
                    CLI_DEST_ROOT=1
                    (( $# > 0 )) && shift
                    ;;
                --target=*)
                    CLI_DEST_ROOT=1
                    ;;
                --directory|-d)
                    CLI_SELECT_DIRECTORY=1
                    (( $# > 0 )) && shift
                    ;;
                --directory=*)
                    CLI_SELECT_DIRECTORY=1
                    ;;
                --match|-m)
                    CLI_SELECT_MATCH=1
                    (( $# > 0 )) && shift
                    ;;
                --match=*)
                    CLI_SELECT_MATCH=1
                    ;;
                --changed-after|-c)
                    CLI_CHANGED_AFTER=1
                    (( $# > 0 )) && shift
                    ;;
                --changed-after=*)
                    CLI_CHANGED_AFTER=1
                    ;;
                --since-last)
                    CLI_SINCE_LAST=1
                    ;;
                --receiver)
                    CLI_RECEIVER_PATH=1
                    (( $# > 0 )) && shift
                    ;;
                --receiver=*)
                    CLI_RECEIVER_PATH=1
                    ;;
            esac
        done

        return 0
    }

    # fn: _validate_parameters - Validate the resolved deployment settings
        # . Returns
        #   0 when all required settings are valid.
        #   1 when one or more settings are unusable.
        #
        # . Usage
        #   _validate_parameters || return $?
    _validate_parameters() {
        local directory=""
        local product_root=""
        local return_directory_found=0

        if (( CLI_SRC_ROOT )); then
            [[ -d "$SRC_ROOT" ]] || {
                sayfail "Workspace root not found: $SRC_ROOT"
                return 1
            }
        else
            (( ${#SELECTED_PRODUCT_ROOTS[@]} > 0 )) || {
                sayfail "No deployment products are selected."
                return 1
            }
        fi

        case "$DEPLOY_TRANSPORT" in
            local) ;;
            remote)
                [[ -n "$REMOTE_TARGET" ]] || {
                    sayfail "A remote SSH target is required."
                    return 1
                }
                ;;
            *)
                sayfail "Deployment transport must be 'local' or 'remote'."
                return 1
                ;;
        esac

        case "$DEST_ROOT" in
            /*) ;;
            *) sayfail "Destination root must be an absolute path: $DEST_ROOT"; return 1 ;;
        esac

        [[ -n "$RECEIVER_PATH" ]] || {
            sayfail "Receiver path cannot be empty."
            return 1
        }

        if [[ -n "${SELECT_DIRECTORY:-}" ]]; then
            directory="$(_normalize_relative_path "$SELECT_DIRECTORY")" || {
                sayfail "Invalid relative directory path: $SELECT_DIRECTORY"
                return 1
            }
            return_directory_found=0
            for product_root in "${SELECTED_PRODUCT_ROOTS[@]}"; do
                [[ -d "$product_root/$directory" ]] || continue
                return_directory_found=1
            done
            if [[ "${return_directory_found:-0}" -ne 1 ]]; then
                sayfail "Selection directory not found in any selected product: $directory"
                return 1
            fi
        fi

        [[ -n "${SELECT_MATCH:-}" ]] || SELECT_MATCH="*"
        [[ -n "${CHANGED_AFTER:-}" ]] || CHANGED_AFTER="1900-01-01"

        if [[ "${FLAG_SINCE_LAST:-0}" -eq 1 ]]; then
            [[ -n "${LAST_DEPLOY_SUCCESS:-}" ]] || {
                sayfail "No successful deployment timestamp is available for --since-last."
                return 1
            }
        elif ! date -d "$CHANGED_AFTER" >/dev/null 2>&1; then
            sayfail "Changed-after value is not a valid date or timestamp: $CHANGED_AFTER"
            return 1
        fi

        return 0
    }

    # fn: _getparameters - Collect deployment parameters from CLI values, state, and ask
        # . Purpose
        #   Resolve command-line overrides first, use saved state as prompt defaults,
        #   and combine directory, filename/mask, and changed-after filters.
        #
        # . Outputs (globals)
        #   DEPLOY_TRANSPORT, REMOTE_TARGET, PRODUCT_ROOT, PRODUCT_SELECTION, DEST_ROOT, SELECT_DIRECTORY,
        #   SELECT_MATCH, CHANGED_AFTER, RECEIVER_PATH
        #
        # . Returns
        #   0 after confirmation or when auto mode has valid resolved settings.
        #   1 when validation fails or the user cancels.
        #
        # . Usage
        #   _getparameters || return $?
    _getparameters() {
        local reply=""
        local since_last="N"

        if [[ "${FLAG_LOCAL:-0}" -eq 1 ]]; then
            DEPLOY_TRANSPORT="local"
        elif [[ -n "${REMOTE_TARGET:-}" ]]; then
            DEPLOY_TRANSPORT="remote"
        fi

        : "${DEPLOY_TRANSPORT:=local}"
        : "${PRODUCT_SELECTION:=A}"
        : "${DEST_ROOT:=/}"
        : "${SELECT_DIRECTORY:=}"
        : "${SELECT_MATCH:=*}"
        : "${CHANGED_AFTER:=1900-01-01}"
        : "${RECEIVER_PATH:=/usr/local/libexec/solidgroundux/receive-files.sh}"

        if [[ "${FLAG_SINCE_LAST:-0}" -eq 1 ]]; then
            since_last="Y"
        fi

        _select_products || return $?

        if [[ "${FLAG_AUTO:-0}" -eq 1 ]]; then
            _validate_parameters || return $?
            return 0
        fi

        while true; do
            if (( ! CLI_DEPLOY_TRANSPORT )); then
                sgnd_print "Choose how the files will be delivered."
                sgnd_print "  local  - Run receive-files.sh on this machine."
                sgnd_print "  remote - Send the stream over SSH to another machine."

                ask --label "Deployment transport" \
                    --var DEPLOY_TRANSPORT \
                    --default "$DEPLOY_TRANSPORT" \
                    --colorize both
                sgnd_save_state || return $?
            fi

            if [[ "$DEPLOY_TRANSPORT" == "remote" ]]; then
                if (( ! CLI_REMOTE_TARGET )); then
                    sgnd_print "Enter the SSH destination in user@host format."
                    sgnd_print "Examples: sysadmin@192.168.0.253 or sysadmin@td-sambaad"

                    ask --label "Remote target (user@host)" \
                        --var REMOTE_TARGET \
                        --default "$REMOTE_TARGET" \
                        --colorize both
                    sgnd_save_state || return $?
                fi
            else
                REMOTE_TARGET=""
            fi

            if (( ! CLI_DEST_ROOT )); then
                sgnd_print "Enter the filesystem root beneath which received paths are installed."
                sgnd_print "Use / to deploy into the destination system root."

                ask --label "Destination root" \
                    --var DEST_ROOT \
                    --default "$DEST_ROOT" \
                    --colorize both
                sgnd_save_state || return $?
            fi

            if (( ! CLI_SELECT_DIRECTORY )); then
                sgnd_print "Optionally restrict the search to a directory below the workspace root."
                sgnd_print "Leave it empty to search the complete workspace."

                ask --label "Directory" \
                    --var SELECT_DIRECTORY \
                    --default "$SELECT_DIRECTORY" \
                    --colorize both
                sgnd_save_state || return $?
            fi

            if (( ! CLI_SELECT_MATCH )); then
                sgnd_print "Enter one or more filenames or shell-style file masks."
                sgnd_print "Separate multiple entries with commas; use * to include every filename."

                ask --label "Files or masks" \
                    --var SELECT_MATCH \
                    --default "$SELECT_MATCH" \
                    --colorize both
                sgnd_save_state || return $?
            fi

            if (( CLI_CHANGED_AFTER )); then
                FLAG_SINCE_LAST=0
            elif (( CLI_SINCE_LAST )); then
                sgnd_print_labeledvalue \
                    --label "Last succeeded deployment" \
                    --value "${LAST_DEPLOY_SUCCESS:-Not available}"
            else
                if [[ -n "${LAST_DEPLOY_SUCCESS:-}" ]]; then
                    sgnd_print "Deploy only files changed since the last successful deployment."
                    ask --label "Since last deployment (Y/N)" \
                        --var since_last \
                        --default "$since_last" \
                        --colorize both
                else
                    since_last="N"
                    sgnd_print "No successful deployment timestamp is available yet."
                fi

                case "${since_last^^}" in
                    Y|YES)
                        FLAG_SINCE_LAST=1
                        sgnd_save_state || return $?
                        sgnd_print_labeledvalue \
                            --label "Last succeeded deployment" \
                            --value "$LAST_DEPLOY_SUCCESS"
                        ;;
                    *)
                        FLAG_SINCE_LAST=0
                        CHANGED_AFTER="1900-01-01"
                        sgnd_save_state || return $?
                        sgnd_print "Only files modified after this date or timestamp are included."
                        sgnd_print "Datetime shortcuts are accepted, for example N, D, -2h, -30m, or -1d."
                        sgnd_print "Use 1900-01-01 to apply no practical date restriction."

                        ask_datetime --label "Changed after" \
                            --var CHANGED_AFTER \
                            --default "$CHANGED_AFTER" \
                            --colorize both
                        sgnd_save_state || return $?
                        ;;
                esac
            fi

            if (( ! CLI_RECEIVER_PATH )); then
                sgnd_print "Enter the receive-files.sh path as it exists on the destination system."

                ask --label "Receiver path" \
                    --var RECEIVER_PATH \
                    --default "$RECEIVER_PATH" \
                    --colorize both
                sgnd_save_state || return $?
            fi

            _validate_parameters || {
                saywarning "Please correct the deployment settings."
                continue
            }

            sgnd_print
            sgnd_print_sectionheader ""
            
            ask_dlg_autocontinue \
                --seconds 15 \
                --message "Select files and start deployment?" \
                --redo \
                --cancel

            reply=$?
            case "$reply" in
                0|1) break ;;
                2) saycancel "Deployment cancelled."; return 1 ;;
                3) continue ;;
                *) sayfail "Unexpected confirmation response: $reply"; return 1 ;;
            esac
        done

        return 0
    }


# --- Reporting ----------------------------------------------------------------------
    # fn: _print_deployment_summary - Display the completed deployment details
        # . Purpose
        #   Show which workspace files were selected and where they were sent.
        #
        # . Behavior
        #   - Displays source, destination, transport, receiver, timing, and result mode.
        #   - Displays every selected relative path on its own aligned value line.
        #   - Uses sgnd_print_labeledmultivalue so no selected path is truncated.
        #   - Clearly marks dry-run deployments.
        #
        # Inputs (globals)
        #   DEPLOY_TRANSPORT, REMOTE_TARGET, SRC_ROOT, DEST_ROOT, RECEIVER_PATH,
        #   SELECTED_PATHS, DEPLOY_STARTED_AT, DEPLOY_FINISHED_AT, FLAG_DRYRUN
        #
        # . Returns
        #   0 after displaying the summary.
        #
        # . Usage
        #   _print_deployment_summary
    _print_deployment_summary() {
        local destination=""
        local result="Completed"

        case "$DEPLOY_TRANSPORT" in
            local)
                destination="$DEST_ROOT"
                ;;
            remote)
                destination="$REMOTE_TARGET:$DEST_ROOT"
                ;;
            *)
                destination="$DEST_ROOT"
                ;;
        esac

        if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
            result="Dry run completed"
        fi

        sgnd_print
        sgnd_print_sectionheader "Deployment summary"
        sgnd_print_labeledvalue --label "Result" --value "$result" --labelwidth 20
        sgnd_print_labeledvalue --label "Transport" --value "$DEPLOY_TRANSPORT" --labelwidth 20
        sgnd_print_labeledmultivalue --label "Products" --labelwidth 20 --items "${SELECTED_PRODUCT_NAMES[@]}"
        sgnd_print_labeledvalue --label "Destination" --value "$destination" --labelwidth 20
        sgnd_print_labeledvalue --label "Receiver" --value "$RECEIVER_PATH" --labelwidth 20
        sgnd_print_labeledvalue --label "Started" --value "${DEPLOY_STARTED_AT:-Unknown}" --labelwidth 20
        sgnd_print_labeledvalue --label "Finished" --value "${DEPLOY_FINISHED_AT:-Unknown}" --labelwidth 20
        sgnd_print_labeledmultivalue \
            --label "Deployed files" \
            --labelwidth 20 \
            --items "${DEPLOYED_PATHS[@]}"
        sgnd_print
        sgnd_print_sectionheader ""
        return 0
    }

# --- Transport ----------------------------------------------------------------------
    # fn: _quote_remote_arg - Shell-quote one argument for the remote receive command
        # . Arguments
        #   $1  Argument value.
        #
        # . Output
        #   Writes one shell-safe argument to stdout.
        #
        # . Returns
        #   0 always.
        #
        # . Usage
        #   quoted="$(_quote_remote_arg "$DEST_ROOT")"
    _quote_remote_arg() {
        printf '%q' "$1"
    }

    # fn: _stream_local - Stream selected workspace files to the local receiver
        # . Returns
        #   Status returned by tar or receive-files.sh through pipefail.
        #
        # . Usage
        #   _stream_local
    _stream_local() {
        local -a receiver_args=("$RECEIVER_PATH" --target "$DEST_ROOT")

        if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
            receiver_args+=(--dry-run)
        fi

        sudo -v || {
            sayfail "Unable to obtain local sudo authorization."
            return 1
        }

        tar -C "$SRC_ROOT" -cf - -- "${SELECTED_PATHS[@]}" |
            sudo "${receiver_args[@]}"
    }

    # fn: _ensure_remote_receiver_sudo - Ensure the remote receiver may run without a sudo password
        # . Purpose
        #   Create and validate a narrowly scoped sudoers rule for receive-files.sh
        #   on the remote destination when the rule does not already exist.
        #
        # . Returns
        #   0 when the sudoers rule already exists or was created successfully.
        #   Non-zero when SSH, sudo, or sudoers validation fails.
        #
        # . Usage
        #   _ensure_remote_receiver_sudo
    _ensure_remote_receiver_sudo() {
        local remote_user="${REMOTE_TARGET%@*}"
        local sudoers_file="/etc/sudoers.d/solidgroundux-receiver"
        local sudo_rule=""
        local remote_setup=""

        sudo_rule="$remote_user ALL=(root) NOPASSWD: $RECEIVER_PATH"

        saywarning "Remote deployment may request your password up to three times:"
        saywarning "  1. SSH authentication for receiver setup"
        saywarning "  2. Remote sudo authentication if the sudoers rule must be created"
        saywarning "  3. SSH authentication for the file transfer"

        remote_setup="
            if [[ ! -f $(_quote_remote_arg "$sudoers_file") ]]; then
                printf '%s\n' $(_quote_remote_arg "$sudo_rule") |
                    sudo tee $(_quote_remote_arg "$sudoers_file") >/dev/null &&
                sudo chmod 0440 $(_quote_remote_arg "$sudoers_file") &&
                sudo visudo -cf $(_quote_remote_arg "$sudoers_file") >/dev/null
            fi
        "

        ssh -t "$REMOTE_TARGET" "$remote_setup" || {
            sayfail "Unable to configure remote receiver sudo access."
            return 1
        }

        return 0
    }

    # fn: _stream_remote - Stream selected workspace files to the remote receiver over SSH
        # . Returns
        #   Status returned by tar, SSH, or receive-files.sh through pipefail.
        #
        # . Usage
        #   _stream_remote
    _stream_remote() {
        local remote_command=""

        _ensure_remote_receiver_sudo || return $?

        remote_command="sudo -n $(_quote_remote_arg "$RECEIVER_PATH") --target $(_quote_remote_arg "$DEST_ROOT")"

        if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
            remote_command+=" --dry-run"
        fi

        tar -C "$SRC_ROOT" -cf - -- "${SELECTED_PATHS[@]}" |
            ssh "$REMOTE_TARGET" "$remote_command"
    }

    # fn: _deploy - Select files and stream them to the configured receiver
        # . Returns
        #   0 after a successful receive operation.
        #   Non-zero when selection, transport, or receiver processing fails.
        #
        # . Usage
        #   _deploy || return $?
    _deploy() {
        local i=0 product_name="" product_root=""

        DEPLOY_STARTED_AT="$(date --iso-8601=seconds)"
        DEPLOY_FINISHED_AT=""
        DEST_ROOT="${DEST_ROOT%/}"
        [[ -n "$DEST_ROOT" ]] || DEST_ROOT="/"
        DEPLOYED_PATHS=()

        for i in "${!SELECTED_PRODUCT_ROOTS[@]}"; do
            product_root="${SELECTED_PRODUCT_ROOTS[$i]%/}"
            product_name="${SELECTED_PRODUCT_NAMES[$i]}"
            SRC_ROOT="$product_root"

            saystart "Selecting files for $product_name"
            if ! _select_files; then
                saywarning "No files selected for $product_name; skipping product."
                continue
            fi

            saystart "Deploying ${#SELECTED_PATHS[@]} file(s) from $product_name"

            case "$DEPLOY_TRANSPORT" in
                local)
                    sayinfo "Receiver: local $RECEIVER_PATH"
                    _stream_local || {
                        sayfail "Local receiver failed for $product_name."
                        return 1
                    }
                    ;;
                remote)
                    sayinfo "Receiver: $REMOTE_TARGET:$RECEIVER_PATH"
                    _stream_remote || {
                        sayfail "Remote receiver failed for $product_name."
                        return 1
                    }
                    ;;
            esac

            for deployed_path in "${SELECTED_PATHS[@]}"; do
                DEPLOYED_PATHS+=("$product_name: $deployed_path")
            done
        done

        (( ${#DEPLOYED_PATHS[@]} > 0 )) || {
            saywarning "No deployable files matched the selected products and filters."
            return 1
        }

        if [[ "${FLAG_DRYRUN:-0}" -eq 0 ]]; then
            LAST_DEPLOY_SUCCESS="$DEPLOY_STARTED_AT"
        fi

        DEPLOY_FINISHED_AT="$(date --iso-8601=seconds)"
        _print_deployment_summary
        sayend "Deployment completed successfully."
        return 0
    }

# --- Main ----------------------------------------------------------------------------
    # fn: main - Run the workspace deployment workflow
        # . Arguments
        #   $@  Framework and script-specific arguments.
        #
        # . Returns
        #   Exit status from parameter collection, selection, transport, or receiver processing.
        #
        # . Usage
        #   main "$@"
    main() {
        local reply=0

        _capture_cli_parameters "$@"
        _framework_locator || exit $?
        sgnd_exe_start --autostate -- "$@"

        # Load this script's persisted inputs explicitly before building prompt defaults.
        # This keeps deploy-workspace deterministic instead of relying on implicit autostate load timing.
        sgnd_state_load_keys --array SGND_STATE_VARIABLES || return $?

        _getparameters || return $?

        # Persist the confirmed interactive/CLI settings before deployment.
        # Do not rely solely on exit-time autostate: a failed transfer should not
        # force the operator to re-enter the deployment parameters next time.
        sgnd_save_state || return $?

        _deploy || return $?

        ask_dlg_autocontinue \
            --seconds 15 \
            --message "Deployment finished. Press Enter to exit, or R to deploy again." \
            --redo \
            --pause

        reply=$?
        case "$reply" in
            0|1)
                return 0
                ;;
            3)
                sgnd_save_state || return $?
                exec "$SGND_SCRIPT_FILE" "$@"
                ;;
            *)
                sayfail "Unexpected continuation response: $reply"
                return 1
                ;;
        esac
    }

    main "$@"
    exit $?
