#!/usr/bin/env bash
# ==================================================================================
# SolidGroundUX SDK - Project Definitions
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626712
#   Checksum    : 4c737927b28eb80ed80d9c33f19161fd9367de288b95c847de1b0350342155ed
#   Source      : solidgroundux-sdk-definitions.sh
#   Type        : library
#   Group       : SDK
#   Subgroup    : Definitions
#   Purpose     : Define SolidGroundUX SDK product identity and release globals
#
# Description:
#   Defines the canonical product identity used by SolidGroundUX SDK release tooling.
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# ==================================================================================
set -uo pipefail
# - Library guard ------------------------------------------------------------------
    # fn$ _sgnd_lib_guard - Enforce source-only, single-load library initialization
        # . Purpose
        #   Ensure the file is sourced as a library and initialized only once.
        #
        # . Behavior
        #   - Derives a unique guard variable name from the current filename.
        #   - Aborts execution when the file is run directly instead of sourced.
        #   - Sets the guard variable on first load.
        #   - Returns immediately when the library was already loaded.
        #
        # Inputs
        #   BASH_SOURCE[0]
        #   $0
        #
        # Outputs (globals)
        #   SGND_<MODULE>_LOADED
        #
        # . Returns
        #   0 when already loaded or successfully initialized.
        #   Exits with code 2 when executed instead of sourced.
        #
        # . Usage
        #   _sgnd_lib_guard
    _sgnd_lib_guard() {
        local lib_base=""
        local guard=""

        lib_base="$(basename "${BASH_SOURCE[0]}" .sh)"
        lib_base="${lib_base//-/_}"
        guard="SGND_${lib_base^^}_LOADED"

        [[ "${BASH_SOURCE[0]}" != "$0" ]] || {
            printf 'This is a library; source it, do not execute it: %s\n' "${BASH_SOURCE[0]}" >&2
            exit 2
        }

        [[ -n "${!guard-}" ]] && return 0
        printf -v "$guard" '1'
    }

    _sgnd_lib_guard
    unset -f _sgnd_lib_guard

    if declare -F sgnd_module_init_metadata >/dev/null 2>&1 \
        && declare -F sgnd_header_buffer_load >/dev/null 2>&1; then
        sgnd_module_init_metadata "${BASH_SOURCE[0]}"
    fi
# - SDK identity --------------------------------------------------------------------
    SGND_SOLIDGROUNDUX_SDK_PRODUCT="SolidGroundUX SDK"
    SGND_SOLIDGROUNDUX_SDK_VERSION=2.1
    SGND_SOLIDGROUNDUX_SDK_BUILD=2626712
    SGND_SOLIDGROUNDUX_SDK_COMPANY="Testadura Consultancy"
    SGND_SOLIDGROUNDUX_SDK_COPYRIGHT="© 2025 - 2026 Testadura Consultancy"
    SGND_SOLIDGROUNDUX_SDK_LICENSE="Testadura Non-Commercial License (TD-NC) v1.1."
    SGND_SOLIDGROUNDUX_SDK_DOCUMENTATION=""
    SGND_SOLIDGROUNDUX_SDK_RELEASE_URL=""
    SGND_SOLIDGROUNDUX_SDK_APPENDICES="attribution,license,changelog"
    SGND_SOLIDGROUNDUX_SDK_RELEASE_EXCLUDES="usr/local/lib/solidgroundux/templates"

