---
name: Bare HTML/CSS targeting — no divitis, no utility classes
description: Always use bare element selectors (nav a, main, h1) not BEM classes or utility class strings on elements
type: feedback
originSessionId: ab7bf92a-5fdc-43bb-998c-dc1d5598f33d
---
Use bare element and structural selectors throughout. Never add class attributes to elements that can be targeted by tag or relationship.

**Why:** User explicitly stated "always bare targeting for clean HTML/CSS" and "no divitis." Confirmed with rejection of `.nav__link`, `.nav__brand`, `.nav__links` pattern.

**How to apply:**
- `nav a` not `a.nav__link`
- `.brand` only for the logo anchor that needs differentiation from other nav links
- `nav { ... }` for nav bar styling, not `.navbar` or `.nav`
- `main` for main content, not `.main-content` or `.container`
- Use `tag.nav`, `tag.main`, `tag.article` etc. — no wrapper divs with classes unless structurally necessary
- Rails `tag` helper (tag.div, tag.span) preferred over `content_tag`; `class_names` for conditional classes
- In ERB views: no `class:` arguments on links unless the class carries genuine semantic meaning (e.g. `.brand`, `.btn`, `.badge`)
