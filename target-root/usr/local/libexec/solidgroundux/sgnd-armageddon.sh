#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX - Nuclear removal utility
# -------------------------------------------------------------------------------------
# Purpose:
#   Remove an installed SolidGroundUX toolset, including legacy Release Manager,
#   framework/application trees, wrappers, state, and bootstrap configuration.
#
# Warning:
#   This script is intentionally destructive. It removes SolidGroundUX-owned tooling
#   and metadata only. It does NOT remove managed host configuration or service data.
#
# Intended use:
#   One-time migration from older Release Manager based installations to a clean
#   first-install/Setup based SolidGroundUX installation.
# =====================================================================================
set -u
set -o pipefail

if (( EUID != 0 )); then
    printf 'ERROR: sgnd-armageddon.sh must be run as root.\n' >&2
    exit 126
fi

printf '\n'
printf 'SolidGroundUX ARMAGEDDON\n'
printf '=======================\n'
printf '\n'
printf 'This will permanently remove SolidGroundUX tooling, state, and bootstrap config.\n'
printf 'Managed system configuration and service data are not intentionally removed.\n'
printf '\n'
printf 'Type ARMAGEDDON to continue: '
read -r reply

if [[ "$reply" != "ARMAGEDDON" ]]; then
    printf 'Cancelled.\n'
    exit 0
fi

# Canonical SolidGroundUX-owned trees and legacy locations.
paths=(
    /usr/local/lib/solidgroundux
    /usr/local/libexec/solidgroundux
    /usr/local/share/testadura/solidgroundux
    /usr/local/share/doc/solidgroundux-codex
    /etc/solidgroundux
    /etc/testadura/solidgroundux.cfg
    /var/lib/solidgroundux
    /var/log/solidgroundux
)

for path in "${paths[@]}"; do
    if [[ -e "$path" || -L "$path" ]]; then
        printf 'Removing: %s\n' "$path"
        rm -rf -- "$path"
    fi
done

# Remove known SolidGroundUX command wrappers/executables from standard local paths.
# Keep this explicit; do not wildcard unrelated software.
for dir in /usr/local/bin /usr/local/sbin; do
    [[ -d "$dir" ]] || continue

    while IFS= read -r -d '' file; do
        base="$(basename -- "$file")"
        case "$base" in
            sgnd-*|sgnd|solidgroundux*|release-manager*)
                printf 'Removing: %s\n' "$file"
                rm -f -- "$file"
                ;;
        esac
    done < <(find "$dir" -maxdepth 1 \( -type f -o -type l \) -print0)
done

# Remove per-user SolidGroundUX state/config for local interactive users and root.
# This is deliberate for the clean migration path.
while IFS=: read -r user _ uid _ _ home _; do
    [[ -n "$home" && -d "$home" ]] || continue

    # Root and normal human users only.
    if [[ "$user" != "root" && "$uid" -lt 1000 ]]; then
        continue
    fi

    user_paths=(
        "$home/.config/testadura/solidgroundux.cfg"
        "$home/.config/solidgroundux"
        "$home/.local/state/solidgroundux"
        "$home/.state/solidgroundux"
        "$home/.cache/solidgroundux"
    )

    for path in "${user_paths[@]}"; do
        if [[ -e "$path" || -L "$path" ]]; then
            printf 'Removing: %s\n' "$path"
            rm -rf -- "$path"
        fi
    done
done < /etc/passwd

printf '\n'
printf 'SolidGroundUX tooling and metadata removal completed.\n'
printf 'You can now run the standard SolidGroundUX first-install procedure.\n'
