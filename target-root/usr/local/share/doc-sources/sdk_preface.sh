# ==================================================================================
# SolidGroundUX SDK - Introduction
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2627700
#   Checksum    : 9e014fd5edac1d6f614fffc13fe116ea0d6ee89cb05f01c04fe36f6ac7acecd8
#   Source      : sdk_preface.sh
#   Type        : documentation
#   Group       : SolidGroundUX SDK
#   Purpose     : Product preface
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# ==================================================================================
# - SolidGroundUX SDK ---------------------------------------------------------------
#
# > The SolidGroundUX SDK is the development and release-engineering companion to the
# > SolidGroundUX Framework. It contains the tools and templates used to create
# > repository-shaped workspaces, maintain metadata, generate documentation, deploy
# > development trees, and prepare distributable product releases.
#
# > The SDK is not part of the Framework runtime. Applications and servers do not need
# > the SDK merely to run SolidGroundUX. It exists for people building, documenting,
# > testing, packaging, or releasing SolidGroundUX-based products.
#
# -- Product Boundaries -------------------------------------------------------------
#
# > Version 2.1 separates the suite into three sibling products with clear ownership:
# >
# >     SolidGroundUX Framework
# >         Bootstrap, runtime, configuration/state, logging, UI primitives, common
# >         libraries, and reusable application APIs.
# >
# >     SolidGroundUX Management Console Modules
# >         The management-console host plus the modules and role managers used for
# >         guided server administration.
# >
# >     SolidGroundUX SDK
# >         Development workspaces, documentation generation, development deployment,
# >         templates, release preparation, and related engineering tools.
#
# > MCM and SDK both depend on the Framework. They do not depend on each other.
#
# -- Typical Workflow ---------------------------------------------------------------
#
# > A normal SDK-assisted development cycle is:
# >
# >     create or open a workspace
# >         -> edit and test source
# >         -> deploy the workspace to a development target when needed
# >         -> update metadata and documentation
# >         -> prepare a release
# >         -> install/test the resulting product ZIP with sgnd-setup
# >
# > The exact path is intentionally flexible. Documentation can be regenerated without
# > preparing a release, and a workspace can be deployed repeatedly while code is still
# > changing.
#
# -- Repository-Shaped Workspaces ---------------------------------------------------
#
# > SDK tools work with `target-root` layouts that mirror the final filesystem. A source
# > file destined for `/usr/local/libexec/solidgroundux` therefore lives beneath the same
# > path inside the workspace target root.
#
# > This keeps development paths, release manifests, and installed paths aligned. It also
# > allows workspace deployment and release preparation to operate on the same tree
# > without maintaining a second mapping model.
#
# -- Documentation as Part of Development ------------------------------------------
#
# > Documentation generation is a first-class SDK workflow rather than a release-time
# > afterthought. Source comments provide the generated reference material, while
# > documentation-only sources provide introductions, architecture, examples, boundaries,
# > and closing material where prose adds value.
#
# > Product, group, and subgroup prefaces are landing-page content. Epilogues are used
# > only when a section genuinely benefits from closing or reference material after its
# > normal children.
#
# -- Deployment and Release ---------------------------------------------------------
#
# > The SDK deliberately separates development deployment from release installation.
# > `deploy-workspace.sh` copies a development tree so it can be exercised in place.
# > `prepare-release.sh` creates distributable product packages. `sgnd-setup`, supplied
# > by the Framework/first-install package, consumes those releases and owns the installed
# > product lifecycle.
#
# > That separation makes it possible to test quickly during development without
# > pretending every test copy is an installed release.
#
# -- Documentation Map --------------------------------------------------------------
#
# > The main SDK documentation areas are:
# >
# >     SDK
# >         Workspace creation, metadata, release preparation, deployment helpers, and
# >         the general development workflow.
# >
# >     Documentation Generator
# >         Documentation syntax, parsing, rendering, navigation, images, tables,
# >         prefaces/epilogues, and generated output.
# >
# >     Deployment
# >         Release packages, Setup, first installation, GitHub acquisition, development
# >         deployment, rollback, and recovery boundaries.
# >
# >     Templates
# >         Canonical executable, library, module, wrapper, and documentation structures
# >         used when creating new SolidGroundUX components.
#
# > Start with the SDK workflow when building something new, the Documentation Generator
# > when changing the documentation model, and Deployment when turning a tested workspace
# > into an installable release.
