---
name: Bare HTML/CSS targeting — no divitis, no utility classes
description: Always use bare element selectors (nav a, main, h1) not BEM classes or utility class strings on elements
type: feedback
originSessionId: ab7bf92a-5fdc-43bb-998c-dc1d5598f33d
---
Use bare element and structural selectors wherever a tag or DOM relationship suffices—nav a instead of nav-link classes, main instead of container classes. Reserve brand, btn, and badge class names only when semantics cannot carry the distinction.

Prefer Rails tag over content_tag and omit class attributes in ERB unless meaningful. No divitis, BEM naming, or utility class strings.