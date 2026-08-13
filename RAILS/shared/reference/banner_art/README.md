# Banner art (CodePen export, recovered 2026-08-13)

Three 300x300 sponsored-banner units — marketplace, dating, playlist — plus the
original of the dating heart. Recovered from a gist after being lost; kept here
whole rather than only in the form that is wired, so the next person has the
source and not a reconstruction.

Source: gist anon987654321/290153d185fa76944a91159270f72ec7
(CodePen pen ogLWRJL, https://codepen.io/license/pen/ogLWRJL)

## What is wired

`dating/home/_heart.html.erb` renders the dating heart. Its placeholder comment
asked for "the exact snippet ... when ready"; this is that snippet.

## What is not, and what it would cost

- **marketplace** — pulls two images from i.imgur.com. External hosts are a CSP
  and availability problem; self-host before wiring.
- **playlist** — the scifi/iris eye and the floating-particle field are pure
  css-doodle and would drop in, but the `.ml15` letter reveal and the spinning
  `.lp` need anime.js, which this tree does not carry.
- The pen loads css-doodle, Swiper and anime.js from cdnjs. brgen self-hosts
  css-doodle at `/vendor/css-doodle.min.js` and pins nothing to a CDN — seven
  CDN pins once cost a page 537 requests. Vendor anything new the same way.
- `<footer class="bankid">Protected by BankID</footer>` is here too. Its markup
  was removed from the dating intro on 2026-08-12 (d35b40ec0) and its CSS
  deleted as dead on 2026-08-13 (16370042a). Both are recoverable from git if
  the badge is wanted back.

## Second heart

index.html keeps a commented-out alternate: `points: 1000`, `scale: .34`,
`s: sqrt.abs.cos(t) / (sin(t) + 1.6)` — a different parametrisation of the same
shape. Preserved deliberately; it is a variant, not dead code.
