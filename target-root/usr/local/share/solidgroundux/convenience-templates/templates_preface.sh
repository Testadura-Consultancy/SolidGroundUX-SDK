# ==================================================================================
# SolidGroundUX - Script templates 
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626414
#   Checksum    : 9bd698057da84f826391b9ab8add3976abf5f9710601290b4891f3cb7574f275
#   Source      : templates_preface.sh
#   Type        : documentation
#   Group       : SDK
#   Subgroup    : Templates
#   Purpose     : Group preface
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# ==================================================================================
# - Templates -----------------------------------------------------------------------
#
# > The Templates group contains the starting points for creating new
# > SolidGroundUX-compatible scripts, libraries, console modules, and wrappers.
#
# > These templates are intended to capture the current recommended structure for
# > each type of component. Starting from a template helps keep bootstrap logic,
# > metadata headers, documentation comments, guards, naming conventions, and
# > runtime behavior consistent across projects.
#
# -- Template Overview --------------------------------------------------------------
#
# > The group contains four main templates:
#
# >     exe-template.sh
# >         Template for executable command-line tools.
#
# >     lib-template.sh
# >         Template for reusable source-only libraries.
#
# >     mod-template.sh
# >         Template for SolidGround Management Console page modules.
#
# >     wrapper-template
# >         Template for lightweight launcher scripts.
#
# -- Executable Template ------------------------------------------------------------
#
# > The executable template is used for scripts that are intended to be run directly
# > by a user, administrator, scheduled task, or another process.
#
# > It contains the canonical executable locator/bootstrap structure. The locator derives
# > the active framework root from the script path and loads `sgnd-exe-common.sh`; the
# > template then declares dependencies, arguments, state/config contracts, and enters
# > the framework through `sgnd_exe_start` from `main`.
#
# > New command-line tools should normally start from this template rather than
# > copying bootstrap code from an existing script. The template represents the
# > current intended executable structure.
#
# -- Library Template ---------------------------------------------------------------
#
# > The library template is used for reusable Bash libraries that are meant to be
# > sourced, not executed directly.
#
# > It contains the standard library guard pattern. The guard prevents accidental
# > direct execution, avoids repeated initialization when the same library is sourced
# > more than once, and marks the library as loaded before normal initialization
# > continues.
#
# > Libraries created from this template should expose reusable functionality
# > through public functions and keep implementation helpers internal where
# > appropriate.
#
# -- Console Module Template --------------------------------------------------------
#
# > The module template is used for page modules loaded by the SolidGround Management
# > Console. A module is source-only and is sourced only when its page is first opened.
# > It registers menu groups and items through the public `sgnd_menu_*` API, but should
# > not perform the actual action until the user selects the corresponding menu item.
#
# > The main index discovers pages before sourcing them, so each module must expose its
# > page name and description as literal `*_MODULE_NAME="..."` and
# > `*_MODULE_DESC="..."` assignments. Computed values cannot be used for these two
# > discovery fields.
#
# > Modules must not depend on another lazy-loaded page having been opened first. A
# > helper required by multiple modules belongs in `console-helpers.sh` or another
# > appropriately scoped common library.
#
# -- Wrapper Template ---------------------------------------------------------------
#
# > The wrapper template is used for small launcher scripts.
#
# > A wrapper should contain as little logic as possible. Its primary job is to
# > locate and invoke the real implementation script in the expected framework
# > location.
#
# > Wrappers keep user-facing commands short and stable while allowing the
# > implementation to live in the appropriate libexec or framework directory.
#
# -- Why Templates Matter -----------------------------------------------------------
#
# > The templates exist to prevent every script from becoming a slightly different
# > interpretation of the same framework rules.
#
# > They provide a known-good starting point for metadata, bootstrap structure,
# > documentation comments, guards, dependency declarations, and main execution
# > flow.
#
# > When framework conventions evolve, the templates should be updated first. New
# > scripts can then inherit the improved pattern without requiring developers to
# > rediscover the correct structure by reading older files.
