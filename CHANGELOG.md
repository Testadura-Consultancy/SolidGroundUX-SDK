# Changelog

All notable changes to SolidGroundUX Software Development Kit are documented in this file.

The format is inspired by *Keep a Changelog* while remaining focused on practical framework development.

## Unreleased

Changes prepared for SolidGroundUX 2.2 R2.

### Changed
- Updated Deploy Workspace so its end-of-run auto-continue dialog appears after both successful and failed deployments. On failure, the dialog reports the error, offers **R** to retry and retains the failure exit status when exiting.
- Updated workspace documentation scaffolding to use the current `doc-sources` convention rather than an obsolete installed-documentation location.

### Fixed
- Excluded machine-specific `var/lib/solidgroundux/release-manager.state` from Deploy Workspace transfers. A root-owned, private Setup state file can no longer cause the workspace TAR stream to fail with a permission error.
- Removed the obsolete prebuilt-documentation link from the generated Bash workspace README template.

## Pre Release 2.2.2630700
[CHANGELOG-History](CHANGELOG-History.md)
