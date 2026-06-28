---
name: Bare HTML/CSS targeting — no divitis, no utility classes
description: Always use bare element selectors (nav a, main, h1) not BEM classes or utility class strings on elements
type: feedback
originSessionId: ab7bf92a-5fdc-43bb-998c-dc1d5598f33d
---
Bare element/structural selectors only — no classes where tag/relationship suffices. `nav a` not `.nav__link`; `main` not `.container`. `.brand`/`.btn`/`.badge` only when semantic. Rails `tag` over `content_tag`; ERB: no `class:` unless meaningful. No divitis, BEM, or utilities.