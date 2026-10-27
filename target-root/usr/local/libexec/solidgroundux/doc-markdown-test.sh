#!/usr/bin/env bash
# Title: Documentation Markdown Test
# Purpose: Visual regression fixture for the SolidGroundUX source-to-Markdown generator.
# Version: 1.0
# Build: test-fixture
#
# fn: sgnd_doc_markdown_test - Markdown and WCM component showcase
# . Purpose
# This is **ordinary Markdown** embedded in Bash comments.
# It tests the documentation parser and the unchanged WCM renderer.
#
# . Headings and typography
# # Heading level 1
# ## Heading level 2
# ### Heading level 3
# #### Heading level 4
# ##### Heading level 5
# ###### Heading level 6
#
# Regular text with **bold**, *italic*, ~~strikethrough~~, and `inline code`.
#
# > This is a blockquote. It should have its own styling.
#
# ---
#
# . Lists
# - First bullet
# - Second bullet
#   - Nested bullet
# - Third bullet
#
# 1. First step
# 2. Second step
# 3. Third step
#
# . Tables
# | Feature | Expected result | Status |
# |:--------|:----------------|-------:|
# | Heading | Six levels | 6 |
# | Colors  | Styled spans | 4 |
# | Images  | Local files | 3 |
#
# . Links and colors
# [SolidGroundUX](https://github.com/Testadura-Consultancy/SolidGroundUX) is a normal link.
#
# [Green text]{.td-green}, [red text]{.td-red}, [blue text]{.td-blue},
# and [yellow text]{.td-yellow} exercise WCM inline style classes.
#
# . Images
# The images below are provided in the accompanying `assets` directory.
# Asset paths are written as website-root URLs. Confirm that the generator
# copies them to the same root-relative locations.
#
# ![Blue sample card](/assets/test-blue.svg){width=320}
# ![Green sample card](/assets/test-green.svg){width=240}
#
# . Image and text component
# ::: td-image-text /assets/test-red.svg right width=240
# ### Image next to text
# This block checks the custom **td-image-text** component.
# Its image should appear to the right of this descriptive text.
# :::
#
# . Callouts
# ::: td-note
# **Note:** This text should appear in the note component.
# :::
#
# ::: td-warning
# **Warning:** This text should appear in the warning component.
# :::
#
# ::: td-technical
# **Technical:** This text should appear in the technical component.
# :::
#
# . Tiles and grids
# ::: td-grid
# ::: td-tile
# ### First tile
# ![Blue sample](/assets/test-blue.svg){width=160}
# This is the **first** tile.
# :::
# ::: td-tile
# ### Second tile
# ![Green sample](/assets/test-green.svg){width=160}
# This is the *second* tile.
# :::
# ::: td-tile
# ### Third tile
# ![Red sample](/assets/test-red.svg){width=160}
# This is the third tile.
# :::
# :::
#
# . Slider and gallery
# The slider below contains three tiles. Check scrolling/arrow behavior
# according to the currently installed WCM theme.
#
# ::: td-slider
# ::: td-tile
# ### Slide one
# ![Blue slide](/assets/test-blue.svg)
# :::
# ::: td-tile
# ### Slide two
# ![Green slide](/assets/test-green.svg)
# :::
# ::: td-tile
# ### Slide three
# ![Red slide](/assets/test-red.svg)
# :::
# :::
#
# ::: td-gallery
# ![Gallery blue](/assets/test-blue.svg)
# ![Gallery green](/assets/test-green.svg)
# ![Gallery red](/assets/test-red.svg)
# :::
#
# . Expandable details
# ::: td-details Show additional information
# This content should be hidden until the details element is opened.
#
# - A nested list item
# - Another nested list item
# :::
#
# . Code blocks
# ```bash
# # This is displayed as documentation; it is not executed.
# printf '%s\n' 'Hello from Markdown'
# ```
#
# ```python
# print('Python syntax highlighting sample')
# ```
#
# . Final check
# If the Markdown output preserves all examples above, but the HTML website
# renders them incorrectly, the remaining issue is in WCM or its styling,
# not necessarily in source-comment extraction.

sgnd_doc_markdown_test() {
    # Safe no-op: this executable is a documentation fixture, not a test runner.
    return 0
}

# Do not execute anything when sourced or run.
