---
name: Bare HTML/CSS targeting — no divitis, no utility classes
description: Always use bare element selectors (nav a, main, h1) not BEM classes or utility class strings on elements
type: feedback
status: consolidated
canonical: data/principles/feedback_html_css_style.md
---
**Consolidated.** This content is now maintained as single source in `data/principles/feedback_html_css_style.md`.

See the principles/ version for the current authoritative text. This file is kept only for historical session traceability.

**How to apply:**
- `nav a` not `a.nav__link`
- `.brand` only for the logo anchor that needs differentiation from other nav links
- `nav { ... }` for nav bar styling, not `.navbar` or `.nav`
- `main` for main content, not `.main-content` or `.container`
- Use `tag.nav`, `tag.main`, `tag.article` etc. — no wrapper divs with classes unless structurally necessary
- Rails `tag` helper (tag.div, tag.span) preferred over `content_tag`; `class_names` for conditional classes
- In ERB views: no `class:` arguments on links unless the class carries genuine semantic meaning (e.g. `.brand`, `.btn`, `.badge`)
