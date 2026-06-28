---
name: Importance-ordered file layout
description: Every file's lines flow by importance — newspaper inverted pyramid. Most important content at top.
type: feedback
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
Every file you touch gets importance-ordered lines—inverted pyramid so the gist survives a partial read: requires, declaration, public API by importance, primary algorithm, private helpers, constants, edge handlers.

Applies to ruby, yaml, erb, js, css, html, sh, and md. Fix inverted files on touch; do not reshuffle for sport. Encoded in style.yml line_order and patterns.yml IMPORTANCE_ORDER. Maintainer and Layperson evaluate; sweep enforces.