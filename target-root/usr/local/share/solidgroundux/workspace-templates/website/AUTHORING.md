# Website authoring

This project is a source website for SolidGroundUX MCM 55 - Web Content Management.

Write pages in `www/content/` as Markdown. Give each content file a descriptive name
ending in a language suffix, such as `my-article_NL.md`. Use
`sectionname_Index_NL.md` for sections, and keep the homepage at the root of
`www/content/`. The root home page is included in this starter.

Each Markdown page starts with metadata:

```markdown
---
title: Example page
summary: Short explanation of the page.
template: page
draft: false
---

Content goes here.
```

The starter has one Dutch homepage (`NL`). To introduce another language,
create its corresponding root `*_Index_XX.md` page. The generator discovers
languages from these root files.

Styles belong in `www/css/`. Page structure belongs in `www/templates/`.
Edit `www/config/site.cfg` to set the website title, canonical `base_url`,
and default language; add your own branding as needed.

## Workflow

Use MCM Web Content Management with the source directory set to `www/`:

1. Validate the source.
2. Generate public HTML to `public/` (or preview HTML to `public-preview/`).
3. Review the generated HTML.
4. Use **Publish Website** for the public output, selecting the remote Nginx
   website or creating one if needed.

The SDK template does not generate HTML or install Nginx. Preview output may
contain draft pages and must never be published publicly.
