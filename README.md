<table>
<tr>
<td width="170" align="center" valign="middle">
  <img width="96" height="96" alt="SolidGroundUX SDK logo" src="target-root/usr/local/assets/solidgroundux-sdk.png" />
</td>
<td valign="middle">
  <big><big><big><strong>SolidGroundUX SDK</strong></big></big></big><br>
  <sub>Version 2.1.2626414 · © 2026 Testadura</sub>
</td>
</tr>
</table>

<table>
<tr>
<td width="33%" align="center">
  <a href="target-root/usr/local/share/doc/SolidGroundUX SDK/index.html"><strong>Documentation</strong></a><br>
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

---

## About SolidGroundUX SDK

The **SolidGroundUX SDK** contains the development, documentation, workspace, deployment and release tooling used to build and maintain SolidGroundUX-based products.

The SDK was separated from the SolidGroundUX Framework so the Framework can remain focused on runtime services and reusable APIs. SDK tools consume the installed Framework in the same way as other SolidGroundUX applications, while retaining development-root awareness when they operate on staged products.

## Responsibilities

The SDK owns tooling for:

- creating and deploying SolidGroundUX workspaces;
- generating and rendering product documentation;
- normalizing canonical Framework structures;
- preparing individual and multi-product releases;
- managing release installation, rollback and removal;
- creating public wrappers and other development/release artifacts.

The SDK does **not** own the SolidGroundUX runtime or Management Console application. Those belong to the SolidGroundUX Framework and SolidGroundUX Management Console Modules respectively.

## Product-aware tooling

SDK tools are designed around product identity rather than repository identity. A workspace may contain or operate on more than one product, and a release or documentation collection may combine products while preserving their individual ownership, metadata and release history.

`doc-generator` supports multi-product collections, product-specific ignore configuration, deterministic duplicate handling and merged product assets. `prepare-release` supports individual product releases and combined bundles with product-specific metadata, collision checks and removal baselines.

## Workspace creation

`create-workspace` creates the canonical SolidGroundUX workspace tree and project definitions, copies selected convenience templates, creates project starter scripts where requested, and prepares repository-level material such as README, changelog, license placeholder, project icon and MOTD integration.

Project descriptions are stored in the project definitions and reused when rendering generated project material rather than being duplicated as README-specific metadata.

## Framework dependency

The SDK depends on the SolidGroundUX Framework. During development, Framework-owned resources are resolved from a local Framework when one is actually present; otherwise SDK tools fall back to the installed Framework without changing the SDK's own development-root context.
