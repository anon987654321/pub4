# Affiliate banner

**Kept whole as the visual reference for the in-feed affiliate unit, and wired
nowhere.** This is a CodePen export: a parallax-tilted, Packery-packed grid of
product images under "Buy now! / Be happy! / Feel good!" overlays, animated in
with a staggered anime.js entry. It came back from gist
anon987654321/c274ca5da40088a09e2bf28a82ba1de4, pen YzLNyNV, at
https://codepen.io/license/pen/YzLNyNV.

Porting it as it stands breaks four standing rules. It is built on jQuery —
`$("#scene").packery(...)`, `.imagesLoaded(...)` — and this tree has no jQuery
and does not want it. It pulls five scripts from a CDN, and brgen pins nothing to
a CDN: seven pins once cost a page 537 requests, so anything kept has to be
vendored the way css-doodle is. Packery is GPLv3 or paid, and a closed-source
commercial site needs the paid licence for a layout job — packing images of
uneven size into a band — that CSS grid `masonry` or a flex row at fixed heights
does with no dependency and no licence at all. And it sets Comic Sans MS at 44px,
against a two-family type rule.

What is worth keeping is the idea. Product images at mixed sizes, packed edge to
edge, a few large call-to-action tiles interleaved, and a gentle parallax on
pointer move — all of it reachable with CSS grid, a small Stimulus controller for
the tilt, and `prefers-reduced-motion` respected.

The images are i.imgur.com URLs standing in for real product imagery. In the app
the source is `AffiliateProduct`, which already carries title, click_url,
price_cents, commission_rate, market and a placeholder flag.
