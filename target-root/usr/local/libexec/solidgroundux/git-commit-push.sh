#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX SDK - Git Commit and Push
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.2
#   Build       : 2630700
#   Checksum    : 03b26cb04b0c37ab1a0c51d811cd459620da4a9c06fcedfdeb4667eb7942ad25
#   Source      : git-commit-push.sh
#   Type        : script
#   Group       : SDK
#   Subgroup    : Source Management
#   Purpose     : Commit and push changes in selected local Git repositories.
#
# Description:
#   Discovers repositories below a source directory, presents a multi-selection,
#   and applies git add ., git commit -m MESSAGE and git push to the selected repos.
#   Remembers the source directory and selected repository paths between runs.
#   Shows an explicit preview and confirmation before changing any repository.
#   Ends with Repeat, End or an automatic timed exit.
#
# Design principles:
#   - Repository operations remain explicit and scoped to each Git worktree root.
#   - Do not automatically create branches, set upstreams or force a push.
#   - Do not replace Git's staging/index or rewrite existing history.
#   - Persist choices as scalar Framework state keys, not sourced shell code.
#
# Role in framework:
#   - SDK developer utility; uses Framework bootstrap, UI and state facilities.
#
# Non-goals:
#   - Release packaging, merging, rebasing, tags or repository configuration.
#
# Usage:
#   ```bash
#   sgnd-git-commit-push ~/development
#   sgnd-git-commit-push --source ~/development
#   sgnd-git-commit-push             # Reuse the saved directory and selection
#   sgnd-git-commit-push --dryrun    # Inspect without add/commit/push
#   ```
#
# Attribution:
#   Developers  : Testadura Consultancy
#   Company     : Testadura Consultancy
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
        #   ```bash
        #   _framework_locator || return $?
        #   ```
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

# - Script metadata (framework integration) -----------------------------------------
    SGND_USING=()
    SGND_ARGS_SPEC=(
        "source|s|value|ARG_SOURCE_DIR|Directory containing Git repositories|"
    )
    SGND_SCRIPT_EXAMPLES=(
        "  sgnd-git-commit-push ~/development"
        "  sgnd-git-commit-push --source ~/development"
        "  sgnd-git-commit-push --dryrun"
        "  sgnd-git-commit-push  # Reuse saved settings"
    )
    SGND_SCRIPT_GLOBALS=()
    SGND_STATE_VARIABLES=( SGND_GIT_SOURCE_DIR SGND_GIT_SELECTED_B64 )
    SGND_ON_EXIT_HANDLERS=()
    SGND_STATE_SAVE=0
    SGND_GIT_SOURCE_DIR=""
    SGND_GIT_SELECTED_B64=""

# - Local state ---------------------------------------------------------------------
    declare -a SGND_GIT_REPOSITORIES=()
    declare -a SGND_GIT_SELECTED_REPOSITORIES=()

# - Internal helpers ----------------------------------------------------------------
    # fn: _git_path_label - Display a repository path relative to the source directory.
        # . Purpose
        #   Format a discovered repository path for a concise selection display.
        # . Arguments
        #   - $1: Canonical Git worktree path.
        # . Output
        #   Writes the relative path, or a dot for the source directory itself.
        # . Usage
        #   ```bash
        #   label="$(_git_path_label "$repository")"
        #   ```
    _git_path_label() {
        local path="$1"
        if [[ "$path" == "$SGND_GIT_SOURCE_DIR" ]]; then
            printf '%s\n' '.'
        else
            printf '%s\n' "${path#"${SGND_GIT_SOURCE_DIR%/}/"}"
        fi
    }

    # fn: _git_restore_selection - Decode saved repository paths without shell evaluation.
        # . Purpose
        #   Read the base64-encoded, NUL-delimited repository selection from Framework state.
        # . Returns
        #   0, with an empty selection when the state value is absent or invalid.
        # . Usage
        #   ```bash
        #   _git_restore_selection
        #   ```
    _git_restore_selection() {
        SGND_GIT_SELECTED_REPOSITORIES=()
        [[ -n "${SGND_GIT_SELECTED_B64:-}" ]] || return 0
        mapfile -d '' -t SGND_GIT_SELECTED_REPOSITORIES < <(
            printf '%s' "$SGND_GIT_SELECTED_B64" | base64 --decode 2>/dev/null
        )
        return 0
    }

    # fn: _git_persist_selection - Save source directory and selected repositories.
        # . Purpose
        #   Persist the directory and all selected absolute paths through Framework state.
        # . Returns
        #   Status of sgnd_state_save_keys.
        # . Usage
        #   ```bash
        #   _git_persist_selection || return $?
        #   ```
    _git_persist_selection() {
        SGND_GIT_SELECTED_B64=""
        if (( ${#SGND_GIT_SELECTED_REPOSITORIES[@]} )); then
            SGND_GIT_SELECTED_B64="$(printf '%s\0' "${SGND_GIT_SELECTED_REPOSITORIES[@]}" | base64 -w0)" || return 1
        fi
        sgnd_state_save_keys --array SGND_STATE_VARIABLES
    }

    # fn: _git_choose_source - Resolve a requested or saved source directory.
        # . Purpose
        #   Accept a positional/--source directory or offer an editable saved path.
        # . Arguments
        #   - $1: Optional explicit directory (empty permits prompting).
        # . Returns
        #   0 on success; 1 on user cancellation; 2 on invalid path.
        # . Usage
        #   ```bash
        #   _git_choose_source "$ARG_SOURCE_DIR" || return $?
        #   ```
    _git_choose_source() {
        local requested="${1:-}"
        local answer=""
        local canonical=""

        if [[ -n "$requested" ]]; then
            answer="$requested"
        else
            ask --label "Source directory" --var answer \
                --default "${SGND_GIT_SOURCE_DIR:-$PWD}" --back || return 1
        fi
        if [[ ! -d "$answer" ]]; then
            sayfail "Source directory does not exist: $answer"
            return 2
        fi
        canonical="$(cd -- "$answer" && pwd -P)" || return 2
        SGND_GIT_SOURCE_DIR="$canonical"
        return 0
    }

    # fn: _git_discover_repositories - Find Git worktree roots below the chosen directory.
        # . Purpose
        #   Discover nested .git directories or worktree pointer files to depth five.
        # . Behavior
        #   - Validates each candidate with git rev-parse --show-toplevel.
        #   - Excludes bare repositories and duplicates.
        #   - Does not follow symlinks or descend into .git internals.
        # . Returns
        #   0 after discovery; 1 when no repositories were found.
        # . Usage
        #   ```bash
        #   _git_discover_repositories || return 1
        #   ```
    _git_discover_repositories() {
        local marker="" candidate="" top=""
        local -A seen=()
        SGND_GIT_REPOSITORIES=()
        while IFS= read -r -d '' marker; do
            candidate="$(dirname -- "$marker")"
            top="$(git -C "$candidate" rev-parse --show-toplevel 2>/dev/null)" || continue
            top="$(realpath -e -- "$top" 2>/dev/null)" || continue
            [[ "$candidate" == "$top" ]] || continue
            [[ -n "${seen[$top]-}" ]] && continue
            seen["$top"]=1
            SGND_GIT_REPOSITORIES+=("$top")
        done < <(find "$SGND_GIT_SOURCE_DIR" -maxdepth 5 \
                    \( -type d -name .git -print0 -prune \) -o \
                    \( -type f -name .git -print0 \) 2>/dev/null | sort -z)
        # The root itself may be a worktree even if .git is outside the scan depth.
        if (( ${#SGND_GIT_REPOSITORIES[@]} == 0 )) && \
           git -C "$SGND_GIT_SOURCE_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
            top="$(git -C "$SGND_GIT_SOURCE_DIR" rev-parse --show-toplevel 2>/dev/null)"
            top="$(realpath -e -- "$top" 2>/dev/null)" || return 1
            [[ "$top" == "$SGND_GIT_SOURCE_DIR" ]] && SGND_GIT_REPOSITORIES+=("$top")
        fi
        (( ${#SGND_GIT_REPOSITORIES[@]} > 0 ))
    }

    # fn: _git_parse_indices - Expand a validated list of repository selection numbers.
        # . Purpose
        #   Convert comma/range selections (and A for all) into a path array.
        # . Arguments
        #   - $1: Selection such as 1,3-5 or A.
        # . Returns
        #   0 for a nonempty valid selection; 1 for invalid/empty selections.
        # . Usage
        #   ```bash
        #   _git_parse_indices "1,3-4"
        #   ```
    _git_parse_indices() {
        local input="${1//[[:space:]]/}" token="" first=0 last=0 i=0
        local -a parts=()
        local -A chosen=()
        SGND_GIT_SELECTED_REPOSITORIES=()
        if [[ "${input^^}" == "A" ]]; then
            SGND_GIT_SELECTED_REPOSITORIES=("${SGND_GIT_REPOSITORIES[@]}")
            return 0
        fi
        IFS=',' read -r -a parts <<< "$input"
        (( ${#parts[@]} )) || return 1
        for token in "${parts[@]}"; do
            if [[ "$token" =~ ^([1-9][0-9]*)-([1-9][0-9]*)$ ]]; then
                first=$((10#${BASH_REMATCH[1]}))
                last=$((10#${BASH_REMATCH[2]}))
                (( first <= last && last <= ${#SGND_GIT_REPOSITORIES[@]} )) || return 1
                for ((i=first; i<=last; i++)); do chosen[$i]=1; done
            elif [[ "$token" =~ ^[1-9][0-9]*$ ]]; then
                i=$((10#$token))
                (( i <= ${#SGND_GIT_REPOSITORIES[@]} )) || return 1
                chosen[$i]=1
            else
                return 1
            fi
        done
        for ((i=1; i<=${#SGND_GIT_REPOSITORIES[@]}; i++)); do
            [[ -n "${chosen[$i]-}" ]] && \
                SGND_GIT_SELECTED_REPOSITORIES+=("${SGND_GIT_REPOSITORIES[i-1]}")
        done
        (( ${#SGND_GIT_SELECTED_REPOSITORIES[@]} ))
    }

    # fn: _git_select_repositories - Present available repositories and saved selections.
        # . Purpose
        #   Allow numbered multi-selection, with saved choices prefilled and Q to cancel.
        # . Returns
        #   0 when repositories were selected and persisted; 1 on cancel/error.
        # . Usage
        #   ```bash
        #   _git_select_repositories || return 1
        #   ```
    _git_select_repositories() {
        local selection="" labels="" path="" index=0 prior="" match=""
        local -a remembered=()
        _git_restore_selection
        remembered=("${SGND_GIT_SELECTED_REPOSITORIES[@]}")
        sgnd_print_sectionheader --text "Repositories"
        for (( index=0; index<${#SGND_GIT_REPOSITORIES[@]}; index++ )); do
            path="${SGND_GIT_REPOSITORIES[index]}"
            match=" "
            for prior in "${remembered[@]}"; do
                [[ "$prior" == "$path" ]] && { match="x"; break; }
            done
            [[ "$match" == "x" ]] && labels+="${labels:+,}$((index+1))"
            sgnd_print --text " $((index+1))) [$match] $(_git_path_label "$path")"
        done
        sgnd_print --text " A) All repositories"
        sgnd_print --text " Q) Return without committing"
        while :; do
            ask --label "Select (1,3-5 / A / Q)" --var selection --default "$labels" --back || return 1
            if _git_parse_indices "$selection"; then
                _git_persist_selection || { sayfail "Cannot save repository selection"; return 1; }
                return 0
            fi
            saywarning "Select at least one valid repository number."
        done
    }

    # fn: _git_preview - Display each chosen repository's branch and working-tree status.
        # . Purpose
        #   Show branch, upstream and all pending changes before asking to proceed.
        # . Returns
        #   0 after printing a preview; 1 if Git cannot inspect a repository.
        # . Usage
        #   ```bash
        #   _git_preview || return 1
        #   ```
    _git_preview() {
        local repo="" branch="" upstream="" status="" line=""
        sgnd_print_sectionheader --text "Git operation preview"
        for repo in "${SGND_GIT_SELECTED_REPOSITORIES[@]}"; do
            sgnd_print --text "Repository: $(_git_path_label "$repo")"
            branch="$(git -C "$repo" branch --show-current 2>/dev/null)" || return 1
            upstream="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" || upstream="(not configured)"
            sgnd_print --text "Branch: ${branch:-'(detached HEAD)'} | Upstream: $upstream"
            status="$(git -C "$repo" status --short 2>/dev/null)" || return 1
            if [[ -z "$status" ]]; then
                sgnd_print --text "  (working tree clean)"
            else
                while IFS= read -r line; do sgnd_print --text "  $line"; done <<< "$status"
            fi
        done
        saywarning "git add . stages ALL changes beneath each repository root, including untracked files."
    }

    # fn: _git_show_git_output - Route external Git output through Framework printing.
        # . Purpose
        #   Display captured Git command output using the Framework's console renderer.
        # . Arguments
        #   - $1: Captured output text.
        # . Usage
        #   ```bash
        #   _git_show_git_output "$output"
        #   ```
    _git_show_git_output() {
        local output="${1:-}" line=""
        [[ -n "$output" ]] || return 0
        while IFS= read -r line; do
            sgnd_print --text "  $line"
        done <<< "$output"
    }

    # fn: _git_execute - Perform add, commit and push in each selected repository.
        # . Purpose
        #   Stage, commit and push selected repositories independently.
        # . Behavior
        #   - Continues processing other repositories after an individual failure.
        #   - Does not push a repository if its commit failed.
        #   - Can push already-pending commits when the working tree is clean.
        #   - In --dryrun mode only describes actions, without staging or pushing.
        # . Arguments
        #   - $1: Commit message, applied to each repository with staged changes.
        # . Returns
        #   0 when all repositories completed; 1 if any repository failed.
        # . Usage
        #   ```bash
        #   _git_execute "Update documentation"
        #   ```
    _git_execute() {
        local message="$1" repo="" output="" rc=0 branch="" failed=0 succeeded=0
        sgnd_print_sectionheader --text "Git results"
        for repo in "${SGND_GIT_SELECTED_REPOSITORIES[@]}"; do
            sgnd_print --text "Repository: $(_git_path_label "$repo")"
            if [[ "${FLAG_DRYRUN:-0}" == 1 ]]; then
                sgnd_print --text "  Dry run: git add .; git commit -m <message>; git push"
                ((succeeded+=1))
                continue
            fi
            branch="$(git -C "$repo" branch --show-current 2>/dev/null)" || branch=""
            if [[ -z "$branch" ]]; then
                sayfail "Detached HEAD, skipping: $repo"
                ((failed+=1)); continue
            fi
            if [[ -n "$(git -C "$repo" ls-files -u)" ]]; then
                sayfail "Unmerged paths; resolve conflicts before committing: $repo"
                ((failed+=1)); continue
            fi
            output="$(git -C "$repo" add . 2>&1)"; rc=$?
            _git_show_git_output "$output"
            if (( rc != 0 )); then
                sayfail "git add . failed ($rc): $repo"
                ((failed+=1)); continue
            fi
            if git -C "$repo" diff --cached --quiet; then
                rc=0
            else
                rc=$?
            fi
            if (( rc == 1 )); then
                output="$(git -C "$repo" commit -m "$message" 2>&1)"; rc=$?
                _git_show_git_output "$output"
                if (( rc != 0 )); then
                    sayfail "git commit failed ($rc): $repo"
                    ((failed+=1)); continue
                fi
            elif (( rc == 0 )); then
                sayinfo "Nothing new to commit; checking for commits to push."
            else
                sayfail "Cannot inspect staged files ($rc): $repo"
                ((failed+=1)); continue
            fi
            output="$(git -C "$repo" push 2>&1)"; rc=$?
            _git_show_git_output "$output"
            if (( rc != 0 )); then
                sayfail "git push failed ($rc): $repo"
                ((failed+=1))
            else
                sayok "Pushed: $(_git_path_label "$repo")"
                ((succeeded+=1))
            fi
        done
        sgnd_print_sectionheader --text "Summary"
        sgnd_print --text "Successful: $succeeded | Failed: $failed"
        (( failed == 0 ))
    }

    # fn: _git_confirm_and_run - Ask for a message and explicit confirmation.
        # . Purpose
        #   Review worktrees, request a commit message and confirm a multi-repo operation.
        # . Returns
        #   0 after execution; 1 on failure; 2 when cancelled before running Git.
        # . Usage
        #   ```bash
        #   _git_confirm_and_run
        #   ```
    _git_confirm_and_run() {
        local message="" choice=""
        _git_preview || { sayfail "Could not preview repositories"; return 1; }
        if [[ "${FLAG_DRYRUN:-0}" != 1 ]]; then
            while :; do
                ask --label "Commit message" --var message --back || return 2
                [[ "$message" =~ [^[:space:]] ]] && break
                saywarning "Commit message cannot be empty."
            done
            ask --label "Proceed? (Yes/No)" --var choice --default "No" --back || return 2
            case "${choice,,}" in
                y|yes) ;;
                *) saycancel "Git operation cancelled"; return 2 ;;
            esac
        else
            message="(dry run)"
        fi
        _git_execute "$message"
    }

    # fn: _git_finish - Offer Repeat, End and automatic timed exit.
        # . Purpose
        #   Return 3 when R is pressed; otherwise end on Enter or countdown expiry.
        # . Returns
        #   3 for Repeat, 0 for End or Auto end.
        # . Usage
        #   ```bash
        #   _git_finish && return 0
        #   ```
    _git_finish() {
        local rc=0
        ask_dlg_autocontinue --seconds 8 --message "Git workflow finished" --redo \
            --legend "R=Repeat; Enter=End; timeout=Auto end" || rc=$?
        (( rc == 3 )) && return 3
        return 0
    }

# - Main ---------------------------------------------------------------------------
    # fn: main - Execute the interactive multi-repository Git workflow.
        # . Purpose
        #   Load the Framework, restore selections and run the selected Git operations.
        # . Arguments
        #   - $@: One optional source directory, --source DIR and Framework options.
        # . Returns
        #   0 after success or cancellation; nonzero for setup or Git failures.
        # . Usage
        #   ```bash
        #   main "$@"
        #   ```
    main() {
        local requested="" rc=0 final_rc=0
        _framework_locator || return $?
        sgnd_exe_start --state -- "$@" || return $?
        command -v git >/dev/null 2>&1 || { sayfail "Git is not installed"; return 127; }
        sgnd_state_load_keys --array SGND_STATE_VARIABLES || return $?
        if (( ${#SGND_BOOTSTRAP_REST[@]} > 1 )); then
            sayfail "Supply at most one source directory."
            return 2
        fi
        if (( ${#SGND_BOOTSTRAP_REST[@]} == 1 )); then
            requested="${SGND_BOOTSTRAP_REST[0]}"
        fi
        if [[ -n "${ARG_SOURCE_DIR:-}" ]]; then
            if [[ -n "$requested" ]]; then
                sayfail "Choose either a positional source directory or --source, not both."
                return 2
            fi
            requested="$ARG_SOURCE_DIR"
        fi
        while :; do
            final_rc=0
            _git_choose_source "$requested"
            rc=$?
            if (( rc == 1 )); then
                saycancel "Git workflow cancelled"
                return 0
            fi
            (( rc == 0 )) || return "$rc"
            requested=""  # Repeats offer an editable saved path.
            if ! _git_discover_repositories; then
                saywarning "No Git repositories found beneath: $SGND_GIT_SOURCE_DIR"
                sgnd_state_save_keys --array SGND_STATE_VARIABLES || return $?
                _git_finish; rc=$?
                (( rc == 3 )) && continue
                return 0
            fi
            _git_select_repositories || { saycancel "Selection cancelled"; return 0; }
            _git_confirm_and_run; rc=$?
            if (( rc == 1 )); then final_rc=1; fi
            _git_finish; rc=$?
            (( rc == 3 )) && continue
            return "$final_rc"
        done
    }

    main "$@"
