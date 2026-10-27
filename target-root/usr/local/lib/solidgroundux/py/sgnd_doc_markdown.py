#!/usr/bin/env python3
"""Generate a WCM Markdown source repository from a saved documentation bundle.

This generator does not import or alter WCM. It emits its documented source layout.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from collections import Counter
from pathlib import Path

DECL = re.compile(r'^\s*#\s+(fn\$?|cls|var|mod|exe|lib|doc)(:|\$)\s+([A-Za-z_][\w.:-]*)(?:\s+-\s+(.+))?\s*$')
FIELD = re.compile(r'^\s*#\s*\.\s+(.+?)\s*$')
COMMENT = re.compile(r'^\s*#(?: ?)(.*)$')
SECTION = re.compile(r'^\s*#\s(-{1,3})\s+(.+?)\s*$')
HEADER_TITLE = re.compile(r'^#\s+([^-]+?)\s+-\s+(.+?)\s*$')
META = re.compile(r'^\s*#\s*(Version|Build|Purpose|Description|Group|Subgroup|Title)\s*:\s*(.*?)\s*$', re.I)
IDENTITY = re.compile(r'[^a-z0-9]+')
SKIP_DIRS = {'.git', '.cache', '__pycache__', 'node_modules', '.venv', 'venv', 'www-html', 'www-md'}


def slug(value: str) -> str:
    return IDENTITY.sub('-', value.lower()).strip('-') or 'untitled'


def front(title: str, order: int = 1000, summary: str = '', *, section: bool = True, template: str = 'page') -> str:
    values = {'title': title, 'nav_title': title, 'summary': summary, 'template': template,
              'content_type': 'section' if section else 'page', 'nav_order': order,
              'draft': False, 'featured': False}
    return '---\n' + '\n'.join(f'{key}: {json.dumps(value, ensure_ascii=False)}' if isinstance(value, str)
                              else f'{key}: {str(value).lower() if isinstance(value, bool) else value}'
                              for key, value in values.items()) + '\n---\n\n'


def write_index(folder: Path, title: str, body: str, order: int = 1000, summary: str = '', template: str = 'page') -> None:
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f'{slug(title)}_Index_NL.md').write_text(front(title, order, summary, template=template) + body.strip() + '\n', encoding='utf-8')


def _section_marker(text: str, inside_item: bool, in_fence: bool):
    """Recognize old section headers, but never reinterpret Markdown lists."""
    if in_fence:
        return None
    m = SECTION.match(text)
    if not m:
        return None
    marks, label = m.groups()
    # A dashed divider unambiguously identifies the old section syntax.
    ruled = re.search(r'\s-{4,}\s*$', label)
    if ruled:
        label = label[:ruled.start()].strip()
    elif inside_item:
        # Within a documentation item, '# - ...' is ordinary Markdown.
        return None
    if not label or label.startswith(('-', '*', '[', '!')):
        return None
    title = label.split(':', 1)[1].strip() if ':' in label else label
    return {'kind': 'section', 'name': label, 'title': title,
            'level': len(marks), 'lines': []}


def parse_source(path: Path):
    """Extract documented items and Markdown while preserving source comment blocks."""
    lines = path.read_text(encoding='utf-8', errors='replace').splitlines()
    meta = {}
    for line in lines[:100]:
        m = META.match(line)
        if m and m.group(1).lower() not in meta:
            meta[m.group(1).lower()] = m.group(2)
    for line in lines[:30]:
        m = HEADER_TITLE.match(line)
        if m and 'title' not in meta:
            meta['title'] = m.group(2).strip()
            break

    entries = []
    current = None
    fence = False
    in_header = True
    header_category = ''
    header_narrative = []
    in_code = False
    for line in lines:
        comment = COMMENT.match(line)
        if not comment:
            if line.strip() and not line.lstrip().startswith('#'):
                in_header = False
                in_code = True
                current = None
                fence = False
            continue
        value = comment.group(1).rstrip()
        stripped = value.strip()
        # A Markdown code fence owns everything through its closing fence.
        if stripped.startswith(('```', '~~~')):
            fence = not fence
            if current:
                current['lines'].append(value)
            elif in_header or header_category:
                header_narrative.append(value)
            continue

        if not fence:
            decl = DECL.match(line)
            if decl:
                kind, marker, name, short = decl.groups()
                current = {'kind': kind + ('$' if marker == '$' else ''),
                           'name': name, 'title': (short or name).strip(), 'lines': []}
                entries.append(current)
                in_header = False
                in_code = False
                continue
            section = _section_marker(line, inside_item=current is not None and current['kind'] != 'section', in_fence=fence)
            if section and (current is None or current['kind'] == 'section' or re.search(r'\s-{4,}\s*$', stripped)):
                entries.append(section)
                current = section
                in_header = False
                in_code = False
                continue

        if current is not None:
            # Field headers are legacy structural markup, not Markdown paragraphs.
            field = FIELD.match(line) if not fence else None
            if field:
                current['lines'].extend(['', '### ' + field.group(1).strip(), ''])
            else:
                current['lines'].append(value)
            continue

        if in_header:
            # Retain free-form header descriptions, but not scaffolding or raw metadata.
            if re.match(r'^[-=]{6,}$', stripped):
                continue
            category = re.match(r'^(Description|Design principles|Role in framework|Non-goals|Documentation|Introduction|Overview):\s*$', stripped, re.I)
            if category:
                header_category = category.group(1)
                header_narrative.extend(['', '## ' + header_category, ''])
                continue
            if META.match(line) or HEADER_TITLE.match(line):
                continue
            if re.match(r'^(Metadata|Attribution):\s*$', stripped, re.I):
                header_category = ''
                continue
            if header_category:
                header_narrative.append(value)
        elif not in_code and stripped and (stripped.startswith(('>', '|', '#', ':::', '![', '[', '*', '-'))):
            # Standalone documentation outside structured items.
            header_narrative.append(value)
    if any(line.strip() for line in header_narrative):
        entries.insert(0, {'kind': 'narrative', 'name': '', 'title': '', 'lines': header_narrative})
    return meta, entries, len(lines)



IMAGE_HEADING = re.compile(r"^\s*(?:(?:\#{1,6}|[.:])\s*)?Images?\s*$", re.I)
IMAGE_ITEM = re.compile(r"^\s*(.+?\.(?:png|jpe?g|gif|svg|webp|avif))(?:\s*::\s*(.*))?\s*$", re.I)


def markdown_documentation(lines: list[str]) -> list[str]:
    """Translate legacy Images blocks, preserving all other Markdown lines."""
    result = []
    index = 0
    while index < len(lines):
        line = lines[index]
        normalized = line.strip()
        if IMAGE_HEADING.fullmatch(normalized):
            cursor = index + 1
            while cursor < len(lines) and not lines[cursor].strip():
                cursor += 1
            images = []
            while cursor < len(lines):
                next_line = lines[cursor].strip()
                if not next_line:
                    break
                match = IMAGE_ITEM.fullmatch(next_line)
                if not match:
                    break
                name, caption = match.groups()
                name = name.strip()
                alt = (caption or Path(name).stem.replace('-', ' ').replace('_', ' ')).strip()
                if name.startswith(('http://', 'https://', 'data:', '/')):
                    url = name
                elif name.startswith(('assets/', 'images/')):
                    url = '/' + name
                else:
                    url = '/images/' + name
                images.append(f'![{alt}]({url})')
                cursor += 1
            if images:
                result.extend([''] + images + [''])
                index = cursor
                continue
        result.append(line)
        index += 1
    return result


def append_preface(target: list[str], entries: list[dict]) -> None:
    for entry in entries:
        if entry['kind'] == 'section':
            target.extend(['#' * min(entry['level'] + 2, 6) + ' ' + entry['title'], ''])
        elif entry['kind'] not in ('narrative',):
            target.extend(['### ' + entry['title'], ''])
        target.extend(markdown_documentation(entry['lines']))
        target.append('')


def copy_legacy_images(source: Path, root: Path) -> None:
    """Use the original product asset location and the existing doc-sources locations."""
    candidates = [source / 'usr/local/assets', source / 'target-root/usr/local/assets',
                  source / 'doc-sources/assets', source / 'usr/local/share/doc-sources/assets',
                  source / 'target-root/usr/local/share/doc-sources/assets']
    for directory in candidates:
        if not directory.is_dir():
            continue
        for asset in directory.rglob('*'):
            if not asset.is_file() or asset.suffix.lower() not in ('.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp', '.avif'):
                continue
            target = root / 'images' / asset.name
            if target.exists() and target.read_bytes() != asset.read_bytes():
                raise ValueError(f'Image filename conflict: {asset.name} (from {directory})')
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(asset, target)


def copy_assets_checked(source: Path, destination: Path) -> None:
    """Merge resource trees without silently replacing different files."""
    if not source.is_dir():
        return
    for file in sorted(source.rglob('*')):
        if not file.is_file():
            continue
        target = destination / file.relative_to(source)
        if target.exists():
            if target.read_bytes() != file.read_bytes():
                raise ValueError(f'Conflicting resource: {target} (from {file})')
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(file, target)


def missing_image_references(root: Path) -> list[str]:
    """Report unresolved local Markdown images without rejecting documentary examples."""
    image = re.compile(r'!\[[^\]]*\]\(([^)]+)\)')
    unresolved = set()
    for document in (root / 'content').rglob('*.md'):
        body = document.read_text(encoding='utf-8')
        for match in image.finditer(body):
            target = match.group(1).strip().split(' "', 1)[0].strip('<>')
            if not target or target.startswith(('http://', 'https://', 'data:', '#')):
                continue
            path = target.split('#', 1)[0].split('?', 1)[0]
            if path.startswith('/'):
                local = root / path.lstrip('/')
            else:
                local = document.parent / path
            if not local.is_file():
                unresolved.add(f'{document.relative_to(root)}: {target}')
    return sorted(unresolved)


def declaration_template(kind: str) -> str:
    if kind.startswith('fn'):
        return 'function'
    if kind == 'var':
        return 'variable'
    if kind == 'cls':
        return 'class'
    return 'declaration'


def source_document_template(filename: str) -> str:
    name = filename.casefold().replace('_', '-')
    if 'preface' in name:
        return 'preface'
    if 'epilogue' in name:
        return 'epilogue'
    return 'source'

def directory_title(path: Path):
    return path.name.replace('-', ' ').replace('_', ' ').strip().title()


def collect(product, content: Path, order: int, counters: Counter):
    """Use source metadata Group/Subgroup, never installation directories, for navigation."""
    source = Path(product['source_dir']).expanduser().resolve()
    if not source.is_dir():
        raise ValueError(f'Missing source directory: {source}')
    product_folder = content / slug(product['id'])
    write_index(product_folder, product['title'], f'# {product["title"]}\n', order, template='chapter')
    paths = sorted(p for p in source.rglob('*.sh') if p.is_file() and not any(part in SKIP_DIRS for part in p.relative_to(source).parts))
    records = []
    for path in paths:
        metadata, entries, loc = parse_source(path)
        records.append((path, metadata, entries, loc))
    # Legacy renderer sorted groups and subgroups alphabetically, within each product.
    groups = sorted({metadata.get('group', '').strip() or 'Ungrouped' for _, metadata, _, _ in records}, key=str.casefold)
    route_names = set()
    special_pages = {}
    for group_index, group in enumerate(groups, 1):
        group_folder = product_folder / slug(group)
        group_body = [f'# {group}', '']
        write_index(group_folder, group, '\n'.join(group_body), group_index, template='group')
        group_records = [r for r in records if (r[1].get('group', '').strip() or 'Ungrouped') == group]
        subgroup_names = sorted({r[1].get('subgroup', '').strip() for r in group_records if r[1].get('subgroup', '').strip()}, key=str.casefold)
        for subgroup_index, subgroup in enumerate(subgroup_names, 1):
            subfolder = group_folder / slug(subgroup)
            write_index(subfolder, subgroup, f'# {subgroup}\n', subgroup_index, template='group')
        for path, metadata, entries, loc in group_records:
            subgroup = metadata.get('subgroup', '').strip()
            parent = group_folder / slug(subgroup) if subgroup else group_folder
            rel = path.relative_to(source)
            # Defer prefaces/epilogues until every source is discovered, preserving
            # source ordering and placing introductions before closing material.
            special = source_document_template(path.name)
            if special in ('preface', 'epilogue'):
                section_folder = parent
                special_pages.setdefault(section_folder, {'preface': [], 'epilogue': []})[special].append(entries)
                counters['files'] += 1
                counters['lines'] += loc
                continue
            # A source is a section with its own overview and declaration pages.
            basename = slug(path.stem)
            source_folder = parent / basename
            if source_folder in route_names:
                source_folder = parent / slug(str(rel.with_suffix('')))
            if source_folder in route_names or source_folder.exists():
                raise ValueError(f'Route collision: {rel} -> {source_folder}')
            route_names.add(source_folder)
            counters['files'] += 1
            counters['lines'] += loc
            counters['functions'] += sum(e['kind'].startswith('fn') for e in entries)
            counters['declarations'] += sum(e['kind'] not in ('section', 'narrative') for e in entries)
            for key in ('version', 'build'):
                if metadata.get(key) and not counters.get(key):
                    counters[key] = metadata[key]
            title = metadata.get('title') or path.stem.replace('-', ' ')
            introduction = [f'# {title}', '', f'**Source:** `{rel.as_posix()}`', '']
            if metadata.get('purpose'):
                introduction += [metadata['purpose'], '']
            if metadata.get('description'):
                introduction += [metadata['description'], '']
            # Section headings belong to the source index; declarations get pages.
            # Relative links target the WCM page route (not the Markdown filename).
            used_names = set()
            declaration_number = 0
            for entry in entries:
                kind = entry['kind']
                if kind == 'narrative':
                    introduction += markdown_documentation(entry['lines']) + ['']
                    continue
                if kind == 'section':
                    introduction += ['#' * min(2 + entry['level'], 6) + ' ' + entry['title'], '']
                    introduction += markdown_documentation(entry['lines']) + ['']
                    continue
                declaration_number += 1
                template = declaration_template(kind)
                page_name = slug(entry['name'])
                if page_name in used_names:
                    page_name = f'{page_name}-{declaration_number}'
                used_names.add(page_name)
                declaration_path = source_folder / f'{page_name}_NL.md'
                body = [f'# {entry["title"]}', '', f'`{kind}: {entry["name"]}`', '']
                body += markdown_documentation(entry['lines'])
                declaration_path.parent.mkdir(parents=True, exist_ok=True)
                declaration_path.write_text(
                    front(entry['title'], declaration_number, template=template, section=False)
                    + '\n'.join(body).strip() + '\n', encoding='utf-8')
                introduction.append(f'- [{entry["title"]}]({page_name}/)')
            if not entries:
                introduction += ['No documentation comments found in source.', '']
            source_template = source_document_template(path.name)
            write_index(source_folder, title, '\n'.join(introduction),
                        summary=metadata.get('purpose', ''), template=source_template)
    for section_folder, specials in special_pages.items():
        index_files = list(section_folder.glob('*_Index_NL.md'))
        if len(index_files) != 1:
            raise ValueError(f'Expected one section index in {section_folder}')
        index_file = index_files[0]
        existing = index_file.read_text(encoding='utf-8')
        front_end = existing.find('\n---\n', 4)
        if front_end < 0:
            raise ValueError(f'Invalid index front matter: {index_file}')
        prefix, body = existing[:front_end + len('\n---\n')], existing[front_end + len('\n---\n'):]
        intro, closing = [], []
        for entries in specials['preface']:
            append_preface(intro, entries)
        for entries in specials['epilogue']:
            append_preface(closing, entries)
        index_file.write_text(prefix + '\n' + '\n'.join(intro) + '\n' + body + '\n' + '\n'.join(closing), encoding='utf-8')
    return len(paths)


def generate(bundle: dict, docs_root: Path | None = None) -> dict:
    output = Path(bundle['output_dir']).expanduser().resolve()
    if not output.is_absolute() or output == Path('/'):
        raise ValueError('Invalid output directory')
    products = bundle.get('products', [])
    if len({slug(item['id']) for item in products}) != len(products):
        raise ValueError('Product identifiers generate duplicate routes')
    if not products:
        raise ValueError('Bundle has no products')
    for product in products:
        src = Path(product['source_dir']).expanduser().resolve()
        if not src.is_dir():
            raise ValueError(f'Missing source directory: {src}')
        if output == src or src in output.parents:
            raise ValueError('Output directory must not be within a source directory')
    if bundle.get('overwrite', 'replace') not in ('fail', 'replace'):
        raise ValueError('Overwrite policy must be fail or replace')
    if output.exists() and bundle.get('overwrite', 'replace') == 'fail':
        raise ValueError(f'Output already exists: {output}')
    # Generate away from the final directory so a failure leaves the previous site intact.
    import tempfile
    with tempfile.TemporaryDirectory(prefix='sgnd-doc-') as staging:
        root = Path(staging) / 'website'
        content = root / 'content'
        (root / 'config').mkdir(parents=True)
        (root / 'assets').mkdir()
        (root / 'images').mkdir()
        (root / 'css').mkdir()
        (root / 'templates').mkdir()
        (root / 'config' / 'site.cfg').write_text(
            f'[site]\ntitle = {bundle.get("title", bundle["id"])}\ndefault_language = NL\n'
            '[paths]\ncontent = content\ntemplates = templates\ncss = css\nimages = images\n', encoding='utf-8')
        counts = Counter()
        counts['products'] = len(products)
        for i, product in enumerate(products, 1):
            collect(product, content, i, counts)
        # Images referenced by comments belong to each product source tree.
        # Keep /assets/... links valid without depending on an external website.
        for product in products:
            copy_legacy_images(Path(product['source_dir']).expanduser().resolve(), root)
            asset_dir = Path(product['source_dir']).expanduser().resolve() / 'assets'
            copy_assets_checked(asset_dir, root / 'assets')
        chapter0 = bundle.get('chapter0', '')
        if chapter0:
            custom = Path(chapter0)
            if not custom.is_file():
                raise ValueError(f'Chapter 0 Markdown missing: {custom}')
            preface = custom.read_text(encoding='utf-8')
        else:
            preface = ('# ' + bundle.get('title', bundle['id']) + '\n\n'
                       + '\n'.join(f'- **{label}:** {counts.get(key, 0)}' for label, key in
                                   [('Products', 'products'), ('Source files', 'files'),
                                    ('Functions', 'functions'), ('Declarations', 'declarations'),
                                    ('Lines of code and comments', 'lines')]))
            for key in ('version', 'build'):
                if counts.get(key):
                    preface += f'\n- **{key.title()}:** {counts[key]}'
        write_index(content, bundle.get('title', bundle['id']), preface, 0, template='home')
        # Bundle defaults are supplied by the SDK documentation resources.
        # Product resources are scoped to their chapter; no product can overwrite
        # another chapter's templates or the bundle-wide defaults.
        if docs_root:
            for resource in ('assets', 'css', 'templates', 'images'):
                if (docs_root / resource).is_dir():
                    if resource in ('assets', 'images'):
                        copy_assets_checked(docs_root / resource, root / resource)
                    else:
                        shutil.copytree(docs_root / resource, root / resource, dirs_exist_ok=True)
        for product in products:
            source_root = Path(product['source_dir']).expanduser().resolve()
            chapter = slug(product['id'])
            for candidate in (source_root / 'doc-sources', source_root / 'usr/local/share/doc-sources',
                              source_root / 'target-root/usr/local/share/doc-sources'):
                if not candidate.is_dir():
                    continue
                custom_templates = candidate / 'templates'
                if custom_templates.is_dir():
                    shutil.copytree(custom_templates, root / 'templates' / chapter, dirs_exist_ok=True)
                for resource in ('assets', 'css', 'images'):
                    if (candidate / resource).is_dir():
                        if resource in ('assets', 'images'):
                            copy_assets_checked(candidate / resource, root / resource)
                        else:
                            shutil.copytree(candidate / resource, root / resource, dirs_exist_ok=True)
        required = ('base.html', 'home.html', 'page.html', 'article.html')
        missing = [name for name in required if not (root / 'templates' / name).is_file()]
        if missing:
            raise ValueError('Missing default documentation templates in doc-sources/templates: ' + ', '.join(missing))
        image_warnings = missing_image_references(root)
        if output.exists():
            shutil.rmtree(output)
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(root), str(output))
    return {'bundle': bundle['id'], 'output': str(output), **counts, 'missing_images': len(image_warnings), 'image_warnings': image_warnings}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', help='Saved bundle identifier')
    parser.add_argument('--store', default=str(Path.home() / '.config/solidgroundux/documentation-bundles'))
    parser.add_argument('--doc-sources', help='Optional documentation resources directory')
    args = parser.parse_args()
    try:
        name = args.bundle.replace(' ', '-')
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', name):
            raise ValueError('Invalid bundle identifier')
        data = json.loads((Path(args.store) / (name + '.json')).read_text(encoding='utf-8'))
        if data.get('id') != name or data.get('schema') != 1:
            raise ValueError('Invalid saved bundle')
        print(json.dumps(generate(data, Path(args.doc_sources) if args.doc_sources else None), ensure_ascii=False, indent=2, default=str))
        return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
