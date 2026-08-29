# Banner art

**The source, not a reconstruction of it.** Three 300×300 sponsored-banner units
— marketplace, dating, playlist — plus the original of the dating heart, kept
here whole rather than only in the form that is wired, so the next person opens
what was actually drawn. Recovered from gist
anon987654321/290153d185fa76944a91159270f72ec7, pen ogLWRJL, at
https://codepen.io/license/pen/ogLWRJL.

One of the four is live. `dating/home/_heart.html.erb` renders the dating heart,
and the placeholder comment that asked for "the exact snippet ... when ready" was
asking for this one.

The other three each cost something. The marketplace unit pulls two images from
i.imgur.com, and an external host is both a CSP problem and an availability one,
so self-host before wiring it. The playlist unit's scifi iris eye and floating
particle field are pure css-doodle and would drop straight in, but its `.ml15`
letter reveal and spinning `.lp` need anime.js, which this tree does not carry.
The pen as a whole loads css-doodle, Swiper and anime.js from cdnjs, and brgen
self-hosts css-doodle at `/vendor/css-doodle.min.js` and pins nothing — seven CDN
pins once cost a page 537 requests, so vendor anything new the same way.

`<footer class="bankid">Protected by BankID</footer>` sits here too. Neither its
markup nor its CSS is in the dating intro any more; git has both if the badge is
wanted back.

`index.html` also keeps a commented-out alternate heart — `points: 1000`, `scale:
.34`, `s: sqrt.abs.cos(t) / (sin(t) + 1.6)` — a different parametrisation of the
same shape. It is preserved deliberately. It is a variant, not dead code.
