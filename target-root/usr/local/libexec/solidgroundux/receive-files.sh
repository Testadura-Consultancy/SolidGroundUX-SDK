#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX SDK - Receive Files
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626612
#   Checksum    : 5624fd8a9d0d77729d6f3d8d972c5ef60d99e961c93a0a91b0e49c33e2fc8f48
#   Source      : receive-files.sh
#   Type        : script
#   Group       : SDK
#   Purpose     : Receive a workspace tar stream and extract it beneath a target root
#
# Description:
#   Receives a tar archive through standard input, validates that every archive entry
#   is a safe relative path, and extracts the streamed workspace files beneath the
#   requested target root.
#
# Design principles:
#   - File selection remains the responsibility of deploy-workspace.sh
#   - Archive entries always remain relative to the supplied target root
#   - Unsafe absolute paths and parent traversal are rejected before extraction
#   - The received stream is processed as one deployment operation
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# =====================================================================================
set -uo pipefail

# - Bootstrap ----------------------------------------------------------------------
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
# - Script metadata (identity) ------------------------------------------------------
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"
    SGND_SCRIPT_TITLE="Receive files"


# - Script metadata (framework integration) -----------------------------------------
    SGND_USING=(
    )

    SGND_ARGS_SPEC=(
        "target|t|value|DEST_ROOT|Filesystem root beneath which received paths are extracted|"
    )

    SGND_SCRIPT_EXAMPLES=(
        "Receive files beneath the current system root:"
        "  tar -cf - usr/local/bin/example | sudo $SGND_SCRIPT_NAME --target /"
        ""
        "Preview a received stream without extracting it:"
        "  tar -cf - usr/local/bin/example | sudo $SGND_SCRIPT_NAME --target / --dryrun"
    )

    SGND_SCRIPT_GLOBALS=(
    )

    SGND_STATE_VARIABLES=(
    )

    SGND_ON_EXIT_HANDLERS=(
        _cleanup_archive
    )

    SGND_STATE_SAVE=0

# - Local declarations ---------------------------------------------------------------
    DEST_ROOT="${DEST_ROOT:-}"
    RECEIVED_ARCHIVE=""
    RECEIVED_COUNT=0

# - Receive helpers -----------------------------------------------------------------
    # fn: _cleanup_archive - Remove the temporary received archive
        # . Returns
        #   0 always.
        #
        # . Usage
        #   _cleanup_archive
    _cleanup_archive() {
        if [[ -n "${RECEIVED_ARCHIVE:-}" && -f "$RECEIVED_ARCHIVE" ]]; then
            rm -f -- "$RECEIVED_ARCHIVE"
        fi
        return 0
    }

    # fn: _validate_target - Validate and prepare the destination root
        # . Purpose
        #   Ensure the destination is an absolute directory path suitable for extraction.
        #
        # . Returns
        #   0 when the target is valid or can be created.
        #   1 when the target is invalid or cannot be created.
        #
        # . Usage
        #   _validate_target || return $?
    _validate_target() {
        : "${DEST_ROOT:=/}"

        case "$DEST_ROOT" in
            /*) ;;
            *)
                sayfail "Destination root must be an absolute path: $DEST_ROOT"
                return 1
                ;;
        esac

        DEST_ROOT="${DEST_ROOT%/}"
        [[ -n "$DEST_ROOT" ]] || DEST_ROOT="/"

        if [[ -e "$DEST_ROOT" && ! -d "$DEST_ROOT" ]]; then
            sayfail "Destination root is not a directory: $DEST_ROOT"
            return 1
        fi

        if [[ ! -d "$DEST_ROOT" ]]; then
            if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
                sayinfo "Would create destination root: $DEST_ROOT"
            else
                mkdir -p -- "$DEST_ROOT" || {
                    sayfail "Cannot create destination root: $DEST_ROOT"
                    return 1
                }
            fi
        fi

        return 0
    }

    # fn: _receive_stream - Store the incoming tar stream in a temporary archive
        # . Purpose
        #   Capture standard input so the archive can be validated before extraction.
        #
        # . Returns
        #   0 when a non-empty archive stream was received.
        #   1 when the temporary file cannot be created or no data was received.
        #
        # . Usage
        #   _receive_stream || return $?
    _receive_stream() {
        RECEIVED_ARCHIVE="$(mktemp "${TMPDIR:-/tmp}/sgnd-receive-files.XXXXXX.tar")" || {
            sayfail "Cannot create temporary receive archive."
            return 1
        }

        cat > "$RECEIVED_ARCHIVE" || {
            sayfail "Failed while receiving the archive stream."
            return 1
        }

        if [[ ! -s "$RECEIVED_ARCHIVE" ]]; then
            sayfail "No archive data was received on standard input."
            return 1
        fi

        return 0
    }

    # fn: _validate_archive - Validate all received archive entries
        # . Purpose
        #   Reject unsafe paths and non-regular archive entry types before extraction.
        #
        # . Behavior
        #   - Rejects absolute paths and parent-directory traversal.
        #   - Accepts regular files and directories only.
        #   - Counts the entries that will be processed.
        #
        # . Returns
        #   0 when every archive entry is safe.
        #   1 when the archive is unreadable, empty, or contains an unsafe entry.
        #
        # . Usage
        #   _validate_archive || return $?
    _validate_archive() {
        local entry=""
        local listing=""
        local type=""

        listing="$(mktemp "${TMPDIR:-/tmp}/sgnd-receive-list.XXXXXX")" || {
            sayfail "Cannot create temporary archive listing."
            return 1
        }

        if ! tar -tf "$RECEIVED_ARCHIVE" > "$listing"; then
            rm -f -- "$listing"
            sayfail "Received data is not a readable tar archive."
            return 1
        fi

        RECEIVED_COUNT=0
        while IFS= read -r entry; do
            [[ -n "$entry" ]] || continue

            case "$entry" in
                /*|../*|*/../*|*/..|..)
                    rm -f -- "$listing"
                    sayfail "Unsafe archive path rejected: $entry"
                    return 1
                    ;;
            esac

            (( RECEIVED_COUNT += 1 ))
        done < "$listing"

        if (( RECEIVED_COUNT == 0 )); then
            rm -f -- "$listing"
            sayfail "The received archive contains no entries."
            return 1
        fi

        while IFS= read -r type; do
            case "$type" in
                -|d) ;;
                *)
                    rm -f -- "$listing"
                    sayfail "Unsupported archive entry type rejected: $type"
                    return 1
                    ;;
            esac
        done < <(tar -tvf "$RECEIVED_ARCHIVE" | cut -c1)

        rm -f -- "$listing"
        return 0
    }

    # fn: _extract_archive - Extract the validated archive beneath DEST_ROOT
        # . Returns
        #   0 when extraction succeeds or dry-run reporting completes.
        #   1 when tar extraction fails.
        #
        # . Usage
        #   _extract_archive || return $?
    _extract_archive() {
        if [[ "${FLAG_DRYRUN:-0}" -eq 1 ]]; then
            sayinfo "Would extract $RECEIVED_COUNT archive entr$( (( RECEIVED_COUNT == 1 )) && printf 'y' || printf 'ies' ) beneath $DEST_ROOT"
            while IFS= read -r entry; do
                [[ -n "$entry" ]] && sgnd_print "$entry"
            done < <(tar -tf "$RECEIVED_ARCHIVE")
            return 0
        fi

        sayinfo "Extracting $RECEIVED_COUNT archive entr$( (( RECEIVED_COUNT == 1 )) && printf 'y' || printf 'ies' ) beneath $DEST_ROOT"

        tar \
            --extract \
            --file "$RECEIVED_ARCHIVE" \
            --directory "$DEST_ROOT" \
            --no-same-owner \
            --same-permissions \
            --overwrite || {
                sayfail "Failed to extract the received archive beneath: $DEST_ROOT"
                return 1
            }

        return 0
    }

# - Main ----------------------------------------------------------------------------
    # fn: main - Receive, validate, and extract a streamed workspace archive
        # . Arguments
        #   $@  Framework and script-specific arguments.
        #
        # . Returns
        #   0 after successful validation and extraction.
        #   Non-zero when startup, validation, receiving, or extraction fails.
        #
        # . Usage
        #   main "$@"
    main() {
        _framework_locator || exit $?
        sgnd_exe_start --no-clear -- "$@"

        _validate_target || return $?

        saystart "Receiving files for target root $DEST_ROOT"
        _receive_stream || return $?
        _validate_archive || return $?
        _extract_archive || return $?
        sayend "Received files were placed beneath $DEST_ROOT"
        return 0
    }

    main "$@" 
