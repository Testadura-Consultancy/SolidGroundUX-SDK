# Changelog

All notable changes to SolidGroundUX SDK are documented in this file.

## Unreleased

### Added

- Established SolidGroundUX SDK as the owner of development, workspace, deployment, documentation and release tooling separated from the SolidGroundUX Framework.
- Added multi-product documentation collections with product discovery/selection, a primary product, product-specific `.docignore` configuration, deterministic duplicate-module handling and merged product assets.
- Added explicit documentation collection/output handling and documentation table syntax support.
- Added multi-product release preparation with per-product Version/Build policy, primary-product bundle identity, product ownership collision detection and per-product removal-baseline selection.
- Added release-package discovery and product-aware release/removal handling, including manifest-based removal and ownership-based removal paths.
- Added a declarative `workspace-layout.cfg` used by `create-workspace` to instantiate the complete canonical target-root tree, including system/user configuration and state locations, MOTD, runtime, share and var directories.
- Added optional project Description input to `create-workspace`; the description is stored in project definitions and reused by generated repository material.
- Added generated project README, changelog, license placeholder, default SolidGroundUX icon and Git placeholders for otherwise-empty canonical workspace directories.

### Changed

- Moved `create-workspace`, `deploy-workspace`, `prepare-release`, release management, documentation generation/rendering/processing, wrapper generation and canonical normalization into the SDK product boundary.
- `create-workspace` now derives generated README identity from project definitions: Title, Version.Build, Copyright, project name and Description. Generated README navigation points to installed documentation, changelog and license and no longer embeds Framework-specific marketing captions.
- `create-workspace` now creates the full canonical workspace tree even when individual directories are not initially used; empty directories are retained in Git with placeholders that are excluded from release content.
- Convenience templates are discovered by product ownership and copied into workspace-local templates for project use. Starter scripts receive the new project identity and canonical Version/Build defaults.
- `doc-generator` now treats duplicate module basenames across products as deterministic first-wins collisions: the duplicate is warned about and skipped rather than overwriting or aborting the collection.
- `prepare-release` now treats product identity independently from repository identity and keeps release metadata/baseline state with each selected product. Bundles inherit Version/Build from the primary product.
- SDK executables running from a non-root SDK development tree now resolve Framework-owned resources through the Framework resolver while preserving their own SDK development context.

### Fixed

- Fixed `create-workspace` prematurely aborting after starter-script generation when the final selected template was non-executable; subsequent definitions, MOTD, README, changelog, license and placeholder generation now runs normally.
- Fixed `normalize-canon` assuming canonical Framework fragments existed beneath the SDK development root; canonical fragments now resolve from the actual local or installed Framework.
- Fixed `prepare-release` product identity updates for canonically indented `*_VERSION` and `*_BUILD` assignments and improved failure reporting for identity/header/checksum update failures.
- Fixed release baseline discovery so the Framework product-name prefix does not absorb similarly named companion products such as Management Console Modules.
- Fixed documentation output behavior so duplicate modules and assets are reported without silently replacing previously collected product content.

