#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX SDK - Documentation Bundle Manager
# Metadata:
#   Type        : script
#   Group       : SDK
#   Subgroup    : Documentation Generator
#   Purpose     : Manage persistent documentation bundles with the SolidGroundUX UI.
# =====================================================================================
set -uo pipefail

_framework_locator() {
    local script_file="" framework_root="" exe_common=""
    script_file="$(readlink -f "${BASH_SOURCE[0]}")" || return 126
    if [[ "$script_file" == /usr/* ]]; then
        framework_root="/"
    elif [[ "$script_file" == */usr/* ]]; then
        framework_root="${script_file%%/usr/*}"
    else
        printf 'FATAL: Cannot determine SolidGroundUX framework root: %s\n' "$script_file" >&2
        return 126
    fi
    SGND_FRAMEWORK_ROOT="$framework_root"
    exe_common="${framework_root%/}/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"
    [[ "$framework_root" == '/' ]] && exe_common="/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"
    [[ -r "$exe_common" ]] || exe_common="/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"
    [[ -r "$exe_common" ]] || { printf 'FATAL: Missing %s\n' "$exe_common" >&2; return 126; }
    source "$exe_common"
}

SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
SGND_SCRIPT_DIR="$(dirname "$SGND_SCRIPT_FILE")"
SGND_SCRIPT_BASE="$(basename "$SGND_SCRIPT_FILE")"
SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"
SGND_USING=()
SGND_ARGS_SPEC=()
SGND_SCRIPT_GLOBALS=()
SGND_STATE_VARIABLES=("SGND_DOC_ACTIVE_BUNDLE|Active documentation bundle||")
SGND_STATE_SAVE=1
SGND_ON_EXIT_HANDLERS=()

_bundle_python() {
    local script="${SGND_FRAMEWORK_ROOT%/}/usr/local/lib/solidgroundux/py/sgnd_doc_bundles.py"
    [[ "$SGND_FRAMEWORK_ROOT" == '/' ]] && script="/usr/local/lib/solidgroundux/py/sgnd_doc_bundles.py"
    [[ -r "$script" ]] || { sayfail "Bundle manager not found: $script"; return 1; }
    local output="" status=0
    output="$(python3 "$script" "$@" 2>&1)" || status=$?
    if (( status != 0 )); then
        output="${output#ERROR: }"
        sayfail "${output:-Bundle operation failed}"
        return "$status"
    fi
    [[ -z "$output" ]] || printf '%s\n' "$output"
}

# Display widths are local to each view, not global across the application.
_bundle_prompt() {
    local prompt_label="$1" prompt_default="${2:-}" prompt_target="$3"
    local validator="${4:-}" width="${5:-25}"
    local -a options=(--label "$prompt_label" --var "$prompt_target" --default "$prompt_default" --labelwidth "$width" --back)
    [[ -z "$validator" ]] || options+=(--validate "$validator")
    ask "${options[@]}"
}

_bundle_detail() {
    sgnd_print_labeledvalue --label "$1" --value "$2" --labelwidth "${3:-19}"
}

_bundle_validate_overwrite() { [[ "$1" == replace || "$1" == fail ]]; }
_bundle_validate_directory() { [[ -d "$1" ]]; }
_bundle_validate_output() { [[ "$1" == /* ]]; }
_bundle_validate_chapter0() { [[ -z "$1" || "$1" == '-' || -f "$1" ]]; }
_bundle_validate_nonempty() { [[ -n "$1" ]]; }
_bundle_validate_position() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }

_bundle_list() {
    local mode="${1:-list}" raw="" row="" id="" title="" count="" number=0 choice=""
    local -a bundle_ids=()
    raw="$(_bundle_python list-json)" || return $?
    sgnd_print
    sgnd_print_sectionheader "Saved documentation bundles" --padend 0
    while IFS=$'\x1f' read -r id title count; do
        [[ -n "$id" ]] || continue
        ((number+=1))
        bundle_ids+=("$id")
        _bundle_detail "$number" "${title:-'(Untitled)'} ($id) - $count product(s)" 3
    done < <(printf '%s' "$raw" | python3 -c '
import json, sys
for item in json.load(sys.stdin):
    clean = lambda value: str(value).replace("\n", " ").replace("\x1f", " ")
    print("\x1f".join((clean(item["id"]), clean(item["title"]), str(len(item["products"])))) )
')
    if (( number == 0 )); then
        _bundle_detail "Bundles" "None"
        return 0
    fi
    [[ "$mode" == select ]] || return 0
    _bundle_detail "Q" "Back" 3
    while true; do
        choice=""
        _bundle_prompt 'Selection' '' choice '' 10 || return $?
        [[ "${choice^^}" == Q ]] && return 0
        if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && (( 10#$choice <= ${#bundle_ids[@]} )); then
            SGND_DOC_ACTIVE_BUNDLE="${bundle_ids[10#$choice-1]}"
            return 0
        fi
        saywarning "Invalid bundle selection: $choice"
    done
}

_bundle_configure() {
    local raw="" title="" output_dir="" overwrite="" chapter0="" entry="" candidate="" field=""
    local -a current=()
    raw="$(_bundle_python show "$SGND_DOC_ACTIVE_BUNDLE")" || return $?
    mapfile -t current < <(printf '%s\n' "$raw" | python3 -c '
import json, sys
bundle = json.load(sys.stdin)
for field in ("title", "output_dir", "overwrite", "chapter0"):
    print(str(bundle.get(field, "")).replace("\n", " "))
')
    title="${current[0]:-}"
    output_dir="${current[1]:-}"
    overwrite="${current[2]:-replace}"
    chapter0="${current[3]:-}"
    sgnd_print
    sgnd_print_sectionheader "Configure bundle" --padend 0
    _bundle_detail "Bundle" "$SGND_DOC_ACTIVE_BUNDLE"
    _bundle_detail "Chapter 0" "${chapter0:-'(Automatically generated)'}"
    sgnd_print
    sgnd_print "Enter Q to cancel an input. Enter - to clear the Chapter 0 file."
    local width=27
    for field in title output_dir overwrite chapter0; do
        entry=""
        case "$field" in
            title)       _bundle_prompt 'Bundle title' "$title" entry _bundle_validate_nonempty "$width" || return 0 ;;
            output_dir)  _bundle_prompt 'Output directory' "$output_dir" entry _bundle_validate_output "$width" || return 0 ;;
            overwrite)   _bundle_prompt 'Overwrite policy' "$overwrite" entry _bundle_validate_overwrite "$width" || return 0 ;;
            chapter0)    _bundle_prompt 'Chapter 0 Markdown file' "$chapter0" entry _bundle_validate_chapter0 "$width" || return 0 ;;
        esac
        [[ "$entry" == '-' && "$field" == chapter0 ]] && entry=''
        candidate="${!field}"
        [[ "$entry" == "$candidate" ]] && continue
        if ! _bundle_python set "$SGND_DOC_ACTIVE_BUNDLE" "$field" "$entry" >/dev/null; then
            sayfail "Unable to save $field"
            return 1
        fi
        printf -v "$field" '%s' "$entry"
    done
    sgnd_print
    sgnd_print_sectionheader "Bundle configuration" --padend 0
    _bundle_detail "Bundle" "$SGND_DOC_ACTIVE_BUNDLE"
    _bundle_detail "Bundle title" "$title" 25
    _bundle_detail "Output directory" "$output_dir" 25
    _bundle_detail "Overwrite policy" "$overwrite" 25
    _bundle_detail "Chapter 0 Markdown file" "${chapter0:-'(Automatically generated)'}" 25
}

_bundle_product_menu() {
    local action="" id="" title="" source="" position="" raw=""
    local -a current_product=()
    while true; do
        raw="$(_bundle_python show "$SGND_DOC_ACTIVE_BUNDLE")" || return $?
        sgnd_print
        sgnd_print_sectionheader "Manage sources" --padend 0
        _bundle_detail "Bundle" "$SGND_DOC_ACTIVE_BUNDLE"
        sgnd_print "Products in this bundle (read-only):"
        while IFS=$'\x1f' read -r id title source; do
            [[ -n "$id" ]] || continue
            _bundle_detail "$id" "$title ($source)" 18
        done < <(printf '%s' "$raw" | python3 -c '
import json, sys
for p in json.load(sys.stdin)["products"]:
    print("\x1f".join(str(p.get(k, "")).replace("\x1f", " ").replace("\n", " ") for k in ("id", "title", "source_dir")))
')
        _bundle_detail "1" "Add product" 3
        _bundle_detail "2" "Edit product" 3
        _bundle_detail "3" "Move product" 3
        _bundle_detail "4" "Remove product" 3
        _bundle_detail "Q" "Back" 3
        action=""
        _bundle_prompt 'Selection' '' action '' 10 || return 0
        case "${action^^}" in
            Q) return 0 ;;
            1)
                id='' title='' source=''
                _bundle_prompt 'Product identifier' '' id || return $?
                _bundle_prompt 'Chapter title' '' title || return $?
                _bundle_prompt 'Source directory' '' source _bundle_validate_directory || continue
                _bundle_python add-product "$SGND_DOC_ACTIVE_BUNDLE" "$id" "$title" "$source" || true
                ;;
            2)
                id='' title='' source=''
                _bundle_prompt 'Product identifier' '' id || return $?
                raw="$(_bundle_python show "$SGND_DOC_ACTIVE_BUNDLE")" || continue
                current_product=()
                mapfile -t current_product < <(printf '%s' "$raw" | python3 -c '
import json,sys
for p in json.load(sys.stdin)["products"]:
    if p["id"] == sys.argv[1]:
        print(p["title"]); print(p["source_dir"]); break
' "$id")
                if (( ${#current_product[@]} != 2 )); then saywarning "Unknown product: $id"; continue; fi
                _bundle_prompt 'Chapter title' "${current_product[0]}" title || return $?
                _bundle_prompt 'Source directory' "${current_product[1]}" source _bundle_validate_directory || continue
                _bundle_python edit-product "$SGND_DOC_ACTIVE_BUNDLE" "$id" --title "$title" --source-dir "$source" || true
                ;;
            3)
                id='' position=''
                _bundle_prompt 'Product identifier' '' id || return $?
                _bundle_prompt 'New chapter position (1-based)' '' position _bundle_validate_position || continue
                _bundle_python move-product "$SGND_DOC_ACTIVE_BUNDLE" "$id" "$position" || true
                ;;
            4)
                id=''
                _bundle_prompt 'Product identifier' '' id || return $?
                _bundle_python remove-product "$SGND_DOC_ACTIVE_BUNDLE" "$id" || true
                ;;
            *) saywarning 'Unknown option' ;;
        esac
    done
}


_bundle_prepare_markdown() {
    local script="${SGND_FRAMEWORK_ROOT%/}/usr/local/lib/solidgroundux/py/sgnd_doc_markdown.py"
    local docs_root="${SGND_FRAMEWORK_ROOT%/}/usr/local/share/doc-sources"
    local result="" error="" status=0
    [[ "$SGND_FRAMEWORK_ROOT" == '/' ]] && {
        script="/usr/local/lib/solidgroundux/py/sgnd_doc_markdown.py"
        docs_root="/usr/local/share/doc-sources"
    }
    [[ -r "$script" ]] || { sayfail "Markdown generator not found: $script"; return 1; }
    _bundle_python validate "$SGND_DOC_ACTIVE_BUNDLE" >/dev/null || return 1
    sgnd_print
    sgnd_print_sectionheader "Prepare Markdown" --padend 0
    _bundle_detail "Bundle" "$SGND_DOC_ACTIVE_BUNDLE" 19
    local -a args=("$script" "$SGND_DOC_ACTIVE_BUNDLE")
    [[ ! -d "$docs_root" ]] || args+=(--doc-sources "$docs_root")
    result="$(python3 "${args[@]}" 2>&1)" || status=$?
    if (( status != 0 )); then
        sayfail "${result#ERROR: }"
        return "$status"
    fi
    # The Python generator returns one JSON summary. Format it through the SDK UI.
    local summary="" label="" value=""
    summary="$(printf '%s' "$result" | python3 -c '
import json, sys
item = json.load(sys.stdin)
for key, label in (("output", "Output directory"), ("products", "Products"),
                   ("files", "Source files"), ("functions", "Functions"),
                   ("declarations", "Declarations"), ("lines", "Lines")):
    print(label + "\x1f" + str(item.get(key, 0)))
')" || { sayfail 'Unable to read Markdown generation summary'; return 1; }
    sgnd_print
    sgnd_print_sectionheader "Markdown prepared" --padend 0
    while IFS=$'\x1f' read -r label value; do
        [[ -z "$label" ]] || _bundle_detail "$label" "$value" 20
    done <<< "$summary"
}


# _bundle_auto_return
# Returns:
#   0 for Enter or timeout (return to menu); 3 for R (redo action).
# Usage:
#   _bundle_auto_return
_bundle_auto_return() {
    local status=0
    ask_dlg_autocontinue --seconds 60 --message "Enter: menu | R: redo action" --redo --hidelegend || status=$?
    if (( status == 3 )); then
        return 3
    fi
    sgnd_clear
    return 0
}

main() {
    local action="" name="" title="" confirmation="" redo_action="" status=0
    _framework_locator || return $?
    sgnd_exe_start --autostate -- "$@" || return $?
    while true; do
        if [[ -n "$redo_action" ]]; then
            action="$redo_action"
            redo_action=""
        else
            sgnd_print
            sgnd_print_sectionheader "Documentation bundles" --padend 0
            sgnd_print_labeledvalue --label "Active bundle" --value "${SGND_DOC_ACTIVE_BUNDLE:-None}" --labelwidth 18
            sgnd_print
            sgnd_print_sectionheader "Select" --padend 0
            _bundle_detail "1" "List bundles" 3
            _bundle_detail "2" "Select bundle" 3
            sgnd_print
            sgnd_print_sectionheader "Bundle management" --padend 0
            _bundle_detail "3" "Create bundle" 3
            _bundle_detail "4" "Configure bundle" 3
            _bundle_detail "5" "Manage sources" 3
            _bundle_detail "6" "Validate bundle" 3
            _bundle_detail "7" "Delete bundle" 3
            sgnd_print
            sgnd_print_sectionheader "Generation" --padend 0
            _bundle_detail "8" "Prepare Markdown" 3
            sgnd_print
            _bundle_detail "Q" "Exit" 3
            action=""
            _bundle_prompt 'Selection' '' action '' 10 || return 0
        fi
        case "${action^^}" in
            Q) return 0 ;;
            1) _bundle_list || true ;;
            3)
                _bundle_prompt 'Bundle identifier' '' name _bundle_validate_nonempty || continue
                _bundle_prompt 'Bundle title' "$name" title _bundle_validate_nonempty || continue
                name="${name// /-}"
                if _bundle_python create "$name" "$title"; then SGND_DOC_ACTIVE_BUNDLE="$name"; fi
                ;;
            2)
                _bundle_list select || true
                ;;
            4)
                [[ -n "${SGND_DOC_ACTIVE_BUNDLE:-}" ]] || { saywarning 'Select a bundle first'; continue; }
                _bundle_configure || true
                ;;
            5)
                [[ -n "${SGND_DOC_ACTIVE_BUNDLE:-}" ]] || { saywarning 'Select a bundle first'; continue; }
                _bundle_product_menu || return $?
                ;;
            6)
                [[ -n "${SGND_DOC_ACTIVE_BUNDLE:-}" ]] || { saywarning 'Select a bundle first'; continue; }
                _bundle_python validate "$SGND_DOC_ACTIVE_BUNDLE" || true
                ;;
            7)
                [[ -n "${SGND_DOC_ACTIVE_BUNDLE:-}" ]] || { saywarning 'Select a bundle first'; continue; }
                _bundle_prompt 'Type Delete to confirm removal' '' confirmation || return $?
                if [[ "$confirmation" == 'Delete' ]]; then
                    _bundle_python delete "$SGND_DOC_ACTIVE_BUNDLE" && SGND_DOC_ACTIVE_BUNDLE=''
                else
                    saywarning 'Deletion cancelled'
                fi
                ;;
            8)
                [[ -n "${SGND_DOC_ACTIVE_BUNDLE:-}" ]] || { saywarning 'Select a bundle first'; continue; }
                _bundle_prepare_markdown || true
                ;;
            *) saywarning 'Unknown option' ;;
        esac
        status=0
        _bundle_auto_return || status=$?
        if (( status == 3 )); then
            redo_action="$action"
        fi
    done
}
main "$@"
