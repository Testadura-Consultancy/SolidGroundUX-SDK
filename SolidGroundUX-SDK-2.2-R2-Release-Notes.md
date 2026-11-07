<table>
<tr>
<td width="290" align="center" valign="middle">
  <img width="256" alt="SolidGroundUX SDK logo"
       src="target-root/usr/local/share/doc-sources/assets/sdk-readmelogo.png" />
</td>
<td valign="middle">
  <h2>SolidGroundUX SDK</h2>
  <h4>Version 2.2.2631102 R2 · © 2026 Testadura</h4>
</td>
</tr>
</table>

<table>
<tr>
<td width="33%" align="center">
  <a href="https://testadura-consultancy.github.io/SolidGroundUX/"><strong>Documentation</strong></a><br>
  Product reference and guides
</td>
<td width="33%" align="center">
  <a href="CHANGELOG.md"><strong>Changelog</strong></a><br>
  Releases and development history
</td>
<td width="33%" align="center">
  <a href="LICENSE"><strong>License</strong></a><br>
  Terms of use and redistribution
</td>
</tr>
</table>

# SolidGroundUX SDK 2.2 R2 Release Notes

## More reliable workspace deployment

SolidGroundUX SDK 2.2 R2 is a consolidation release focused on the developer experience. It builds on the 2.2 improvements to workspace creation, repository workflows, developer documentation and examples, while correcting deployment behavior that could make working with Framework development trees unnecessarily difficult.

The central change is a more predictable **Deploy Workspace** operation: machine-specific Setup state is excluded from the transfer, and errors now reach the same final interaction point as successful deployments.

## Changes in R2

### Deploy Workspace no longer packages runtime state

Deploy Workspace now excludes `var/lib/solidgroundux/release-manager.state` from the files sent to the target system.

That file contains local Setup state and may be private to root. It does not belong in a deployable development workspace. Previously, trying to include it in a TAR stream could result in a permission-denied error even when the receiving side was running with elevated privileges.

The exclusion protects the workspace transfer without weakening the state file's permissions or changing the transfer mechanism for actual application files.

### Completion dialogs handle errors as well as success

The Deploy Workspace completion interaction now also appears when a deployment fails. The error is reported, and the user is offered **R** to retry. If the user exits the dialog or it times out, the command retains its failure status.

Successful deployments continue to use the existing completion behavior. The change makes failures visible rather than returning immediately to the surrounding menu.

### Documentation workspace cleanup

Documentation scaffolding now follows the current `doc-sources` convention. The generated Bash workspace README no longer points to obsolete prebuilt documentation, and the SDK no longer assumes an old installed-documentation location.

These changes keep generated workspaces aligned with the documentation sources and generator used by SolidGroundUX 2.2.

## Foundation established in 2.2

The original 2.2 release expanded SDK developer guidance and examples, improved development and repository-management workflows, enhanced documentation workspace capabilities and updated SDK architecture illustrations. Source documentation was also reviewed and normalized to make scripts and exposed functions easier to understand and maintain.

R2 preserves that work while concentrating on deployment reliability rather than adding a new developer workflow.

## Compatibility

- Existing workspace transfer and installation mechanisms remain unchanged.
- Runtime-state exclusion applies to workspace deployment; it is not a relaxation of file permissions.
- The SDK remains compatible with the existing SolidGroundUX Framework-based workflow.
- Release packaging and checksum handling remain unchanged.

## Looking forward

R2 provides a cleaner baseline for developing and deploying Framework, SDK and Management Console changes. Future documentation features, including PDF export, remain outside this release.

**Make the difficult easy, without making the difficult impossible.**
