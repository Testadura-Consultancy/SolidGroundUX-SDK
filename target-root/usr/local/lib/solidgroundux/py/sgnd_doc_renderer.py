#!/usr/bin/env python3
# ==================================================================================
# SolidGroundUX SDK - Documentation HTML Renderer Backend
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.0
#   Build       : 2622911
#   Source      : sgnd_doc_renderer.py
#   Type        : python
#   Group       : SDK
#   Subgroup    : Documentation Generator
#   Purpose     : Render normalized SolidGroundUX documentation tables as HTML
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# ==================================================================================
# - Python Renderer Backend ---------------------------------------------------------
#
# > Python backend used by the SolidGroundUX documentation pipeline to transform the
# > normalized PSV tables emitted by the Bash processor into the navigable HTML site.
#
# > The module is intentionally standard-library only and uses the same SolidGroundUX
# > `# fn:`, `# cls:`, `# var:`, and section-comment dialect as Bash source files.

"""
SolidgroundUX - Documentation HTML Renderer Backend
---------------------------------------------------

Purpose:
    Render SolidgroundUX documentation from normalized table exports produced by
    the Bash doc-generator/parser.

Backend contract:
    python3 sgnd_doc_renderer.py <input-dir> <output-dir>

Expected input files in <input-dir>:
    mod_table.psv
    mod_sections.psv
    mod_items.psv
    mod_attribution.psv
    doc_content_lines.psv
    render_config.psv

Notes:
    This script intentionally uses only the Python standard library.
"""

from __future__ import annotations

import html
import os
import re
import shutil
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

RENDERER_BUILD = "2026154"

# var: DOC_INDEX_LOGO - Documentation index branding asset
# . Purpose
#   Name of the image displayed above the documentation navigation index.
DOC_INDEX_LOGO = "doc-index-logo.png"

# var: DOC_HEADER_LOGO - Documentation page header branding asset
# . Purpose
#   Name of the compact image displayed beside the documentation site title.
DOC_HEADER_LOGO = "doc-header-logo.png"

# var: DOC_INDEX_HERO - Documentation landing-page hero asset
# . Purpose
#   Name of the current release/showcase image displayed on the documentation home page.
DOC_INDEX_HERO = "doc-index-hero.png"

Row = Dict[str, str]
CANONICAL_PREFIX = "appendix:canonical:"
ATTRIBUTION_PREFIX = "appendix:attribution:"
GLOSSARY_PREFIX = "appendix:glossary:"
INTEGRITY_PREFIX = "appendix:integrity:"
GLOBALS_PREFIX = "appendix:globals:"
LICENSE_PREFIX = "appendix:license:"
ENUMS_PREFIX = "appendix:enums:"
CHANGELOG_PREFIX = "appendix:changelog:"
INSTALL_PREFIX = "appendix:install:"


# fn: read_psv - Read psv
# . Purpose
#   Read a pipe-separated table with a schema/header row.
#
# . Arguments
#   path  Value consumed by this function; see the typed Python signature for its contract.
#   required  Value consumed by this function; see the typed Python signature for its contract.
# . Usage
#   read_psv(<path>, <required>)
def read_psv(path: Path, *, required: bool = True) -> List[Row]:
    """Read a pipe-separated table with a schema/header row."""
    if not path.exists():
        if required:
            raise FileNotFoundError(f"Missing input table: {path}")
        return []

    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines:
        return []

    columns = lines[0].split("|")
    rows: List[Row] = []

    for line_number, line in enumerate(lines[1:], start=2):
        values = line.split("|")

        if len(values) < len(columns):
            values.extend([""] * (len(columns) - len(values)))

        if len(values) > len(columns):
            raise ValueError(
                f"Invalid column count in {path.name} line {line_number}: "
                f"expected {len(columns)}, got {len(values)}"
            )

        rows.append(dict(zip(columns, values)))

    return rows


# fn: read_config - Read config
# . Purpose
#   Read config for the documentation rendering workflow.
#
# . Arguments
#   path  Value consumed by this function; see the typed Python signature for its contract.
# . Usage
#   read_config(<path>)
def read_config(path: Path) -> Dict[str, str]:
    rows = read_psv(path, required=False)
    config: Dict[str, str] = {}

    for row in rows:
        key = row.get("key", "")
        value = row.get("value", "")
        if key:
            config[key] = value

    return config


# fn: esc - Esc
# . Purpose
#   Esc for the documentation rendering workflow.
#
# . Arguments
#   value  Value consumed by this function; see the typed Python signature for its contract.
# . Usage
#   esc(<value>)
def esc(value: str | None) -> str:
    return html.escape(value or "", quote=True)


# fn: slugify - Create slug for
# . Purpose
#   Create slug for for the documentation rendering workflow.
#
# . Arguments
#   value  Value consumed by this function; see the typed Python signature for its contract.
# . Usage
#   slugify(<value>)
def slugify(value: str | None) -> str:
    text = (value or "").lower()
    text = re.sub(r"[^a-z0-9]+", "-", text)
    text = text.strip("-")
    return text or "page"


# fn: normalize_key - Normalize key
# . Purpose
#   Normalize key for the documentation rendering workflow.
#
# . Arguments
#   value  Value consumed by this function; see the typed Python signature for its contract.
# . Usage
#   normalize_key(<value>)
def normalize_key(value: str | None) -> str:
    text = (value or "").lower()
    text = re.sub(r"[^a-z0-9]+", "_", text)
    text = text.strip("_")
    return text


# fn: content_ref - Build content ref
# . Purpose
#   Build content ref for the documentation rendering workflow.
#
# . Arguments
#   module_name  Value consumed by this function; see the typed Python signature for its contract.
#   grandparent_section  Value consumed by this function; see the typed Python signature for its contract.
#   parent_section  Value consumed by this function; see the typed Python signature for its contract.
#   section_name  Value consumed by this function; see the typed Python signature for its contract.
#   item_name  Value consumed by this function; see the typed Python signature for its contract.
# . Usage
#   content_ref(<module_name>, <grandparent_section>, <parent_section>, <section_name>, <item_name>)
def content_ref(
    module_name: str,
    grandparent_section: str = "",
    parent_section: str = "",
    section_name: str = "",
    item_name: str = "",
) -> str:
    return f"{module_name}:{grandparent_section}:{parent_section}:{section_name}:{item_name}"


# fn: canonical_ref - Build canonical ref
# . Purpose
#   Build canonical ref for the documentation rendering workflow.
#
# . Arguments
#   product_name  Value consumed by this function; see the typed Python signature for its contract.
# . Usage
#   canonical_ref(<product_name>)
def canonical_ref(product_name: str) -> str:
    return f"{CANONICAL_PREFIX}{product_name}"


# fn: attribution_ref - Build attribution ref
# . Purpose
#   Build attribution ref for the documentation rendering workflow.
#
# . Arguments
#   product_name  Value consumed by this function; see the typed Python signature for its contract.
# . Usage
#   attribution_ref(<product_name>)
def attribution_ref(product_name: str) -> str:
    return f"{ATTRIBUTION_PREFIX}{product_name}"


# fn: glossary_ref - Build glossary ref
# . Purpose
#   Build glossary ref for the documentation rendering workflow.
#
# . Arguments
#   product_name  Value consumed by this function; see the typed Python signature for its contract.
# . Usage
#   glossary_ref(<product_name>)
def glossary_ref(product_name: str) -> str:
    return f"{GLOSSARY_PREFIX}{product_name}"


# fn: integrity_ref - Build integrity ref
# . Purpose
#   Build integrity ref for the documentation rendering workflow.
#
# . Arguments
#   product_name  Value consumed by this function; see the typed Python signature for its contract.
# . Usage
#   integrity_ref(<product_name>)
def integrity_ref(product_name: str) -> str:
    return f"{INTEGRITY_PREFIX}{product_name}"


# fn: globals_ref - Build globals ref
# . Purpose
#   Build globals ref for the documentation rendering workflow.
#
# . Arguments
#   product_name  Value consumed by this function; see the typed Python signature for its contract.
# . Usage
#   globals_ref(<product_name>)
def globals_ref(product_name: str) -> str:
    return f"{GLOBALS_PREFIX}{product_name}"


# fn: license_ref - Build license ref
# . Purpose
#   Build license ref for the documentation rendering workflow.
#
# . Arguments
#   product_name  Value consumed by this function; see the typed Python signature for its contract.
# . Usage
#   license_ref(<product_name>)
def license_ref(product_name: str) -> str:
    return f"{LICENSE_PREFIX}{product_name}"


# fn: enums_ref - Build enums ref
# . Purpose
#   Build enums ref for the documentation rendering workflow.
#
# . Arguments
#   product_name  Value consumed by this function; see the typed Python signature for its contract.
# . Usage
#   enums_ref(<product_name>)
def enums_ref(product_name: str) -> str:
    return f"{ENUMS_PREFIX}{product_name}"


# fn: changelog_ref - Build changelog ref
# . Purpose
#   Build changelog ref for the documentation rendering workflow.
#
# . Arguments
#   product_name  Value consumed by this function; see the typed Python signature for its contract.
# . Usage
#   changelog_ref(<product_name>)
def changelog_ref(product_name: str) -> str:
    return f"{CHANGELOG_PREFIX}{product_name}"


# fn: install_ref - Build install ref
# . Purpose
#   Build install ref for the documentation rendering workflow.
#
# . Arguments
#   product_name  Value consumed by this function; see the typed Python signature for its contract.
# . Usage
#   install_ref(<product_name>)
def install_ref(product_name: str) -> str:
    return f"{INSTALL_PREFIX}{product_name}"


# fn: page_href_from_contentref - Build page href from contentref
# . Purpose
#   Build page href from contentref for the documentation rendering workflow.
#
# . Arguments
#   ref  Value consumed by this function; see the typed Python signature for its contract.
# . Usage
#   page_href_from_contentref(<ref>)
def page_href_from_contentref(ref: str) -> str:
    return f"pages/{slugify(ref)}.html"


# fn: is_item_node - Determine whether item node
# . Purpose
#   Determine whether item node for the documentation rendering workflow.
#
# . Arguments
#   node_type  Value consumed by this function; see the typed Python signature for its contract.
# . Usage
#   is_item_node(<node_type>)
def is_item_node(node_type: str) -> bool:
    return node_type in {"function", "class", "variable", "general documentation"}


# fn: display_name_with_title - Resolve display name with title
# . Purpose
#   Resolve display name with title for the documentation rendering workflow.
#
# . Arguments
#   name  Value consumed by this function; see the typed Python signature for its contract.
#   title  Value consumed by this function; see the typed Python signature for its contract.
# . Usage
#   display_name_with_title(<name>, <title>)
def display_name_with_title(name: str, title: str) -> str:
    clean_name = name or ""
    clean_title = title or ""

    if clean_title:
        return clean_title

    return clean_name


# cls: AppendixSpec - Appendix specification
# . Purpose
#   Describe one generated documentation appendix and its renderer binding.
@dataclass(frozen=True)
class AppendixSpec:
    key: str
    letter: str
    title: str
    ref_factory: object
    renderer_name: str


APPENDIX_SPECS: tuple[AppendixSpec, ...] = (
    AppendixSpec("canonical", "0", "Unimatrix 01", canonical_ref, "render_canonical_page"),
    AppendixSpec("attribution", "A", "Attribution", attribution_ref, "render_attribution_page"),
    AppendixSpec("glossary", "B", "Glossary", glossary_ref, "render_glossary_page"),
    AppendixSpec("integrity", "C", "Integrity Information", integrity_ref, "render_integrity_page"),
    AppendixSpec("globals", "D", "Global Variables", globals_ref, "render_globals_page"),
    # AppendixSpec("enums", "E", "Framework Value Sets", enums_ref, "render_enums_page"),
    AppendixSpec("license", "X", "License", license_ref, "render_license_page"),
    AppendixSpec("changelog", "Y", "Change Log", changelog_ref, "render_changelog_page"),
    AppendixSpec("install", "Z", "First Installation", install_ref, "render_install_page"),
)


# cls: NavNode - Navigation node
# . Purpose
#   Represent one node in the generated documentation navigation hierarchy.
@dataclass
class NavNode:
    nodeid: str
    parentnodeid: str
    nodetype: str
    node_name: str
    node_title: str
    hierarchy_level: int
    docindex: str
    contentref: str
    hasitems: bool = False
    isinternal: bool = False
    istemplate: bool = False


# cls: DocRenderer - Documentation HTML renderer
# . Purpose
#   Transform normalized SolidGroundUX documentation tables into the generated HTML site.
class DocRenderer:
    # fn: __init__ - Initialize renderer instance
    # . Purpose
    #   Initialize renderer instance for the documentation rendering workflow.
    #
    # . Arguments
    #   input_dir  Value consumed by this function; see the typed Python signature for its contract.
    #   output_dir  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.__init__(<input_dir>, <output_dir>)
    def __init__(self, input_dir: Path, output_dir: Path) -> None:
        self.input_dir = input_dir
        self.output_dir = output_dir
        self.asset_dir = output_dir / "assets"
        self.page_dir = output_dir / "pages"
        asset_sources = os.environ.get("SGND_DOC_ASSETS_DIRS", "").strip()
        if not asset_sources:
            asset_sources = os.environ.get("SGND_DOC_ASSETS_DIR", "").strip()
        self.asset_source_dirs = [
            Path(source).resolve()
            for source in asset_sources.split(os.pathsep)
            if source.strip()
        ]

        self.mod_table: List[Row] = []
        self.mod_sections: List[Row] = []
        self.mod_items: List[Row] = []
        self.mod_attribution: List[Row] = []
        self.mod_globals: List[Row] = []
        self.doc_license_lines: List[Row] = []
        self.product_manifests: List[Row] = []
        self.product_manifest_by_name: Dict[str, Row] = {}
        self.doc_enums: List[Row] = []
        self.doc_content_lines: List[Row] = []
        self.config: Dict[str, str] = {}

        self.nav: List[NavNode] = []
        self.content_by_ref: Dict[str, List[Row]] = defaultdict(list)

        self.doc_title = ""
        self.doc_subtitle = ""
        self.doc_version = ""
        self.doc_product = ""
        self.collection_name = ""
        self.doc_render_date = ""

    # fn: run - Run
    # . Purpose
    #   Run for the documentation rendering workflow.
    # . Usage
    #   self.run()
    def run(self) -> None:
        self.load_input()
        self.prepare_output()
        self.init_metadata()
        self.build_content_index()
        self.build_doc_hierarchy()
        self.render_assets()
        self.render_content_pages()
        self.render_index_page()

    # fn: load_input - Load input
    # . Purpose
    #   Load input for the documentation rendering workflow.
    # . Usage
    #   self.load_input()
    def load_input(self) -> None:
        self.mod_table = read_psv(self.input_dir / "mod_table.psv")
        self.mod_sections = read_psv(self.input_dir / "mod_sections.psv")
        self.mod_items = read_psv(self.input_dir / "mod_items.psv")
        self.mod_attribution = read_psv(self.input_dir / "mod_attribution.psv", required=False)
        self.mod_globals = read_psv(self.input_dir / "mod_globals.psv", required=False)
        self.doc_license_lines = read_psv(self.input_dir / "doc_license_lines.psv", required=False)
        self.product_manifests = read_psv(self.input_dir / "product_manifests.psv", required=False)
        self.product_manifest_by_name = {normalize_key(row.get("product", "")): row for row in self.product_manifests if row.get("product", "")}
        self.doc_enums = read_psv(self.input_dir / "doc_enums.psv", required=False)
        self.doc_content_lines = read_psv(self.input_dir / "doc_content_lines.psv")
        self.config = read_config(self.input_dir / "render_config.psv")

    # fn: prepare_output - Prepare output
    # . Purpose
    #   Prepare output for the documentation rendering workflow.
    # . Usage
    #   self.prepare_output()
    def prepare_output(self) -> None:
        clean_output = self.config.get("FLAG_CLEAN_OUTPUT", "1") == "1"

        if clean_output and self.output_dir.exists():
            shutil.rmtree(self.output_dir)

        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.asset_dir.mkdir(parents=True, exist_ok=True)
        self.page_dir.mkdir(parents=True, exist_ok=True)

    # fn: init_metadata - Initialize metadata
    # . Purpose
    #   Initialize metadata for the documentation rendering workflow.
    # . Usage
    #   self.init_metadata()
    def init_metadata(self) -> None:
        self.doc_title = self.config.get("VAL_DOCUMENT_TITLE", "SolidGroundUX Documentation")
        self.doc_subtitle = self.config.get("VAL_DOCUMENT_SUBTITLE", "")
        self.doc_version = self.config.get("VAL_DOCUMENT_VERSION", "")
        self.doc_product = self.config.get("VAL_DOCUMENT_PRODUCT", "")
        self.collection_name = self.config.get("VAL_COLLECTION_NAME", "") or self.doc_title or self.doc_product
        self.doc_render_date = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # ----------------------------------------------------------------------
    # Hierarchy construction
    # ----------------------------------------------------------------------

    # fn: product_has_appendices - Determine whether generated appendices belong to a product
    # . Purpose
    #   Generated framework appendices are SolidGroundUX product documentation and must not
    #   be synthesized for companion products in the same collection.
    # . Usage
    #   self.product_has_appendices(product_name)
    def product_has_appendices(self, product_name: str) -> bool:
        manifest = self.product_manifest_by_name.get(normalize_key(product_name), {})
        if manifest:
            return bool((manifest.get("appendices", "") or "").strip())
        return normalize_key(product_name) == normalize_key("SolidGroundUX")

    def product_appendix_keys(self, product_name: str) -> set[str]:
        manifest = self.product_manifest_by_name.get(normalize_key(product_name), {})
        spec = (manifest.get("appendices", "") or "").strip()
        if not spec and normalize_key(product_name) == normalize_key("SolidGroundUX"):
            return {item.key for item in APPENDIX_SPECS}
        return {normalize_key(item) for item in spec.split(",") if item.strip()}

    # fn: build_doc_hierarchy - Build doc hierarchy
    # . Purpose
    #   Build doc hierarchy for the documentation rendering workflow.
    # . Usage
    #   self.build_doc_hierarchy()
    def build_doc_hierarchy(self) -> None:
        self.nav = []

        section_rows = list(self.mod_sections)
        item_rows = list(self.mod_items)
        modules_by_product = self.modules_by_product()

        for product_index, product_name in enumerate(sorted(modules_by_product.keys(), key=str.casefold), start=1):
            product_node_id = f"product:{product_name}"
            product_docindex = str(product_index)
            product_modules = modules_by_product[product_name]

            self.nav.append(
                NavNode(
                    nodeid=product_node_id,
                    parentnodeid="root",
                    nodetype="product",
                    node_name=product_name,
                    node_title=product_name,
                    hierarchy_level=0,
                    docindex=product_docindex,
                    contentref="",
                )
            )

            product_specials, group_specials, normal_modules = self.split_special_comment_modules(
                product_name,
                product_modules,
            )

            sequence_index = 0

            for role in ("preface",):
                for module in product_specials.get(role, []):
                    sequence_index += 1
                    self.add_standalone_doc_node(
                        module=module,
                        parent_node_id=product_node_id,
                        hierarchy_level=1,
                        docindex=f"{product_docindex}.{sequence_index}",
                        fallback_name="Product Preface",
                        nodetype="preface",
                    )

            groups = sorted({module.get("group", "") or "Ungrouped" for module in normal_modules}, key=str.casefold)

            for group_name in groups:
                sequence_index += 1
                group_docindex = f"{product_docindex}.{sequence_index}"
                group_node_id = f"group:{product_name}:{group_name}"

                self.nav.append(
                    NavNode(
                        nodeid=group_node_id,
                        parentnodeid=product_node_id,
                        nodetype="group",
                        node_name=group_name,
                        node_title=group_name,
                        hierarchy_level=1,
                        docindex=group_docindex,
                        contentref="",
                    )
                )

                group_sequence_index = 0

                for module in group_specials.get(group_name, {}).get("preface", []):
                    group_sequence_index += 1
                    self.add_standalone_doc_node(
                        module=module,
                        parent_node_id=group_node_id,
                        hierarchy_level=2,
                        docindex=f"{group_docindex}.{group_sequence_index}",
                        fallback_name="Group Preface",
                        nodetype="preface",
                    )

                group_modules = [
                    module for module in normal_modules
                    if (module.get("group", "") or "Ungrouped") == group_name
                ]

                subgroup_names = sorted(
                    {module.get("subgroup", "") for module in group_modules if module.get("subgroup", "")},
                    key=str.casefold,
                )

                # Subgroups render before direct group modules so a focused collection such as
                # SDK / Documentation Generator stays together beneath the group overview.
                for subgroup_name in subgroup_names:
                    group_sequence_index += 1
                    subgroup_docindex = f"{group_docindex}.{group_sequence_index}"
                    subgroup_node_id = f"subgroup:{product_name}:{group_name}:{subgroup_name}"

                    self.nav.append(
                        NavNode(
                            nodeid=subgroup_node_id,
                            parentnodeid=group_node_id,
                            nodetype="subgroup",
                            node_name=subgroup_name,
                            node_title=subgroup_name,
                            hierarchy_level=2,
                            docindex=subgroup_docindex,
                            contentref="",
                        )
                    )

                    subgroup_sequence_index = 0
                    subgroup_modules = [
                        module for module in group_modules
                        if module.get("subgroup", "") == subgroup_name
                    ]

                    for module in subgroup_modules:
                        role = self.subgroup_comment_role(
                            normalize_key(Path(module.get("name", "")).stem),
                            normalize_key(subgroup_name),
                            module.get("purpose", ""),
                        )
                        if role == "preface":
                            subgroup_sequence_index += 1
                            self.add_standalone_doc_node(
                                module=module,
                                parent_node_id=subgroup_node_id,
                                hierarchy_level=3,
                                docindex=f"{subgroup_docindex}.{subgroup_sequence_index}",
                                fallback_name="Subgroup Preface",
                                nodetype="preface",
                            )

                    for module in sorted(
                        subgroup_modules,
                        key=lambda module: (
                            (module.get("name", "") or module.get("title", "")).casefold(),
                            module.get("title", "").casefold(),
                        ),
                    ):
                        role = self.subgroup_comment_role(
                            normalize_key(Path(module.get("name", "")).stem),
                            normalize_key(subgroup_name),
                            module.get("purpose", ""),
                        )
                        if role:
                            continue
                        subgroup_sequence_index += 1
                        self.add_module_node(
                            module=module,
                            parent_node_id=subgroup_node_id,
                            hierarchy_level=3,
                            module_docindex=f"{subgroup_docindex}.{subgroup_sequence_index}",
                            section_rows=section_rows,
                            item_rows=item_rows,
                        )

                    for module in subgroup_modules:
                        role = self.subgroup_comment_role(
                            normalize_key(Path(module.get("name", "")).stem),
                            normalize_key(subgroup_name),
                            module.get("purpose", ""),
                        )
                        if role == "epilogue":
                            subgroup_sequence_index += 1
                            self.add_standalone_doc_node(
                                module=module,
                                parent_node_id=subgroup_node_id,
                                hierarchy_level=3,
                                docindex=f"{subgroup_docindex}.{subgroup_sequence_index}",
                                fallback_name="Subgroup Epilogue",
                                nodetype="epilogue",
                            )

                direct_modules = sorted(
                    [module for module in group_modules if not module.get("subgroup", "")],
                    key=lambda module: (
                        (module.get("name", "") or module.get("title", "")).casefold(),
                        module.get("title", "").casefold(),
                    ),
                )

                for module in direct_modules:
                    group_sequence_index += 1
                    self.add_module_node(
                        module=module,
                        parent_node_id=group_node_id,
                        hierarchy_level=2,
                        module_docindex=f"{group_docindex}.{group_sequence_index}",
                        section_rows=section_rows,
                        item_rows=item_rows,
                    )

                for module in group_specials.get(group_name, {}).get("epilogue", []):
                    group_sequence_index += 1
                    self.add_standalone_doc_node(
                        module=module,
                        parent_node_id=group_node_id,
                        hierarchy_level=2,
                        docindex=f"{group_docindex}.{group_sequence_index}",
                        fallback_name="Group Epilogue",
                        nodetype="epilogue",
                    )

            for role in ("epilogue",):
                for module in product_specials.get(role, []):
                    sequence_index += 1
                    self.add_standalone_doc_node(
                        module=module,
                        parent_node_id=product_node_id,
                        hierarchy_level=1,
                        docindex=f"{product_docindex}.{sequence_index}",
                        fallback_name="Product Epilogue",
                        nodetype="epilogue",
                    )

            if self.product_has_appendices(product_name):
                sequence_index += 1
                appendices_docindex = f"{product_docindex}.{sequence_index}"
                appendices_node_id = f"appendices:{product_name}"

                self.nav.append(
                    NavNode(
                        nodeid=appendices_node_id,
                        parentnodeid=product_node_id,
                        nodetype="appendices",
                        node_name="Appendices",
                        node_title="Appendices",
                        hierarchy_level=1,
                        docindex=appendices_docindex,
                        contentref="",
                    )
                )

                product_appendix_keys = self.product_appendix_keys(product_name)
                enabled_appendices = [a for a in APPENDIX_SPECS if normalize_key(a.key) in product_appendix_keys]
                for appendix_index, appendix in enumerate(enabled_appendices, start=1):
                    appendix_label = f"Appendix {appendix.letter}: {appendix.title}"
                    self.nav.append(
                        NavNode(
                            nodeid=f"appendix:{product_name}:{appendix.key}",
                            parentnodeid=appendices_node_id,
                            nodetype="appendix",
                            node_name=appendix_label,
                            node_title=appendix_label,
                            hierarchy_level=2,
                            docindex=f"{appendices_docindex}.{appendix_index}",
                            contentref=appendix.ref_factory(product_name),
                        )
                    )

    # fn: modules_by_product - Modules by product
    # . Purpose
    #   Modules by product for the documentation rendering workflow.
    # . Usage
    #   self.modules_by_product()
    def modules_by_product(self) -> Dict[str, List[Row]]:
        result: Dict[str, List[Row]] = defaultdict(list)

        for module in self.mod_table:
            product_name = module.get("product", "") or self.doc_product or "Documentation"
            result[product_name].append(module)

        if not result:
            result[self.doc_product or "Documentation"] = []

        return result

    # fn: split_special_comment_modules - Split special comment modules
    # . Purpose
    #   Split special comment modules for the documentation rendering workflow.
    #
    # . Arguments
    #   product_name  Value consumed by this function; see the typed Python signature for its contract.
    #   modules  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.split_special_comment_modules(<product_name>, <modules>)
    def split_special_comment_modules(
        self,
        product_name: str,
        modules: List[Row],
    ) -> tuple[Dict[str, List[Row]], Dict[str, Dict[str, List[Row]]], List[Row]]:
        product_specials: Dict[str, List[Row]] = {"preface": [], "epilogue": []}
        group_specials: Dict[str, Dict[str, List[Row]]] = defaultdict(lambda: {"preface": [], "epilogue": []})
        normal_modules: List[Row] = []

        product_key = normalize_key(product_name)

        for module in modules:
            module_name = module.get("name", "")
            module_key = normalize_key(Path(module_name).stem)
            group_name = module.get("group", "") or "Ungrouped"
            group_key = normalize_key(group_name)

            purpose_key = normalize_key(module.get("purpose", ""))
            # A product-level *_preface file belongs directly beneath its product.
            # Matching Group to product avoids stealing ordinary group/subgroup prefaces.
            if module_key.endswith("_preface") and group_key == product_key:
                product_specials["preface"].append(module)
                continue
            if purpose_key in {"product_preface", "documentation_preface"}:
                product_specials["preface"].append(module)
                continue
            if purpose_key in {"product_epilogue", "documentation_epilogue"}:
                product_specials["epilogue"].append(module)
                continue

            role = self.product_comment_role(module_key, product_key)
            if role:
                product_specials[role].append(module)
                continue
            role = ""
            if purpose_key == "group_preface" and not module.get("subgroup", ""):
                role = "preface"
            elif purpose_key == "group_epilogue" and not module.get("subgroup", ""):
                role = "epilogue"
            else:
                role = self.group_comment_role(module_key, group_key)
            if role:
                group_specials[group_name][role].append(module)
                continue

            normal_modules.append(module)

        for rows in product_specials.values():
            rows.sort(key=lambda row: row.get("name", "").casefold())

        for group_rows in group_specials.values():
            for rows in group_rows.values():
                rows.sort(key=lambda row: row.get("name", "").casefold())

        return product_specials, group_specials, normal_modules

    # fn: product_comment_role - Product comment role
    # . Purpose
    #   Product comment role for the documentation rendering workflow.
    #
    # . Arguments
    #   module_key  Value consumed by this function; see the typed Python signature for its contract.
    #   product_key  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.product_comment_role(<module_key>, <product_key>)
    def product_comment_role(self, module_key: str, product_key: str) -> str:
        pre_names = {
            f"{product_key}_pref_comment",
            f"{product_key}_pre_comment",
            f"{product_key}_preface",
            "product_pref_comment",
            "product_pre_comment",
            "product_preface",
            "doc_product_preface",
        }
        epilogue_names = {
            f"{product_key}_epilogue",
            "product_epilogue",
            "doc_product_epilogue",
        }

        if module_key in pre_names:
            return "preface"
        if module_key in epilogue_names:
            return "epilogue"
        return ""

    # fn: group_comment_role - Group comment role
    # . Purpose
    #   Group comment role for the documentation rendering workflow.
    #
    # . Arguments
    #   module_key  Value consumed by this function; see the typed Python signature for its contract.
    #   group_key  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.group_comment_role(<module_key>, <group_key>)
    def group_comment_role(self, module_key: str, group_key: str) -> str:
        pre_names = {
            f"{group_key}_comment",
            f"{group_key}_pref_comment",
            f"{group_key}_pre_comment",
            f"{group_key}_preface",
            f"group_{group_key}_comment",
            f"group_{group_key}_pref_comment",
            f"group_{group_key}_preface",
        }
        epilogue_names = {
            f"{group_key}_epilogue",
            f"group_{group_key}_epilogue",
        }

        if module_key in pre_names:
            return "preface"
        if module_key in epilogue_names:
            return "epilogue"
        return ""

    # fn: subgroup_comment_role - Subgroup comment role
    # . Purpose
    #   Subgroup comment role for the documentation rendering workflow.
    #
    # . Arguments
    #   module_key  Value consumed by this function; see the typed Python signature for its contract.
    #   subgroup_key  Value consumed by this function; see the typed Python signature for its contract.
    #   purpose  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.subgroup_comment_role(<module_key>, <subgroup_key>, <purpose>)
    def subgroup_comment_role(self, module_key: str, subgroup_key: str, purpose: str = "") -> str:
        purpose_key = normalize_key(purpose)
        if purpose_key == "subgroup_preface":
            return "preface"
        if purpose_key == "subgroup_epilogue":
            return "epilogue"

        pre_names = {
            f"{subgroup_key}_comment",
            f"{subgroup_key}_pref_comment",
            f"{subgroup_key}_pre_comment",
            f"{subgroup_key}_preface",
            f"subgroup_{subgroup_key}_preface",
        }
        epilogue_names = {
            f"{subgroup_key}_epilogue",
            f"subgroup_{subgroup_key}_epilogue",
        }
        if module_key in pre_names:
            return "preface"
        if module_key in epilogue_names:
            return "epilogue"
        return ""

    # fn: add_standalone_doc_node - Add standalone doc node
    # . Purpose
    #   Add standalone doc node for the documentation rendering workflow.
    #
    # . Arguments
    #   module  Value consumed by this function; see the typed Python signature for its contract.
    #   parent_node_id  Value consumed by this function; see the typed Python signature for its contract.
    #   hierarchy_level  Value consumed by this function; see the typed Python signature for its contract.
    #   docindex  Value consumed by this function; see the typed Python signature for its contract.
    #   fallback_name  Value consumed by this function; see the typed Python signature for its contract.
    #   nodetype  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.add_standalone_doc_node(<module>, <parent_node_id>, <hierarchy_level>, <docindex>, <fallback_name>, <nodetype>)
    def add_standalone_doc_node(
        self,
        module: Row,
        parent_node_id: str,
        hierarchy_level: int,
        docindex: str,
        fallback_name: str,
        nodetype: str = "documentation",
    ) -> None:
        module_name = module.get("name", "")
        module_title = module.get("title", "") or fallback_name or module_name
        module_ref = content_ref(module_name)

        self.nav.append(
            NavNode(
                nodeid=f"doc:{module_name}:{docindex}",
                parentnodeid=parent_node_id,
                nodetype=nodetype,
                node_name=module_title,
                node_title=module_title,
                hierarchy_level=hierarchy_level,
                docindex=docindex,
                contentref=module_ref,
            )
        )

    # fn: is_template_module - Determine whether template module
    # . Purpose
    #   Determine whether template module for the documentation rendering workflow.
    #
    # . Arguments
    #   module  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.is_template_module(<module>)
    def is_template_module(self, module: Row) -> bool:
        source_file = Path(module.get("file", "") or "").name
        return "template" in source_file.casefold()

    # fn: should_render_item - Determine whether render item
    # . Purpose
    #   Determine whether render item for the documentation rendering workflow.
    #
    # . Arguments
    #   module  Value consumed by this function; see the typed Python signature for its contract.
    #   item  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.should_render_item(<module>, <item>)
    def should_render_item(self, module: Row, item: Row) -> bool:
        # ':' items are always documented. '$' items describe template scaffolding
        # and are documented only when the source script itself is a template.
        if item.get("itemrole", "") != "template":
            return True

        return self.is_template_module(module)

    # fn: section_key - Section key
    # . Purpose
    #   Section key for the documentation rendering workflow.
    #
    # . Arguments
    #   section  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.section_key(<section>)
    def section_key(self, section: Row) -> tuple[str, str, str]:
        return (
            section.get("section", ""),
            section.get("parent", ""),
            section.get("grandparent", ""),
        )

    # fn: section_level - Section level
    # . Purpose
    #   Section level for the documentation rendering workflow.
    #
    # . Arguments
    #   section  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.section_level(<section>)
    def section_level(self, section: Row) -> int:
        try:
            return int(section.get("level", "1") or "1")
        except ValueError:
            return 1

    # fn: is_direct_child_section - Determine whether direct child section
    # . Purpose
    #   Determine whether direct child section for the documentation rendering workflow.
    #
    # . Arguments
    #   parent_section  Value consumed by this function; see the typed Python signature for its contract.
    #   child_section  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.is_direct_child_section(<parent_section>, <child_section>)
    def is_direct_child_section(self, parent_section: Row, child_section: Row) -> bool:
        parent_name = parent_section.get("section", "")
        parent_parent = parent_section.get("parent", "")
        parent_level = self.section_level(parent_section)
        child_parent = child_section.get("parent", "")
        child_grandparent = child_section.get("grandparent", "")

        if parent_level == 1:
            return child_parent == parent_name and child_grandparent == ""

        if parent_level == 2:
            return child_parent == parent_name and child_grandparent == parent_parent

        return False

    # fn: section_has_body_content - Section has body content
    # . Purpose
    #   Section has body content for the documentation rendering workflow.
    #
    # . Arguments
    #   module_name  Value consumed by this function; see the typed Python signature for its contract.
    #   section  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.section_has_body_content(<module_name>, <section>)
    def section_has_body_content(self, module_name: str, section: Row) -> bool:
        section_name = section.get("section", "")
        parent_section = section.get("parent", "")
        grandparent_section = section.get("grandparent", "")
        ref = content_ref(module_name, grandparent_section, parent_section, section_name, "")

        for row in self.content_by_ref.get(ref, []):
            if row.get("suppress", "0") == "1":
                continue

            content_type = row.get("contenttype", "")
            content = (row.get("content", "") or "").strip()

            if not content:
                continue

            if content_type.endswith("header"):
                continue

            return True

        return False

    # fn: section_has_visible_direct_items - Section has visible direct items
    # . Purpose
    #   Section has visible direct items for the documentation rendering workflow.
    #
    # . Arguments
    #   module  Value consumed by this function; see the typed Python signature for its contract.
    #   section  Value consumed by this function; see the typed Python signature for its contract.
    #   module_items  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.section_has_visible_direct_items(<module>, <section>, <module_items>)
    def section_has_visible_direct_items(self, module: Row, section: Row, module_items: List[Row]) -> bool:
        section_name = section.get("section", "")
        parent_section = section.get("parent", "")
        grandparent_section = section.get("grandparent", "")

        for item in module_items:
            if item.get("section", "") != section_name:
                continue
            if item.get("parentsection", "") != parent_section:
                continue
            if item.get("grandparentsection", "") != grandparent_section:
                continue
            if self.should_render_item(module, item):
                return True

        return False

    # fn: should_render_section - Determine whether render section
    # . Purpose
    #   Determine whether render section for the documentation rendering workflow.
    #
    # . Arguments
    #   module  Value consumed by this function; see the typed Python signature for its contract.
    #   section  Value consumed by this function; see the typed Python signature for its contract.
    #   module_sections  Value consumed by this function; see the typed Python signature for its contract.
    #   module_items  Value consumed by this function; see the typed Python signature for its contract.
    #   cache  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.should_render_section(<module>, <section>, <module_sections>, <module_items>, <cache>)
    def should_render_section(
        self,
        module: Row,
        section: Row,
        module_sections: List[Row],
        module_items: List[Row],
        cache: Dict[tuple[str, str, str], bool],
    ) -> bool:
        key = self.section_key(section)
        if key in cache:
            return cache[key]

        module_name = module.get("name", "")

        if self.section_has_body_content(module_name, section):
            cache[key] = True
            return True

        if self.section_has_visible_direct_items(module, section, module_items):
            cache[key] = True
            return True

        for child_section in module_sections:
            if child_section is section:
                continue
            if not self.is_direct_child_section(section, child_section):
                continue
            if self.should_render_section(module, child_section, module_sections, module_items, cache):
                cache[key] = True
                return True

        cache[key] = False
        return False

    # fn: add_module_node - Add module node
    # . Purpose
    #   Add module node for the documentation rendering workflow.
    #
    # . Arguments
    #   module  Value consumed by this function; see the typed Python signature for its contract.
    #   parent_node_id  Value consumed by this function; see the typed Python signature for its contract.
    #   hierarchy_level  Value consumed by this function; see the typed Python signature for its contract.
    #   module_docindex  Value consumed by this function; see the typed Python signature for its contract.
    #   section_rows  Value consumed by this function; see the typed Python signature for its contract.
    #   item_rows  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.add_module_node(<module>, <parent_node_id>, <hierarchy_level>, <module_docindex>, <section_rows>, <item_rows>)
    def add_module_node(
        self,
        module: Row,
        parent_node_id: str,
        hierarchy_level: int,
        module_docindex: str,
        section_rows: List[Row],
        item_rows: List[Row],
    ) -> None:
        module_name = module.get("name", "")
        module_title = module.get("title", "") or module_name
        module_node_id = f"mod:{module_name}"
        module_ref = content_ref(module_name)

        self.nav.append(
            NavNode(
                nodeid=module_node_id,
                parentnodeid=parent_node_id,
                nodetype="module",
                node_name=module_name,
                node_title=module_title,
                hierarchy_level=hierarchy_level,
                docindex=module_docindex,
                contentref=module_ref,
            )
        )

        module_sections = [section for section in section_rows if section.get("modulename", "") == module_name]
        module_items = [item for item in item_rows if item.get("modulename", "") == module_name]
        visible_section_cache: Dict[tuple[str, str, str], bool] = {}

        l1_index = 0
        l2_index = 0
        l3_index = 0
        section_node_ids: Dict[tuple[str, str, str], str] = {}
        section_docindex_by_id: Dict[str, str] = {}

        for section in module_sections:
            if not self.should_render_section(module, section, module_sections, module_items, visible_section_cache):
                continue

            section_name = section.get("section", "")
            section_title = section.get("title", "") or section_name
            parent_section = section.get("parent", "")
            grandparent_section = section.get("grandparent", "")
            level_text = section.get("level", "1")

            try:
                section_level = int(level_text)
            except ValueError:
                section_level = 1

            if section_level < 1 or section_level > 3:
                continue

            if section_level == 1:
                l1_index += 1
                l2_index = 0
                l3_index = 0
                parent_node_id = module_node_id
                docindex = f"{module_docindex}.{l1_index}"
                node_id = f"sec:{module_name}:{section_name}"

            elif section_level == 2:
                l2_index += 1
                l3_index = 0
                parent_node_id = section_node_ids.get((parent_section, "", ""), module_node_id)
                parent_docindex = section_docindex_by_id.get(parent_node_id, module_docindex)
                docindex = f"{parent_docindex}.{l2_index}"
                node_id = f"sec:{module_name}:{parent_section}:{section_name}"

            else:
                l3_index += 1
                parent_node_id = section_node_ids.get((parent_section, grandparent_section, ""), module_node_id)
                parent_docindex = section_docindex_by_id.get(parent_node_id, module_docindex)
                docindex = f"{parent_docindex}.{l3_index}"
                node_id = f"sec:{module_name}:{grandparent_section}:{parent_section}:{section_name}"

            section_node_ids[(section_name, parent_section, grandparent_section)] = node_id
            section_docindex_by_id[node_id] = docindex

            section_ref = content_ref(module_name, grandparent_section, parent_section, section_name, "")
            nav_level = hierarchy_level + section_level

            self.nav.append(
                NavNode(
                    nodeid=node_id,
                    parentnodeid=parent_node_id,
                    nodetype="section",
                    node_name=section_name,
                    node_title=section_title,
                    hierarchy_level=nav_level,
                    docindex=docindex,
                    contentref=section_ref,
                )
            )

            section_items = [
                item for item in module_items
                if item.get("section", "") == section_name
                and item.get("parentsection", "") == parent_section
                and item.get("grandparentsection", "") == grandparent_section
            ]

            rendered_item_index = 0
            for item in section_items:
                if not self.should_render_item(module, item):
                    continue

                rendered_item_index += 1
                item_name = item.get("name", "")
                item_title = item.get("title", "") or item_name
                item_type = item.get("type", "")
                item_typecode = item.get("typecode", "item")
                item_visibility = item.get("itemvisibility", "")
                item_role = item.get("itemrole", "")

                item_ref = content_ref(module_name, grandparent_section, parent_section, section_name, item_name)
                item_node_id = f"{item_typecode}:{module_name}:{grandparent_section}:{parent_section}:{section_name}:{item_name}"
                item_docindex = f"{docindex}.{rendered_item_index}"

                self.nav.append(
                    NavNode(
                        nodeid=item_node_id,
                        parentnodeid=node_id,
                        nodetype=item_type,
                        node_name=item_name,
                        node_title=item_title,
                        hierarchy_level=nav_level + 1,
                        docindex=item_docindex,
                        contentref=item_ref,
                        isinternal=item_visibility == "internal",
                        istemplate=item_role == "template",
                    )
                )

    # fn: build_content_index - Build content index
    # . Purpose
    #   Build content index for the documentation rendering workflow.
    # . Usage
    #   self.build_content_index()
    def build_content_index(self) -> None:
        rows = sorted(
            self.doc_content_lines,
            key=lambda row: (
                row.get("file", "").casefold(),
                int(row.get("source_linenr", "0") or "0"),
                int(row.get("doc_linenr", "0") or "0"),
            ),
        )

        for row in rows:
            ref = row.get("contentref", "")
            self.content_by_ref[ref].append(row)

    # ----------------------------------------------------------------------
    # Rendering
    # ----------------------------------------------------------------------

    # fn: render_assets - Render assets
    # . Purpose
    #   Render assets for the documentation rendering workflow.
    # . Usage
    #   self.render_assets()
    def render_assets(self) -> None:
        self.render_layout_css()
        self.ensure_theme_css()
        self.copy_documentation_images()
        self.copy_branding_assets()

    # fn: copy_documentation_images - Copy shared documentation images
    # . Purpose
    #   Copy the framework-wide documentation image collection into the generated site.
    # . Usage
    #   self.copy_documentation_images()
    def copy_documentation_images(self) -> None:
        """Merge documentation images from the selected products' canonical asset directories."""
        source_dirs = [source for source in self.asset_source_dirs if source.is_dir()]
        if not source_dirs:
            return

        image_target_dir = self.asset_dir / "images"
        if image_target_dir.exists():
            shutil.rmtree(image_target_dir)
        image_target_dir.mkdir(parents=True, exist_ok=True)

        copied: Dict[str, Path] = {}
        for source_dir in source_dirs:
            for source in source_dir.iterdir():
                target = image_target_dir / source.name
                key = source.name.casefold()
                if key in copied:
                    print(
                        f"WARNING: duplicate documentation asset '{source.name}' in '{source_dir}'; "
                        f"already supplied by '{copied[key].parent}'. Skipping duplicate.",
                        file=sys.stderr,
                    )
                    continue
                if source.is_dir():
                    shutil.copytree(source, target)
                elif source.is_file():
                    shutil.copy2(source, target)
                else:
                    continue
                copied[key] = source

    # fn: copy_branding_assets - Copy branding assets
    # . Purpose
    #   Copy optional documentation branding images into the generated site.
    # . Usage
    #   self.copy_branding_assets()
    def copy_branding_assets(self) -> None:
        """Copy optional documentation branding images into the generated site."""
        branding_dir = self.asset_dir / "branding"
        branding_dir.mkdir(parents=True, exist_ok=True)

        candidates = {
            DOC_HEADER_LOGO: tuple(
                [source / DOC_HEADER_LOGO for source in self.asset_source_dirs]
                + [self.input_dir / DOC_HEADER_LOGO, self.input_dir / "assets" / DOC_HEADER_LOGO]
            ),
            DOC_INDEX_LOGO: tuple(
                [source / DOC_INDEX_LOGO for source in self.asset_source_dirs]
                + [self.input_dir / DOC_INDEX_LOGO, self.input_dir / "assets" / DOC_INDEX_LOGO]
            ),
        }

        for target_name, source_candidates in candidates.items():
            for source_file in source_candidates:
                if source_file.is_file():
                    shutil.copy2(source_file, branding_dir / target_name)
                    break

    # fn: branding_asset_exists - Branding asset exists
    # . Purpose
    #   Branding asset exists for the documentation rendering workflow.
    #
    # . Arguments
    #   name  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.branding_asset_exists(<name>)
    def branding_asset_exists(self, name: str) -> bool:
        return (self.asset_dir / "branding" / name).is_file()

    # fn: render_page_branding - Render page branding
    # . Purpose
    #   Render the compact SolidGroundUX identity used on documentation pages.
    # . Usage
    #   self.render_page_branding()
    def render_page_branding(self) -> str:
        """Render the compact SolidGroundUX identity used on documentation pages."""
        if not self.branding_asset_exists(DOC_HEADER_LOGO):
            return ""

        return (
            '<div class="doc-page-branding">'
            '<span class="doc-page-branding-title">SolidGroundUX Documentation</span>'
            f'<img src="../assets/branding/{esc(DOC_HEADER_LOGO)}" alt="SolidGroundUX">'
            '</div>'
        )

    # fn: render_nav_branding - Render nav branding
    # . Purpose
    #   Render the Testadura publisher identity above the navigation index.
    # . Usage
    #   self.render_nav_branding()
    def render_nav_branding(self) -> str:
        """Render the Testadura publisher identity above the navigation index."""
        if not self.branding_asset_exists(DOC_INDEX_LOGO):
            return ""

        return (
            '<div class="doc-nav-branding">'
            f'<img src="assets/branding/{esc(DOC_INDEX_LOGO)}" alt="Documentation publisher">'
            '</div>'
        )

    # ----------------------------------------------------------------------
    # Theme specimen rendering
    # ----------------------------------------------------------------------

    # fn: is_theme_module - Determine whether theme module
    # . Purpose
    #   Return True for numbered SolidGroundUX semantic style modules.
    #
    # . Arguments
    #   module  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.is_theme_module(<module>)
    def is_theme_module(self, module: Row) -> bool:
        """Return True for numbered SolidGroundUX semantic style modules."""
        source_name = Path(module.get("file", "") or module.get("name", "")).name
        subgroup = (module.get("subgroup", "") or "").casefold()

        return bool(
            re.match(r"^\d+-style-[a-z0-9_-]+\.sh$", source_name, flags=re.IGNORECASE)
            and subgroup == "styles"
        )

    # fn: parse_shell_assignments - Parse shell assignments
    # . Purpose
    #   Read simple top-level shell assignments without executing the file.
    #
    # . Arguments
    #   path  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.parse_shell_assignments(<path>)
    def parse_shell_assignments(self, path: Path) -> Dict[str, str]:
        """Read simple top-level shell assignments without executing the file."""
        assignments: Dict[str, str] = {}

        if not path.is_file():
            return assignments

        assignment_re = re.compile(r"^\s*([A-Z][A-Z0-9_]*)=(.*)$")

        for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            match = assignment_re.match(raw_line)
            if not match:
                continue

            name = match.group(1)
            value = self.strip_shell_inline_comment(match.group(2).strip())
            assignments[name] = value.strip()

        return assignments

    # fn: strip_shell_inline_comment - Strip shell inline comment
    # . Purpose
    #   Strip an unquoted shell comment from an assignment value.
    #
    # . Arguments
    #   value  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.strip_shell_inline_comment(<value>)
    def strip_shell_inline_comment(self, value: str) -> str:
        """Strip an unquoted shell comment from an assignment value."""
        single = False
        double = False
        escaped = False

        for index, char in enumerate(value):
            if escaped:
                escaped = False
                continue

            if char == "\\":
                escaped = True
                continue

            if char == "'" and not double:
                single = not single
                continue

            if char == '"' and not single:
                double = not double
                continue

            if char == "#" and not single and not double:
                if index == 0 or value[index - 1].isspace():
                    return value[:index].rstrip()

        return value

    # fn: xterm_256_rgb - Xterm 256 rgb
    # . Purpose
    #   Convert an xterm 256-color index to an RGB tuple.
    #
    # . Arguments
    #   index  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.xterm_256_rgb(<index>)
    def xterm_256_rgb(self, index: int) -> Tuple[int, int, int]:
        """Convert an xterm 256-color index to an RGB tuple."""
        basic = (
            (0, 0, 0), (128, 0, 0), (0, 128, 0), (128, 128, 0),
            (0, 0, 128), (128, 0, 128), (0, 128, 128), (192, 192, 192),
            (128, 128, 128), (255, 0, 0), (0, 255, 0), (255, 255, 0),
            (0, 0, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255),
        )

        if 0 <= index < 16:
            return basic[index]

        if 16 <= index <= 231:
            value = index - 16
            red = value // 36
            green = (value % 36) // 6
            blue = value % 6
            levels = (0, 95, 135, 175, 215, 255)
            return levels[red], levels[green], levels[blue]

        if 232 <= index <= 255:
            gray = 8 + ((index - 232) * 10)
            return gray, gray, gray

        return 192, 192, 192

    # fn: parse_sgr_color - Parse sgr color
    # . Purpose
    #   Extract a CSS foreground color from a literal SGR assignment.
    #
    # . Arguments
    #   value  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.parse_sgr_color(<value>)
    def parse_sgr_color(self, value: str) -> str:
        """Extract a CSS foreground color from a literal SGR assignment."""
        rgb_match = re.search(r"38;2;(\d+);(\d+);(\d+)m", value)
        if rgb_match:
            red, green, blue = (int(part) for part in rgb_match.groups())
            return f"rgb({red}, {green}, {blue})"

        indexed_match = re.search(r"38;5;(\d+)m", value)
        if indexed_match:
            red, green, blue = self.xterm_256_rgb(int(indexed_match.group(1)))
            return f"rgb({red}, {green}, {blue})"

        return ""

    # fn: resolve_theme_style - Resolve theme style
    # . Purpose
    #   Resolve a semantic style variable to CSS without sourcing shell code.
    #
    # . Arguments
    #   variable_name  Value consumed by this function; see the typed Python signature for its contract.
    #   assignments  Value consumed by this function; see the typed Python signature for its contract.
    #   palette  Value consumed by this function; see the typed Python signature for its contract.
    #   seen  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.resolve_theme_style(<variable_name>, <assignments>, <palette>, <seen>)
    def resolve_theme_style(
        self,
        variable_name: str,
        assignments: Dict[str, str],
        palette: Dict[str, str],
        seen: set[str] | None = None,
    ) -> Dict[str, str]:
        """Resolve a semantic style variable to CSS without sourcing shell code."""
        if seen is None:
            seen = set()

        if variable_name in seen:
            return {}

        seen.add(variable_name)
        raw = assignments.get(variable_name, palette.get(variable_name, "")).strip()
        if not raw:
            return {}

        # Direct variable alias: $NAME or ${NAME}
        alias_match = re.fullmatch(r"\$(?:\{)?([A-Z][A-Z0-9_]*)(?:\})?", raw)
        if alias_match:
            return self.resolve_theme_style(alias_match.group(1), assignments, palette, seen)

        # sgnd_sgr "$BASE" "" "$FX_*"
        sgr_match = re.search(
            r'sgnd_sgr\s+"\$(?:\{)?([A-Z][A-Z0-9_]*)(?:\})?"\s+""\s+"\$(?:\{)?([A-Z][A-Z0-9_]*)(?:\})?"',
            raw,
        )
        if sgr_match:
            style = self.resolve_theme_style(sgr_match.group(1), assignments, palette, seen)
            effect_name = sgr_match.group(2)
            self.apply_theme_effect(style, effect_name, assignments, palette)
            return style

        color = self.parse_sgr_color(raw)
        if color:
            return {"color": color}

        return {}

    # fn: apply_theme_effect - Apply theme effect
    # . Purpose
    #   Map the SolidGroundUX SGR effect constants used by themes to CSS.
    #
    # . Arguments
    #   style  Value consumed by this function; see the typed Python signature for its contract.
    #   effect_name  Value consumed by this function; see the typed Python signature for its contract.
    #   assignments  Value consumed by this function; see the typed Python signature for its contract.
    #   palette  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.apply_theme_effect(<style>, <effect_name>, <assignments>, <palette>)
    def apply_theme_effect(
        self,
        style: Dict[str, str],
        effect_name: str,
        assignments: Dict[str, str],
        palette: Dict[str, str],
    ) -> None:
        """Map the SolidGroundUX SGR effect constants used by themes to CSS."""
        effect_value = assignments.get(effect_name, palette.get(effect_name, "")).strip()

        if effect_name == "FX_BOLD" or effect_value == "1":
            style["font-weight"] = "700"
        elif effect_name == "FX_FAINT" or effect_value == "2":
            style["opacity"] = "0.62"
        elif effect_name == "FX_ITALIC" or effect_value == "3":
            style["font-style"] = "italic"
        elif effect_name == "FX_UNDERLINE" or effect_value == "4":
            style["text-decoration"] = "underline"
        elif effect_name == "FX_STRIKE" or effect_value == "9":
            style["text-decoration"] = "line-through"

    # fn: css_style_attr - Css style attr
    # . Purpose
    #   Css style attr for the documentation rendering workflow.
    #
    # . Arguments
    #   style  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.css_style_attr(<style>)
    def css_style_attr(self, style: Dict[str, str]) -> str:
        if not style:
            return ""
        return "; ".join(f"{name}: {value}" for name, value in style.items())

    # fn: theme_sample - Theme sample
    # . Purpose
    #   Theme sample for the documentation rendering workflow.
    #
    # . Arguments
    #   label  Value consumed by this function; see the typed Python signature for its contract.
    #   variable_name  Value consumed by this function; see the typed Python signature for its contract.
    #   assignments  Value consumed by this function; see the typed Python signature for its contract.
    #   palette  Value consumed by this function; see the typed Python signature for its contract.
    #   sample_text  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.theme_sample(<label>, <variable_name>, <assignments>, <palette>, <sample_text>)
    def theme_sample(
        self,
        label: str,
        variable_name: str,
        assignments: Dict[str, str],
        palette: Dict[str, str],
        sample_text: str = "",
    ) -> str:
        style = self.resolve_theme_style(variable_name, assignments, palette)
        style_attr = self.css_style_attr(style)
        text = sample_text or label

        return (
            '<div class="theme-sample-row">'
            f'<code>{esc(variable_name)}</code>'
            f'<span class="theme-sample-label">{esc(label)}</span>'
            f'<span class="theme-sample-value" style="{esc(style_attr)}">{esc(text)}</span>'
            '</div>'
        )

    # fn: theme_pair - Theme pair
    # . Purpose
    #   Theme pair for the documentation rendering workflow.
    #
    # . Arguments
    #   left_label  Value consumed by this function; see the typed Python signature for its contract.
    #   left_variable  Value consumed by this function; see the typed Python signature for its contract.
    #   right_label  Value consumed by this function; see the typed Python signature for its contract.
    #   right_variable  Value consumed by this function; see the typed Python signature for its contract.
    #   assignments  Value consumed by this function; see the typed Python signature for its contract.
    #   palette  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.theme_pair(<left_label>, <left_variable>, <right_label>, <right_variable>, <assignments>, <palette>)
    def theme_pair(
        self,
        left_label: str,
        left_variable: str,
        right_label: str,
        right_variable: str,
        assignments: Dict[str, str],
        palette: Dict[str, str],
    ) -> str:
        left_style = self.css_style_attr(self.resolve_theme_style(left_variable, assignments, palette))
        right_style = self.css_style_attr(self.resolve_theme_style(right_variable, assignments, palette))

        return (
            '<div class="theme-pair">'
            f'<span style="{esc(left_style)}">{esc(left_label)}</span>'
            '<span class="theme-pair-separator">/</span>'
            f'<span style="{esc(right_style)}">{esc(right_label)}</span>'
            '</div>'
        )

    # fn: render_theme_specimen - Render theme specimen
    # . Purpose
    #   Render a live HTML specimen derived from a SolidGroundUX style file.
    #
    # . Arguments
    #   module  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_theme_specimen(<module>)
    def render_theme_specimen(self, module: Row) -> str:
        """Render a live HTML specimen derived from a SolidGroundUX style file."""
        source_file = Path(module.get("file", "") or "")
        if not source_file.is_file():
            return ""

        palette_file = source_file.parent / "default-ui-palette.sh"
        assignments = self.parse_shell_assignments(source_file)
        palette = self.parse_shell_assignments(palette_file)

        if not assignments or not palette:
            return ""

        source_name = source_file.name
        theme_key = re.sub(r"^\d+-style-", "", source_file.stem, flags=re.IGNORECASE)
        theme_name = theme_key.replace("-", " ").replace("_", " ").title()

        title_style = self.css_style_attr(
            self.resolve_theme_style("SGND_TITLE_TEXTCLR", assignments, palette)
        )
        subtitle_style = self.css_style_attr(
            self.resolve_theme_style("SGND_TITLE_SUBTEXTCLR", assignments, palette)
        )
        border_style = self.css_style_attr(
            self.resolve_theme_style("SGND_TITLE_BORDERCLR", assignments, palette)
        )
        section_style = self.css_style_attr(
            self.resolve_theme_style("SGND_SECTION_TEXTCLR", assignments, palette)
        )
        section_border_style = self.css_style_attr(
            self.resolve_theme_style("SGND_SECTION_BORDERCLR", assignments, palette)
        )
        progress_bar_style = self.css_style_attr(
            self.resolve_theme_style("PROG_BAR_CLR", assignments, palette)
        )
        progress_ind_style = self.css_style_attr(
            self.resolve_theme_style("PROG_IND_CLR", assignments, palette)
        )
        progress_text_style = self.css_style_attr(
            self.resolve_theme_style("PROG_TEXT_CLR", assignments, palette)
        )

        message_rows = (
            ("START", "MSG_CLR_STRT", "START"),
            ("INFO", "MSG_CLR_INFO", "Informational message"),
            ("WARNING", "MSG_CLR_WARN", "Warning message"),
            ("ERROR", "MSG_CLR_FAIL", "Failure message"),
            ("SUCCESS", "MSG_CLR_OK", "Successful operation"),
            ("CANCEL", "MSG_CLR_CNCL", "Cancelled operation"),
            ("END", "MSG_CLR_END", "Completed operation"),
            ("DEBUG", "MSG_CLR_DEBUG", "Diagnostic message"),
            ("EMPTY", "MSG_CLR_EMPTY", "Neutral / empty message"),
        )

        ui_rows = (
            ("Border", "SGND_UI_BORDER", "────────────"),
            ("Label", "SGND_UI_LABEL", "SGND_UI_LABEL"),
            ("Value", "SGND_UI_VALUE", "SGND_UI_VALUE"),
            ("Text", "SGND_UI_TEXT", "Normal themed interface text"),
            ("Default", "SGND_UI_DEFAULT", "Default / secondary value"),
            ("Bold", "SGND_UI_BOLD", "Bold themed text"),
            ("Faint", "SGND_UI_FAINT", "Faint themed text"),
            ("Italic", "SGND_UI_ITALIC", "Italic themed text"),
        )

        lines: List[str] = [
            '<section class="theme-specimen">',
            '<div class="theme-specimen-heading">',
            '<div>',
            f'<div class="theme-specimen-title">{esc(theme_name)} Theme</div>',
            f'<div class="theme-specimen-source">{esc(source_name)} · generated from semantic assignments</div>',
            '</div>',
            '<div class="theme-specimen-badge">Live specimen</div>',
            '</div>',
            '<div class="theme-terminal">',
            f'<div class="theme-titlebar" style="border-color:{esc(self.resolve_theme_style("SGND_TITLE_BORDERCLR", assignments, palette).get("color", "currentColor"))}">',
            f'<span style="{esc(title_style)}">SolidGroundUX Theme Showcase</span>',
            f'<span style="{esc(title_style)}">{esc(source_file.stem)}</span>',
            '</div>',
            f'<div class="theme-subtitle" style="{esc(subtitle_style)}">Semantic UI colors and framework components</div>',
            '<div class="theme-specimen-grid">',
            '<section>',
            f'<h3 style="{esc(section_style)}; border-color:{esc(self.resolve_theme_style("SGND_SECTION_BORDERCLR", assignments, palette).get("color", "currentColor"))}">Message output</h3>',
        ]

        for label, variable_name, sample in message_rows:
            lines.append(self.theme_sample(label, variable_name, assignments, palette, sample))

        lines.extend([
            '</section>',
            '<section>',
            f'<h3 style="{esc(section_style)}; border-color:{esc(self.resolve_theme_style("SGND_SECTION_BORDERCLR", assignments, palette).get("color", "currentColor"))}">General UI elements</h3>',
        ])

        for label, variable_name, sample in ui_rows:
            lines.append(self.theme_sample(label, variable_name, assignments, palette, sample))

        lines.extend([
            '</section>',
            '<section>',
            f'<h3 style="{esc(section_style)}; border-color:{esc(self.resolve_theme_style("SGND_SECTION_BORDERCLR", assignments, palette).get("color", "currentColor"))}">Run modes</h3>',
            self.theme_pair("COMMIT", "SGND_UI_COMMIT", "DRY-RUN", "SGND_UI_DRYRUN", assignments, palette),
            f'<h3 style="{esc(section_style)}; border-color:{esc(self.resolve_theme_style("SGND_SECTION_BORDERCLR", assignments, palette).get("color", "currentColor"))}">States and validation</h3>',
            self.theme_pair("ENABLED", "SGND_UI_ENABLED", "DISABLED", "SGND_UI_DISABLED", assignments, palette),
            self.theme_pair("ON", "SGND_UI_ON", "OFF", "SGND_UI_OFF", assignments, palette),
            self.theme_pair("VALID", "SGND_UI_VALID", "INVALID", "SGND_UI_INVALID", assignments, palette),
            self.theme_pair("SUCCESS", "SGND_UI_SUCCESS", "ERROR", "SGND_UI_ERROR", assignments, palette),
            '</section>',
            '<section>',
            f'<h3 style="{esc(section_style)}; border-color:{esc(self.resolve_theme_style("SGND_SECTION_BORDERCLR", assignments, palette).get("color", "currentColor"))}">Prompt and input</h3>',
            self.theme_pair("Prompt", "SGND_UI_PROMPT", "Input value", "SGND_UI_INPUT", assignments, palette),
            f'<h3 style="{esc(section_style)}; border-color:{esc(self.resolve_theme_style("SGND_SECTION_BORDERCLR", assignments, palette).get("color", "currentColor"))}">Progress display</h3>',
            '<div class="theme-progress-row">',
            f'<span class="theme-progress-bar" style="{esc(progress_bar_style)}">[##############........]</span>',
            f'<span style="{esc(progress_ind_style)}">65%</span>',
            f'<span style="{esc(progress_text_style)}">65/100</span>',
            '</div>',
            '</section>',
            '</div>',
            '</div>',
            '</section>',
        ])

        return "\n".join(lines)

    # fn: render_layout_css - Render layout css
    # . Purpose
    #   Render layout css for the documentation rendering workflow.
    # . Usage
    #   self.render_layout_css()
    def render_layout_css(self) -> None:
        css_file = self.asset_dir / "doc.css"
        css_file.write_text("""html, body {
    margin: 0;
    padding: 0;
    height: 100%;
}

* {
    box-sizing: border-box;
}

body {
    border-top: 0;
}

:root {
    --doc-nav-width: 340px;
}

.doc-shell {
    display: grid;
    grid-template-columns: var(--doc-nav-width, """ + self.config.get("VAL_NAV_WIDTH", "340px") + """) 7px minmax(0, 1fr);
    height: 100vh;
}

.doc-nav {
    overflow: auto;
    padding: 32px 20px 18px;
}

.doc-nav-resizer {
    position: relative;
    cursor: col-resize;
    background: var(--doc-border);
    touch-action: none;
}

.doc-nav-resizer::after {
    content: "";
    position: absolute;
    inset: 0 -3px;
}

.doc-nav-resizer:hover,
.doc-nav-resizer.is-resizing {
    filter: brightness(0.8);
}

.doc-nav-title {
    margin: 0 0 14px;
    padding-bottom: 8px;
    border-bottom: 1px solid var(--doc-border);
}

.doc-nav-branding {
    margin: -12px 0 22px;
    text-align: center;
}

.doc-nav-branding img {
    display: block;
    width: min(100%, 220px);
    height: auto;
    max-height: 72px;
    object-fit: contain;
    margin: 0 auto;
}

.doc-page-branding {
    position: sticky;
    top: 0;
    z-index: 100;
    display: flex;
    justify-content: flex-end;
    align-items: center;
    gap: 12px;
    min-height: 46px;
    margin: -18px -48px 20px;
    padding: 10px 48px;
    color: var(--doc-muted);
    background: var(--doc-page-background, #ffffff);
    border-bottom: 1px solid var(--doc-border);
}

.doc-page-branding-title {
    font-size: 11pt;
    font-weight: 600;
    white-space: nowrap;
}

.doc-page-branding img {
    display: block;
    width: auto;
    height: 46px;
    object-fit: contain;
}

.doc-nav-node {
    margin: 4px 0;
}

.doc-nav-node summary {
    cursor: pointer;
    line-height: 1.35;
}

.doc-nav-module,
.doc-nav-section,
.doc-nav-item {
    text-decoration: none;
}

.doc-nav-section {
    display: block;
    margin: 6px 0 2px;
}

.doc-nav-item {
    display: block;
    line-height: 1.3;
    margin: 3px 0;
}

.doc-nav-module:hover,
.doc-nav-section:hover,
.doc-nav-item:hover {
    text-decoration: underline;
}

.doc-nav-special,
.doc-nav-special a,
.doc-nav-special > summary,
.type-product,
.type-product a,
.type-group,
.type-group a,
.type-group > summary,
.type-subgroup,
.type-subgroup a,
.type-subgroup > summary,
.type-appendices,
.type-appendices a,
.type-appendices > summary,
.type-appendix,
.type-appendix a,
.type-preface,
.type-preface a,
.type-epilogue,
.type-epilogue a {
    font-weight: 700;
}

.doc-content-frame {
    width: 100%;
    height: 100vh;
    border: 0;
}

.doc-page {
    width: min(100%, 1080px);
    padding: 42px 48px 64px;
}

.doc-page-header {
    border-bottom: 1px solid var(--doc-border);
    margin-bottom: 24px;
    padding-bottom: 14px;
}

.doc-attribution-meta {
    display: grid;
    grid-template-columns: max-content 1fr;
    column-gap: 12px;
    row-gap: 5px;
}

.doc-attribution-meta dt {
    font-weight: 700;
}

.doc-attribution-meta dd {
    margin: 0;
}

.doc-license-text {
    white-space: pre-wrap;
    padding: 1rem;
    border: 1px solid var(--doc-border);
    border-radius: 8px;
}


.doc-aligned-block {
    display: grid;
    column-gap: 1.25ch;
    row-gap: 0;
    margin: 0;
}

.doc-aligned-cell { min-width: 0; }
.doc-aligned-cell:not(.doc-aligned-last) { white-space: nowrap; }

.doc-data-table {
    border-collapse: collapse;
    margin-top: 12px;
    width: 100%;
}

.doc-data-table th,
.doc-data-table td {
    border: 1px solid var(--doc-border);
    padding: 7px 9px;
    text-align: left;
    vertical-align: top;
}

.doc-summary-tiles {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 14px;
    margin-top: 14px;
}

.doc-summary-tile {
    min-height: 104px;
    padding: 18px;
    border: 1px solid var(--doc-border);
    border-radius: 12px;
    background: var(--doc-panel);
}

.doc-summary-value {
    font-size: 24pt;
    font-weight: 700;
    line-height: 1;
    font-variant-numeric: tabular-nums;
}

.doc-summary-label {
    margin-top: 10px;
}

.doc-image-group {
    display: grid;
    gap: 18px;
    margin: 22px 0 28px;
    align-items: start;
}

.doc-image-group.images-1 {
    grid-template-columns: minmax(0, 1fr);
}

.doc-image-group.images-2 {
    grid-template-columns: repeat(2, minmax(0, 1fr));
}

.doc-image-group.images-3 {
    grid-template-columns: repeat(3, minmax(0, 1fr));
}

.doc-image-group.images-4 {
    grid-template-columns: repeat(2, minmax(0, 1fr));
}

.doc-image {
    margin: 0;
}

.doc-image img {
    display: block;
    width: 100%;
    height: auto;
    max-height: 680px;
    object-fit: contain;
    border: 1px solid var(--doc-border);
    border-radius: 10px;
    background: #fff;
}

.doc-image figcaption {
    margin-top: 8px;
    text-align: center;
    color: var(--doc-muted);
    font-size: 9.5pt;
}

.theme-specimen {
    margin: 0 0 28px;
    border: 1px solid var(--doc-border);
    border-radius: 12px;
    overflow: hidden;
    background: var(--doc-panel);
}

.theme-specimen-heading {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 18px;
    padding: 14px 18px;
    border-bottom: 1px solid var(--doc-border);
}

.theme-specimen-title {
    font-size: 13pt;
    font-weight: 700;
}

.theme-specimen-source {
    margin-top: 3px;
    color: var(--doc-muted);
    font-size: 9pt;
}

.theme-specimen-badge {
    padding: 4px 9px;
    border: 1px solid var(--doc-border);
    border-radius: 999px;
    color: var(--doc-muted);
    font-size: 8.5pt;
    white-space: nowrap;
}

.theme-terminal {
    padding: 18px;
    background: #242424;
    color: #c8c8c8;
    font-family: "Cascadia Mono", "Cascadia Code", Consolas, monospace;
    font-size: 9pt;
}

.theme-titlebar {
    display: flex;
    justify-content: space-between;
    gap: 18px;
    padding: 4px 2px 8px;
    border-top: 1px solid;
    border-bottom: 1px solid;
}

.theme-subtitle {
    padding: 6px 2px 14px;
    text-align: center;
}

.theme-specimen-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 12px 28px;
}

.theme-specimen-grid h3 {
    margin: 10px 0 8px;
    padding: 0 0 4px;
    border-bottom: 1px solid;
    font-family: inherit;
    font-size: 9.5pt;
}

.theme-sample-row {
    display: grid;
    grid-template-columns: 165px 90px minmax(0, 1fr);
    gap: 10px;
    align-items: baseline;
    min-height: 22px;
}

.theme-sample-row code {
    color: #8a8a8a;
    font-family: inherit;
    font-size: 8pt;
}

.theme-sample-label {
    color: #aaa;
}

.theme-pair {
    display: flex;
    gap: 12px;
    align-items: baseline;
    min-height: 25px;
}

.theme-pair-separator {
    color: #666;
}

.theme-progress-row {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
    align-items: baseline;
    padding: 6px 0;
}

.theme-progress-bar {
    white-space: pre;
}

@media (max-width: 900px) {
    .doc-shell {
        --doc-nav-width: 270px;
        grid-template-columns: var(--doc-nav-width) 5px minmax(0, 1fr);
    }

    .doc-page {
        padding: 32px 28px 48px;
    }

    .doc-page-branding {
        margin-left: -28px;
        margin-right: -28px;
        padding-left: 28px;
        padding-right: 28px;
    }

    .doc-summary-tiles,
    .doc-image-group.images-3 {
        grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    .theme-specimen-grid {
        grid-template-columns: 1fr;
    }
}

@media (max-width: 640px) {
    .doc-shell {
        --doc-nav-width: 240px;
    }

    .doc-summary-tiles,
    .doc-image-group.images-2,
    .doc-image-group.images-3,
    .doc-image-group.images-4 {
        grid-template-columns: 1fr;
    }
}
""", encoding="utf-8")

    # fn: ensure_theme_css - Ensure theme css
    # . Purpose
    #   Ensure theme css for the documentation rendering workflow.
    # . Usage
    #   self.ensure_theme_css()
    def ensure_theme_css(self) -> None:
        theme_file = self.asset_dir / "theme.css"

        if theme_file.exists():
            return

        theme_file.write_text(self.default_theme_css(), encoding="utf-8")

    # fn: default_theme_css - Provide default theme css
    # . Purpose
    #   Provide default theme css for the documentation rendering workflow.
    # . Usage
    #   self.default_theme_css()
    def default_theme_css(self) -> str:
        return """:root {
    --doc-page-background: #ffffff;
    --doc-text: #1f2933;
    --doc-muted: #667085;
    --doc-border: #d9dee7;
    --doc-panel: #f7f9fc;
    --doc-nav: #f3f5f8;
    --doc-accent: #245b8f;
    --doc-accent-soft: #eaf2f8;
}

html, body {
    font-family: "Segoe UI", Inter, system-ui, -apple-system, BlinkMacSystemFont, sans-serif;
    color: var(--doc-text);
    background: #ffffff;
}

body {
    font-size: 10.5pt;
}

.doc-nav {
    background: var(--doc-nav);
}

.doc-nav-title {
    font-size: 17pt;
    font-weight: 700;
}

.doc-nav-node summary {
    font-weight: 650;
}

.doc-nav-node.level-0 > summary {
    font-size: 12pt;
}

.doc-nav-module,
.doc-nav-section {
    color: #18212b;
}

.doc-nav-section {
    font-size: 10pt;
}

.doc-nav-section.level-1,
.doc-nav-section.level-2 {
    font-weight: 600;
}

.doc-nav-item {
    color: var(--doc-accent);
    font-size: 9.5pt;
}

.doc-title,
.ct-prefaceheader,
.ct-moduleheader,
.ct-epilogueheader,
.ct-appendixheader {
    font-size: 19pt;
    font-weight: 700;
    line-height: 1.2;
    margin: 0 0 16px;
}

.doc-breadcrumb {
    font-style: italic;
    color: var(--doc-muted);
    font-size: 10pt;
}

.ct-L1Sectionheader {
    font-size: 16pt;
    font-weight: 700;
    line-height: 1.25;
    margin: 30px 0 12px;
}

.ct-L2Sectionheader {
    font-size: 13.5pt;
    font-weight: 700;
    line-height: 1.25;
    margin: 24px 0 10px;
}

.ct-L3Sectionheader {
    font-size: 12pt;
    font-weight: 650;
    line-height: 1.25;
    margin: 18px 0 8px;
}

.ct-functionheader,
.ct-classheader,
.ct-variableheader,
.ct-gendocheader {
    font-size: 11.5pt;
    font-weight: 700;
    line-height: 1.35;
    margin: 16px 0 5px;
}

.ct-prefacebody,
.ct-modulebody,
.ct-epiloguebody,
.ct-appendixbody,
.ct-L1Sectionbody,
.ct-L2Sectionbody,
.ct-L3Sectionbody,
.ct-functionbody,
.ct-classbody,
.ct-variablebody,
.ct-gendocbody,
.ct-documentbody {
    font-size: 10.5pt;
    font-weight: 400;
    line-height: 1.55;
    margin: 0 0 7px;
    white-space: pre-wrap;
    tab-size: 4;
}

.sh-label,
.sh-highlight {
    font-weight: 700;
    margin: 12px 0 4px;
}

.sh-emphasis {
    font-weight: 700;
}

.sh-underline {
    text-decoration: underline;
}

.sh-quote {
    font-style: italic;
    color: var(--doc-muted);
}

.sh-listitem {
    margin-left: 22px;
}

.sh-listitem::before {
    content: "\2022 \";
}

.sh-indent {
    margin-left: 22px;
}

.doc-title-page {
    max-width: 1040px;
}

.doc-title-page-title {
    font-size: 26pt;
    font-weight: 750;
    line-height: 1.15;
    margin: 0 0 10px;
    letter-spacing: -0.02em;
}

.doc-title-page-subtitle {
    font-size: 17pt;
    font-style: normal;
    color: var(--doc-muted);
    margin: 0 0 24px;
}

.doc-title-page-hero {
    margin: 26px 0 30px;
}

.doc-title-page-hero img {
    display: block;
    width: 100%;
    max-width: 1280px;
    height: auto;
    margin: 0 auto;
    border: 1px solid var(--doc-border);
    border-radius: 14px;
    box-shadow: 0 12px 32px rgba(16, 24, 40, 0.12);
}

.doc-title-page-meta {
    display: flex;
    flex-wrap: wrap;
    gap: 8px 22px;
    margin-top: 22px;
    color: var(--doc-muted);
    font-size: 10.5pt;
}

.doc-title-page-summary {
    margin-top: 30px;
}

.doc-title-page-note {
    margin: 28px 0 0;
    padding: 16px 18px;
    border-left: 4px solid var(--doc-accent);
    background: var(--doc-accent-soft);
    border-radius: 0 8px 8px 0;
    font-size: 12pt;
    font-style: italic;
}

.doc-summary-tile {
    border-top: 4px solid var(--doc-accent);
    background: linear-gradient(145deg, var(--doc-accent-soft), var(--doc-panel));
    box-shadow: 0 3px 10px rgba(16, 24, 40, 0.08);
}

.doc-summary-value {
    color: var(--doc-accent);
}

.doc-summary-label {
    color: var(--doc-muted);
    font-weight: 600;
}
"""

    # fn: title_from_rows - Title from rows
    # . Purpose
    #   Title from rows for the documentation rendering workflow.
    #
    # . Arguments
    #   ref  Value consumed by this function; see the typed Python signature for its contract.
    #   fallback  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.title_from_rows(<ref>, <fallback>)
    def title_from_rows(self, ref: str, fallback: str) -> str:
        for row in self.content_by_ref.get(ref, []):
            if row.get("suppress", "0") == "1":
                continue
            content_type = row.get("contenttype", "")
            if content_type.endswith("header"):
                return row.get("content", "") or fallback
        return fallback

    # fn: regular_module_rows - Regular module rows
    # . Purpose
    #   Regular module rows for the documentation rendering workflow.
    # . Usage
    #   self.regular_module_rows()
    def regular_module_rows(self) -> List[Row]:
        rows: List[Row] = []

        for product_name, product_modules in self.modules_by_product().items():
            _product_specials, _group_specials, normal_modules = self.split_special_comment_modules(
                product_name,
                product_modules,
            )
            rows.extend(normal_modules)

        return rows

    # fn: count_source_lines - Count source lines
    # . Purpose
    #   Count source lines for the documentation rendering workflow.
    #
    # . Arguments
    #   source_path  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.count_source_lines(<source_path>)
    def count_source_lines(self, source_path: str) -> tuple[int, int]:
        if not source_path:
            return (0, 0)

        path = Path(source_path)
        if not path.exists():
            return (0, 0)

        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            return (0, 0)

        line_count = len(lines)
        code_line_count = 0

        for line in lines:
            stripped = line.strip()
            if not stripped:
                continue
            if stripped.startswith("#"):
                continue
            code_line_count += 1

        return (line_count, code_line_count)

    # fn: collect_landing_summary - Collect landing summary
    # . Purpose
    #   Collect landing summary for the documentation rendering workflow.
    # . Usage
    #   self.collect_landing_summary()
    def collect_landing_summary(self) -> Dict[str, int]:
        module_rows = self.regular_module_rows()
        source_files = {row.get("file", "") for row in module_rows if row.get("file", "")}
        documented_modules = {row.get("name", "") for row in module_rows if row.get("name", "")}

        total_lines = 0
        total_code_lines = 0

        for source_file in sorted(source_files):
            line_count, code_line_count = self.count_source_lines(source_file)
            total_lines += line_count
            total_code_lines += code_line_count

        function_count = 0
        for item in self.mod_items:
            if item.get("type", "") != "function":
                continue
            if item.get("modulename", "") not in documented_modules:
                continue
            function_count += 1

        return {
            "modules": len(module_rows),
            "lines": total_lines,
            "code_lines": total_code_lines,
            "functions": function_count,
        }

    # fn: render_landing_summary - Render landing summary
    # . Purpose
    #   Render landing summary for the documentation rendering workflow.
    # . Usage
    #   self.render_landing_summary()
    def render_landing_summary(self) -> str:
        summary = self.collect_landing_summary()

        tiles = [
            ("Modules", summary["modules"]),
            ("Functions", summary["functions"]),
            ("Source lines", summary["lines"]),
            ("Code lines", summary["code_lines"]),
        ]

        lines = [
            '<section class="doc-title-page-summary">',
            '<div class="doc-summary-tiles">',
        ]

        for label, value in tiles:
            lines.extend([
                '<div class="doc-summary-tile">',
                f'<div class="doc-summary-value">{value:,}</div>',
                f'<div class="doc-summary-label">{esc(label)}</div>',
                '</div>',
            ])

        lines.extend([
            '</div>',
            '</section>',
        ])

        return "\n".join(lines)

    # fn: render_title_page - Render title page
    # . Purpose
    #   Render title page for the documentation rendering workflow.
    # . Usage
    #   self.render_title_page()
    def render_title_page(self) -> None:
        output_file = self.page_dir / "title.html"
        output_file.parent.mkdir(parents=True, exist_ok=True)

        product = self.doc_product or "SolidGroundUX"
        brand = self.collection_name or ("SolidGroundUX" if product.lower() == "solidgroundux" else product)
        subtitle = self.doc_subtitle or "Documentation Collection"
        release_image = self.output_dir / "assets" / "images" / DOC_INDEX_HERO

        meta_lines = []
        if self.doc_version:
            meta_lines.append(f'<div><strong>Version:</strong> {esc(self.doc_version)}</div>')
        meta_lines.append(f'<div><strong>Generated:</strong> {esc(self.doc_render_date)}</div>')

        hero_html = ""
        if release_image.is_file():
            hero_html = "\n".join([
                '<figure class="doc-title-page-hero">',
                f'<img src="../assets/images/{esc(DOC_INDEX_HERO)}" alt="{esc(brand)} release overview">',
                '</figure>',
            ])

        summary_html = self.render_landing_summary()

        html_lines = [
            "<!doctype html>",
            "<html>",
            "<head>",
            '  <meta charset="utf-8">',
            f"  <title>{esc(self.doc_title)}</title>",
            '  <link rel="stylesheet" href="../assets/doc.css">',
            '  <link rel="stylesheet" href="../assets/theme.css">',
            "</head>",
            "<body>",
            '<main class="doc-page doc-title-page">',
            self.render_page_branding(),
            f'<h1 class="doc-title-page-title">{esc(brand)}</h1>',
            f'<div class="doc-title-page-subtitle">{esc(subtitle)}</div>',
            hero_html,
            summary_html,
            '<p class="doc-title-page-note">This collection is generated directly from the selected product source.</p>',
            '<div class="doc-title-page-meta">',
            *meta_lines,
            '</div>',
            "</main>",
            "</body>",
            "</html>",
        ]

        output_file.write_text("\n".join(line for line in html_lines if line), encoding="utf-8")

    # fn: render_index_page - Render index page
    # . Purpose
    #   Render index page for the documentation rendering workflow.
    # . Usage
    #   self.render_index_page()
    def render_index_page(self) -> None:
        first_page = "pages/title.html"
        index_file = self.output_dir / "index.html"

        html_lines = [
            "<!doctype html>",
            "<html>",
            "<head>",
            '  <meta charset="utf-8">',
            f"  <title>{esc(self.doc_title)}</title>",
            '  <link rel="stylesheet" href="assets/doc.css">\n  <link rel="stylesheet" href="assets/theme.css">',
            "</head>",
            "<body>",
            '<div class="doc-shell">',
            '<nav class="doc-nav">',
            self.render_nav_branding(),
            '  <div class="doc-nav-title">Index</div>',
            self.render_navigation(),
            "</nav>",
            '<div class="doc-nav-resizer" role="separator" aria-orientation="vertical" aria-label="Resize index column" tabindex="0"></div>',
            f'<iframe class="doc-content-frame" name="docframe" src="{esc(first_page)}"></iframe>',
            "</div>",
            "<script>",
            "(() => {",
            "  const shell = document.querySelector('.doc-shell');",
            "  const resizer = document.querySelector('.doc-nav-resizer');",
            "  if (!shell || !resizer) return;",
            "  const storageKey = 'solidgroundux.codex.navWidth';",
            "  const clamp = (value) => Math.max(240, Math.min(value, Math.min(720, window.innerWidth * 0.6)));",
            "  const applyWidth = (value, persist = false) => {",
            "    const width = clamp(Number(value) || 340);",
            "    shell.style.setProperty('--doc-nav-width', `${width}px`);",
            "    if (persist) localStorage.setItem(storageKey, String(Math.round(width)));",
            "  };",
            "  const saved = localStorage.getItem(storageKey);",
            "  if (saved) applyWidth(saved);",
            "  let resizing = false;",
            "  const stop = () => {",
            "    if (!resizing) return;",
            "    resizing = false;",
            "    resizer.classList.remove('is-resizing');",
            "    const width = parseFloat(getComputedStyle(shell).getPropertyValue('--doc-nav-width'));",
            "    if (Number.isFinite(width)) localStorage.setItem(storageKey, String(Math.round(width)));",
            "  };",
            "  resizer.addEventListener('pointerdown', (event) => {",
            "    resizing = true;",
            "    resizer.classList.add('is-resizing');",
            "    resizer.setPointerCapture(event.pointerId);",
            "    event.preventDefault();",
            "  });",
            "  resizer.addEventListener('pointermove', (event) => {",
            "    if (resizing) applyWidth(event.clientX);",
            "  });",
            "  resizer.addEventListener('pointerup', stop);",
            "  resizer.addEventListener('pointercancel', stop);",
            "  resizer.addEventListener('keydown', (event) => {",
            "    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;",
            "    const current = parseFloat(getComputedStyle(shell).getPropertyValue('--doc-nav-width')) || 340;",
            "    applyWidth(current + (event.key === 'ArrowRight' ? 20 : -20), true);",
            "    event.preventDefault();",
            "  });",
            "  window.addEventListener('resize', () => {",
            "    const current = parseFloat(getComputedStyle(shell).getPropertyValue('--doc-nav-width')) || 340;",
            "    applyWidth(current);",
            "  });",
            "})();",
            "</script>",
            "</body>",
            "</html>",
        ]

        index_file.write_text("\n".join(html_lines), encoding="utf-8")

    # fn: is_appendix_ref - Determine whether appendix ref
    # . Purpose
    #   Determine whether appendix ref for the documentation rendering workflow.
    #
    # . Arguments
    #   ref  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.is_appendix_ref(<ref>)
    def is_appendix_ref(self, ref: str) -> bool:
        return any(ref.startswith(prefix) for prefix in (
            CANONICAL_PREFIX,
            ATTRIBUTION_PREFIX,
            GLOSSARY_PREFIX,
            INTEGRITY_PREFIX,
            GLOBALS_PREFIX,
            ENUMS_PREFIX,
            LICENSE_PREFIX,
            CHANGELOG_PREFIX,
            INSTALL_PREFIX,
        ))

    # fn: has_renderable_page - Determine whether renderable page
    # . Purpose
    #   Determine whether renderable page for the documentation rendering workflow.
    #
    # . Arguments
    #   ref  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.has_renderable_page(<ref>)
    def has_renderable_page(self, ref: str) -> bool:
        return self.is_appendix_ref(ref) or ref in self.content_by_ref
    
    # fn: render_navigation - Render navigation
    # . Purpose
    #   Render navigation for the documentation rendering workflow.
    # . Usage
    #   self.render_navigation()
    def render_navigation(self) -> str:
        lines: List[str] = []
        open_detail_levels: List[int] = []
        container_types = {"group", "subgroup", "module", "appendices"}

        for node in self.nav:
            label = node.node_name
            current_level = node.hierarchy_level
            indent = current_level * 10
            special_nav_types = {"product", "group", "subgroup", "appendices", "appendix", "preface", "epilogue"}
            style = f"padding-left:{indent}px"
            href = page_href_from_contentref(node.contentref) if node.contentref else ""
            if node.nodetype == "product":
                href = "pages/title.html"
            special_class = " doc-nav-special" if node.nodetype in special_nav_types else ""
            type_class = slugify(node.nodetype)

            while open_detail_levels and open_detail_levels[-1] >= current_level:
                lines.append("</details>")
                open_detail_levels.pop()

            if node.nodetype in container_types:
                lines.append(f'<details class="doc-nav-node level-{current_level} type-{type_class}{special_class}">')

                if node.contentref and self.has_renderable_page(node.contentref):
                    lines.append(
                        f'<summary style="{style}"><a class="doc-nav-module" href="{esc(href)}" '
                        f'target="docframe">{esc(label)}</a></summary>'
                    )
                else:
                    lines.append(f'<summary style="{style}">{esc(label)}</summary>')

                open_detail_levels.append(current_level)
                continue

            if is_item_node(node.nodetype):
                lines.append(
                    f'<a class="doc-nav-item type-{type_class}" style="{style}" '
                    f'href="{esc(href)}" target="docframe">{esc(label)}</a>'
                )

            elif self.has_renderable_page(node.contentref) or self.is_module_level_special_page(node):
                lines.append(
                    f'<a class="doc-nav-section type-{type_class}{special_class}" style="{style}" '
                    f'href="{esc(href)}" target="docframe">{esc(label)}</a>'
                )

            elif node.nodetype == "product":
                lines.append(
                    f'<a class="doc-nav-section type-{type_class}{special_class}" style="{style}" '
                    f'href="{esc(href)}" target="docframe">{esc(label)}</a>'
                )

            else:
                lines.append(f'<div class="doc-nav-section type-{type_class}{special_class}" style="{style}">{esc(label)}</div>')

        while open_detail_levels:
            lines.append("</details>")
            open_detail_levels.pop()

        return "\n".join(lines)

    # fn: get_first_item_page - Get first item page
    # . Purpose
    #   Get first item page for the documentation rendering workflow.
    # . Usage
    #   self.get_first_item_page()
    def get_first_item_page(self) -> str:
        for node in self.nav:
            if node.contentref and node.contentref in self.content_by_ref:
                return page_href_from_contentref(node.contentref)

        for node in self.nav:
            if node.contentref and self.is_appendix_ref(node.contentref):
                return page_href_from_contentref(node.contentref)

        return "about:blank"

    # fn: render_content_pages - Render content pages
    # . Purpose
    #   Render content pages for the documentation rendering workflow.
    # . Usage
    #   self.render_content_pages()
    def render_content_pages(self) -> None:
        rendered_refs: set[str] = set()

        self.render_title_page()

        for product_name in sorted(self.modules_by_product().keys(), key=str.casefold):
            if not self.product_has_appendices(product_name):
                continue
            for appendix in APPENDIX_SPECS:
                renderer = getattr(self, appendix.renderer_name)
                renderer(product_name)

        for node in self.nav:
            if not node.contentref:
                continue
            if self.is_appendix_ref(node.contentref):
                continue
            if node.contentref not in self.content_by_ref and not self.is_module_level_special_page(node):
                continue

            self.render_content_page(node)
            rendered_refs.add(node.contentref)

        for ref, rows in self.content_by_ref.items():
            if ref in rendered_refs:
                continue
            self.render_content_page_for_ref(ref, rows)

    # fn: render_attribution_page - Render attribution page
    # . Purpose
    #   Render attribution page for the documentation rendering workflow.
    #
    # . Arguments
    #   product_name  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_attribution_page(<product_name>)
    def render_attribution_page(self, product_name: str) -> None:
        ref = attribution_ref(product_name)
        href = page_href_from_contentref(ref)
        output_file = self.output_dir / href
        output_file.parent.mkdir(parents=True, exist_ok=True)

        body = self.render_attribution_body(product_name)

        html_lines = [
            "<!doctype html>",
            "<html>",
            "<head>",
            '  <meta charset="utf-8">',
            "  <title>Appendix A: Attribution</title>",
            '  <link rel="stylesheet" href="../assets/doc.css">',
            '  <link rel="stylesheet" href="../assets/theme.css">',
            "</head>",
            "<body>",
            '<main class="doc-page">',
            self.render_page_branding(),
            '<header class="doc-page-header">',
            '  <div class="doc-title">Appendix A: Attribution</div>',
            f'  <div class="doc-breadcrumb">{esc(product_name)} / Appendices / Appendix A: Attribution</div>',
            "</header>",
            body,
            "</main>",
            "</body>",
            "</html>",
        ]

        output_file.write_text("\n".join(html_lines), encoding="utf-8")

    # fn: render_attribution_body - Render attribution body
    # . Purpose
    #   Render attribution body for the documentation rendering workflow.
    #
    # . Arguments
    #   product_name  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_attribution_body(<product_name>)
    def render_attribution_body(self, product_name: str) -> str:
        modules_by_name: Dict[str, Row] = {
            module.get("name", ""): module
            for module in self.mod_table
            if module.get("name", "")
        }

        grouped_rows: Dict[tuple[str, str, str, str], List[Row]] = defaultdict(list)

        for attribution in self.mod_attribution:
            module_name = attribution.get("modulename", "")
            module = modules_by_name.get(module_name, {})
            row_product = module.get("product", "") or self.doc_product or "Documentation"
            if row_product != product_name:
                continue

            merged: Row = dict(attribution)
            merged["group"] = module.get("group", "")
            merged["moduletitle"] = module.get("title", "")
            merged["moduleversion"] = module.get("version", "")

            key = (
                attribution.get("copyright", ""),
                attribution.get("company", ""),
                attribution.get("developers", ""),
                attribution.get("license", ""),
            )
            grouped_rows[key].append(merged)

        lines: List[str] = [
            '<div class="ct-documentbody">This appendix lists module attribution metadata collected from module headers.</div>',
        ]

        if not grouped_rows:
            lines.append('<div class="ct-documentbody">No attribution data was exported.</div>')
            return "\n".join(lines)

        for group_key in sorted(grouped_rows.keys(), key=lambda value: tuple(part.casefold() for part in value)):
            copyright_text, company, developers, license_text = group_key
            rows = sorted(
                grouped_rows[group_key],
                key=lambda row: (
                    row.get("group", "").casefold(),
                    row.get("modulename", "").casefold(),
                ),
            )

            lines.extend([
                '<section class="doc-attribution-block">',
                f'<h2 class="ct-L2Sectionheader">{esc(company or "Unspecified company")}</h2>',
                '<dl class="doc-attribution-meta">',
                f'<dt>Copyright</dt><dd>{esc(copyright_text or "-")}</dd>',
                f'<dt>Company</dt><dd>{esc(company or "-")}</dd>',
                f'<dt>Developers</dt><dd>{esc(developers or "-")}</dd>',
                f'<dt>License</dt><dd>{esc(license_text or "-")}</dd>',
                '</dl>',
                '<table class="doc-data-table">',
                '<thead><tr><th>Group</th><th>Module</th><th>Title</th><th>Version</th></tr></thead>',
                '<tbody>',
            ])

            for row in rows:
                lines.append(
                    "<tr>"
                    f'<td>{esc(row.get("group", ""))}</td>'
                    f'<td>{esc(row.get("modulename", ""))}</td>'
                    f'<td>{esc(row.get("moduletitle", ""))}</td>'
                    f'<td>{esc(row.get("moduleversion", ""))}</td>'
                    "</tr>"
                )

            lines.extend(['</tbody>', '</table>', '</section>'])

        return "\n".join(lines)

    # fn: render_glossary_page - Render glossary page
    # . Purpose
    #   Render glossary page for the documentation rendering workflow.
    #
    # . Arguments
    #   product_name  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_glossary_page(<product_name>)
    def render_glossary_page(self, product_name: str) -> None:
        ref = glossary_ref(product_name)
        href = page_href_from_contentref(ref)
        output_file = self.output_dir / href
        output_file.parent.mkdir(parents=True, exist_ok=True)

        body = self.render_glossary_body(product_name)

        html_lines = [
            "<!doctype html>",
            "<html>",
            "<head>",
            '  <meta charset="utf-8">',
            "  <title>Appendix B: Glossary</title>",
            '  <link rel="stylesheet" href="../assets/doc.css">',
            '  <link rel="stylesheet" href="../assets/theme.css">',
            "</head>",
            "<body>",
            '<main class="doc-page">',
            self.render_page_branding(),
            '<header class="doc-page-header">',
            '  <div class="doc-title">Appendix B: Glossary</div>',
            f'  <div class="doc-breadcrumb">{esc(product_name)} / Appendices / Appendix B: Glossary</div>',
            "</header>",
            body,
            "</main>",
            "</body>",
            "</html>",
        ]

        output_file.write_text("\n".join(html_lines), encoding="utf-8")

    # fn: render_glossary_body - Render glossary body
    # . Purpose
    #   Render glossary body for the documentation rendering workflow.
    #
    # . Arguments
    #   product_name  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_glossary_body(<product_name>)
    def render_glossary_body(self, product_name: str) -> str:
        function_rows = self.collect_glossary_rows(product_name, "function")
        variable_rows = self.collect_glossary_rows(product_name, "variable")

        lines: List[str] = [
            '<div class="ct-documentbody">This appendix lists documented functions and variables, sorted alphabetically by name.</div>',
            self.render_glossary_table("Functions", "Function", function_rows),
            self.render_glossary_table("Variables", "Variable", variable_rows),
        ]

        return "\n".join(lines)

    # fn: collect_glossary_rows - Collect glossary rows
    # . Purpose
    #   Collect glossary rows for the documentation rendering workflow.
    #
    # . Arguments
    #   product_name  Value consumed by this function; see the typed Python signature for its contract.
    #   item_type  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.collect_glossary_rows(<product_name>, <item_type>)
    def collect_glossary_rows(self, product_name: str, item_type: str) -> List[Row]:
        modules_by_name: Dict[str, Row] = {
            module.get("name", ""): module
            for module in self.mod_table
            if module.get("name", "")
        }

        rows: List[Row] = []

        for item in self.mod_items:
            if item.get("type", "") != item_type:
                continue

            module_name = item.get("modulename", "")
            module = modules_by_name.get(module_name, {})
            row_product = module.get("product", "") or self.doc_product or "Documentation"

            if row_product != product_name:
                continue
            if self.is_template_module(module):
                continue
            if item.get("itemrole", "") == "template":
                continue

            item_name = item.get("name", "")
            item_ref = content_ref(
                module_name,
                item.get("grandparentsection", ""),
                item.get("parentsection", ""),
                item.get("section", ""),
                item_name,
            )

            rows.append({
                "name": item_name,
                "title": item.get("title", ""),
                "purpose": self.extract_item_purpose(item_ref),
                "module": module_name,
            })

        rows.sort(key=lambda row: (row.get("name", "").casefold(), row.get("module", "").casefold()))
        return rows

    # fn: extract_item_purpose - Extract item purpose
    # . Purpose
    #   Extract item purpose for the documentation rendering workflow.
    #
    # . Arguments
    #   ref  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.extract_item_purpose(<ref>)
    def extract_item_purpose(self, ref: str) -> str:
        rows = self.content_by_ref.get(ref, [])

        if not rows:
            parts = ref.split(":")
            item_name = parts[4] if len(parts) > 4 else ""
            if item_name:
                for candidate_ref, candidate_rows in self.content_by_ref.items():
                    candidate_parts = candidate_ref.split(":")
                    if len(candidate_parts) > 4 and candidate_parts[0] == parts[0] and candidate_parts[4] == item_name:
                        rows = candidate_rows
                        break

        purpose_lines: List[str] = []
        in_purpose = False

        for row in rows:
            if row.get("suppress", "0") == "1":
                continue

            content_type = row.get("contenttype", "")
            content = (row.get("content", "") or "").strip()

            if not content:
                if in_purpose and purpose_lines:
                    break
                continue

            normalized = content.rstrip(":").casefold()

            if normalized == "purpose":
                in_purpose = True
                continue

            if in_purpose:
                if content_type.endswith("header"):
                    break
                if content.endswith(":") and len(content.split()) <= 4:
                    break
                purpose_lines.append(content)

        return " ".join(purpose_lines)

    # fn: render_glossary_table - Render glossary table
    # . Purpose
    #   Render glossary table for the documentation rendering workflow.
    #
    # . Arguments
    #   title  Value consumed by this function; see the typed Python signature for its contract.
    #   name_header  Value consumed by this function; see the typed Python signature for its contract.
    #   rows  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_glossary_table(<title>, <name_header>, <rows>)
    def render_glossary_table(self, title: str, name_header: str, rows: List[Row]) -> str:
        lines: List[str] = [
            '<section class="doc-glossary-block">',
            f'<h2 class="ct-L2Sectionheader">{esc(title)}</h2>',
        ]

        if not rows:
            lines.extend([
                '<div class="ct-documentbody">No entries found.</div>',
                '</section>',
            ])
            return "\n".join(lines)

        lines.extend([
            '<table class="doc-data-table">',
            f'<thead><tr><th>{esc(name_header)}</th><th>Title</th><th>Purpose</th><th>Module</th></tr></thead>',
            '<tbody>',
        ])

        for row in rows:
            lines.append(
                "<tr>"
                f'<td>{esc(row.get("name", ""))}</td>'
                f'<td>{esc(row.get("title", ""))}</td>'
                f'<td>{esc(row.get("purpose", ""))}</td>'
                f'<td>{esc(row.get("module", ""))}</td>'
                "</tr>"
            )

        lines.extend([
            '</tbody>',
            '</table>',
            '</section>',
        ])
        return "\n".join(lines)

    # fn: render_integrity_page - Render integrity page
    # . Purpose
    #   Render integrity page for the documentation rendering workflow.
    #
    # . Arguments
    #   product_name  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_integrity_page(<product_name>)
    def render_integrity_page(self, product_name: str) -> None:
        ref = integrity_ref(product_name)
        href = page_href_from_contentref(ref)
        output_file = self.output_dir / href
        output_file.parent.mkdir(parents=True, exist_ok=True)

        body = self.render_integrity_body(product_name)

        html_lines = [
            "<!doctype html>",
            "<html>",
            "<head>",
            '  <meta charset="utf-8">',
            "  <title>Appendix C: Integrity Information</title>",
            '  <link rel="stylesheet" href="../assets/doc.css">',
            '  <link rel="stylesheet" href="../assets/theme.css">',
            "</head>",
            "<body>",
            '<main class="doc-page">',
            self.render_page_branding(),
            '<header class="doc-page-header">',
            '  <div class="doc-title">Appendix C: Integrity Information</div>',
            f'  <div class="doc-breadcrumb">{esc(product_name)} / Appendices / Appendix C: Integrity Information</div>',
            "</header>",
            body,
            "</main>",
            "</body>",
            "</html>",
        ]

        output_file.write_text("\n".join(html_lines), encoding="utf-8")

    # fn: render_integrity_body - Render integrity body
    # . Purpose
    #   Render integrity body for the documentation rendering workflow.
    #
    # . Arguments
    #   product_name  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_integrity_body(<product_name>)
    def render_integrity_body(self, product_name: str) -> str:
        rows: List[Row] = []

        for module in self.mod_table:
            row_product = module.get("product", "") or self.doc_product or "Documentation"
            if row_product != product_name:
                continue

            rows.append({
                "group": module.get("group", ""),
                "module": module.get("name", ""),
                "version": module.get("version", ""),
                "build": module.get("build", ""),
                "checksum": module.get("checksum", ""),
            })

        rows.sort(key=lambda row: (
            row.get("group", "").casefold(),
            row.get("module", "").casefold(),
        ))

        lines: List[str] = [
            '<div class="ct-documentbody">This appendix lists module integrity metadata collected from module headers.</div>',
        ]

        if not rows:
            lines.append('<div class="ct-documentbody">No integrity data was exported.</div>')
            return "\n".join(lines)

        lines.extend([
            '<table class="doc-data-table">',
            '<thead><tr><th>Group</th><th>Module</th><th>Version</th><th>Build</th><th>Checksum</th></tr></thead>',
            '<tbody>',
        ])

        for row in rows:
            lines.append(
                "<tr>"
                f'<td>{esc(row.get("group", ""))}</td>'
                f'<td>{esc(row.get("module", ""))}</td>'
                f'<td>{esc(row.get("version", ""))}</td>'
                f'<td>{esc(row.get("build", ""))}</td>'
                f'<td>{esc(row.get("checksum", ""))}</td>'
                "</tr>"
            )

        lines.extend([
            '</tbody>',
            '</table>',
        ])

        return "\n".join(lines)

    # fn: render_license_page - Render license page
    # . Purpose
    #   Render license page for the documentation rendering workflow.
    #
    # . Arguments
    #   product_name  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_license_page(<product_name>)
    def render_license_page(self, product_name: str) -> None:
        ref = license_ref(product_name)
        href = page_href_from_contentref(ref)
        output_file = self.output_dir / href
        output_file.parent.mkdir(parents=True, exist_ok=True)

        body = self.render_license_body()

        html_lines = [
            "<!doctype html>",
            "<html>",
            "<head>",
            '  <meta charset="utf-8">',
            "  <title>Appendix X: License</title>",
            '  <link rel="stylesheet" href="../assets/doc.css">',
            '  <link rel="stylesheet" href="../assets/theme.css">',
            "</head>",
            "<body>",
            '<main class="doc-page">',
            self.render_page_branding(),
            '<header class="doc-page-header">',
            '  <div class="doc-title">Appendix X: License</div>',
            f'  <div class="doc-breadcrumb">{esc(product_name)} / Appendices / Appendix X: License</div>',
            "</header>",
            body,
            "</main>",
            "</body>",
            "</html>",
        ]

        output_file.write_text("\n".join(html_lines), encoding="utf-8")

    # fn: render_license_body - Render license body
    # . Purpose
    #   Render license body for the documentation rendering workflow.
    # . Usage
    #   self.render_license_body()
    def render_license_body(self) -> str:
        lines: List[str] = [
            '<div class="ct-documentbody">This appendix contains the active SolidGroundUX license text exported by the Bash renderer hand-off.</div>',
        ]

        if not self.doc_license_lines:
            lines.append('<div class="ct-documentbody">No license text was exported.</div>')
            return "\n".join(lines)

        lines.append('<pre class="doc-license-text">')
        for row in sorted(self.doc_license_lines, key=lambda value: int(value.get("linenr", "0") or "0")):
            lines.append(esc(row.get("content", "")))
        lines.append('</pre>')
        return "\n".join(lines)

    # fn: render_enums_page - Render enums page
    # . Purpose
    #   Render enums page for the documentation rendering workflow.
    #
    # . Arguments
    #   product_name  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_enums_page(<product_name>)
    def render_enums_page(self, product_name: str) -> None:
        ref = enums_ref(product_name)
        href = page_href_from_contentref(ref)
        output_file = self.output_dir / href
        output_file.parent.mkdir(parents=True, exist_ok=True)

        body = self.render_enums_body()

        html_lines = [
            "<!doctype html>",
            "<html>",
            "<head>",
            '  <meta charset="utf-8">',
            "  <title>Appendix E: Framework Value Sets</title>",
            '  <link rel="stylesheet" href="../assets/doc.css">',
            '  <link rel="stylesheet" href="../assets/theme.css">',
            "</head>",
            "<body>",
            '<main class="doc-page">',
            self.render_page_branding(),
            '<header class="doc-page-header">',
            '  <div class="doc-title">Appendix E: Framework Value Sets</div>',
            f'  <div class="doc-breadcrumb">{esc(product_name)} / Appendices / Appendix E: Framework Value Sets</div>',
            "</header>",
            body,
            "</main>",
            "</body>",
            "</html>",
        ]

        output_file.write_text("\n".join(html_lines), encoding="utf-8")

    # fn: render_enums_body - Render enums body
    # . Purpose
    #   Render enums body for the documentation rendering workflow.
    # . Usage
    #   self.render_enums_body()
    def render_enums_body(self) -> str:
        grouped: Dict[str, List[Row]] = defaultdict(list)

        for row in self.doc_enums:
            grouped[row.get("category", "Other") or "Other"].append(row)

        lines: List[str] = [
            '<div class="ct-documentbody">This appendix lists framework value sets whose possible values behave like enums, even when they are not all defined in one source line.</div>',
        ]

        if not grouped:
            lines.append('<div class="ct-documentbody">No framework value sets were exported.</div>')
            return "\n".join(lines)

        for category in sorted(grouped.keys(), key=str.casefold):
            rows = sorted(
                grouped[category],
                key=lambda row: (
                    row.get("name", "").casefold(),
                    row.get("value", "").casefold(),
                ),
            )
            lines.extend([
                '<section class="doc-enums-block">',
                f'<h2 class="ct-L2Sectionheader">{esc(category)}</h2>',
                '<table class="doc-data-table">',
                '<thead><tr><th>Name</th><th>Value</th><th>Aliases</th><th>Description</th><th>Source</th></tr></thead>',
                '<tbody>',
            ])
            for row in rows:
                lines.append(
                    "<tr>"
                    f'<td>{esc(row.get("name", ""))}</td>'
                    f'<td>{esc(row.get("value", ""))}</td>'
                    f'<td>{esc(row.get("aliases", ""))}</td>'
                    f'<td>{esc(row.get("description", ""))}</td>'
                    f'<td>{esc(row.get("source", ""))}</td>'
                    "</tr>"
                )
            lines.extend(['</tbody>', '</table>', '</section>'])

        return "\n".join(lines)

    # fn: render_globals_page - Render globals page
    # . Purpose
    #   Render globals page for the documentation rendering workflow.
    #
    # . Arguments
    #   product_name  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_globals_page(<product_name>)
    def render_globals_page(self, product_name: str) -> None:
        ref = globals_ref(product_name)
        href = page_href_from_contentref(ref)
        output_file = self.output_dir / href
        output_file.parent.mkdir(parents=True, exist_ok=True)

        body = self.render_globals_body(product_name)

        html_lines = [
            "<!doctype html>",
            "<html>",
            "<head>",
            '  <meta charset="utf-8">',
            "  <title>Appendix D: Global Variables</title>",
            '  <link rel="stylesheet" href="../assets/doc.css">',
            '  <link rel="stylesheet" href="../assets/theme.css">',
            "</head>",
            "<body>",
            '<main class="doc-page">',
            self.render_page_branding(),
            '<header class="doc-page-header">',
            '  <div class="doc-title">Appendix D: Global Variables</div>',
            f'  <div class="doc-breadcrumb">{esc(product_name)} / Appendices / Appendix D: Global Variables</div>',
            "</header>",
            body,
            "</main>",
            "</body>",
            "</html>",
        ]

        output_file.write_text("\n".join(html_lines), encoding="utf-8")

    # fn: render_globals_body - Render globals body
    # . Purpose
    #   Render globals body for the documentation rendering workflow.
    #
    # . Arguments
    #   product_name  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_globals_body(<product_name>)
    def render_globals_body(self, product_name: str) -> str:
        modules_by_name: Dict[str, Row] = {
            module.get("name", ""): module
            for module in self.mod_table
            if module.get("name", "")
        }

        rows: List[Row] = []
        for global_row in self.mod_globals:
            module_name = global_row.get("modulename", "")
            module = modules_by_name.get(module_name, {})
            row_product = module.get("product", "") or self.doc_product or "Documentation"

            if row_product != product_name:
                continue

            rows.append({
                "scope": global_row.get("scope", ""),
                "audience": global_row.get("audience", ""),
                "name": global_row.get("name", ""),
                "description": global_row.get("description", ""),
                "extra": global_row.get("extra", ""),
                "currentvalue": global_row.get("currentvalue", ""),
                "module": module_name,
                "group": module.get("group", ""),
            })

        lines: List[str] = [
            '<div class="ct-documentbody">This appendix lists global variables declared through SGND_FRAMEWORK_GLOBALS, SGND_RUNTIME_GLOBALS, and SGND_SCRIPT_GLOBALS.</div>',
        ]

        if not rows:
            lines.append('<div class="ct-documentbody">No global variable declarations were exported.</div>')
            return "\n".join(lines)

        framework_rows = [row for row in rows if row.get("scope", "") == "framework"]
        runtime_rows = [row for row in rows if row.get("scope", "") == "runtime"]
        script_rows = [row for row in rows if row.get("scope", "") == "script"]
        other_rows = [row for row in rows if row.get("scope", "") not in {"framework", "runtime", "script"}]

        lines.append(self.render_globals_table("Framework Globals", framework_rows))
        lines.append(self.render_globals_table("Runtime Globals", runtime_rows))
        lines.append(self.render_globals_table("Script Globals", script_rows))

        if other_rows:
            lines.append(self.render_globals_table("Other Globals", other_rows))

        return "\n".join(lines)

    # fn: render_globals_table - Render globals table
    # . Purpose
    #   Render globals table for the documentation rendering workflow.
    #
    # . Arguments
    #   title  Value consumed by this function; see the typed Python signature for its contract.
    #   rows  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_globals_table(<title>, <rows>)
    def render_globals_table(self, title: str, rows: List[Row]) -> str:
        lines: List[str] = [
            '<section class="doc-globals-block">',
            f'<h2 class="ct-L2Sectionheader">{esc(title)}</h2>',
        ]

        if not rows:
            lines.extend([
                '<div class="ct-documentbody">No entries found.</div>',
                '</section>',
            ])
            return "\n".join(lines)

        rows = sorted(
            rows,
            key=lambda row: (
                row.get("group", "").casefold(),
                row.get("module", "").casefold(),
                row.get("name", "").casefold(),
            ),
        )

        lines.extend([
            '<table class="doc-data-table">',
            '<thead><tr><th>Variable</th><th>Audience</th><th>Description</th><th>Current Value</th><th>Module</th><th>Group</th><th>Extra</th></tr></thead>',
            '<tbody>',
        ])

        for row in rows:
            lines.append(
                "<tr>"
                f'<td>{esc(row.get("name", ""))}</td>'
                f'<td>{esc(row.get("audience", ""))}</td>'
                f'<td>{esc(row.get("description", ""))}</td>'
                f'<td>{esc(row.get("currentvalue", ""))}</td>'
                f'<td>{esc(row.get("module", ""))}</td>'
                f'<td>{esc(row.get("group", ""))}</td>'
                f'<td>{esc(row.get("extra", ""))}</td>'
                "</tr>"
            )

        lines.extend([
            '</tbody>',
            '</table>',
            '</section>',
        ])
        return "\n".join(lines)

    # fn: read_optional_project_document - Read optional project document
    # . Purpose
    #   Read optional project document for the documentation rendering workflow.
    #
    # . Arguments
    #   candidates  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.read_optional_project_document(<candidates>)
    def read_optional_project_document(self, candidates: Sequence[str], product_name: str = "") -> tuple[str, str]:
        roots: List[Path] = []
        manifest = self.product_manifest_by_name.get(normalize_key(product_name), {}) if product_name else {}
        if manifest.get("project_root"):
            roots.append(Path(manifest["project_root"]))
        roots.append(self.input_dir)
        for root in roots:
            for name in candidates:
                path = root / name
                if path.is_file():
                    return name, path.read_text(encoding="utf-8", errors="replace")
        return candidates[0], ""

    # fn: render_markdown_document - Render markdown document
    # . Purpose
    #   Render markdown document for the documentation rendering workflow.
    #
    # . Arguments
    #   markdown_text  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_markdown_document(<markdown_text>)
    def render_markdown_document(self, markdown_text: str) -> str:
        if not markdown_text.strip():
            return ""

        lines: List[str] = []
        paragraph: List[str] = []
        list_type = ""
        in_code = False
        code_lines: List[str] = []

        # fn: flush_paragraph - Flush paragraph
        # . Purpose
        #   Flush paragraph for the documentation rendering workflow.
        # . Usage
        #   self.flush_paragraph()
        def flush_paragraph() -> None:
            if paragraph:
                lines.append(f'<p class="ct-documentbody">{esc(" ".join(paragraph))}</p>')
                paragraph.clear()

        # fn: close_list - Close list
        # . Purpose
        #   Close list for the documentation rendering workflow.
        # . Usage
        #   self.close_list()
        def close_list() -> None:
            nonlocal list_type
            if list_type:
                lines.append(f"</{list_type}>")
                list_type = ""

        for raw_line in markdown_text.splitlines():
            stripped = raw_line.strip()

            if stripped.startswith("```"):
                flush_paragraph()
                close_list()
                if in_code:
                    lines.append('<pre class="doc-license-text"><code>' + esc("\n".join(code_lines)) + '</code></pre>')
                    code_lines.clear()
                    in_code = False
                else:
                    in_code = True
                continue

            if in_code:
                code_lines.append(raw_line)
                continue

            heading = re.match(r"^(#{1,6})\s+(.+)$", stripped)
            if heading:
                flush_paragraph()
                close_list()
                level = min(len(heading.group(1)) + 1, 6)
                lines.append(f'<h{level} class="ct-L{min(level - 1, 3)}Sectionheader">{esc(heading.group(2))}</h{level}>')
                continue

            unordered = re.match(r"^[-*+]\s+(.+)$", stripped)
            ordered = re.match(r"^\d+[.)]\s+(.+)$", stripped)
            if unordered or ordered:
                flush_paragraph()
                wanted = "ul" if unordered else "ol"
                if list_type != wanted:
                    close_list()
                    list_type = wanted
                    lines.append(f"<{list_type}>")
                item = (unordered or ordered).group(1)
                lines.append(f"<li>{esc(item)}</li>")
                continue

            if not stripped:
                flush_paragraph()
                close_list()
                continue

            paragraph.append(stripped)

        flush_paragraph()
        close_list()
        if in_code:
            lines.append('<pre class="doc-license-text"><code>' + esc("\n".join(code_lines)) + '</code></pre>')

        return "\n".join(lines)

    # fn: render_project_document_page - Render project document page
    # . Purpose
    #   Render project document page for the documentation rendering workflow.
    #
    # . Arguments
    #   product_name  Value consumed by this function; see the typed Python signature for its contract.
    #   ref  Value consumed by this function; see the typed Python signature for its contract.
    #   letter  Value consumed by this function; see the typed Python signature for its contract.
    #   title  Value consumed by this function; see the typed Python signature for its contract.
    #   candidates  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_project_document_page(<product_name>, <ref>, <letter>, <title>, <candidates>)
    def render_project_document_page(
        self,
        product_name: str,
        ref: str,
        letter: str,
        title: str,
        candidates: Sequence[str],
    ) -> None:
        href = page_href_from_contentref(ref)
        output_file = self.output_dir / href
        output_file.parent.mkdir(parents=True, exist_ok=True)

        source_name, markdown_text = self.read_optional_project_document(candidates, product_name)
        body = self.render_markdown_document(markdown_text)
        if not body:
            body = (
                f'<div class="ct-documentbody">No {esc(source_name)} document was found in the renderer input directory.</div>'
            )

        label = f"Appendix {letter}: {title}"
        html_lines = [
            "<!doctype html>",
            "<html>",
            "<head>",
            '  <meta charset="utf-8">',
            f"  <title>{esc(label)}</title>",
            '  <link rel="stylesheet" href="../assets/doc.css">',
            '  <link rel="stylesheet" href="../assets/theme.css">',
            "</head>",
            "<body>",
            '<main class="doc-page">',
            self.render_page_branding(),
            '<header class="doc-page-header">',
            f'  <div class="doc-title">{esc(label)}</div>',
            f'  <div class="doc-breadcrumb">{esc(product_name)} / Appendices / {esc(label)}</div>',
            "</header>",
            body,
            "</main>",
            "</body>",
            "</html>",
        ]
        output_file.write_text("\n".join(html_lines), encoding="utf-8")

    # fn: render_canonical_page - Render canonical page
    # . Purpose
    #   Render canonical page for the documentation rendering workflow.
    #
    # . Arguments
    #   product_name  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_canonical_page(<product_name>)
    def render_canonical_page(self, product_name: str) -> None:
        self.render_project_document_page(
            product_name,
            canonical_ref(product_name),
            "0",
            "Unimatrix 01",
            (
                "SolidGroundUX-Canonical.md",
                "SolidGroundUX-Cannonical.md",
                "solidgroundux-canonical.md",
            ),
        )

    # fn: render_changelog_page - Render changelog page
    # . Purpose
    #   Render changelog page for the documentation rendering workflow.
    #
    # . Arguments
    #   product_name  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_changelog_page(<product_name>)
    def render_changelog_page(self, product_name: str) -> None:
        self.render_project_document_page(
            product_name,
            changelog_ref(product_name),
            "Y",
            "Change Log",
            ("CHANGELOG.md", "Changelog.md", "changelog.md"),
        )

    # fn: render_install_page - Render install page
    # . Purpose
    #   Render install page for the documentation rendering workflow.
    #
    # . Arguments
    #   product_name  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_install_page(<product_name>)
    def render_install_page(self, product_name: str) -> None:
        self.render_project_document_page(
            product_name,
            install_ref(product_name),
            "Z",
            "First Installation",
            ("INSTALL.md", "Install.md", "install.md"),
        )

    # fn: render_content_page - Render content page
    # . Purpose
    #   Render content page for the documentation rendering workflow.
    #
    # . Arguments
    #   node  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_content_page(<node>)
    def render_content_page(self, node: NavNode) -> None:
        href = page_href_from_contentref(node.contentref)
        output_file = self.output_dir / href
        output_file.parent.mkdir(parents=True, exist_ok=True)

        if is_item_node(node.nodetype) and node.node_title:
            title = node.node_title
        else:
            title = self.title_from_rows(node.contentref, node.node_title or node.node_name)
        
        breadcrumb = self.breadcrumb_from_contentref(node.contentref)

        if self.is_module_level_special_page(node):
            module_name = node.contentref.split(":", 1)[0]
            body = self.render_module_content(module_name, skip_first_header=True)
        else:
            body = self.render_content_for_ref(node.contentref, skip_first_header=True)

        if node.nodetype == "module":
            module_row = next(
                (module for module in self.mod_table if module.get("name", "") == node.node_name),
                None,
            )
            if module_row is not None and self.is_theme_module(module_row):
                specimen = self.render_theme_specimen(module_row)
                if specimen:
                    body = specimen + "\n" + body

        html_lines = [
            "<!doctype html>",
            "<html>",
            "<head>",
            '  <meta charset="utf-8">',
            f"  <title>{esc(title)}</title>",
            '  <link rel="stylesheet" href="../assets/doc.css">',
            '  <link rel="stylesheet" href="../assets/theme.css">',
            "</head>",
            "<body>",
            '<main class="doc-page">',
            self.render_page_branding(),
            '<header class="doc-page-header">',
            f'  <div class="doc-title">{esc(title)}</div>',
            f'  <div class="doc-breadcrumb">{esc(breadcrumb)}</div>',
            "</header>",
            body,
            "</main>",
            "</body>",
            "</html>",
        ]

        output_file.write_text("\n".join(html_lines), encoding="utf-8")

    # fn: render_content_page_for_ref - Render content page for ref
    # . Purpose
    #   Render content page for ref for the documentation rendering workflow.
    #
    # . Arguments
    #   ref  Value consumed by this function; see the typed Python signature for its contract.
    #   rows  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_content_page_for_ref(<ref>, <rows>)
    def render_content_page_for_ref(self, ref: str, rows: List[Row]) -> None:
        href = page_href_from_contentref(ref)
        output_file = self.output_dir / href
        output_file.parent.mkdir(parents=True, exist_ok=True)

        title = ref.split(":")[-1] or ref.split(":")[0] or "Documentation"
        for row in rows:
            content_type = row.get("contenttype", "")
            if content_type.endswith("header"):
                title = row.get("content", title) or title
                break

        body = self.render_content_for_ref(ref, skip_first_header=True)

        html_lines = [
            "<!doctype html>",
            "<html>",
            "<head>",
            '  <meta charset="utf-8">',
            f"  <title>{esc(title)}</title>",
            '  <link rel="stylesheet" href="../assets/doc.css">',
            '  <link rel="stylesheet" href="../assets/theme.css">',
            "</head>",
            "<body>",
            '<main class="doc-page">',
            self.render_page_branding(),
            '<header class="doc-page-header">',
            f'  <div class="doc-title">{esc(title)}</div>',
            f'  <div class="doc-breadcrumb">{esc(ref)}</div>',
            "</header>",
            body,
            "</main>",
            "</body>",
            "</html>",
        ]

        output_file.write_text("\n".join(html_lines), encoding="utf-8")

    # fn: breadcrumb_from_contentref - Breadcrumb from contentref
    # . Purpose
    #   Breadcrumb from contentref for the documentation rendering workflow.
    #
    # . Arguments
    #   ref  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.breadcrumb_from_contentref(<ref>)
    def breadcrumb_from_contentref(self, ref: str) -> str:
        parts = ref.split(":")
        while len(parts) < 5:
            parts.append("")

        module_name, grandparent_section, parent_section, section_name, item_name = parts[:5]

        breadcrumb_parts = [
            self.doc_product,
            module_name,
            grandparent_section,
            parent_section,
            section_name,
            item_name,
        ]

        return " / ".join(part for part in breadcrumb_parts if part)

    # fn: is_module_level_special_page - Determine whether module level special page
    # . Purpose
    #   Determine whether module level special page for the documentation rendering workflow.
    #
    # . Arguments
    #   node  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.is_module_level_special_page(<node>)
    def is_module_level_special_page(self, node: NavNode) -> bool:
        if node.nodetype not in {"preface", "epilogue", "documentation"}:
            return False

        parts = node.contentref.split(":")
        while len(parts) < 5:
            parts.append("")

        return bool(parts[0]) and not any(parts[1:5])

    # fn: render_module_content - Render module content
    # . Purpose
    #   Render module content for the documentation rendering workflow.
    #
    # . Arguments
    #   module_name  Value consumed by this function; see the typed Python signature for its contract.
    #   skip_first_header  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_module_content(<module_name>, <skip_first_header>)
    def render_module_content(self, module_name: str, skip_first_header: bool = False) -> str:
        rows = sorted(
            [row for row in self.doc_content_lines if row.get("file", "") == module_name],
            key=lambda row: (
                int(row.get("source_linenr", "0") or "0"),
                int(row.get("doc_linenr", "0") or "0"),
            ),
        )

        return self.render_rows(rows, skip_first_header=skip_first_header)

    # fn: is_images_marker - Determine whether images marker
    # . Purpose
    #   Determine whether images marker for the documentation rendering workflow.
    #
    # . Arguments
    #   row  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.is_images_marker(<row>)
    def is_images_marker(self, row: Row) -> bool:
        if (row.get("content", "") or "").strip().casefold() not in {"image", "images"}:
            return False
        return (row.get("stylehint", "normal") or "normal") in {"label", "highlight"}

    # fn: is_table_marker - Determine whether table marker
    # . Purpose
    #   Determine whether a documentation row starts a table block.
    #
    # . Arguments
    #   row  Documentation content row to inspect.
    # . Usage
    #   self.is_table_marker(<row>)
    def is_table_marker(self, row: Row) -> bool:
        if (row.get("content", "") or "").strip().casefold() not in {"table", "tables"}:
            return False
        return (row.get("stylehint", "normal") or "normal") in {"label", "highlight"}

    # fn: parse_table_row - Parse table row
    # . Purpose
    #   Split one double-colon-delimited documentation table row into cells.
    #
    # . Arguments
    #   value  Double-colon-delimited table row.
    # . Usage
    #   self.parse_table_row(<value>)
    def parse_table_row(self, value: str) -> List[str]:
        text = (value or "").strip()
        return [cell.strip() for cell in text.split("::")]

    # fn: is_endtable_marker - Determine whether end-table marker
    # . Purpose
    #   Determine whether a documentation row explicitly ends a table block.
    #
    # . Arguments
    #   row  Documentation content row to inspect.
    # . Usage
    #   self.is_endtable_marker(<row>)
    def is_endtable_marker(self, row: Row) -> bool:
        if (row.get("content", "") or "").strip().casefold() not in {"endtable", "endtables"}:
            return False
        return (row.get("stylehint", "normal") or "normal") in {"label", "highlight"}

    # fn: render_table - Render documentation table
    # . Purpose
    #   Render parsed documentation table rows using the standard data-table styling.
    #
    # . Arguments
    #   rows  Parsed table rows as (cells, stylehint); the first row is the header.
    # . Usage
    #   self.render_table(<rows>)
    def render_table(self, rows: Sequence[tuple[Sequence[str], str]]) -> str:
        if not rows:
            return ""

        column_count = max(len(cells) for cells, _style_hint in rows)
        normalized = [
            (list(cells) + [""] * (column_count - len(cells)), style_hint)
            for cells, style_hint in rows
        ]
        header, header_style = normalized[0]
        body = normalized[1:]

        def row_class(style_hint: str) -> str:
            if not style_hint or style_hint == "normal":
                return ""
            return f' class="{esc(f"sh-{style_hint}")}"'

        lines = [
            '<table class="doc-data-table">',
            f'<thead><tr{row_class(header_style)}>'
            + ''.join(f'<th>{esc(cell)}</th>' for cell in header)
            + '</tr></thead>',
        ]
        if body:
            lines.append('<tbody>')
            for cells, style_hint in body:
                lines.append(
                    f'<tr{row_class(style_hint)}>'
                    + ''.join(f'<td>{esc(cell)}</td>' for cell in cells)
                    + '</tr>'
                )
            lines.append('</tbody>')
        lines.append('</table>')
        return "\n".join(lines)

    # fn: parse_image_entry - Parse image entry
    # . Purpose
    #   Parse image entry for the documentation rendering workflow.
    #
    # . Arguments
    #   value  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.parse_image_entry(<value>)
    def parse_image_entry(self, value: str) -> tuple[str, str]:
        text = (value or "").strip()

        if "::" in text:
            source, caption = text.split("::", 1)
            return source.strip(), caption.strip()

        return text, ""

    # fn: image_source - Image source
    # . Purpose
    #   Image source for the documentation rendering workflow.
    #
    # . Arguments
    #   source  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.image_source(<source>)
    def image_source(self, source: str) -> str:
        clean_source = source.strip().replace("\\", "/")
        if re.match(r"^(?:https?:|data:|/)" , clean_source, flags=re.IGNORECASE):
            return clean_source
        if clean_source.startswith("assets/"):
            return f"../{clean_source}"
        return f"../assets/images/{clean_source}"

    # fn: render_image_group - Render image group
    # . Purpose
    #   Render image group for the documentation rendering workflow.
    #
    # . Arguments
    #   entries  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_image_group(<entries>)
    def render_image_group(self, entries: Sequence[tuple[str, str]]) -> str:
        valid_entries = [(source, caption) for source, caption in entries if source]
        if not valid_entries:
            return ""

        count_class = f"images-{min(len(valid_entries), 4)}"
        lines = [f'<div class="doc-image-group {count_class}">']

        for source, caption in valid_entries:
            alt_text = caption or Path(source).stem.replace("-", " ").replace("_", " ")
            lines.append('<figure class="doc-image">')
            lines.append(
                f'<img src="{esc(self.image_source(source))}" alt="{esc(alt_text)}" loading="lazy">'
            )
            if caption:
                lines.append(f'<figcaption>{esc(caption)}</figcaption>')
            lines.append('</figure>')

        lines.append('</div>')
        return "\n".join(lines)

    # fn: parse_alignment_row - Parse an aligned documentation row
    # . Purpose
    #   Split the renderer-owned <> alignment token into presentation columns.
    def parse_alignment_row(self, value: str) -> List[str]:
        return [cell.strip() for cell in (value or "").split("<>")]

    # fn: render_alignment_block - Render aligned documentation rows
    # . Purpose
    #   Align corresponding <> columns across consecutive documentation lines.
    def render_alignment_block(self, rows: Sequence[Row]) -> str:
        parsed = [self.parse_alignment_row(row.get("content", "") or "") for row in rows]
        if not parsed:
            return ""
        column_count = max(len(cells) for cells in parsed)
        template = " ".join(["max-content"] * max(0, column_count - 1) + ["minmax(0, 1fr)"])
        lines = [f'<div class="doc-aligned-block" style="grid-template-columns:{esc(template)}">']
        for row, cells in zip(rows, parsed):
            cells = cells + [""] * (column_count - len(cells))
            style_hint = row.get("stylehint", "normal") or "normal"
            content_type = row.get("contenttype", "documentbody") or "documentbody"
            classes = [f"ct-{content_type}", "doc-aligned-cell"]
            if style_hint != "normal":
                classes.append(f"sh-{style_hint}")
            for cell_index, cell in enumerate(cells):
                cell_classes = list(classes)
                if cell_index == column_count - 1:
                    cell_classes.append("doc-aligned-last")
                lines.append(f'<div class="{esc(" ".join(cell_classes))}">{esc(cell)}</div>')
        lines.append('</div>')
        return "\n".join(lines)

    # fn: is_flowing_prose_row - Determine whether flowing prose row
    # . Purpose
    #   Return True when a row may be reflowed into a logical paragraph.
    #
    # . Arguments
    #   row  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.is_flowing_prose_row(<row>)
    def is_flowing_prose_row(self, row: Row) -> bool:
        """Return True when a row may be reflowed into a logical paragraph."""
        if row.get("suppress", "0") == "1":
            return False

        content_type = row.get("contenttype", "documentbody") or "documentbody"
        style_hint = row.get("stylehint", "normal") or "normal"
        content = row.get("content", "") or ""

        if not content_type.endswith("body"):
            return False
        if style_hint != "normal":
            return False
        if not content.strip():
            return False

        # Leading whitespace is intentional author formatting: examples, trees,
        # command lines, diagrams, and aligned blocks must remain line-oriented.
        if content[:1].isspace():
            return False

        # Preserve common source-level list/code forms even when they were not
        # explicitly marked with a style hint.
        if re.match(r"^(?:[-*+]\s+|\d+[.)]\s+|```|~~~|[$>]\s)", content):
            return False

        return True

    # fn: render_rows - Render rows
    # . Purpose
    #   Render rows for the documentation rendering workflow.
    #
    # . Arguments
    #   rows  Value consumed by this function; see the typed Python signature for its contract.
    #   skip_first_header  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_rows(<rows>, <skip_first_header>)
    def render_rows(self, rows: Sequence[Row], skip_first_header: bool = False) -> str:
        lines: List[str] = []
        skipped_first_header = False
        index = 0

        while index < len(rows):
            row = rows[index]

            if row.get("suppress", "0") == "1":
                index += 1
                continue

            content_type = row.get("contenttype", "documentbody") or "documentbody"
            if skip_first_header and not skipped_first_header and content_type.endswith("header"):
                skipped_first_header = True
                index += 1
                continue

            if self.is_table_marker(row):
                table_rows: List[tuple[List[str], str]] = []
                index += 1

                while index < len(rows):
                    table_row = rows[index]
                    if table_row.get("suppress", "0") == "1":
                        index += 1
                        continue

                    if self.is_endtable_marker(table_row):
                        index += 1
                        break

                    table_content = table_row.get("content", "") or ""
                    table_style = table_row.get("stylehint", "normal") or "normal"

                    # Keep blank-line termination for compatibility with existing documents.
                    if not table_content.strip():
                        index += 1
                        break
                    if table_row.get("contenttype", "") != content_type:
                        break

                    # Style hints describe the row; they do not affect table membership.
                    table_rows.append((self.parse_table_row(table_content), table_style))
                    index += 1

                table_html = self.render_table(table_rows)
                if table_html:
                    lines.append(table_html)
                continue

            if self.is_images_marker(row):
                entries: List[tuple[str, str]] = []
                index += 1

                while index < len(rows):
                    image_row = rows[index]
                    if image_row.get("suppress", "0") == "1":
                        index += 1
                        continue

                    image_content = image_row.get("content", "") or ""
                    image_style = image_row.get("stylehint", "normal") or "normal"

                    if not image_content.strip():
                        index += 1
                        break
                    if image_style != "normal" or image_row.get("contenttype", "") != content_type:
                        break

                    entries.append(self.parse_image_entry(image_content))
                    index += 1

                image_html = self.render_image_group(entries)
                if image_html:
                    lines.append(image_html)
                continue

            # <> is a renderer-owned alignment token. Consecutive rows containing it
            # form one grid so corresponding columns share one browser-calculated width.
            if "<>" in (row.get("content", "") or ""):
                alignment_rows: List[Row] = []
                alignment_content_type = content_type
                while index < len(rows):
                    alignment_row = rows[index]
                    if alignment_row.get("suppress", "0") == "1":
                        index += 1
                        continue
                    if (alignment_row.get("contenttype", "documentbody") or "documentbody") != alignment_content_type:
                        break
                    if "<>" not in (alignment_row.get("content", "") or ""):
                        break
                    alignment_rows.append(alignment_row)
                    index += 1
                alignment_html = self.render_alignment_block(alignment_rows)
                if alignment_html:
                    lines.append(alignment_html)
                continue

            if self.is_flowing_prose_row(row):
                paragraph_parts = [(row.get("content", "") or "").strip()]
                index += 1

                while index < len(rows):
                    next_row = rows[index]

                    if next_row.get("suppress", "0") == "1":
                        index += 1
                        continue
                    if self.is_images_marker(next_row):
                        break
                    if not self.is_flowing_prose_row(next_row):
                        break
                    if (next_row.get("contenttype", "documentbody") or "documentbody") != content_type:
                        break

                    paragraph_parts.append((next_row.get("content", "") or "").strip())
                    index += 1

                css_class = f"ct-{content_type}"
                paragraph = " ".join(part for part in paragraph_parts if part)
                lines.append(f'<p class="{esc(css_class)}">{esc(paragraph)}</p>')
                continue

            style_hint = row.get("stylehint", "normal") or "normal"
            content = row.get("content", "")

            classes = [f"ct-{content_type}"]
            if style_hint != "normal":
                classes.append(f"sh-{style_hint}")

            css_class = " ".join(classes)
            lines.append(f'<div class="{esc(css_class)}">{esc(content)}</div>')
            index += 1

        return "\n".join(lines)

    # fn: render_content_for_ref - Render content for ref
    # . Purpose
    #   Render content for ref for the documentation rendering workflow.
    #
    # . Arguments
    #   ref  Value consumed by this function; see the typed Python signature for its contract.
    #   skip_first_header  Value consumed by this function; see the typed Python signature for its contract.
    # . Usage
    #   self.render_content_for_ref(<ref>, <skip_first_header>)
    def render_content_for_ref(self, ref: str, skip_first_header: bool = False) -> str:
        return self.render_rows(self.content_by_ref.get(ref, []), skip_first_header=skip_first_header)


# fn: main - Run documentation renderer
# . Purpose
#   Run documentation renderer for the documentation rendering workflow.
#
# . Arguments
#   argv  Value consumed by this function; see the typed Python signature for its contract.
# . Usage
#   main(<argv>)
def main(argv: Sequence[str]) -> int:
    if len(argv) != 3:
        print("Usage: python3 sgnd_doc_renderer.py <input-dir> <output-dir>", file=sys.stderr)
        return 2

    input_dir = Path(argv[1]).resolve()
    output_dir = Path(argv[2]).resolve()

    try:
        renderer = DocRenderer(input_dir, output_dir)
        renderer.run()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
