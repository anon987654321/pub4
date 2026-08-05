# LLM-safe frontend rules

Recovered from `DEPLOY/rails/shared/frontend/LLM_SAFE_FRONTEND_RULES.md`, deleted
at `ee3a56e33`. These constrain agents editing frontend code under `RAILS/`, so
they were absent for the whole period agents have been editing it.

The behavioural rules are restored as written. The numeric baselines are not —
they are replaced by pointers, for the reason in the last section.

## Core rule

Large HTML/ERB files carrying inline CSS, JavaScript, SVG, chart configuration or
animations must be split into external tracked files before further model
editing.

Do not ask a model to rewrite a large mixed HTML/CSS/JS document unless the
requested output is a minimal unified diff.

## Required separation

- ERB/HTML structure: `app/views/…`
- SCSS/CSS: `app/assets/stylesheets/…`
- Stimulus controllers: `app/javascript/controllers/…`, or `shared/frontend/` when
  more than one app uses it
- Chart configuration: `app/javascript/charts/…`, chart data in its own file
- Animations and keyframes: a dedicated file
- Font declarations: a dedicated file
- SVG icons: partials or external assets

## Preservation rules

1. Preserve exact old SCSS/CSS where a source stylesheet exists.
2. Where styling exists only inline in an old shell script or ERB block, extract
   it verbatim into a named stylesheet first.
3. Do not normalize, modernize, minify or rename classes during extraction.
4. Do not remove vendor prefixes during extraction.
5. Do not collapse custom animations into generic transitions.
6. Do not replace CSS custom properties with hardcoded values.
7. Do not alter chart options while editing chart data.
8. Do not edit sections marked `PROTECTED` unless the task asks for it.
9. Prefer additive classes over modifying existing ones.
10. Use unified diffs for surgical edits to large view or style files.

Class names are `snake_case` here. No jQuery.

## Protected section markers

```erb
<%# BEGIN PROTECTED CHARTJS: do not modify without explicit chart task %>
<canvas id="revenue_chart"></canvas>
<%# END PROTECTED CHARTJS %>
```

```scss
/* BEGIN PROTECTED ANIMATIONS: restored from old pub source */
/* END PROTECTED ANIMATIONS */
```

## Numbers live in the tokens, not here

Spacing scale, tap targets, bar heights, type families and weights come from
`RAILS/shared/design_tokens.yml`, surfaced as custom properties through
`shared/app/assets/stylesheets/_dialect_tokens.scss`. Read them there.

The deleted version of this file restated them, and drifted: it prescribed an
8px scale of `4, 8, 16, 24, 32, 48, 64` while `design_tokens.yml` defines
`space_sm: 0.75rem` — 12px, not 16. A single law carrying two spacing scales is
not hypothetical here; gates picked different ones and disagreed with each other
until `82831623a` settled it. Restoring the numbers would restart that.

What has no other home, and stays:

- Line length 45–75 characters, 66 ideal; 35–50 on mobile.
- Body line-height 1.4–1.6; headings 1.0–1.2.
- Avoid centre-aligned text blocks longer than three lines.
- Internal padding no greater than the external grouping space.

Rendered conformance — real box heights, occlusion, contrast, 8px rhythm — is
measured by `ruby RAILS/gates/runner.rb geometry` against Chrome, not by reading
CSS. Token colours are never rewritten automatically: `design_metrics` prints the
hex that clears AA and leaves the brand decision to a person.

## Code quality

Functions under 20 lines where practical. No more than three parameters; use
keyword arguments or an object. Guard clauses over deep nesting. Do not mix
refactoring and behaviour change in one patch. Prefer tracked source files over
shell-generated ones. Keep a provenance note in the commit or file header for
anything extracted from an old script.

## Prompting rule

```text
Modify only the target file/section. Preserve all class names, IDs, comments,
CSS custom properties, animation names, chart configuration, and formatting
outside the target. Return a unified diff, not a full rewrite.
```

## Before accepting a frontend change

1. Read the diff.
2. Confirm protected sections are unchanged.
3. Confirm chart canvases and configs still exist.
4. Confirm animation and keyframe names are unchanged.
5. Confirm no inline CSS or JS was added to a shell script.
6. Confirm extracted CSS is actually linked by the layout or asset pipeline.
7. For layout claims, diff the live CSS before believing the source — most layout
   defects in this tree are stale deployed CSS, not wrong source.

## A standing constraint

The user is a trained architect and the visual design is deliberate. Restore or
ask; do not invent layout fixes. Hidden swipe-reveal navigation is intended
behaviour, not a bug. Visual system: `RAILS/shared/WIRING_NOTES.md`.
