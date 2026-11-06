#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX SDK - Prepare VM Template
# ------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.2
#   Build       : 2630913
#   Checksum    : 271da4d69f635254a67e4d602d447baf6cf2ee73a073eb43551e3f4ed0d8c63c
#   Source      : prepare-template.sh
#   Type        : script
#   Group       : SDK
#   Purpose     : Prepares a VM for conversion to a reusable clone template.
#
# Description:
#   Prepares a VM for cloning by clearing transient state, resetting network configuration, and removing machine-specific identifiers.
#
# Usage:
#   Use the installed `sgnd-` command wrapper (or run the libexec script directly):
#   ```bash
#   # Preview the changes without cleaning or shutting down the VM.
#   sgnd-prepare-template --dryrun
#
#   # Prepare this VM and request shutdown afterward.
#   sudo sgnd-prepare-template
#
#   # Enable verbose framework logging during preparation.
#   sudo sgnd-prepare-template --verbose
#   ```
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
# - Script identity ------------------------------------------------------------------
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"

    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"

    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"

    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"
    # var$ SGND_SCRIPT_FILE
        # Absolute path to the currently executing script.
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"

    # var$ SGND_SCRIPT_DIR
        # Directory containing the currently executing script.
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"

    # var$ SGND_SCRIPT_BASE
        # Filename of the currently executing script, including extension.
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"

    # var$ SGND_SCRIPT_NAME
        # Script basename without the .sh extension; used for help and display text.
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"

# - Framework integration ----------------------------------------------------------
    # var: SGND_USING - Optional framework libraries to source after core bootstrap
        # Libraries to source from SGND_COMMON_LIB.
        # These are loaded automatically by sgnd_bootstrap AFTER core libraries.
        #
        # Example:
        #   SGND_USING=( net.sh fs.sh )
        #
        # Leave empty if no extra libs are needed.
    SGND_USING=(
    )

    # var: SGND_ARGS_SPEC - Script-specific command-line argument specification
        # Optional: script-specific arguments
        # --- Example: Arguments
        # Each entry:
        #   "name|short|type|var|help|choices"
        #
        #   name    = long option name WITHOUT leading --
        #   short   - short option name WITHOUT leading -
        #   type    = flag | value | enum
        #   var     = shell variable that will be set
        #   help    = help string for auto-generated --help output
        #   choices = for enum: comma-separated values (e.g. fast,slow,auto)
        #             for flag/value: leave empty
        #
        # Notes:
        #   - -h / --help is built in, you don't need to define it here.
        #   - After parsing you can use: FLAG_VERBOSE, VAL_CONFIG, ENUM_MODE, ...
    SGND_ARGS_SPEC=(
    )

    # var: SGND_SCRIPT_EXAMPLES - Optional help examples for this script
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

    # var: SGND_SCRIPT_GLOBALS - Script globals participating in configuration loading
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

    # var: SGND_STATE_VARIABLES - Script variables participating in persistent state
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
    )

    # var: SGND_ON_EXIT_HANDLERS - Script-specific exit handler list
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
    
    # var$ SGND_STATE_SAVE
        # State persistence toggle used by sgnd_bootstrap when state support is enabled.
        #
        # Scripts that want persistent state must:
        #   1) set SGND_STATE_SAVE=1
        #   2) call sgnd_bootstrap --state or --autostate
    SGND_STATE_SAVE=0

# - Local script declarations -------------------------------------------------------
    # doc$ Local script declarations
        # Put script-local constants and defaults here, not framework configuration.
        # Prefer local variables inside functions unless a value must be shared.

# - Local script functions ----------------------------------------------------------
    # doc$ Local script functions
        # Organize script-specific functions here.
        # These functions are not reusable framework behavior; they implement the
        # unique logic and features of the executable script.
        #
        # Suggested organization:
        #   - Initialization
        #   - Local script helpers
        #   - Layout and display helpers
        #   - Input handling
        #   - Business logic
        #   - Validation
        #   - Reporting
        #   - Cleanup

    # fn: _detect_primary_iface - Find the interface that will receive DHCP configuration
        # . Purpose
        #   Print the IPv4 default-route interface, falling back to the first non-loopback interface.
        #
        # . Returns
        #   0 after printing an interface; 1 when no eligible interface is found.
        #
        # . Usage
        #   ```bash
        #   _detect_primary_iface
        #   ```
    _detect_primary_iface() {
        local primary_iface

        primary_iface="$(ip -o -4 route show to default | awk '{print $5; exit}')"
        if [[ -z "$primary_iface" ]]; then
            primary_iface="$(find /sys/class/net -mindepth 1 -maxdepth 1 -printf '%f\n' | grep -v '^lo$' | head -n 1)"
        fi

        if [[ -z "$primary_iface" ]]; then
            sayerror 'No network interface found.'
            return 1
        fi

        printf '%s\n' "$primary_iface"
    }

    # fn: _reset_networkmanager_for_template - Reset only the active NetworkManager profile to DHCP.
        # . Purpose
        #   Keep the NetworkManager renderer and other connection profiles intact.
        #   On current Ubuntu desktops NetworkManager persists profiles as Netplan YAML.
        #   No connection reactivation is needed: the VM is about to shut down.
        # . Arguments
        #   - `$1`: Primary interface.
        # . Usage
        #   ```bash
        #   _reset_networkmanager_for_template "ens18"
        #   ```
    _reset_networkmanager_for_template() {
        local iface="${1:-}"
        local connection=""
        local uuid=""
        local output=""

        connection="$(nmcli -g GENERAL.CONNECTION device show "$iface" 2>/dev/null)" || return 1
        if [[ -z "$connection" || "$connection" == "--" ]]; then
            sayfail "No active NetworkManager profile on $iface; refusing to create a competing configuration."
            return 1
        fi
        uuid="$(nmcli -g connection.uuid connection show "$connection" 2>/dev/null)" || return 1
        [[ -n "$uuid" && "$uuid" != "--" ]] || return 1

        sayinfo "Resetting the existing NetworkManager profile on $iface to DHCP."
        if ! output="$(nmcli connection modify "$uuid" \
            ipv4.method auto \
            ipv4.addresses "" \
            ipv4.gateway "" \
            ipv4.dns "" \
            ipv4.dns-search "" \
            ipv4.ignore-auto-dns no 2>&1)"; then
            sayfail "Failed to reset NetworkManager profile: $output"
            return 1
        fi
        sayinfo "NetworkManager profile saved; other Netplan files and network profiles are unchanged."
        return 0
    }

    # fn: _template_netplan_file_is_dedicated - Reject ambiguous networkd configurations.
        # . Purpose
        #   The networkd reset overwrites a single YAML file. Refuse files containing
        #   unrelated interfaces or complex network definitions.
        # . Arguments
        #   - `$1`: Netplan file to inspect.
        #   - `$2`: Interface that should be the only configured Ethernet device.
        # . Usage
        #   ```bash
        #   _template_netplan_file_is_dedicated "/etc/netplan/50-cloud-init.yaml" "ens18"
        #   ```
    _template_netplan_file_is_dedicated() {
        local file="${1:-}"
        local iface="${2:-}"
        [[ -f "$file" ]] || return 0
        awk -v iface="$iface" '
            /^  (wifis|bridges|bonds|vlans|tunnels|modems|vrfs|nm-devices|dummy-devices):/ { exit 1 }
            /^  [^ #][^:]*:/ {
                key=$0
                sub(/^  /, "", key)
                sub(/:.*/, "", key)
                if (key != "version" && key != "renderer" && key != "ethernets") exit 1
            }
            /^    [^ #][^:]*:/ {
                key=$0
                sub(/^    /, "", key)
                sub(/:.*/, "", key)
                gsub(/["\047]/, "", key)
                if (key != iface) exit 1
            }
        ' "$file"
    }

    # fn: _reset_network_for_template - Reset the selected interface to DHCP without deleting other profiles.
        # . Purpose
        #   Detect the active renderer and preserve NetworkManager connection profiles.
        #   For simple networkd installations, replace only the YAML file belonging
        #   to the selected interface, with backup and generation rollback.
        # . Returns
        #   0 if the profile was saved or Netplan generation succeeds; nonzero on error.
        # . Usage
        #   ```bash
        #   _reset_network_for_template
        #   ```
    _reset_network_for_template() {
        local primary_iface=""
        local managed=""
        local renderer=""
        local netplan_file=""
        local file=""
        local backup_file=""
        local candidate_file=""
        local original_exists=0

        primary_iface="$(_detect_primary_iface)" || return $?
        sayinfo "Resetting network configuration to DHCP on $primary_iface"

        if command -v nmcli >/dev/null 2>&1; then
            managed="$(nmcli -g GENERAL.NM-MANAGED device show "$primary_iface" 2>/dev/null)" || managed=""
            if [[ "${managed,,}" == "yes" || "${managed,,}" == "true" ]]; then
                _reset_networkmanager_for_template "$primary_iface"
                return $?
            fi
        fi

        renderer="$(netplan get "network.ethernets.${primary_iface}.renderer" 2>/dev/null)" || renderer=""
        if [[ -z "$renderer" || "$renderer" == "null" ]]; then
            renderer="$(netplan get network.renderer 2>/dev/null)" || renderer=""
        fi
        case "${renderer,,}" in
            ""|null|networkd) ;;
            networkmanager)
                sayfail "NetworkManager is the Netplan renderer, but $primary_iface has no active managed profile."
                return 1
                ;;
            *)
                sayfail "Unsupported Netplan renderer '$renderer'; refusing to change network configuration."
                return 1
                ;;
        esac

        # Select the networkd file defining this interface; never discard the others.
        while IFS= read -r -d '' file; do
            if grep -Eq "^    ['\"]?${primary_iface}['\"]?:" "$file"; then
                if [[ -n "$netplan_file" ]]; then
                    sayfail "Multiple Netplan files define $primary_iface; refusing an ambiguous template reset."
                    return 1
                fi
                netplan_file="$file"
            fi
        done < <(find /etc/netplan -maxdepth 1 -type f -name '*.yaml' -print0 2>/dev/null)

        if [[ -z "$netplan_file" ]]; then
            netplan_file='/etc/netplan/90-solidgroundux-template.yaml'
            if find /etc/netplan -maxdepth 1 -type f -name '*.yaml' -print -quit 2>/dev/null | grep -q .; then
                sayfail "Cannot identify the primary interface in Netplan; refusing to create an overriding profile."
                return 1
            fi
        fi

        if ! _template_netplan_file_is_dedicated "$netplan_file" "$primary_iface"; then
            sayfail "Netplan file '$netplan_file' includes other networks; refusing to replace it."
            return 1
        fi

        candidate_file="$(mktemp)" || return 1
        backup_file="$(mktemp)" || { rm -f -- "$candidate_file"; return 1; }
        if [[ -f "$netplan_file" ]]; then
            original_exists=1
            cp -a -- "$netplan_file" "$backup_file" || {
                rm -f -- "$candidate_file" "$backup_file"
                return 1
            }
        fi

        {
            printf '%s\n' 'network:'
            printf '%s\n' '  version: 2'
            printf '%s\n' '  renderer: networkd'
            printf '%s\n' '  ethernets:'
            printf '    %s:\n' "$primary_iface"
            printf '%s\n' '      dhcp4: true'
        } > "$candidate_file" || {
            rm -f -- "$candidate_file" "$backup_file"
            return 1
        }

        if ! install -o root -g root -m 600 -- "$candidate_file" "$netplan_file"; then
            rm -f -- "$candidate_file" "$backup_file"
            return 1
        fi
        rm -f -- "$candidate_file"

        if ! netplan generate; then
            sayfail "Netplan validation failed; restoring the original network configuration."
            if (( original_exists == 1 )); then
                cp -a -- "$backup_file" "$netplan_file" || saywarning "Failed to restore $netplan_file."
            else
                rm -f -- "$netplan_file" || saywarning "Failed to remove new Netplan configuration."
            fi
            netplan generate >/dev/null 2>&1 || true
            rm -f -- "$backup_file"
            return 1
        fi

        rm -f -- "$backup_file"
        sayinfo "Networkd DHCP configuration saved; unrelated Netplan files preserved."
        return 0
    }

    # fn: _prepare_template - Clear machine-specific state before cloning a VM
        # . Side effects
        #   - Normal mode runs apt clean/autoremove and updates only the active network configuration.
        #   - Deletes SSH host keys, systemd journal history and temporary files.
        #   - Clears /etc/machine-id and links the D-Bus machine-id to it.
        #   - Invokes an auto-continue dialog, then requests shutdown.
        #   - Dry-run reports the cleanup actions without performing them or shutting down.
        #
        # . Purpose
        #   Clear machine-specific state before cloning or imaging the VM.
        #   Normal mode resets network, clears SSH keys and machine ID, then shuts down.
        #
        # . Returns
        #   Status of the first failed command, or 0 when the preparation completes;
        #   dry-run skips cleanup and shutdown.
        #
        # . Usage
        #   ```bash
        #   _prepare_template
        #   ```
    _prepare_template() {
        sayinfo "Preparing VM for template conversion..."

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: would have:"
            sayinfo "- Cleaned package cache"
            sayinfo "- Removed unused packages"
            sayinfo "- Reset network configuration to DHCP"
            sayinfo "- Removed SSH host keys"
            sayinfo "- Cleaned systemd journal"
            sayinfo "- Cleaned temporary files"
            sayinfo "- Cleared machine-id"
            sayinfo "- Shut down the machine"
        else
            sayinfo "Cleaning package cache..."
            apt clean || return $?

            sayinfo "Removing unused packages..."
            apt autoremove -y || return $?

            _reset_network_for_template || return $?

            sayinfo "Removing SSH host keys..."
            rm -f /etc/ssh/ssh_host_* || return $?
            sayinfo "After cloning, regenerate SSH host keys from the Proxmox console before using SSH."

            sayinfo "Cleaning systemd journal..."
            journalctl --rotate || return $?
            journalctl --vacuum-time=1s || return $?

            sayinfo "Cleaning temporary files..."
            find /tmp -mindepth 1 -delete || return $?
            find /var/tmp -mindepth 1 -delete || return $?

            sayinfo "Clearing machine-id..."
            truncate -s 0 /etc/machine-id || return $?
            rm -f /var/lib/dbus/machine-id || return $?
            ln -sf /etc/machine-id /var/lib/dbus/machine-id || return $?

            sayinfo "Flushing filesystem buffers..."
            sync || return $?
        fi

        ask_dlg_autocontinue --seconds 10 --message "Shutting down system in " --redo --cancel --pause

        if (( ${FLAG_DRYRUN:-0} == 0 )); then
            shutdown now || return $?
        fi
    }

# - Main ----------------------------------------------------------------------------
    # fn: main - Bootstrap and run the VM-template preparation workflow
        # . Purpose
        #   Initialize the Framework as root and prepare the VM for cloning.
        #
        # . Arguments
        #   $@  Command-line arguments.
        #
        # . Behavior
        #   - Locates the SolidGroundUX framework.
        #   - Loads executable runtime support.
        #   - Starts the framework runtime through sgnd_exe_start.
        #   - Calls _prepare_template; normal mode requests shutdown after cleanup.
        #
        # . Returns
        #   Exits with the resulting status code from startup or script logic.
        #
        # . Usage
        #   ```bash
        #   main "$@"
        #   ```
    main() {     
        _framework_locator || exit $?
        sgnd_exe_start --needroot "$@"

        _prepare_template || exit $?
    }

    # Entrypoint: sgnd_bootstrap will split framework args from script args.
    main "$@"
