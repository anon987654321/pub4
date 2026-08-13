# Affiliate banner (CodePen export, recovered 2026-08-13)

A parallax-tilted, Packery-packed grid of product images with "Buy now! /
Be happy! / Feel good!" overlays, animated in with a staggered anime.js entry.
Recovered from gist anon987654321/c274ca5da40088a09e2bf28a82ba1de4
(CodePen pen YzLNyNV, https://codepen.io/license/pen/YzLNyNV).

Kept whole as the visual reference for the in-feed affiliate unit. It is not
wired, and porting it as-is would break four standing rules:

- **jQuery.** The pen is built on it (`$("#scene").packery(...)`,
  `.imagesLoaded(...)`). This tree has no jQuery and does not want it.
- **Five CDN scripts** — jquery, imagesloaded, parallax, packery, anime.
  brgen pins nothing to a CDN; seven pins once cost a page 537 requests.
  Anything kept has to be vendored the way css-doodle is.
- **Packery is GPLv3 or paid.** A commercial licence is required for a
  closed-source commercial site. Its layout job — pack images of uneven size
  into a band — is what CSS grid `masonry` or a flex row with fixed heights
  does without a dependency or a licence.
- **Comic Sans MS at 44px**, against a two-family type rule.

What is worth keeping is the *idea*: product images at mixed sizes, packed
edge to edge, with a few large call-to-action tiles interleaved, and a gentle
parallax on pointer move. All of that is reachable with CSS grid, a small
Stimulus controller for the tilt, and `prefers-reduced-motion` respected.

The images are i.imgur.com URLs and are stand-ins for real product imagery —
in the app the source is AffiliateProduct, which already carries title,
click_url, price_cents, commission_rate, market and a placeholder flag.
