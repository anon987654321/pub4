# LLM-safe frontend restoration rules

These rules apply to all restored Rails apps under `DEPLOY/rails`.

## Core rule

Large HTML/ERB files with inline CSS, JavaScript, SVG, Chart.js, or animations must be split into external tracked files before further LLM editing.

Do not ask a model to rewrite large mixed HTML/CSS/JS documents unless the requested output is a minimal unified diff.

## Required separation

- ERB/HTML structure: `app/views/...`
- SCSS/CSS: `app/assets/stylesheets/...` or app frontend stylesheet path
- Stimulus controllers: `app/javascript/controllers/...`
- Chart configuration: `app/javascript/charts/...`
- Chart data: separate JSON or JS data file
- Animations/keyframes: dedicated SCSS/CSS file
- Font declarations: dedicated SCSS/CSS file
- SVG icons: partials or external assets

## Preservation rules

When restoring old assets:

1. Preserve exact old SCSS/CSS where a source stylesheet exists.
2. If styling only exists inline in an old shell script or ERB block, extract it verbatim into a named stylesheet first.
3. Do not normalize, modernize, minify, or rename classes during extraction.
4. Do not remove vendor prefixes during extraction.
5. Do not collapse custom animations into generic transitions.
6. Do not replace CSS variables with hardcoded values.
7. Do not alter Chart.js options while editing chart data.
8. Do not edit files marked `PROTECTED` unless explicitly requested.
9. Prefer additive classes over modifying old classes.
10. Use unified diffs for surgical edits to large view/style files.

## Protected section markers

Use comments like these around fragile restored sections:

```erb
<%# BEGIN PROTECTED CHARTJS: do not modify without explicit chart task %>
<canvas id="revenue_chart"></canvas>
<%# END PROTECTED CHARTJS %>
```

```scss
/* BEGIN PROTECTED ANIMATIONS: restored from old pub source */
/* END PROTECTED ANIMATIONS */
```

## Typography baseline

- Body line length: 45-75 characters, ideal 66ch.
- Mobile line length: 35-50 characters.
- Body line-height: 1.4-1.6.
- Heading line-height: 1.0-1.2.
- Body font size: at least 16px.
- ALL CAPS tracking: 0.05em-0.15em.
- Maximum type families: 2.
- Maximum weights: 3.
- Maximum distinct type sizes: 8.

## Layout baseline

- Prefer 8px spacing scale: 4, 8, 16, 24, 32, 48, 64.
- Minimum touch target: 44x44 CSS pixels, recommended 48x48.
- Avoid center-aligned text blocks longer than three lines.
- Keep internal padding less than or equal to external grouping space.
- Use 12-column grids where grid layout is appropriate.

## Code quality baseline

- Keep functions under 20 lines where practical.
- Avoid more than three parameters; introduce objects or keyword arguments.
- Use guard clauses instead of deep nesting.
- Do not mix refactoring and feature behavior in the same patch.
- Prefer tracked source files over shell-generated files.
- For every extraction from old scripts, keep a provenance note in the commit or file header.

## Prompting rule for future LLM work

Use surgical edit prompts:

```text
Modify only the target file/section. Preserve all class names, IDs, comments, CSS custom properties, animation names, Chart.js configuration, and formatting outside the target. Return a unified diff, not a full rewrite.
```

## Verification checklist

Before accepting frontend changes:

1. Review git diff.
2. Confirm protected sections are unchanged.
3. Confirm Chart.js canvases and configs still exist.
4. Confirm animation/keyframe names are unchanged.
5. Confirm no inline CSS/JS was added to shell scripts.
6. Confirm extracted SCSS/CSS is linked by the app layout or asset pipeline.
