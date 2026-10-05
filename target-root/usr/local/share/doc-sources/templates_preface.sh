# ==================================================================================
# SolidGroundUX - Script templates 
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2627808
#   Checksum    : 19ae2baa1cd59d90b78b81eef65b037d5fa386f84a2efbd56a03f04c542a4bd0
#   Source      : templates_preface.sh
#   Type        : documentation
#   Group       : SDK
#   Subgroup    : Templates
#   Purpose     : Subgroup preface
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
# > The Templates subgroup contains the SDK-owned starting points for creating
# > SolidGroundUX-compatible executables, libraries, documentation source files, and wrappers.
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
# >     doc-template.sh
# >         Template for documentation prefaces, epilogues, and authored source pages.
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
# -- Documentation Template ---------------------------------------------------------
#
# > The documentation template is used for authored documentation source files such as
# > product, group, and subgroup prefaces or epilogues. It provides the canonical
# > documentation markers, style hints, image blocks, tables, and alignment syntax
# > understood by the documentation generator.
#
# > The Management Console module template is owned by the Management Console Modules
# > product and is therefore documented with that product rather than in this SDK
# > Deployment/Templates subgroup.
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
