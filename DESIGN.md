---
name: MASTER Visual Contract
version: 1
colors:
  background: "#000000"
  foreground: "#ffffff"
  muted_foreground: "rgba(255,255,255,0.55)"
spacing:
  base: 0.5rem
  scale: [0.5rem, 1rem, 1.5rem, 2rem, 3rem]
typography:
  body: "system-ui, -apple-system, Segoe UI, Roboto, sans-serif"
  mono: "ui-monospace, SFMono-Regular, Menlo, monospace"
  text_size: "0.95rem"
borders:
  hairline: "1px solid #ffffff"
radius:
  default: "0"
particles:
  size: "1px"
  count: 3000
  color: "#ffffff"
---

# MASTER DESIGN.md

MASTER web surfaces are terminal-first and constitution-first.

## Core directives

1. Absolute black (`#000000`) edge-to-edge background.
2. White foreground only; no accent palette unless explicitly specified by feature requirements.
3. Particle visuals are device-pixel points (`1px x 1px`), no blur, glow, gradient, or bloom.
4. Preserve whitespace; typography remains restrained and readable.
5. Avoid ornamental components: no hamburger menus, no decorative borders, no floating chrome.
6. Prefer declarative HTML + SSE updates; minimize custom JavaScript to simulation/runtime needs.
7. Use rem-based spacing aligned to an 8px grid.
8. No framework class explosion and no `!important`.

## Canvas behavior contract

- Idle state: low-amplitude Brownian drift.
- Boot state: brief wireframe face coalescence (about two seconds), then dissolve.
- Command state: particles can regroup into structural diagrams for scans, pipeline stages, and council signals.
- Mood state: motion quality reflects homeostat state (focused/curious/tense/weary).
- Audio state: low frequencies influence cohesion; transients trigger short scatter impulses.

## Text treatment contract

- Messages render as plain white text in upper-third left alignment.
- Assistant messages may use a temporary 1px left hairline for emphasis.
- Input is a bottom hairline that expands only while typing.
