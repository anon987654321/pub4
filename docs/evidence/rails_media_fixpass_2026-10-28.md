# RAILS media-pack /fix pass — nine sites, twenty captures, 2026-10-28

The thor/alfa fixpass (18aaee2) run over the nine Rails sites' media packs
(591a67d): every screenshot read, every claimed defect verified against source
before fixing, each verdict recorded. The captures were taken against a seeded
database on Ruby 3.4.12; this pass ran in a sandbox whose toolchain was reset
(no Ruby anywhere), so rendered re-verification of the fixes is listed under
"Blocked on boot" rather than pretended.

## Verified and fixed

1. **Bergen streets corrupted to "… check"** — `plausible_content.rb`
   BERGEN_STREETS held "Kong Oscars check", "Ibsens check", "Lars Hilles
   check", "Christies check", "Olav Kyrres check", "Neumanns check" (and
   `bergen_demo_data.rb` the matching address). The maps capture rendered the
   corruption on every generated place: "Butikk Kong Oscars check", "Park
   Ibsens check". The comment above the list promises "real Bergen street
   names"; they are "… gate". Fixed to gate. Existing seeded rows keep the old
   name until a replant — noted, not migrated (fictive seed data).

2. **Dating: every button teal-on-teal** — `body.vertical-dating .btn`
   painted the bright teal fill under the #00705c ink, 1.6:1, so Angre,
   Matcher, Krysset spor and Opprett profil all rendered as filled pills that
   read as disabled. Fix: the fill rule is scoped to `.btn-primary` /
   `.swipe-signin` (one strong CTA per view), the fill is now the AA ink teal
   (6.05:1 under the light ground; dark mode's bright teal ≈4.6:1 over
   #16181c), and ghosts return to the shared ghost anatomy (subtle fill,
   muted ink). Both modes clear WCAG AA for button text.

3. **Dating: Latin lorem bios on a bokmål surface** —
   `bio: Faker::Lorem.paragraph` put "Provident vitae exercitationem…" on deck
   cards (captured on the mobile swipe card), which NORWEGIAN_COPY_BOKMAL
   exists to prevent and reads as a scam sign on a dating profile. Replaced
   with a ten-line Norwegian bio bank (same pattern the DM openers already
   use). Also: marketplace order messages (`Faker::Lorem.sentence` in the
   order thread) and playlist descriptions — both user-visible — moved to
   Norwegian banks.

4. **Messenger: seven identical "#" chips** — channel names are IRC-style
   ("#brgen"), so the rail chip's `name.first.upcase` rendered "#" for every
   room; the desktop capture shows a rail of seven empty hashes. The chip now
   takes the letter behind the hash (B, M, D, P, T, T, M); "#" remains only as
   the fallback for a nameless room. aria-label and title still carry the
   full name.

5. **Maps: raw point type leaked as copy** — when MapLibre is unavailable the
   controller's `_fallback()` rendered `<span>place</span>` above every name
   (the desktop/mobile captures show the literal word "place" twenty-plus
   times). The fallback card now leads with the human subtitle ("Kafé,
   Sentrum") the popup already used, type demoted to last resort, and the
   redundant `<small>` dropped.

6. **Radio: "Utvalgt spor" showed a bare grey square** — seeded tracks never
   attached artwork, so the featured-track square and every list cover
   rendered empty; the media-station direction asks media to carry the focal
   field. `find_or_create_radio_track!` now attaches a deterministic catalogue
   cover per title (`Brgen::DemoMedia.attach_catalog!`, seed
   `radio-track-<slug>`), the same pipeline listings and dating profiles use.

## Checked and left alone (artifact or as-designed)

- **Master input "c-6ae1e85a… master varmer opp…"** — the string before the
  warm-up placeholder is `Master::Face::Contract.shell_prompt`'s
  `hostname:path$`; the capture box's hostname IS that UUID. On vm23 the face
  shows the short host. Sandbox artifact.
- **Marketplace hero letterform "B"** — the giant blue B is the coded
  fallback (`--store-text-glyph`, aria-hidden) for a promo listing without a
  photo, not a broken image. Working as designed; wiring real promo imagery
  is the top opportunity, not a defect.
- **"oppdateringsalder ukjent" under every bsdports row** — first read as a
  concatenation bug at 10px; it is the correct `ports.age_unknown` string
  rendered small. Verify-before-fix caught the misread.
- **Master ASCII face cropped at 390px** — the glyph grid is wider than the
  phone viewport; the fixed layer clips it. Real, but it lives in the face
  renderer's column count, not in CSS this pass could fix honestly. Left with
  the renderer.

## Blocked on boot (sandbox reset: no Ruby toolchain)

- **bsdports footer collision** — the capture shows the build line
  ("v… aa3834606c22 Endringsslogg") running into the affiliate disclosure, and
  "Laster mer…" overlapping the "Ingen importering er kjørt." block and the
  sort chips. brgen's footer grid separates these; bsdports loads only the
  shared `_site_legal.scss`, which has no container rule. Needs the booted DOM
  to pin which rule to add.
- **"Laster mer…" idle text** — the sentinel prints its loading copy whenever
  `pagy.next` exists, before any load. Candidate fix (visually hide until
  loading, keep aria-live) wants one rendered confirmation.
- **Below-fold blankness on brgen/marketplace/radio/tv captures** — full-page
  heights (1923/2367px) with content ending at the first screen. Either the
  feed really rendered short or a reveal layer never settled. Needs a boot.
- **amber "Bymorgen" mid-word break at 1440** — the look title broke per
  character in the desktop tile; no `overflow-wrap` rule explains it in the
  tree, so the h2's computed width at that viewport needs a live DOM to
  diagnose (mobile renders the same title unbroken).
- **amber tile titles set in the sans** — `--font-display` (Source Serif 4) is
  wired to h1/h2 and the mirror holds in code; whether the captured tile
  headings resolve to it needs computed styles.

## Re-verification receipt (to close these)

Boot per docs/evidence/rails_media_packs_2026-10-28.md (`env -u DATABASE_URL`,
Ruby ≥3.4, Playwright Chromium, host-resolver-rules portless), re-seed, and
re-capture the affected surfaces: maps/places, dating home (both viewports),
messenger inbox, radio index, bsdports index, amber home at 1440. The
thor/alfa pass's standard applies: read every page, then declare it done.
