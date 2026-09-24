#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX SDK - Prepare Release
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626710
#   Checksum    : 81ee5c900372c55d53b5b06ae01fb1e6fe11fe91cbd8a06e1e5fe2ac44d0d853
#   Source      : prepare-release.sh
#   Type        : script
#   Group       : SDK
#   Purpose     : Prepare framework scripts for release
#
# Description:
#   Provides a release-preparation utility for SolidGroundUX workspaces.
#
#   The script:
#     - Selects target scripts by file or folder
#     - Refreshes version, build, and checksum metadata unless source updates are disabled
#     - Applies optional major or minor version bumps
#     - Supports dry-run verification before committing changes
#     - Ensures release metadata is consistent across processed scripts
#     - Verifies public command wrappers for executable top-level libexec scripts
#     - Creates release tar/manifests/checksums and a complete distributable release ZIP
#     - Writes release-package.info at ZIP root so the package identifies its project/release
#     - Uses an explicit removal-baseline manifest from persistent manifest history
#     - Ships release-manager.sh only with the SolidGroundUX framework bootstrap package
#
# Design principles:
#   - Release preparation is deterministic and repeatable
#   - Metadata updates are explicit and convention-based
#   - Safe verification is supported through dry-run mode
#   - Script formatting is preserved when updating field values
#
# Role in framework:
#   - Pre-release maintenance tool for framework and utility scripts
#   - Ensures release metadata is synchronized before distribution
#
# Non-goals:
#   - Deploying files to target environments
#   - Managing version control, tagging, or publication workflows
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

# - Script metadata (framework integration) -----------------------------------------
    # SGND_USING
        # Libraries to source from SGND_COMMON_LIB.
        # These are loaded automatically by sgnd_bootstrap AFTER core libraries.
        #
        # Example:
        #   SGND_USING=( net.sh fs.sh )
        #
        # Leave empty if no extra libs are needed.
    SGND_USING=(
        sgnd-comment-header-parser.sh
    )

    # SGND_ARGS_SPEC
        # Each entry:
        #   "name|short|type|var|help|choices"
        #
        #   name    = long option name WITHOUT leading --
        #   short   - short option name WITHOUT leading -
        #   type    = flag | value | enum
        # var: = shell variable that will be set
        #   help    = help string for auto-generated --help output
        #   choices = for enum: comma-separated values (e.g. fast,slow,auto)
        #             for flag/value: leave empty
        #
        # Notes:
        #   - -h / --help is built in, you don't need to define it here.
        #   - After parsing you can use: FLAG_VERBOSE, VAL_CONFIG, ENUM_MODE, ...
    SGND_ARGS_SPEC=(
        "auto|a|flag|FLAG_AUTO|Repeat with last settings|0|"
        "cleanup|c|flag|FLAG_CLEANUP|Cleanup staging files after run|1|"
        "useexisting|u|flag|FLAG_USEEXISTING|Use existing staging files|1|"
        "bumpmajor||flag|FLAG_BUMP_MAJOR|Bump major version in source headers before packaging|"
        "bumpminor||flag|FLAG_BUMP_MINOR|Bump minor version in source headers before packaging|"
        "updatebuild||enum|MODE_UPDATEBUILD|Build metadata policy: A=all, C=changed, N=none|C"
        "updateversion||enum|MODE_UPDATEVERSION|Version metadata policy: A=all, C=changed, N=none|C"
        "createwrappers|w|flag|FLAG_CREATEWRAPPERS|Create missing /usr/local/bin wrappers for top-level libexec scripts|1|"
        "normalizecanon||flag|FLAG_NORMALIZE_CANON|Normalize canonical framework/guard structures before metadata processing|1|"
        "previous-manifest||value|PREVIOUS_MANIFEST|Removal baseline manifest path|"
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
        "Run in dry-run mode:"
        "  $SGND_SCRIPT_NAME --dryrun"
        ""
        "Show verbose logging"
        "  $SGND_SCRIPT_NAME --verbose"
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
        #   - Variables listed here can be loaded and saved explicitly by the script.
        #   - On startup, previously saved values are restored before main logic runs.
        #
        # Contract:
        #   - Variables must be simple scalars (no arrays/associatives unless explicitly supported).
        #   - Script remains fully functional when state is disabled.
        #
        # Leave empty if:
        #   - The script does not use persistent state.
   SGND_STATE_VARIABLES=(
        SOURCE_DIR
        STAGING_ROOT
        FLAG_CLEANUP
        FLAG_USEEXISTING
        FLAG_SAVEPARMS
        MODE_UPDATEBUILD
        MODE_UPDATEVERSION
        FLAG_CREATEWRAPPERS
        FLAG_NORMALIZE_CANON
        PREVIOUS_MANIFEST
        DEVELOPMENT_ROOT
        COMPANION_PRODUCT_PATHS
        FLAG_CREATE_INDIVIDUAL_RELEASES
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

    # Automatic state saving is disabled.
        # State is loaded explicitly and saved only when FLAG_SAVEPARMS=1.
    SGND_STATE_SAVE=0

# - Local script Declarations -------------------------------------------------------
    # Put script-local constants and defaults here (NOT framework config).
    # Prefer local variables inside functions unless a value must be shared.

    # Selected release products, ordered with the primary product first.
    RELEASE_PRODUCT_NAMES=()
    RELEASE_PRODUCT_VERSIONS=()
    RELEASE_PRODUCT_BUILDS=()
    RELEASE_PRODUCT_VERSION_MODES=()
    RELEASE_PRODUCT_BUILD_MODES=()
    RELEASE_PRODUCT_BASELINES=()
    BUNDLE_PREVIOUS_MANIFEST=""

# - Local script functions ----------------------------------------------------------
    # fn$ _release_resolve_project_identity - Resolve the authoritative project definitions
        # . Usage
        #   _release_resolve_project_identity "<script>"
    _release_resolve_project_identity() {
        local globals_dir="${SOURCE_DIR%/}/usr/local/lib/solidgroundux/globals"
        local file="" base="" slug="" key="" product_var="" version_var=""
        local -a project_defs=()
        PROJECT_DEFINITIONS_FILE=""
        PROJECT_DEFINITIONS_KEY=""
        PROJECT_IS_FRAMEWORK=0
        PROJECT_SLUG=""

        [[ -d "$globals_dir" ]] || { sayfail "Project globals directory not found: $globals_dir"; return 1; }

        if [[ -f "$globals_dir/sgnd-definitions.sh" ]]; then
            PROJECT_DEFINITIONS_FILE="$globals_dir/sgnd-definitions.sh"
            PROJECT_DEFINITIONS_KEY="SGND"
            PROJECT_IS_FRAMEWORK=1
            PROJECT_SLUG="solidgroundux"
            source "$PROJECT_DEFINITIONS_FILE"
            PRODUCT="${SGND_PRODUCT:-SolidGroundUX}"
            VERSION="${SGND_VERSION:-}"
            [[ -n "$VERSION" ]] || return 1
            return 0
        fi

        while IFS= read -r -d '' file; do project_defs+=("$file"); done < <(
            find "$globals_dir" -maxdepth 1 -type f -name '*-definitions.sh' -print0 2>/dev/null | sort -z
        )
        (( ${#project_defs[@]} == 1 )) || { sayfail "Expected exactly one project definitions file in $globals_dir; found ${#project_defs[@]}"; return 1; }

        PROJECT_DEFINITIONS_FILE="${project_defs[0]}"
        base="$(basename -- "$PROJECT_DEFINITIONS_FILE")"
        slug="${base%-definitions.sh}"
        PROJECT_SLUG="$slug"
        source "$PROJECT_DEFINITIONS_FILE"

        # The filename is a filesystem identity, not the authoritative variable prefix.
        # Discover the product variable from the definitions content so renamed/slightly
        # different project slugs do not break version/build updates.
        product_var="$(sed -n -E 's/^[[:space:]]*(SGND_[A-Za-z0-9_]+_PRODUCT)[[:space:]]*=.*$/\1/p' "$PROJECT_DEFINITIONS_FILE" | head -n 1)"
        [[ -n "$product_var" ]] || { sayfail "Project product global missing in: $PROJECT_DEFINITIONS_FILE"; return 1; }

        key="${product_var#SGND_}"
        key="${key%_PRODUCT}"
        PROJECT_DEFINITIONS_KEY="$key"
        version_var="SGND_${key}_VERSION"
        PRODUCT="${!product_var-}"
        VERSION="${!version_var-}"
        [[ -n "$PRODUCT" ]] || { sayfail "Project product global is empty: $product_var"; return 1; }
        [[ -n "$VERSION" ]] || { sayfail "Project version global missing: $version_var"; return 1; }
    }

    # fn$ _release_product_record - Read product metadata from one target-root
    _release_product_record() {
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

    # fn$ _release_product_excludes - Return the complete release exclusion policy for a product root
    _release_product_excludes() {
        local root="${1:?missing target root}"
        local repo_root="" ignore_file="" line=""
        local globals_dir="${root%/}/usr/local/lib/solidgroundux/globals" file="" value=""

        # Mandatory release safety policy. These paths are runtime/development state and
        # must never be shipped, even when a repository has no .release-ignore file.
        printf '%s\n' \
            '.*' \
            '*.state' \
            '*.cfg' \
            '*.code-workspace' \
            '/var/log/solidgroundux.log*' \
            '/var/lib/solidgroundux/archive/' \
            '/var/lib/solidgroundux/releases/' \
            '/var/lib/solidgroundux/projects/'

        # A normal product workspace packages <repo>/target-root. Keep release policy at
        # repository root so it is versioned with the product without becoming payload.
        if [[ "$(basename -- "$root")" == "target-root" ]]; then
            repo_root="$(dirname -- "$root")"
            ignore_file="${repo_root%/}/.release-ignore"
            if [[ -f "$ignore_file" ]]; then
                while IFS= read -r line || [[ -n "$line" ]]; do
                    line="${line#"${line%%[![:space:]]*}"}"
                    line="${line%"${line##*[![:space:]]}"}"
                    [[ -n "$line" && "$line" != \#* ]] && printf '%s\n' "$line"
                done < "$ignore_file"
            fi
        fi

        # Product definitions may add exceptional/generated exclusions dynamically.
        [[ -d "$globals_dir" ]] || return 0
        while IFS= read -r -d '' file; do
            value="$(bash -c '
                source "$1"
                for var in $(compgen -A variable SGND_); do
                    case "$var" in *_RELEASE_EXCLUDES|SGND_RELEASE_EXCLUDES) printf "%s\\n" "${!var-}"; exit;; esac
                done
            ' bash "$file" 2>/dev/null || true)"
            [[ -n "$value" ]] || continue
            tr ',' '\n' <<< "$value"
            return 0
        done < <(find "$globals_dir" -maxdepth 1 -type f \( -name 'sgnd-definitions.sh' -o -name '*-definitions.sh' \) -print0 2>/dev/null | sort -z)
    }

    # fn$ _release_parse_product_selection - Parse A/comma/range product selection
    _release_parse_product_selection() {
        local spec="${1:-}" max="${2:-0}" token="" begin="" finish="" i=0 idx=0
        local -n out_ref=$3
        local -A seen=()
        out_ref=()
        spec="${spec//[[:space:]]/}"
        [[ -n "$spec" ]] || return 1
        if [[ "${spec^^}" == "A" ]]; then
            for (( i=1; i<=max; i++ )); do out_ref+=("$i"); done
            return 0
        fi
        IFS=',' read -r -a _tokens <<< "$spec"
        for token in "${_tokens[@]}"; do
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

    # fn$ _release_select_products - Select the product(s) that participate in this release
    _release_select_products() {
        local repo="" root="" record="" product="" version="" build="" defs=""
        local selection="" primary_choice="1" answer="N" primary_pos=1 i=0 index=0
        local current_repo="" current_root="${SOURCE_DIR:-$SGND_FRAMEWORK_ROOT}"
        local -a roots=() products=() versions=() builds=() definitions=() selected_indexes=()
        local -a selected_roots=() selected_products=() selected_versions=() selected_builds=()

        [[ "$(basename -- "$current_root")" == "target-root" ]] && current_repo="$(dirname -- "$current_root")"
        DEVELOPMENT_ROOT="${DEVELOPMENT_ROOT:-$(dirname -- "${current_repo:-$current_root}")}"

        # Product discovery starts with the development root. This is the registry root
        # beneath which releasable product workspaces are discovered.
        if (( ! ${FLAG_AUTO:-0} )); then
            sgnd_print
            sgnd_print_sectionheader "Product discovery" --padend 0
            ask --label "Development root" --var DEVELOPMENT_ROOT --default "$DEVELOPMENT_ROOT" \
                --validate sgnd_validate_dir_exists --colorize both --labelclr "${CYAN}" --labelwidth 30
        fi
        DEVELOPMENT_ROOT="${DEVELOPMENT_ROOT%/}"
        [[ -d "$DEVELOPMENT_ROOT" ]] || { sayfail "Development root not found: $DEVELOPMENT_ROOT"; return 1; }

        while IFS= read -r -d '' repo; do
            root="$repo/target-root"
            [[ -d "$root" ]] || continue
            record="$(_release_product_record "$root" 2>/dev/null || true)"
            [[ -n "$record" ]] || continue
            IFS='|' read -r product version build defs <<< "$record"
            roots+=("$root"); products+=("$product"); versions+=("$version"); builds+=("$build"); definitions+=("$defs")
        done < <(find "$DEVELOPMENT_ROOT" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

        (( ${#roots[@]} > 0 )) || { sayfail "No releasable products found below: $DEVELOPMENT_ROOT"; return 1; }

        sgnd_print
        sgnd_print_sectionheader "Release products" --padend 0
        for i in "${!roots[@]}"; do
            sgnd_print "$((i+1)) : ${products[$i]}  v${versions[$i]}.${builds[$i]}"
        done
        (( ${#roots[@]} > 1 )) && sgnd_print "A : All products"
        sgnd_print

        while true; do
            selection="${PRODUCT_SELECTION:-A}"
            (( ${#roots[@]} == 1 )) && selection="1"
            ask --label "Products (comma/range or A)" --var selection --default "$selection" --colorize both --labelclr "${CYAN}" --labelwidth 30
            if _release_parse_product_selection "$selection" "${#roots[@]}" selected_indexes; then
                break
            fi
            saywarning "Invalid product selection: $selection"
        done
        PRODUCT_SELECTION="$selection"

        for index in "${selected_indexes[@]}"; do
            i=$((index-1))
            selected_roots+=("${roots[$i]}")
            selected_products+=("${products[$i]}")
            selected_versions+=("${versions[$i]}")
            selected_builds+=("${builds[$i]}")
        done

        # Each selected product can use a different source tree. Discovery supplies the
        # default, but the operator may point a product at another assembled target-root.
        sgnd_print
        sgnd_print_sectionheader "Product source directories" --padend 0
        for i in "${!selected_roots[@]}"; do
            root="${selected_roots[$i]}"
            ask --label "${selected_products[$i]}" --var root --default "$root" --validate sgnd_validate_dir_exists --colorize both --labelclr "${CYAN}" --labelwidth 46
            selected_roots[$i]="${root%/}"
            record="$(_release_product_record "${selected_roots[$i]}" 2>/dev/null || true)"
            [[ -n "$record" ]] || { sayfail "No product definitions found below: ${selected_roots[$i]}"; return 1; }
            IFS='|' read -r product version build defs <<< "$record"
            selected_products[$i]="$product"
            selected_versions[$i]="$version"
            selected_builds[$i]="$build"
        done

        # Prefer SolidGroundUX as the primary identity when it is among the selected products.
        primary_pos=1
        for i in "${!selected_products[@]}"; do
            [[ "${selected_products[$i]}" == "SolidGroundUX" ]] && { primary_pos=$((i+1)); break; }
        done

        if (( ${#selected_roots[@]} > 1 )); then
            sgnd_print
            sgnd_print_sectionheader "Primary release product" --padend 0
            for i in "${!selected_roots[@]}"; do
                sgnd_print "$((i+1)) : ${selected_products[$i]}  v${selected_versions[$i]}.${selected_builds[$i]}"
            done
            primary_choice="$primary_pos"
            ask --label "Primary product" --var primary_choice --default "$primary_choice" --colorize both --labelclr "${CYAN}" --labelwidth 30
            [[ "$primary_choice" =~ ^[0-9]+$ ]] && (( primary_choice >= 1 && primary_choice <= ${#selected_roots[@]} )) || {
                sayfail "Invalid primary product selection: $primary_choice"
                return 1
            }
        else
            primary_choice=1
        fi

        # Put the primary product first; the remaining products are bundle overlays.
        RELEASE_SOURCE_DIRS=("${selected_roots[$((primary_choice-1))]}")
        RELEASE_PRODUCT_NAMES=("${selected_products[$((primary_choice-1))]}")
        RELEASE_PRODUCT_VERSIONS=("${selected_versions[$((primary_choice-1))]}")
        RELEASE_PRODUCT_BUILDS=("${selected_builds[$((primary_choice-1))]}")
        for i in "${!selected_roots[@]}"; do
            (( i == primary_choice-1 )) && continue
            RELEASE_SOURCE_DIRS+=("${selected_roots[$i]}")
            RELEASE_PRODUCT_NAMES+=("${selected_products[$i]}")
            RELEASE_PRODUCT_VERSIONS+=("${selected_versions[$i]}")
            RELEASE_PRODUCT_BUILDS+=("${selected_builds[$i]}")
        done
        SOURCE_DIR="${RELEASE_SOURCE_DIRS[0]}"
        COMPANION_PRODUCT_PATHS=""
        for root in "${RELEASE_SOURCE_DIRS[@]:1}"; do
            [[ -n "$COMPANION_PRODUCT_PATHS" ]] && COMPANION_PRODUCT_PATHS+=","
            COMPANION_PRODUCT_PATHS+="$root"
        done

        FLAG_CREATE_INDIVIDUAL_RELEASES="${FLAG_CREATE_INDIVIDUAL_RELEASES:-0}"
        if (( ${#RELEASE_SOURCE_DIRS[@]} > 1 )); then
            answer="N"
            (( FLAG_CREATE_INDIVIDUAL_RELEASES )) && answer="Y"
            ask --label "Also create individual product releases (Y/N)" --var answer --default "$answer" --choices "Y,Yes,N,No" --colorize both --labelclr "${CYAN}" --labelwidth 46
            case "${answer^^}" in Y|YES) FLAG_CREATE_INDIVIDUAL_RELEASES=1 ;; *) FLAG_CREATE_INDIVIDUAL_RELEASES=0 ;; esac
        else
            FLAG_CREATE_INDIVIDUAL_RELEASES=0
        fi

        _release_resolve_project_identity || return 1
    }

    # fn$ _release_write_bundle_manifest - Record products included in an assembled release
    _release_write_bundle_manifest() {
        local stage="${1:?missing stage}" product_index=0 root="" record="" product="" version="" build="" defs=""
        (( ${FLAG_DRYRUN:-0} )) && return 0
        {
            printf '# SolidGroundUX assembled release products\n'
            for product_index in "${!RELEASE_SOURCE_DIRS[@]}"; do
                root="${RELEASE_SOURCE_DIRS[$product_index]}"
                record="$(_release_product_record "$root" 2>/dev/null || true)"
                [[ -n "$record" ]] || continue
                IFS='|' read -r product version build defs <<< "$record"
                version="${RELEASE_PRODUCT_VERSIONS[$product_index]:-$version}"
                build="${RELEASE_PRODUCT_BUILDS[$product_index]:-$build}"
                printf '%s|%s|%s|%s\n' "$product" "$version" "$build" "$defs"
            done
        } > "$stage/RELEASE-PRODUCTS"
    }

    # fn$ _release_update_project_identity - Update version/build in the correct definitions file
        # . Usage
        #   _release_update_project_identity
    _release_update_project_identity() {
        local file="${PROJECT_DEFINITIONS_FILE:-}" key="${PROJECT_DEFINITIONS_KEY:-}"
        local version_var="" build_var="" checksum=""
        [[ -f "$file" ]] || return 1

        if (( ${FLAG_DRYRUN:-0} )); then
            sayinfo "[DRYRUN] Would update project identity in $file to $VERSION.$BUILD"
            return 0
        fi

        if (( ${PROJECT_IS_FRAMEWORK:-0} )); then
            sgnd_framework_set_version "$file" "$VERSION" "$BUILD"
            return $?
        fi

        version_var="SGND_${key}_VERSION"
        build_var="SGND_${key}_BUILD"
        # Project definitions are canonically indented, so assignment matching must
        # accept leading whitespace just as identity discovery already does.
        grep -Eq "^[[:space:]]*${version_var}[[:space:]]*=" "$file" || {
            sayfail "Project version global missing from definitions: $version_var ($file)"
            return 1
        }
        grep -Eq "^[[:space:]]*${build_var}[[:space:]]*=" "$file" || {
            sayfail "Project build global missing from definitions: $build_var ($file)"
            return 1
        }
        sed -i -E "s|^([[:space:]]*)${version_var}[[:space:]]*=.*$|\1${version_var}=$(printf '%q' "$VERSION")|" "$file" || {
            sayfail "Could not update project version global: $version_var ($file)"
            return 1
        }
        sed -i -E "s|^([[:space:]]*)${build_var}[[:space:]]*=.*$|\1${build_var}=$(printf '%q' "$BUILD")|" "$file" || {
            sayfail "Could not update project build global: $build_var ($file)"
            return 1
        }
        sgnd_header_upsert_field "$file" "Metadata" "Version" "$VERSION" || {
            sayfail "Could not update definitions header Version: $file"
            return 1
        }
        sgnd_header_upsert_field "$file" "Metadata" "Build" "$BUILD" || {
            sayfail "Could not update definitions header Build: $file"
            return 1
        }
        checksum="$(sgnd_header_calc_checksum "$file")" || {
            sayfail "Could not calculate definitions checksum: $file"
            return 1
        }
        sgnd_header_upsert_field "$file" "Metadata" "Checksum" "$checksum" || {
            sayfail "Could not update definitions header Checksum: $file"
            return 1
        }
    }

    # fn$ _release_wrapper_name_for_script - Resolve wrapper metadata or conventional name
        # . Usage
        #   _release_wrapper_name_for_script "<script>"
    _release_wrapper_name_for_script() {
        local script="${1:-}" wrapper_name="" base=""
        if sgnd_header_get_field "$script" "Metadata" "Wrapper" wrapper_name 2>/dev/null; then
            wrapper_name="${wrapper_name#"${wrapper_name%%[![:space:]]*}"}"
            wrapper_name="${wrapper_name%"${wrapper_name##*[![:space:]]}"}"
            [[ -n "$wrapper_name" ]] && { printf '%s\n' "$wrapper_name"; return 0; }
        fi
        base="$(basename -- "$script")"; base="${base%.sh}"
        [[ "$base" == sgnd-* ]] && printf '%s\n' "$base" || printf 'sgnd-%s\n' "$base"
    }

    # _get_parameters
        # . Purpose
        #   Resolve and collect all parameters required to prepare a release archive.
        #
        # . Behavior
        #   - Computes default values from framework metadata and workspace paths.
        #   - In auto mode, reuses existing or default values without prompting.
        #   - In interactive mode, prompts for release settings and confirms them.
        #   - Saves confirmed parameters through _save_parameters().
        #
        # Parameters handled:
        #   RELEASE
        #       Release identifier used for staging and filenames
        #   RELEASE_SOURCE_DIRS
        #       Product-specific source directories selected during product discovery
        #   STAGING_ROOT
        #       Root directory containing staging files and release outputs
        #   TAR_FILE
        #       Final tar.gz filename
        #   FLAG_CLEANUP
        #       Whether to remove staging files after completion
        #   FLAG_USEEXISTING
        #       Whether to reuse a non-empty staging tree
        #
        # Outputs (globals):
        #   RELEASE
        #   RELEASE_SOURCE_DIRS
        #   STAGING_ROOT
        #   TAR_FILE
        #   FLAG_AUTO
        #   FLAG_CLEANUP
        #   FLAG_USEEXISTING
        #
        # . Returns
        #   0 on successful resolution and confirmation
        #   Exits the script with status 1 if the user cancels
        #
        # . Usage
        #   _get_parameters
        #
        # Examples:
        #   _get_parameters || return 1
        #
        # Notes:
        #   - Uses ask() and ask_ok_redo_quit() for interactive input.
        #   - Auto mode assumes state was loaded during bootstrap (--state).
    # fn: _get_parameters - Collect prepare-release parameters
        # . Purpose
        #   Collect prepare-release parameters.
        #
        # . Behavior
        #
        # . Returns
        #   Returns the underlying command or workflow status.
        #
        # . Usage
        #   _get_parameters
    _get_parameters(){
        FLAG_AUTO="${FLAG_AUTO:-0}"
        FLAG_CLEANUP="${FLAG_CLEANUP:-1}"
        FLAG_USEEXISTING="${FLAG_USEEXISTING:-1}"
        FLAG_SAVEPARMS="${FLAG_SAVEPARMS:-1}"
        MODE_UPDATEBUILD="${MODE_UPDATEBUILD:-C}"
        MODE_UPDATEVERSION="${MODE_UPDATEVERSION:-C}"
        FLAG_CREATEWRAPPERS="${FLAG_CREATEWRAPPERS:-1}"
        FLAG_NORMALIZE_CANON="${FLAG_NORMALIZE_CANON:-1}"
        PREVIOUS_MANIFEST="${PREVIOUS_MANIFEST:-}"

        # Persisted user choices are loaded in main before project identity resolution.

        PRODUCT="${PRODUCT:?project identity not resolved}"
        VERSION="${VERSION:?project identity not resolved}"
        BUILD="$(date +%y%j%H)"

        SOURCE_DIR="${SOURCE_DIR:-"$SGND_FRAMEWORK_ROOT"}"

        if [[ -z "${STAGING_ROOT:-}" ]]; then
            if [[ "$SGND_FRAMEWORK_ROOT" == "/" ]]; then
                STAGING_ROOT="/var/local/lib/solidgroundux/releases"
            else
                STAGING_ROOT="$(dirname "$SGND_FRAMEWORK_ROOT")/releases"
            fi
        fi

        # Derived state: always follow the resolved staging root.
        MANIFEST_HISTORY_DIR="${STAGING_ROOT%/}/manifest-history"
        
        if [[ "${FLAG_AUTO:-0}" -eq 1 ]]; then
             local auto_index=0
             RELEASE_PRODUCT_VERSION_MODES=()
             RELEASE_PRODUCT_BUILD_MODES=()
             RELEASE_PRODUCT_BASELINES=()
             BUNDLE_PREVIOUS_MANIFEST=""
             for auto_index in "${!RELEASE_PRODUCT_NAMES[@]}"; do
                 RELEASE_PRODUCT_VERSION_MODES+=("${MODE_UPDATEVERSION^^}")
                 RELEASE_PRODUCT_BUILD_MODES+=("${MODE_UPDATEBUILD^^}")
                 RELEASE_PRODUCT_BUILDS[$auto_index]="$BUILD"
             done
             VERSION="${RELEASE_PRODUCT_VERSIONS[0]}"
             for auto_index in "${!RELEASE_PRODUCT_NAMES[@]}"; do
                 if (( ${#RELEASE_SOURCE_DIRS[@]} == 1 || ${FLAG_CREATE_INDIVIDUAL_RELEASES:-0} )); then
                     _sgnd_release_select_product_baseline "$auto_index" || return 1
                 else
                     RELEASE_PRODUCT_BASELINES[$auto_index]=""
                 fi
             done
             if (( ${#RELEASE_SOURCE_DIRS[@]} > 1 )); then
                 _sgnd_release_select_bundle_baseline || return 1
             else
                 BUNDLE_PREVIOUS_MANIFEST=""
             fi
             sayinfo "Auto mode: using last deployment or default settings."
             return 0
        fi
        local lw=20
        local lp=4
        while true; do
            sgnd_print
            sgnd_print_sectionheader "Release locations" --padend 0
            ask --label "Staging directory" --var STAGING_ROOT --default "$STAGING_ROOT" --colorize both --labelclr "${CYAN}" --pad "$lp" --labelwidth "$lw"

            sgnd_print
            sgnd_print_sectionheader "Release identification" --padend 0
            sgnd_print_labeledvalue --label "Product" --value "$PRODUCT" --colorize both --labelclr "${CYAN}" --pad "$lp" --labelwidth "$lw"
            sgnd_print_labeledvalue --label "Version" --value "$VERSION" --colorize both --labelclr "${CYAN}" --pad "$lp" --labelwidth "$lw"
            sgnd_print_labeledvalue --label "Build" --value "$BUILD" --colorize both --labelclr "${CYAN}" --pad "$lp" --labelwidth "$lw"

            sgnd_print
            RELEASE="${RELEASE:-"$(_release_product_artifact_name "$PRODUCT")-$VERSION.$BUILD"}"
            ask --label "Release" --var RELEASE --default "$RELEASE" --colorize both --labelclr "${CYAN}" --pad "$lp" --labelwidth "$lw"
            RELEASE="$(printf '%s\n' "$RELEASE" | sed -E 's/[[:space:]]+/-/g')"
            TAR_FILE="${TAR_FILE:-"$RELEASE.tar.gz"}"
            ask --label "Tar file" --var TAR_FILE --default "$TAR_FILE" --colorize both --labelclr "${CYAN}" --pad "$lp" --labelwidth "$lw"

            if (( ${#RELEASE_SOURCE_DIRS[@]} > 1 )); then
                sgnd_print
                sgnd_print_sectionheader "Bundled products" --padend 0
                local bundle_root="" bundle_record="" bundle_product="" bundle_version="" bundle_build="" bundle_defs=""
                for bundle_root in "${RELEASE_SOURCE_DIRS[@]}"; do
                    bundle_record="$(_release_product_record "$bundle_root" 2>/dev/null || true)"
                    [[ -n "$bundle_record" ]] || continue
                    IFS='|' read -r bundle_product bundle_version bundle_build bundle_defs <<< "$bundle_record"
                    sgnd_print_labeledvalue --label "$bundle_product" --value "v${bundle_version}.${bundle_build}" --colorize both --labelclr "${CYAN}" --pad "$lp" --labelwidth 46
                done
                sgnd_print_labeledvalue --label "Individual product releases" --value "$([[ ${FLAG_CREATE_INDIVIDUAL_RELEASES:-0} -eq 1 ]] && printf Yes || printf No)" --colorize both --labelclr "${CYAN}" --pad "$lp" --labelwidth 46
                sgnd_print_labeledvalue --label "Bundled release" --value "$(_release_product_artifact_name "$PRODUCT")-bundled-$VERSION.$BUILD" --colorize both --labelclr "${CYAN}" --pad "$lp" --labelwidth 46
            fi

            sgnd_print
            sgnd_print_sectionheader "Release metadata" --padend 0
            local product_index=0 product_version="" product_version_mode="" product_build_mode=""
            for product_index in "${!RELEASE_PRODUCT_NAMES[@]}"; do
                sgnd_print_labeledvalue --label "Product" --value "${RELEASE_PRODUCT_NAMES[$product_index]}" --colorize both --labelclr "${CYAN}" --pad "$lp" --labelwidth "$lw"
                product_version="${RELEASE_PRODUCT_VERSIONS[$product_index]}"
                ask --label "  Version" --var product_version --default "$product_version" --colorize both --labelclr "${CYAN}" --pad "$lp" --labelwidth "$lw"
                RELEASE_PRODUCT_VERSIONS[$product_index]="$product_version"
                sgnd_print_labeledvalue --label "  Build" --value "$BUILD" --colorize both --labelclr "${CYAN}" --pad "$lp" --labelwidth "$lw"
                RELEASE_PRODUCT_BUILDS[$product_index]="$BUILD"
                product_version_mode="${RELEASE_PRODUCT_VERSION_MODES[$product_index]:-${MODE_UPDATEVERSION:-C}}"
                product_build_mode="${RELEASE_PRODUCT_BUILD_MODES[$product_index]:-${MODE_UPDATEBUILD:-C}}"
                ask_decision --label "  Update version (A/C/N)" \
                    --choices "A,C,N" --default "${product_version_mode^^}" --var product_version_mode \
                    --displaychoices 0 --colorize both --labelclr "${CYAN}" --pad "$lp" --labelwidth "$lw"
                ask_decision --label "  Update build (A/C/N)" \
                    --choices "A,C,N" --default "${product_build_mode^^}" --var product_build_mode \
                    --displaychoices 0 --colorize both --labelclr "${CYAN}" --pad "$lp" --labelwidth "$lw"
                RELEASE_PRODUCT_VERSION_MODES[$product_index]="${product_version_mode^^}"
                RELEASE_PRODUCT_BUILD_MODES[$product_index]="${product_build_mode^^}"
                sgnd_print
            done
            VERSION="${RELEASE_PRODUCT_VERSIONS[0]}"
            for product_index in "${!RELEASE_PRODUCT_BUILDS[@]}"; do
                RELEASE_PRODUCT_BUILDS[$product_index]="$BUILD"
            done
            # Release filenames follow the selected primary product's entered Version.
            RELEASE="$(_release_product_artifact_name "$PRODUCT")-$VERSION.$BUILD"
            TAR_FILE="$RELEASE.tar.gz"
            MODE_UPDATEVERSION="${RELEASE_PRODUCT_VERSION_MODES[0]:-${MODE_UPDATEVERSION:-C}}"
            MODE_UPDATEBUILD="${RELEASE_PRODUCT_BUILD_MODES[0]:-${MODE_UPDATEBUILD:-C}}"

            # Removal baselines belong to the release artifact they will be applied to.
            # Select them immediately after the per-product release metadata.
            RELEASE_PRODUCT_BASELINES=()
            for product_index in "${!RELEASE_PRODUCT_NAMES[@]}"; do
                if (( ${#RELEASE_SOURCE_DIRS[@]} == 1 || ${FLAG_CREATE_INDIVIDUAL_RELEASES:-0} )); then
                    _sgnd_release_select_product_baseline "$product_index" || {
                        saycancel "Release preparation cancelled."
                        return 1
                    }
                else
                    RELEASE_PRODUCT_BASELINES[$product_index]=""
                fi
            done

            if (( ${#RELEASE_SOURCE_DIRS[@]} > 1 )); then
                _sgnd_release_select_bundle_baseline || {
                    saycancel "Release preparation cancelled."
                    return 1
                }
            else
                BUNDLE_PREVIOUS_MANIFEST=""
            fi

            sgnd_print
            sgnd_print_sectionheader "Switches" --padend 0
            lw=41

            if [[ "$FLAG_CLEANUP" -eq 1 ]]; then
                cleanup="Y"
            else
                cleanup="N"
            fi
            ask --label "Cleanup staging files after run (Y/N)" --var cleanup --default "$cleanup" --colorize both --labelclr "${CYAN}" --pad "$lp" --labelwidth "$lw"
            if [[ "$cleanup" == "Y" || "$cleanup" == "y" ]]; then
                FLAG_CLEANUP=1
            else
                FLAG_CLEANUP=0
            fi

            # detect if staging root contains anything
            local staging_has_files=0
            if [[ -d "$STAGING_ROOT" ]] && find "$STAGING_ROOT" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
                staging_has_files=1
            fi

            if (( staging_has_files )); then
                if [[ "$FLAG_USEEXISTING" -eq 1 ]]; then
                    useexisting="Y"
                else
                    useexisting="N"
                fi

                ask --label "Use existing staging files (Y/N)" --var useexisting --default "$useexisting" --colorize both --labelclr "${CYAN}" --pad "$lp" --labelwidth "$lw"

                case "${useexisting^^}" in
                    Y) FLAG_USEEXISTING=1 ;;
                    *) FLAG_USEEXISTING=0 ;;
                esac
            else
                # no files -> force behavior
                FLAG_USEEXISTING=0
                sayinfo "Staging folder is empty -> cannot reuse files."
            fi

             if [[ "$FLAG_SAVEPARMS" -eq 1 ]]; then
                saveparms="Y"
            else
                saveparms="N"
            fi

            if [[ "$FLAG_CREATEWRAPPERS" -eq 1 ]]; then
                createwrappers="Y"
            else
                createwrappers="N"
            fi
            ask --label "Create missing command wrappers (Y/N)" \
                --var createwrappers \
                --default "$createwrappers" \
                --choices "Y,Yes,N,No" \
                --colorize both \
                --labelclr "${CYAN}" \
                --pad "$lp" \
                --labelwidth "$lw"
            case "${createwrappers^^}" in
                Y|YES) FLAG_CREATEWRAPPERS=1 ;;
                *)     FLAG_CREATEWRAPPERS=0 ;;
            esac

            if [[ "$FLAG_NORMALIZE_CANON" -eq 1 ]]; then
                normalizecanon="Y"
            else
                normalizecanon="N"
            fi
            ask --label "Normalize canonical structures (Y/N)" \
                --var normalizecanon \
                --default "$normalizecanon" \
                --choices "Y,Yes,N,No" \
                --colorize both \
                --labelclr "${CYAN}" \
                --pad "$lp" \
                --labelwidth "$lw"
            case "${normalizecanon^^}" in
                Y|YES) FLAG_NORMALIZE_CANON=1 ;;
                *)     FLAG_NORMALIZE_CANON=0 ;;
            esac

            ask --label "Save these settings for future use (Y/N)" --var saveparms --default "$saveparms" --colorize both --labelclr "${CYAN}" --pad "$lp" --labelwidth "$lw"
            if [[ "$saveparms" == "Y" || "$saveparms" == "y" ]]; then
                FLAG_SAVEPARMS=1
            else
                FLAG_SAVEPARMS=0
            fi

            sgnd_print_sectionheader
            printf "\n"

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

        if (( FLAG_SAVEPARMS == 1 )); then
            if (( FLAG_DRYRUN == 1 )); then
                sayinfo "Would have saved state variables (manual)"
            else
                sgnd_state_save_keys --array SGND_STATE_VARIABLES || return $?
            fi
        fi
    }


    # fn: _sgnd_release_list_manifest_history - List removal-baseline manifests for an artifact
        # . Purpose
        #   List persistent manifest-history files for one explicit release artifact identity,
        #   newest build first.
        #
        # . Arguments
        #   $1  Artifact product name, for example SolidGroundUX or SolidGroundUX-bundled.
        #
        # . Behavior
        #   - Matches only the requested artifact identity.
        #   - Keeps bundled and individual release histories separate.
        #   - Sorts by the numeric build suffix first, then by version as a tie-breaker.
        #
        # . Returns
        #   0 always.
        #
        # . Usage
        #   _sgnd_release_list_manifest_history "SolidGroundUX"
    _sgnd_release_list_manifest_history() {
        local artifact_product="${1:?missing artifact product}"
        local file="" base="" remainder="" version="" build=""
        local want_bundle=0

        [[ -d "$MANIFEST_HISTORY_DIR" ]] || return 0
        [[ "$artifact_product" == *-bundled ]] && want_bundle=1

        while IFS= read -r -d '' file; do
            base="$(basename -- "$file")"
            remainder="${base#${artifact_product}-}"
            remainder="${remainder%.manifest}"

            # An individual product prefix also matches its bundled artifact. Exclude that
            # explicitly so the two histories can never contaminate each other.
            if (( ! want_bundle )) && [[ "$remainder" == bundled-* ]]; then
                continue
            fi

            # The filename glob is necessarily prefix-based.  A product such as
            # SolidGroundUX must not therefore absorb manifests belonging to
            # SolidGroundUX-Management-Console-Modules.  After removing the exact
            # artifact prefix, a valid remainder must start with the release version.
            [[ "$remainder" =~ ^([0-9][0-9A-Za-z._+-]*)\.([0-9]+)$ ]] || continue
            version="${BASH_REMATCH[1]}"
            build="${BASH_REMATCH[2]}"
            printf '%020d\t%s\t%s\n' "$build" "$version" "$base"
        done < <(find "$MANIFEST_HISTORY_DIR" -maxdepth 1 -type f -name "${artifact_product}-*.manifest" -print0 2>/dev/null) \
            | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2Vr \
            | cut -f3-

        return 0
    }

    # fn: _sgnd_release_select_baseline_for_artifact - Select one artifact removal baseline
        # . Purpose
        #   Resolve the manifest against which removed paths are calculated for one release
        #   artifact rather than for the prepare-release run as a whole.
        #
        # . Arguments
        #   $1  Display label.
        #   $2  Artifact product name used to filter manifest history.
        #   $3  Name of the variable that receives the selected absolute manifest path.
        #
        # . Behavior
        #   - Defaults to the matching manifest with the highest numeric build number.
        #   - Offers older manifests, a custom path, and an explicit baseless release.
        #   - In auto mode selects the latest matching manifest, or no baseline when none exists.
        #
        # . Returns
        #   0 on success; 1 on invalid/cancelled selection.
        #
        # . Usage
        #   _sgnd_release_select_baseline_for_artifact "SolidGroundUX" "SolidGroundUX" baseline
    _sgnd_release_select_baseline_for_artifact() {
        local display_label="${1:?missing display label}"
        local artifact_product="${2:?missing artifact product}"
        local output_var="${3:?missing output variable}"
        local selection="" custom="" latest="" manifest="" current="${!output_var-}"
        local i=0
        local -a manifests=() options=()

        if [[ -n "$current" && ! -f "$current" ]]; then
            saywarning "Stored removal baseline not found for $display_label: $current"
            current=""
        fi

        mapfile -t manifests < <(_sgnd_release_list_manifest_history "$artifact_product")
        (( ${#manifests[@]} > 0 )) && latest="${manifests[0]}"

        if (( ${FLAG_AUTO:-0} )); then
            [[ -z "$current" && -n "$latest" ]] && current="${MANIFEST_HISTORY_DIR%/}/$latest"
            printf -v "$output_var" '%s' "$current"
            return 0
        fi

        sgnd_print
        sgnd_print_sectionheader "Removal baseline: $display_label" --padend 0

        if [[ -n "$latest" ]]; then
            options+=("Latest baseline: $latest")
            for (( i=1; i<${#manifests[@]}; i++ )); do
                options+=("${manifests[$i]}")
            done
        else
            sayinfo "No matching manifests are currently stored in $MANIFEST_HISTORY_DIR"
        fi
        options+=("Custom path" "No removal baseline")

        ask_selection --label "Selection" --var selection --items "${options[@]}" || return 1

        case "$selection" in
            "No removal baseline") current="" ;;
            "Custom path")
                ask --label "Manifest path" --var custom --default "" \
                    --validate sgnd_validate_file_exists --colorize both --labelclr "${CYAN}" \
                    --pad 4 --labelwidth 20
                current="$(readlink -f "$custom")"
                ;;
            "Latest baseline: "*)
                manifest="${selection#Latest baseline: }"
                current="${MANIFEST_HISTORY_DIR%/}/$manifest"
                ;;
            *)
                current="${MANIFEST_HISTORY_DIR%/}/$selection"
                ;;
        esac

        printf -v "$output_var" '%s' "$current"
        return 0
    }

    # fn: _sgnd_release_select_product_baseline - Select baseline for one product release
        # . Returns
        #   0 on success; non-zero on cancelled/invalid selection.
        # . Usage
        #   _sgnd_release_select_product_baseline 0
    _sgnd_release_select_product_baseline() {
        local product_index="${1:?missing product index}"
        local product="${RELEASE_PRODUCT_NAMES[$product_index]:?missing product name}"
        local artifact_product=""
        local selected="${RELEASE_PRODUCT_BASELINES[$product_index]-}"

        artifact_product="$(_release_product_artifact_name "$product")"
        _sgnd_release_select_baseline_for_artifact "$product" "$artifact_product" selected || return $?
        RELEASE_PRODUCT_BASELINES[$product_index]="$selected"
    }

    # fn: _sgnd_release_select_bundle_baseline - Select baseline for the assembled bundle
        # . Returns
        #   0 on success; non-zero on cancelled/invalid selection.
        # . Usage
        #   _sgnd_release_select_bundle_baseline
    _sgnd_release_select_bundle_baseline() {
        local artifact_product="$(_release_product_artifact_name "$PRODUCT")-bundled"
        local selected="${BUNDLE_PREVIOUS_MANIFEST:-}"

        _sgnd_release_select_baseline_for_artifact "${PRODUCT} bundle" "$artifact_product" selected || return $?
        BUNDLE_PREVIOUS_MANIFEST="$selected"
    }

    # _sgnd_release_write_checksum
        # . Purpose
        #   Add or update a SHA256SUMS entry for a release artifact.
        #
        # . Behavior
        #   - Ensures SHA256SUMS contains exactly one entry for the specified filename.
        #   - Removes any existing line for the same filename before appending a new one.
        #   - Stores only the basename in the checksum file.
        #
        # . Arguments
        #   $1  TAR_PATH
        #       Path to the file to hash.
        #   $2  TAR_FILE
        #       Filename to write into SHA256SUMS.
        #   $3  STAGING_ROOT
        #       Directory containing SHA256SUMS.
        #
        # . Side effects
        #   - Creates or updates:
        #       <staging_root>/SHA256SUMS
        #
        # . Returns
        #   0 on success
        #   1 if required arguments are missing or file operations fail
        #
        # . Usage
        #   _sgnd_release_write_checksum "/tmp/sgnd-example" "/tmp/sgnd-example.txt" "/tmp/sgnd-example"
        # . Purpose
        #   Write release checksum metadata for a file.
        #
        # . Behavior
        #
        # . Returns
        #   Returns the underlying command or workflow status.
        #
        # . Usage
        #   _sgnd_release_write_checksum
    _sgnd_release_write_checksum() {
        local tar_path="${1:-}"
        local tar_file="${2:-}"
        local staging_root="${3:-}"

        [[ -n "$tar_path" ]] || return 1
        [[ -n "$tar_file" ]] || return 1
        [[ -n "$staging_root" ]] || return 1

        local sums_file
        sums_file="${staging_root%/}/SHA256SUMS"

        touch "$sums_file" || return 1

        # Remove any existing entry for this filename (idempotent).
        # Match: two spaces + filename at end of line.
        sed -i "\|  $tar_file$|d" "$sums_file" || return 1

        local hash
        hash="$(sha256sum "$tar_path" | awk '{print $1}')" || return 1
        [[ -n "$hash" ]] || return 1

        printf '%s  %s\n' "$hash" "$tar_file" >> "$sums_file" || return 1
    }


    # fn: _sgnd_release_write_removed_manifest - Write removed-path delta
        # . Purpose
        #   Create the release removal manifest by comparing the selected baseline and
        #   current package manifests.
        #
        # . Behavior
        #   - Uses PREVIOUS_MANIFEST as the explicit removal baseline.
        #   - Computes paths present in the baseline but absent from the current manifest.
        #   - Writes one removed relative path per line in sorted order.
        #   - Excludes persistent *.cfg and *.state files from automatic removal.
        #   - Creates an empty removal manifest when no baseline was selected.
        #
        # . Arguments
        #   $1  CURRENT_MANIFEST - Newly generated release manifest.
        #   $2  REMOVED_MANIFEST - Output path for the removal manifest.
        #
        # . Returns
        #   0 on success; 1 when validation, comparison, or output creation fails.
        #
        # . Usage
        #   _sgnd_release_write_removed_manifest "$manifest_path" "$removed_path"
    _sgnd_release_write_removed_manifest() {
        local current_manifest="${1:-}"
        local removed_manifest="${2:-}"
        local previous_sorted=""
        local current_sorted=""
        local removed_count=0

        [[ -f "$current_manifest" ]] || return 1
        [[ -n "$removed_manifest" ]] || return 1

        if [[ -z "${PREVIOUS_MANIFEST:-}" ]]; then
            : > "$removed_manifest" || return 1
            sayinfo "No removal baseline selected; removal manifest is empty."
            return 0
        fi

        [[ -f "$PREVIOUS_MANIFEST" ]] || {
            sayfail "Removal baseline manifest does not exist: $PREVIOUS_MANIFEST"
            return 1
        }

        sayinfo "Removal baseline: $(basename -- "$PREVIOUS_MANIFEST")"

        previous_sorted="$(mktemp)" || return 1
        current_sorted="$(mktemp)" || {
            rm -f -- "$previous_sorted"
            return 1
        }

        if ! LC_ALL=C sort -u -- "$PREVIOUS_MANIFEST" > "$previous_sorted"; then
            rm -f -- "$previous_sorted" "$current_sorted"
            return 1
        fi

        if ! LC_ALL=C sort -u -- "$current_manifest" > "$current_sorted"; then
            rm -f -- "$previous_sorted" "$current_sorted"
            return 1
        fi

        if ! LC_ALL=C comm -23 -- "$previous_sorted" "$current_sorted" \
            | grep -Ev '\.(cfg|state)$' \
            > "$removed_manifest"; then
            # grep returns 1 when every removed path was intentionally filtered out.
            if [[ ${PIPESTATUS[0]} -ne 0 || ${PIPESTATUS[1]} -gt 1 ]]; then
                rm -f -- "$previous_sorted" "$current_sorted"
                return 1
            fi
        fi

        rm -f -- "$previous_sorted" "$current_sorted"

        removed_count="$(grep -cve '^[[:space:]]*$' "$removed_manifest" 2>/dev/null || true)"
        sayinfo "Removal manifest contains $removed_count obsolete path(s)."
        return 0
    }

    # _create_tar
        # . Purpose
        #   Stage a clean release tree and produce a versioned tar.gz archive.
        #
        # . Behavior
        #   - Ensures the release-specific staging directory exists.
        #   - Populates the staging directory from SOURCE_DIR via rsync.
        #   - Reuses existing staging files when requested and non-empty.
        #   - Creates an uncompressed tar archive from the staged files.
        #   - Generates an uninstall manifest from the tar contents.
        #   - Compares the new manifest with the selected removal-baseline manifest and writes a removal delta.
        #   - Embeds the uninstall manifest into the tar archive.
        #   - Compresses the archive to tar.gz.
        #   - Updates SHA256SUMS and writes sidecar .sha256 files.
        #
        # Inputs (globals):
        #   RELEASE
        #   SOURCE_DIR
        #   STAGING_ROOT
        #   TAR_FILE
        #   FLAG_DRYRUN
        #   FLAG_USEEXISTING
        #
        # . Side effects
        #   - Creates and updates staged files and release artifacts under STAGING_ROOT.
        #
        # Output artifacts:
        #   - $STAGING_ROOT/$TAR_FILE
        #   - $STAGING_ROOT/$RELEASE.manifest
        #   - $STAGING_ROOT/$RELEASE.removed
        #   - $STAGING_ROOT/SHA256SUMS
        #   - $STAGING_ROOT/$TAR_FILE.sha256
        #   - $STAGING_ROOT/$RELEASE.manifest.sha256
        #   - $STAGING_ROOT/$RELEASE.removed.sha256
        #
        # . Returns
        #   0 on success
        #   1 on failure to stage, package, hash, or write artifacts
        #
        # . Usage
        #   _create_tar
        #
        # Examples:
        #   _create_tar || return 1
        #
        # Notes:
        #   - In dry-run mode, only reports the intended actions.
        #   - Manifest is generated before embedding, so it does not list itself.
    # fn: _create_tar - Create the release tar archive
        # . Purpose
        #   Create the release tar archive.
        #
        # . Behavior
        #
        # . Returns
        #   Returns the underlying command or workflow status.
        #
        # . Usage
        #   _create_tar
    _create_tar() {
        saystart "Creating release: $RELEASE"

        local stage_path tar_path_tar tar_path_gz manifest_path removed_path sums_path
        local manifest_base manifest_hash removed_base removed_hash

        stage_path="${STAGING_ROOT%/}/$RELEASE"

        # --- Ensure staging directory ----------------------------------------------
        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have check/created directory: $stage_path"
        else
            saydebug "Ensuring staging dir exists: $stage_path"
            mkdir -p "$stage_path" || { sayfail "mkdir failed."; return 1; }
        fi

        # --- Stage clean copy -------------------------------------------------------
        if [[ "$FLAG_USEEXISTING" -eq 1 && -n "$(ls -A "$stage_path" 2>/dev/null)" ]]; then
            sayinfo "Using existing staging files as requested."
        else
            if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
                sayinfo "Would have staged files from $SOURCE_DIR to $stage_path"
            else
                saydebug "Staging files from $SOURCE_DIR to $stage_path"
                local -a primary_excludes=() primary_rsync_args=()
                local exclude=""
                while IFS= read -r exclude; do [[ -n "$exclude" ]] && primary_excludes+=("$exclude"); done < <(_release_product_excludes "$SOURCE_DIR")
                primary_rsync_args=( -a --delete )
                for exclude in "${primary_excludes[@]}"; do primary_rsync_args+=( --exclude "$exclude" ); done
                rsync "${primary_rsync_args[@]}" \
                    "${SOURCE_DIR%/}/" "$stage_path/" || {
                        sayfail "rsync failed."
                        return 1
                    }
            fi
        fi

        # --- Overlay selected companion products --------------------------------------
        if (( ${#RELEASE_SOURCE_DIRS[@]} > 1 )); then
            local companion="" rel="" existing="" incoming=""
            for companion in "${RELEASE_SOURCE_DIRS[@]:1}"; do
                local -a companion_excludes=() companion_rsync_args=()
                local exclude=""
                while IFS= read -r exclude; do [[ -n "$exclude" ]] && companion_excludes+=("$exclude"); done < <(_release_product_excludes "$companion")
                companion_rsync_args=( -a )
                for exclude in "${companion_excludes[@]}"; do companion_rsync_args+=( --exclude "$exclude" ); done
                if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
                    sayinfo "Would have overlaid companion product from $companion"
                    continue
                fi

                # Use rsync itself to enumerate the files that survive the release policy.
                # Collision detection and the actual overlay therefore obey identical rules.
                while IFS= read -r rel; do
                    [[ -n "$rel" && "$rel" != */ ]] || continue
                    incoming="${companion%/}/$rel"
                    [[ -f "$incoming" ]] || continue
                    existing="$stage_path/$rel"
                    if [[ -f "$existing" ]] && ! cmp -s "$existing" "$incoming"; then
                        local primary_record="" primary_product="" primary_version="" primary_build="" primary_defs=""
                        local companion_record="" companion_product="" companion_version="" companion_build="" companion_defs=""
                        primary_record="$(_release_product_record "$SOURCE_DIR" 2>/dev/null || true)"
                        companion_record="$(_release_product_record "$companion" 2>/dev/null || true)"
                        IFS='|' read -r primary_product primary_version primary_build primary_defs <<< "$primary_record"
                        IFS='|' read -r companion_product companion_version companion_build companion_defs <<< "$companion_record"
                        sayfail "Product ownership conflict"
                        sgnd_print_labeledvalue --label "Primary product" --value "${primary_product:-$PRODUCT}"
                        sgnd_print_labeledvalue --label "Companion product" --value "${companion_product:-Unknown}"
                        sgnd_print_labeledvalue --label "File" --value "$rel"
                        return 1
                    fi
                done < <(rsync "${companion_rsync_args[@]}" --dry-run --out-format='%n' "${companion%/}/" "$stage_path/" 2>/dev/null)
                rsync "${companion_rsync_args[@]}" "${companion%/}/" "$stage_path/" || return 1
            done
        fi
        _release_write_bundle_manifest "$stage_path" || return 1

        # --- Build paths ------------------------------------------------------------
        tar_path_tar="${STAGING_ROOT%/}/${TAR_FILE%.gz}"
        tar_path_gz="${STAGING_ROOT%/}/$TAR_FILE"
        manifest_path="${STAGING_ROOT%/}/${RELEASE}.manifest"
        removed_path="${STAGING_ROOT%/}/${RELEASE}.removed"
        sums_path="${STAGING_ROOT%/}/SHA256SUMS"

        saydebug "Creating tar archive $tar_path_tar from staged files in $stage_path"

        if [[ "$FLAG_DRYRUN" -eq 1 ]]; then
            sayinfo "Would have created tar archive at: $tar_path_tar"
            sayinfo "Would have written manifest to: $manifest_path"
            sayinfo "Would have compared the selected removal baseline and written removals to: $removed_path"
            sayinfo "Would have updated checksums file: $sums_path"
            sayinfo "Would have generated manifest and compressed to: $tar_path_gz"
            sayinfo "Would have written checksum to: ${tar_path_gz}.sha256"
            sayinfo "Would have written checksum to: ${manifest_path}.sha256"
            sayinfo "Would have written checksum to: ${removed_path}.sha256"
        else

            # --- Create uncompressed tar -----------------------------------------------
            tar -C "$stage_path" \
                --owner=0 \
                --group=0 \
                --numeric-owner \
                -cpf "$tar_path_tar" . || { sayfail "tar failed."; return 1; }

            # --- Write uninstall manifest (external) ------------------------------------
            tar -tf "$tar_path_tar" \
                | sed 's|^\./||' \
                | sed '/^[[:space:]]*$/d' \
                > "$manifest_path" || { sayfail "Failed to write manifest."; return 1; }

            # --- Write removed-path delta ------------------------------------------------
            _sgnd_release_write_removed_manifest "$manifest_path" "$removed_path" \
                || { sayfail "Failed to write removal manifest."; return 1; }

            # --- Embed manifest into tar ------------------------------------------------
            tar -C "$STAGING_ROOT" \
                --owner=0 \
                --group=0 \
                --numeric-owner \
                -rf "$tar_path_tar" "${RELEASE}.manifest" \
                || { sayfail "Failed to embed manifest into tar."; return 1; }

            # --- Compress to tar.gz -----------------------------------------------------
            gzip -f "$tar_path_tar" || { sayfail "gzip failed."; return 1; }

            # --- Update SHA256SUMS ------------------------------------------------------
            _sgnd_release_write_checksum "$tar_path_gz" "$TAR_FILE" "$STAGING_ROOT" \
                || { sayfail "Failed to update SHA256SUMS."; return 1; }

            # Remove existing manifest entry (idempotent)
            sed -i "\|  $(basename "$manifest_path")$|d" "$sums_path" \
                || { sayfail "Failed to update SHA256SUMS (manifest)."; return 1; }

            manifest_base="$(basename "$manifest_path")"
            manifest_hash="$(sha256sum "$manifest_path" | awk '{print $1}')" \
                || { sayfail "Failed to hash manifest."; return 1; }

            printf '%s  %s\n' "$manifest_hash" "$manifest_base" >> "$sums_path" \
                || { sayfail "Failed to append manifest checksum to SHA256SUMS."; return 1; }

            # Add removal manifest checksum (idempotent)
            removed_base="$(basename "$removed_path")"
            removed_hash="$(sha256sum "$removed_path" | awk '{print $1}')" \
                || { sayfail "Failed to hash removal manifest."; return 1; }

            sed -i "\|  $removed_base$|d" "$sums_path" \
                || { sayfail "Failed to update SHA256SUMS (removal manifest)."; return 1; }

            printf '%s  %s\n' "$removed_hash" "$removed_base" >> "$sums_path" \
                || { sayfail "Failed to append removal manifest checksum to SHA256SUMS."; return 1; }

            # Write sidecar .sha256 files
            printf '%s  %s\n' "$(sha256sum "$tar_path_gz" | awk '{print $1}')" "$TAR_FILE" > "${tar_path_gz}.sha256"
            printf '%s  %s\n' "$manifest_hash" "$manifest_base" > "${manifest_path}.sha256"
            printf '%s  %s\n' "$removed_hash" "$removed_base" > "${removed_path}.sha256"

            sayinfo "Created $tar_path_gz"

            # Inspect archive (first few entries)
            tar -tf "$tar_path_gz" | head -n 30
        fi

        sayend "Done creating release."
        return 0
    }


    # fn: _find_release_manager_source - Resolve the release-manager source file
        # . Purpose
        #   Locate release-manager.sh in the managed source tree.
        #
        # . Returns
        #   0 with the path on stdout when found; 1 otherwise.
        #
        # . Usage
        #   manager="$(_find_release_manager_source)"
    _find_release_manager_source() {
        local direct="${SOURCE_DIR%/}/var/lib/solidgroundux/release-manager.sh"
        local candidate=""
        local -a candidates=()

        if [[ -f "$direct" ]]; then
            printf '%s\n' "$direct"
            return 0
        fi

        mapfile -t candidates < <(find "$SOURCE_DIR" -type f -name 'release-manager.sh' -not -path '*/releases/*' -print 2>/dev/null)
        (( ${#candidates[@]} == 1 )) || return 1

        candidate="${candidates[0]}"
        printf '%s\n' "$candidate"
    }

    # fn$ _write_release_package_info - Write ZIP-root package identity metadata
        # . Purpose
        #   Write a small machine-readable shipping label for the release package.
        #
        # . Behavior
        #   - Uses the resolved project identity from the authoritative definitions file.
        #   - Writes only simple shell-style key/value assignments; the release manager
        #     parses these values and does not source the file.
        #
        # . Arguments
        #   $1  Destination file.
        #
        # . Returns
        #   0 on success; non-zero on write failure.
        # . Usage
        #   _write_release_package_info "<destination>"
    _write_release_package_info() {
        local destination="${1:?missing destination}"

        local package_type="individual"
        (( ${#RELEASE_SOURCE_DIRS[@]} > 1 )) && package_type="bundle"

        {
            printf 'SGND_PACKAGE_FORMAT=%s\n' "2"
            printf 'SGND_PACKAGE_TYPE=%s\n' "$package_type"
            printf 'SGND_PACKAGE_PROJECT=%s\n' "${PROJECT_SLUG:?project slug not resolved}"
            printf 'SGND_PACKAGE_PRODUCT=%s\n' "${PRODUCT:?product not resolved}"
            printf 'SGND_PACKAGE_VERSION=%s\n' "${VERSION:?version not resolved}"
            printf 'SGND_PACKAGE_BUILD=%s\n' "${BUILD:?build not resolved}"
            printf 'SGND_PACKAGE_RELEASE=%s\n' "${RELEASE:?release not resolved}"
        } > "$destination"
    }

    # fn: _create_release_package - Create the complete distributable release ZIP
        # . Purpose
        #   Package the standalone release manager and release payload into one ZIP.
        #
        # . Behavior
        #   - Requires the six canonical release artifacts created by _create_tar.
        #   - Adds release-manager.sh at the ZIP root only for the SolidGroundUX framework bundle.
#   - Generic project bundles contain only their release artifacts and require an installed release manager.
        #   - Does not include SHA256SUMS; the manager verifies individual sidecars.
        #
        # . Returns
        #   0 on success; 1 on missing artifacts or packaging failure.
        #
        # . Usage
        #   _create_release_package
    _create_release_package() {
        local manager=""
        local package_dir=""
        local package_info=""
        local zip_path="${STAGING_ROOT%/}/${RELEASE}-release.zip"
        local artifact=""
        local -a zip_items=()
        local -a artifacts=(
            "${TAR_FILE}"
            "${TAR_FILE}.sha256"
            "${RELEASE}.manifest"
            "${RELEASE}.manifest.sha256"
            "${RELEASE}.removed"
            "${RELEASE}.removed.sha256"
        )

        # Only the SolidGroundUX framework bundle must be self-bootstrapping.
        # Generic project releases are consumed by an already installed release manager.
        if (( ${PROJECT_IS_FRAMEWORK:-0} )); then
            manager="$(_find_release_manager_source)" || {
                sayfail "Could not uniquely locate release-manager.sh beneath $SOURCE_DIR"
                return 1
            }
        fi

        for artifact in "${artifacts[@]}"; do
            [[ -f "${STAGING_ROOT%/}/${artifact}" ]] || {
                sayfail "Missing release artifact for package: ${STAGING_ROOT%/}/${artifact}"
                return 1
            }
        done

        if (( ${FLAG_DRYRUN:-0} )); then
            sayinfo "Would have created release package: $zip_path"
            if (( ${PROJECT_IS_FRAMEWORK:-0} )); then
                sayinfo "Would have included release-package.info, release-manager.sh, and ${#artifacts[@]} release artifacts at ZIP root"
            else
                sayinfo "Would have included release-package.info and ${#artifacts[@]} project release artifacts at ZIP root"
            fi
            return 0
        fi

        command -v zip >/dev/null 2>&1 || {
            sayfail "Required command not found: zip"
            return 1
        }

        package_dir="$(mktemp -d)" || return 1
        package_info="$package_dir/release-package.info"

        _write_release_package_info "$package_info" || {
            rm -rf -- "$package_dir"
            sayfail "Failed to create release-package.info."
            return 1
        }
        zip_items+=("release-package.info")

        if (( ${#RELEASE_SOURCE_DIRS[@]} > 1 )); then
            local bundle_products="${STAGING_ROOT%/}/${RELEASE}/RELEASE-PRODUCTS"
            [[ -f "$bundle_products" ]] || {
                rm -rf -- "$package_dir"
                sayfail "Bundled release is missing RELEASE-PRODUCTS."
                return 1
            }
            cp -f -- "$bundle_products" "$package_dir/RELEASE-PRODUCTS" || {
                rm -rf -- "$package_dir"
                return 1
            }
            zip_items+=("RELEASE-PRODUCTS")
        fi

        if (( ${PROJECT_IS_FRAMEWORK:-0} )); then
            cp -f -- "$manager" "$package_dir/release-manager.sh" || {
                rm -rf -- "$package_dir"
                return 1
            }
            zip_items+=("release-manager.sh")
        fi

        for artifact in "${artifacts[@]}"; do
            cp -f -- "${STAGING_ROOT%/}/${artifact}" "$package_dir/$artifact" || {
                rm -rf -- "$package_dir"
                return 1
            }
            zip_items+=("$artifact")
        done

        rm -f -- "$zip_path"
        (
            cd "$package_dir" || exit 1
            zip -q "$zip_path" "${zip_items[@]}"
        ) || {
            rm -rf -- "$package_dir"
            sayfail "Failed to create release ZIP."
            return 1
        }

        rm -rf -- "$package_dir"
        sayok "Created release package: $zip_path"
        return 0
    }

    # fn: _archive_release_manifest - Persist the current manifest for future removal baselines
        # . Purpose
        #   Store the successfully packaged release manifest in persistent manifest history.
        #
        # . Returns
        #   0 on success; 1 on copy failure.
        #
        # . Usage
        #   _archive_release_manifest
    _archive_release_manifest() {
        local manifest_path="${STAGING_ROOT%/}/${RELEASE}.manifest"
        local destination="${MANIFEST_HISTORY_DIR%/}/${RELEASE}.manifest"

        [[ -f "$manifest_path" ]] || {
            sayfail "Cannot archive missing release manifest: $manifest_path"
            return 1
        }

        if (( ${FLAG_DRYRUN:-0} )); then
            sayinfo "Would have archived release manifest to: $destination"
            return 0
        fi

        mkdir -p -- "$MANIFEST_HISTORY_DIR" || return 1
        cp -f -- "$manifest_path" "$destination" || return 1
        sayinfo "Archived release manifest: $destination"
        return 0
    }

    # fn: _cleanup_staging - Remove gathered staging data
        # . Purpose
        #   Remove the release-specific staging directory if cleanup is enabled.
        #
        # . Behavior
        #   - Checks FLAG_CLEANUP to determine whether to remove the staging directory.
        #   - If FLAG_CLEANUP is 1, deletes the directory at STAGING_ROOT/RELEASE.
        #   - If FLAG_CLEANUP is 0, logs that cleanup is skipped.
        #
        # Inputs (globals):
        #   STAGING_ROOT
        #   RELEASE
        #   FLAG_CLEANUP
        #
        # . Side effects
        #   - Deletes files and directories under STAGING_ROOT/RELEASE when cleanup is enabled.
        #
        # . Returns
        #   0 on success (or if cleanup is skipped)
        #   1 if deletion fails
        #
        # . Usage
        #   _cleanup_staging
    _cleanup_staging() {
        if [[ "$FLAG_CLEANUP" -eq 1 ]]; then
            sayinfo "Cleaning up staging files in $STAGING_ROOT"
            rm -rf "${STAGING_ROOT%/}/$RELEASE" || {
                saywarning "Failed to remove staging directory: ${STAGING_ROOT%/}/$RELEASE"
            }
        else
            sayinfo "Skipping cleanup of staging files (--nocleanup)"
        fi
    }


    # fn: _set_script_header_version - Set an explicit version in a managed script header
        #
        # . Usage
        #   _set_script_header_version "/tmp/sgnd-example.txt" "1.8.0"
    _set_script_header_version() {
        local file="${1:-}"
        local version="${2:-}"

        [[ -n "$file" && -n "$version" ]] || return 2
        [[ -f "$file" ]] || return 1

        sed -i -E \
            "0,/^#([[:space:]]*)Version([[:space:]]*):[[:space:]]*.*/s//#\1Version\2: $version/" \
            "$file"
    }

    # fn$ _normalize_canonical_sources - Normalize canonical structures before metadata processing
        # . Purpose
        #   Apply the canonical framework locator and library guard to managed shell files
        #   before version/build/checksum metadata is evaluated.
        #
        # . Behavior
        #   - Honors FLAG_NORMALIZE_CANON; disabled runs are skipped.
        #   - Uses normalize-canon.sh from the active framework libexec directory.
        #   - Passes the same recursive shell-file mask represented by SOURCE_DIR.
        #   - Runs the normalizer in --auto mode so prepare-release remains non-interactive.
        #   - Propagates dry-run mode when prepare-release is running dry.
        #
        # . Returns
        #   0 when normalization is disabled or completes successfully; non-zero otherwise.
        #
        # . Usage
        #   _normalize_canonical_sources
    _normalize_canonical_sources() {
        local normalizer=""
        local source_mask="${SOURCE_DIR%/}/**/*.sh"
        local -a command=()

        (( ${FLAG_NORMALIZE_CANON:-1} )) || {
            sayinfo "Canonical normalization disabled."
            return 0
        }

        if [[ "$SGND_FRAMEWORK_ROOT" == "/" ]]; then
            normalizer="/usr/local/libexec/solidgroundux/normalize-canon.sh"
        else
            normalizer="${SGND_FRAMEWORK_ROOT%/}/usr/local/libexec/solidgroundux/normalize-canon.sh"
        fi

        [[ -x "$normalizer" ]] || {
            sayfail "Canonical normalizer not found or not executable: $normalizer"
            return 1
        }

        command=("$normalizer" --auto)
        if (( ${FLAG_DRYRUN:-0} )); then
            command+=(--dryrun)
        fi
        command+=("$source_mask")

        saystart "Normalizing canonical shell structures"
        "${command[@]}" || {
            sayfail "Canonical normalization failed."
            return 1
        }
        sayend "Canonical normalization complete."
        return 0
    }

    # fn: _release_sync_module_metadata_field - Synchronize module runtime release metadata
        # . Purpose
        #   Keep conventional SGND_*_MODULE_VERSION / SGND_*_MODULE_BUILD assignments
        #   synchronized with the canonical header value when prepare-release updates it.
        #
        # . Arguments
        #   $1  File to update.
        #   $2  Field name: Version or Build.
        #   $3  Value to write.
        #
        # . Behavior
        #   - Updates every matching conventional module assignment in the file.
        #   - Leaves files without such assignments untouched.
        #   - Preserves leading indentation and the variable name.
        #
        # . Returns
        #   0 on success (including no matching assignment); non-zero on update failure.
    _release_sync_module_metadata_field() {
        local file="${1:-}"
        local field="${2:-}"
        local value="${3:-}"
        local suffix=""
        local escaped=""

        [[ -f "$file" ]] || return 1
        case "$field" in
            Version) suffix="VERSION" ;;
            Build)   suffix="BUILD" ;;
            *)       return 2 ;;
        esac

        grep -Eq "^[[:space:]]*SGND_[A-Za-z0-9_]+_MODULE_${suffix}[[:space:]]*=" "$file" || return 0

        escaped="${value//\\/\\\\}"
        escaped="${escaped//&/\\&}"
        escaped="${escaped//|/\\|}"
        sed -i -E \
            "s|^([[:space:]]*)(SGND_[A-Za-z0-9_]+_MODULE_${suffix})[[:space:]]*=.*$|\1\2=\"${escaped}\"|" \
            "$file"
    }

    # fn: _apply_version_bump - Apply release metadata policy to managed source files
        # . Purpose
        #   Apply Version and Build according to A/C/N policy and always refresh Checksum
        #   for files whose source or metadata changed.
        #
        # . Behavior
        #   - Detects source changes by comparing the stored checksum with the current
        #     managed-body checksum.
        #   - MODE_UPDATEVERSION: active product policy; A=all, C=changed, N=none.
        #   - MODE_UPDATEBUILD:   active product policy; A=all, C=changed, N=none.
        #   - Any file changed by source edits or metadata policy receives a refreshed
        #     checksum after metadata updates are applied.
        #   - Optional major/minor bump flags override explicit Version policy.
        #
        # . Returns
        #   0 on success; 1 when one or more managed files could not be updated.
        #
        # . Usage
        #   _apply_version_bump
    _apply_version_bump() {
        local file=""
        local stored_checksum=""
        local current_checksum=""
        local source_changed=0
        local metadata_changed=0
        local failed=0
        local version_mode="${MODE_UPDATEVERSION:-C}"
        local -a failed_files=()
        local build_mode="${MODE_UPDATEBUILD:-C}"

        version_mode="${version_mode^^}"
        build_mode="${build_mode^^}"

        case "$version_mode" in A|C|N) ;; *) sayfail "Invalid version update mode: $version_mode"; return 1 ;; esac
        case "$build_mode" in A|C|N) ;; *) sayfail "Invalid build update mode: $build_mode"; return 1 ;; esac

        if (( ${FLAG_BUMP_MAJOR:-0} )) && (( ${FLAG_BUMP_MINOR:-0} )); then
            sayfail "Use either --bumpmajor or --bumpminor, not both"
            return 1
        fi

        while IFS= read -r -d '' file; do
            local existing_version=""

            # Files without a canonical Metadata/Version field are not managed by the
            # release metadata pass. Warn and continue; they must not block packaging.
            if ! sgnd_header_get_field "$file" "Metadata" "Version" existing_version; then
                saywarning "Skipping unmanaged file (missing metadata header): $file"
                continue
            fi

            current_checksum="$(sgnd_header_calc_checksum "$file")" || {
                saywarning "Skipping unmanaged file (checksum unavailable): $file"
                continue
            }

            sgnd_header_get_field "$file" "Metadata" "Checksum" stored_checksum || stored_checksum=""
            source_changed=0
            metadata_changed=0
            [[ "$stored_checksum" != "$current_checksum" ]] && source_changed=1

            if (( ${FLAG_DRYRUN:-0} )); then
                sayinfo "[DRYRUN] $file source_changed=$source_changed version=$version_mode build=$build_mode"
                continue
            fi

            if (( ${FLAG_BUMP_MAJOR:-0} || ${FLAG_BUMP_MINOR:-0} )); then
                local bump_mode="major"
                local bumped_version=""
                (( ${FLAG_BUMP_MINOR:-0} )) && bump_mode="minor"
                sgnd_header_bump_version "$file" "$bump_mode" || { saywarning "Could not bump version in $file"; failed=1; failed_files+=("$file"); continue; }
                sgnd_header_get_field "$file" "Metadata" "Version" bumped_version || { saywarning "Could not read bumped version from $file"; failed=1; failed_files+=("$file"); continue; }
                _release_sync_module_metadata_field "$file" "Version" "$bumped_version" || { saywarning "Could not synchronize module version in $file"; failed=1; failed_files+=("$file"); continue; }
                metadata_changed=1
            else
                if [[ "$version_mode" == "A" || ( "$version_mode" == "C" && "$source_changed" -eq 1 ) ]]; then
                    sgnd_header_upsert_field "$file" "Metadata" "Version" "$VERSION" || { saywarning "Could not set version in $file"; failed=1; failed_files+=("$file"); continue; }
                    _release_sync_module_metadata_field "$file" "Version" "$VERSION" || { saywarning "Could not synchronize module version in $file"; failed=1; failed_files+=("$file"); continue; }
                    metadata_changed=1
                fi

                if [[ "$build_mode" == "A" || ( "$build_mode" == "C" && "$source_changed" -eq 1 ) ]]; then
                    sgnd_header_upsert_field "$file" "Metadata" "Build" "$BUILD" || { saywarning "Could not set build in $file"; failed=1; failed_files+=("$file"); continue; }
                    _release_sync_module_metadata_field "$file" "Build" "$BUILD" || { saywarning "Could not synchronize module build in $file"; failed=1; failed_files+=("$file"); continue; }
                    metadata_changed=1
                fi
            fi

            if (( source_changed || metadata_changed )); then
                current_checksum="$(sgnd_header_calc_checksum "$file")" || { saywarning "Could not calculate checksum for $file"; failed=1; failed_files+=("$file"); continue; }
                sgnd_header_upsert_field "$file" "Metadata" "Checksum" "$current_checksum" || { saywarning "Could not set checksum in $file"; failed=1; failed_files+=("$file"); continue; }
            fi

            if (( source_changed || metadata_changed )); then
                sayok "Updated metadata in $file"
            else
                sayinfo "$file is unchanged, no metadata applied."
            fi
        done < <(find "$SOURCE_DIR" -type f -name '*.sh' -not -path '*/releases/*' -print0)

        _release_update_project_identity \
            || { sayfail "Failed to update project version/build identity"; return 1; }

        if (( failed )); then
            sayfail "One or more source files could not be prepared. Release creation aborted."
            if (( ${#failed_files[@]} > 0 )); then
                sayinfo "Files requiring attention:"
                local failed_file=""
                for failed_file in "${failed_files[@]}"; do
                    sgnd_print "    $failed_file"
                done
            fi
            return 1
        fi

        sayok "Source metadata preparation completed."
        return 0
    }


    # fn$ _ensure_libexec_executables
        # . Purpose
        #   Ensure top-level SolidGroundUX libexec files are executable before packaging.
        #
        # . Behavior
        #   - Inspects files directly beneath usr/local/libexec/solidgroundux.
        #   - Does not recurse into subdirectories.
        #   - Adds the executable bit for user, group, and others when missing.
        #   - Reports intended changes without modifying files in dry-run mode.
        #   - Succeeds quietly when the directory does not exist or contains no files.
        #
        # Inputs (globals):
        #   SOURCE_DIR
        #   FLAG_DRYRUN
        #
        # . Returns
        #   0 when all applicable files are executable or the directory is absent.
        #   1 when one or more permission updates fail.
        #
        # . Usage
        #   _ensure_libexec_executables
    _ensure_libexec_executables() {
        local libexec_root="${SOURCE_DIR%/}/usr/local/libexec/solidgroundux"
        local file=""
        local failed=0

        [[ -d "$libexec_root" ]] || {
            saydebug "No SolidGroundUX libexec directory found at $libexec_root; skipping executable-bit verification."
            return 0
        }

        while IFS= read -r -d '' file; do
            [[ -x "$file" ]] && continue

            if (( ${FLAG_DRYRUN:-0} )); then
                sayinfo "[DRYRUN] Would have set executable permissions on $file"
                continue
            fi

            if chmod a+x "$file"; then
                sayok "Set executable permissions on $file"
            else
                saywarning "Could not set executable permissions on $file"
                failed=1
            fi
        done < <(find "$libexec_root" -mindepth 1 -maxdepth 1 -type f -print0)

        return "$failed"
    }

    # fn: _ensure_public_command_wrappers - Ensure public wrappers exist for top-level libexec scripts
        # . Purpose
        #   Ensure every executable top-level shell script under the SolidGroundUX
        #   libexec directory has a matching public command wrapper in /usr/local/bin.
        #
        # . Behavior
        #   - Inspects executable *.sh files directly beneath usr/local/libexec/solidgroundux.
        #   - Uses optional Metadata/Wrapper when present; otherwise uses the canonical sgnd-<script> name.
        #   - Leaves existing wrappers untouched.
        #   - Creates only missing wrappers when FLAG_CREATEWRAPPERS=1.
        #   - Reports missing wrappers without creating them when the option is disabled.
        #   - Honors dry-run mode.
        #
        # Inputs (globals):
        #   SOURCE_DIR
        #   FLAG_CREATEWRAPPERS
        #   FLAG_DRYRUN
        #
        # Side effects:
        #   May create executable files beneath SOURCE_DIR/usr/local/bin.
        #
        # . Returns
        #   0 when all wrappers exist or missing wrappers were created successfully.
        #   1 when one or more wrapper creations fail.
        #
        # . Usage
        #   _ensure_public_command_wrappers
    _ensure_public_command_wrappers() {
        local libexec_root="${SOURCE_DIR%/}/usr/local/libexec/solidgroundux"
        local bin_root="${SOURCE_DIR%/}/usr/local/bin"
        local script=""
        local script_base=""
        local command_name=""
        local wrapper=""
        local installed_target=""
        local missing=0
        local created=0
        local failed=0

        [[ -d "$libexec_root" ]] || {
            saydebug "No SolidGroundUX libexec directory found at $libexec_root; skipping wrapper verification."
            return 0
        }

        while IFS= read -r -d '' script; do
            script_base="$(basename -- "$script")"
            command_name="$(_release_wrapper_name_for_script "$script")"
            wrapper="${bin_root}/${command_name}"
            installed_target="/usr/local/libexec/solidgroundux/${script_base}"

            [[ -e "$wrapper" || -L "$wrapper" ]] && continue

            (( missing++ ))

            if (( ! ${FLAG_CREATEWRAPPERS:-0} )); then
                saywarning "Missing command wrapper: $wrapper -> $installed_target"
                continue
            fi

            if (( ${FLAG_DRYRUN:-0} )); then
                sayinfo "[DRYRUN] Would create command wrapper: $wrapper -> $installed_target"
                continue
            fi

            mkdir -p -- "$bin_root" || {
                saywarning "Could not create wrapper directory: $bin_root"
                failed=1
                continue
            }

            printf '%s\n' \
                '#!/usr/bin/env bash' \
                "exec \"$installed_target\" \"\$@\"" \
                > "$wrapper" || {
                    saywarning "Could not create command wrapper: $wrapper"
                    failed=1
                    continue
                }

            chmod 0755 -- "$wrapper" || {
                saywarning "Could not make command wrapper executable: $wrapper"
                failed=1
                continue
            }

            sayok "Created command wrapper: $wrapper -> $installed_target"
            (( created++ ))
        done < <(find "$libexec_root" -mindepth 1 -maxdepth 1 -type f -name '*.sh' -perm /111 -print0)

        if (( missing == 0 )); then
            sayinfo "All executable top-level libexec scripts have public command wrappers."
        elif (( ${FLAG_CREATEWRAPPERS:-0} )); then
            sayinfo "Wrapper summary: $created created, $failed failed."
        else
            saywarning "Wrapper summary: $missing missing; creation disabled."
        fi

        return "$failed"
    }

# - Release artifact identity --------------------------------------------------------
    # fn$ _release_product_artifact_name - Convert a display product name to its file-safe release identity
        # . Returns
        #   Product name with whitespace runs replaced by hyphens.
        # . Usage
        #   artifact_product="$(_release_product_artifact_name "$PRODUCT")"
    _release_product_artifact_name() {
        local product_name="${1:-}"
        printf '%s\n' "$product_name" | sed -E 's/[[:space:]]+/-/g'
    }

# - Individual / bundled release helpers --------------------------------------------
    # fn$ _release_create_primary_individual_release - Create the primary product as a standalone release
    _release_create_primary_individual_release() {
        (( ${FLAG_CREATE_INDIVIDUAL_RELEASES:-0} )) || return 0
        (( ${#RELEASE_SOURCE_DIRS[@]} > 1 )) || return 0

        local saved_release="$RELEASE" saved_tar="$TAR_FILE"
        local -a saved_sources=("${RELEASE_SOURCE_DIRS[@]}")

        # The primary product has already had its release identity resolved and metadata
        # prepared by the normal main workflow. Package that product by itself before
        # assembling the multi-product bundle.
        RELEASE_SOURCE_DIRS=("$SOURCE_DIR")

        sgnd_print
        sgnd_print_sectionheader "Individual product release" --padend 0
        sgnd_print_labeledvalue --label "Product" --value "$PRODUCT"
        sgnd_print_labeledvalue --label "Version" --value "$VERSION"
        sgnd_print_labeledvalue --label "Build" --value "$BUILD"

        PREVIOUS_MANIFEST="${RELEASE_PRODUCT_BASELINES[0]-}"
        _create_tar || return 1
        _create_release_package || return 1
        _archive_release_manifest || return 1
        _cleanup_staging

        RELEASE_SOURCE_DIRS=("${saved_sources[@]}")
        RELEASE="$saved_release"
        TAR_FILE="$saved_tar"
        return 0
    }

    # fn$ _release_use_bundled_identity - Name the assembled release after the primary product
    _release_use_bundled_identity() {
        (( ${#RELEASE_SOURCE_DIRS[@]} > 1 )) || return 0

        # The bundle always inherits the primary product version/build; it is never
        # prompted for a separate identity. RELEASE-PRODUCTS records every included product.
        RELEASE="$(_release_product_artifact_name "$PRODUCT")-bundled-$VERSION.$BUILD"
        TAR_FILE="$RELEASE.tar.gz"

        sgnd_print
        sgnd_print_sectionheader "Bundled release" --padend 0
        sgnd_print_labeledvalue --label "Release" --value "$RELEASE"
        sgnd_print_labeledvalue --label "Products" --value "${#RELEASE_SOURCE_DIRS[@]}"
    }

# - Main Sequence -------------------------------------------------------------------
    # fn$ _release_create_standalone_bundled_products - Optionally create standalone releases for non-primary selected products
    _release_create_standalone_bundled_products() {
        (( ${#RELEASE_SOURCE_DIRS[@]} > 1 )) || return 0

        local saved_source="$SOURCE_DIR" saved_product="$PRODUCT" saved_version="$VERSION" saved_build="$BUILD"
        local saved_release="$RELEASE" saved_tar="$TAR_FILE" saved_previous="${PREVIOUS_MANIFEST:-}"
        local saved_project_file="${PROJECT_DEFINITIONS_FILE:-}" saved_project_key="${PROJECT_DEFINITIONS_KEY:-}"
        local saved_project_slug="${PROJECT_SLUG:-}" saved_project_is_framework="${PROJECT_IS_FRAMEWORK:-0}"
        local root="" record="" product="" version="" build="" defs="" product_index=0
        local saved_version_mode="${MODE_UPDATEVERSION:-C}" saved_build_mode="${MODE_UPDATEBUILD:-C}"
        local -a saved_sources=("${RELEASE_SOURCE_DIRS[@]}")

        for product_index in "${!saved_sources[@]}"; do
            (( product_index == 0 )) && continue
            root="${saved_sources[$product_index]}"
            SOURCE_DIR="$root"
            _release_resolve_project_identity || return 1
            VERSION="${RELEASE_PRODUCT_VERSIONS[$product_index]:-$VERSION}"
            MODE_UPDATEVERSION="${RELEASE_PRODUCT_VERSION_MODES[$product_index]:-${MODE_UPDATEVERSION:-C}}"
            MODE_UPDATEBUILD="${RELEASE_PRODUCT_BUILD_MODES[$product_index]:-${MODE_UPDATEBUILD:-C}}"
            BUILD="$(date +%y%j%H)"
            RELEASE_PRODUCT_BUILDS[$product_index]="$BUILD"
            RELEASE="$(_release_product_artifact_name "$PRODUCT")-$VERSION.$BUILD"
            TAR_FILE="$RELEASE.tar.gz"
            RELEASE_SOURCE_DIRS=("$SOURCE_DIR")
            PREVIOUS_MANIFEST="${RELEASE_PRODUCT_BASELINES[$product_index]-}"

            sgnd_print
            if (( ${FLAG_CREATE_INDIVIDUAL_RELEASES:-0} )); then
                sgnd_print_sectionheader "Standalone product release" --padend 0
            else
                sgnd_print_sectionheader "Bundled product metadata" --padend 0
            fi
            sgnd_print_labeledvalue --label "Product" --value "$PRODUCT"
            sgnd_print_labeledvalue --label "Version" --value "$VERSION"
            sgnd_print_labeledvalue --label "Build" --value "$BUILD"

            _normalize_canonical_sources || return 1
            _apply_version_bump || return 1
            _ensure_libexec_executables || return 1
            _ensure_public_command_wrappers || return 1
            if (( ${FLAG_CREATE_INDIVIDUAL_RELEASES:-0} )); then
                _create_tar || return 1
                _create_release_package || return 1
                _archive_release_manifest || return 1
                _cleanup_staging
            fi
        done

        SOURCE_DIR="$saved_source" PRODUCT="$saved_product" VERSION="$saved_version" BUILD="$saved_build"
        RELEASE="$saved_release" TAR_FILE="$saved_tar" PREVIOUS_MANIFEST="$saved_previous"
        PROJECT_DEFINITIONS_FILE="$saved_project_file" PROJECT_DEFINITIONS_KEY="$saved_project_key"
        PROJECT_SLUG="$saved_project_slug" PROJECT_IS_FRAMEWORK="$saved_project_is_framework"
        MODE_UPDATEVERSION="$saved_version_mode" MODE_UPDATEBUILD="$saved_build_mode"
        RELEASE_SOURCE_DIRS=("${saved_sources[@]}")
        return 0
    }

    # fn: main - Run the executable main sequence - Run the executable main sequence
        # . Purpose
        #   Execute the release preparation workflow.
        #
        # . Behavior
        #   - Loads and initializes the framework bootstrap.
        #   - Executes builtin framework argument handling.
        #   - Prepares the standard UI state and title bar.
        #   - Resolves the development root and selects release products first.
        #   - Resolves release parameters for the selected product set.
        #   - Creates the release archive and related metadata.
        #
        # . Arguments
        #   $@  Framework and script-specific command-line arguments
        #
        # . Returns
        #   Exits with the resulting status from bootstrap or release operations
        #
        # . Usage
        #   main "$@"
        #
        # Examples:
        #   main "$@"
    main() {
        # -- Startup
            _framework_locator || exit $?
            sgnd_exe_start --state -- "$@"

        # -- Main script logic

        SOURCE_DIR="${SOURCE_DIR:-"$SGND_FRAMEWORK_ROOT"}"
        sgnd_state_load_keys --array SGND_STATE_VARIABLES || exit $?
        SOURCE_DIR="${SOURCE_DIR:-"$SGND_FRAMEWORK_ROOT"}"

        _release_select_products || {
            sayfail "Could not resolve release product selection; release was not created."
            exit 1
        }

        _get_parameters || exit $?

        # Product selection resolves the definitions; interactive Version remains authoritative
        # for the selected primary product. Build is the common YYDDDHH release build.
        _release_resolve_project_identity || exit $?
        VERSION="${RELEASE_PRODUCT_VERSIONS[0]:-$VERSION}"
        RELEASE_PRODUCT_BUILDS[0]="$BUILD"

        _normalize_canonical_sources || {
            sayfail "Canonical normalization failed; release was not created."
            exit 1
        }

        _apply_version_bump || {
            sayfail "Metadata preparation failed; release was not created."
            exit 1
        }

        _ensure_libexec_executables || {
            sayfail "Executable verification failed; release was not created."
            exit 1
        }

        _ensure_public_command_wrappers || {
            sayfail "Wrapper verification failed; release was not created."
            exit 1
        }

        _release_create_primary_individual_release || {
            sayfail "Primary individual product release failed."
            exit 1
        }

        _release_create_standalone_bundled_products || {
            sayfail "One or more individual product releases failed."
            exit 1
        }

        _release_use_bundled_identity || exit $?

        if (( ${#RELEASE_SOURCE_DIRS[@]} > 1 )); then
            PREVIOUS_MANIFEST="${BUNDLE_PREVIOUS_MANIFEST:-}"
        else
            PREVIOUS_MANIFEST="${RELEASE_PRODUCT_BASELINES[0]-}"
        fi

        _create_tar || {
            sayfail "Release archive creation failed."
            exit 1
        }

        _create_release_package || {
            sayfail "Release package creation failed."
            exit 1
        }

        _archive_release_manifest || {
            sayfail "Release manifest history update failed."
            exit 1
        }

        _cleanup_staging
    }

    # Run main with positional args only (not the options)
    main "$@"
