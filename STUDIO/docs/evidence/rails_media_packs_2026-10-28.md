# RAILS media packs — images and screenshots for every site, 2026-10-28

Scope: the nine RAILS sites that had no media pack. Until this commit only
the two static_exports trees (`RAILS/__other/alfa`, `RAILS/__other/sommerseth`)
carried `images/` + `screenshots/`. Every site now carries the same layout:

- `amber` 3+2, `brgen` 3+2, `bsdports` 3+2, `master` 3+2
- `brgen_dating` 3+2, `brgen_maps` 3+2, `brgen_marketplace` 3+2,
  `brgen_messenger` 3+2, `brgen_radio` 3+4 (radio + tv surfaces)

The media packs are brand assets and honest captures at the site root, the
same convention the static_exports trees use. They are not referenced by the
apps' views (no `app/assets` wiring, no view changes in this commit).

## Image generation

Prompts were derived from each site's `apps.yml` brand block (category,
visual_character, experience_principles) and rendered with the image
generation service:

- heroes 1440×704 (the 32-px-multiple the API enforces; matches the
  `alfa-hero.jpg` / `som-hero.jpg` size exactly)
- context landscapes 1344×768, detail portraits 864×1152
- saved as RGB JPEG q86; one hero per site plus two context shots

Style: editorial local photography, muted, flat surfaces, no readable text,
no faces — per the house visual character (deep_blue/ivory/terminal_green
palettes per site).

## Screenshot capture

Real captures of the real apps booted from this exact tree — no mockups:

- Ruby 3.4.12 (source build; the apps pin `ruby ">= 3.4"`), Rails
  8.2.0.alpha at the pinned ref, development mode
- `db:prepare` + the apps' own fictive seed data (brgen: 68 posts, 12 dating
  profiles, 20 radio tracks; amber: 100 users/2000 items/1000 outfits;
  bsdports: 240 users/46 ports)
- headless Chromium 1.57 (Playwright), full-page, desktop viewport 1440×900,
  mobile viewport 390×844, entrance animations settled by scrolling the page
  before capture — the same procedure the static_exports receipt documents
- host authorization satisfied portlessly: URLs carry no `:port`, the
  loopback port rides in Chromium `--host-resolver-rules` (`MAP
  dating.brgen.no 127.0.0.1:38182`), so the Host header is the plain
  hostname the allowlist regexes expect

Captured surfaces:

| Site | URL | desktop | mobile |
|---|---|---|---|
| brgen | brgen.no | 1440×1923 | 390×2367 |
| dating | dating.brgen.no | 1440×900 | 390×844 |
| marketplace | markedsplass.brgen.no | 1440×1923 | 390×2367 |
| messenger | messenger.brgen.no | 1440×1923 | 390×2367 |
| maps | maps.brgen.no | 1440×1923 | 390×2367 |
| radio | radio.brgen.no | 1440×1923 | 390×2367 |
| tv | tv.brgen.no | 1440×1923 | 390×2367 |
| amber | amberapp.art | 1440×3014 | 390×3459 |
| bsdports | bsdports.org | 1440×2333 | 390×2318 |
| master | ai.brgen.no | 1440×900 | 390×844 |

The two viewport-height captures are honest geometry: dating is a swipe-deck
surface and master is a 100vh chat face; neither page scrolls.

## Laws

`MASTER/bin/operator lint` (deterministic, no model) over all eighteen
`images/` + `screenshots/` dirs: **clean, 47 files, no law broken** — binary
media carries no lintable surface.

For context, the same lint over the static_exports trees measures 112
findings across 6 files: the Snøhetta-grade v2 redesigns
(6fb122156) postdate the 8efb4092d law run, and the redesigned pages have
not been through a law pass yet. That is the /fix experiment's input, not a
regression of this commit.

## Sandbox blockers found on the way

- The z.ai sandbox exports `DATABASE_URL=file:/home/z/my-project/db/custom.db`
  platform-wide; Rails merges it over every app's `config/database.yml` and
  AR then resolves a nonexistent `file` adapter at boot. All app commands
  here ran with `env -u DATABASE_URL`. Worth a line in OPENBSD/docs if it
  ever bites a real box; it is a sandbox artifact, not a repo bug.
- The image API rejects 1440×720 (720 is not a 32-px multiple) although the
  CLI advertises it; heroes therefore use 1440×704, which is also what the
  existing static_exports heroes already were.
