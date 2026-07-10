# MASTER/web — architecture notes and known gotchas

Written 2026-07-10 after a live debugging session that traced a "tap to
continue does nothing" bug through the full stack to a production asset
mismatch, then on to a VPS-wide resource crisis. Read this before touching
the boot sequence or the deploy path — it'll save you re-deriving all of it.

## Overview

The web tier is Rails 8 on Falcon, bound to loopback port 53187 and published
at https://ai.brgen.no through relayd. The chat surface at `GET /` combines
the assistant stream and the face runtime. Health is at `GET /up`. SSE
endpoints include `GET /chat/message` (assistant stream), `GET /chat/metrics`
(session metrics), and `GET /events/stream` (event bus).

The single HTML entrypoint is `app/views/chat/index.html.erb` via
`ChatController#index`. Runtime assets live under `public/`: `face.js` for
the THREE.js wireframe mesh, `cognition_ecology.js` for the ecology particle
layer above the face canvas, `particle_kernel.js` for the typed cell pool,
and `topology_registry.js` for topology dispatch. Topology configuration is
in `MASTER/data/topologies.yml`, not a path relative to the web app root.

Authentication accepts Bearer tokens, `X-Token`, or a `master_session`
cookie; visitors receive chat only without full tool access (see
`AuthTier` in `app/middleware/auth_tier.rb`).

After deploying web changes on the VPS, restart with `doas rcctl restart
master` and confirm with `curl` against `http://127.0.0.1:53187/up`.

## Boot contract (high-risk path)

The chat face boot path is high-risk. The recurring regression class is:
"tap to start does nothing" — 30+ commits across this repo's history are
titled some variant of "fix primer tap/dead tap/boot," so treat any fix
here as provisional until it survives a real-browser tap test, not just a
code read.

**Invariants:**
- The page must render the primer before heavy face work starts.
- No WebGL context may be created before `_primerFired` is true.
- `three.face.module.js` must not be compiled during initial page load.
- `face.js` must be imported only after the primer tap.
- The prompt must become visible even if face loading fails.
- The boot manifest must keep `particle_kernel.js` before face/runtime consumers.
- SSE may remain open; tests must not wait for network idle on the face page.

**Files:**
- `app/views/chat/index.html.erb`: primer, WebGL guard, boot manifest, lazy `import("face.js")`.
- `public/face.js`: deferred face loader.
- `public/face.part*.txt`: split face runtime payload.
- `public/three.face.module.js`: heavy WebGL module, warmed by prefetch only.
- `public/visual_bridge.js`: runtime event/SSE bridge.
- `public/cognition_ecology*.js`: 2D canvas ecology, allowed before primer.

**Checks:**
- `bin/check-web`
- `ruby -Ilib:test test/test_web_ui.rb --name test_public_asset_manifest_matches_source_files`
- Manual real-browser tap test after boot changes (see below) — headless
  CDP tools have shown false hangs in sandboxed environments in this repo's
  history, so a real browser is the trustworthy signal, not a scripted one.

**Manual tap test:**
1. Start the web app on a local port.
2. Open the chat page in a real browser.
3. Before tapping, confirm the primer is responsive and the prompt is hidden.
4. Tap or press Enter.
5. Confirm the primer dismisses, prompt appears, and the face either starts or fails visibly.
6. Confirm console errors do not indicate eager WebGL or THREE.js boot before tap.

## The primer → face boot sequence

The page loads with a black `#primer` overlay ("tap to start"). Two
independent mechanisms can dismiss it:

1. An early inline `<script>` in `<head>` (`armPrimer()`) attaches
   pointerdown/click/touchend/keydown listeners as soon as the DOM is ready.
   It's a **fallback** — if the fuller boot script below hasn't defined
   `window.__MASTER_PRIMER_GO__` yet, it does a minimal dismiss itself.
2. A later inline `<script>` (non-deferred, so it runs synchronously at
   parse time, before `DOMContentLoaded`) defines the real `go()` function,
   assigns it to `window.__MASTER_PRIMER_GO__`, and attaches its own
   listeners directly to `#primer`. In practice this one wins essentially
   every time, since it's parsed before any real user tap can occur.

`go()` calls `dismissPrimer()` and `revealPrompt()` **synchronously and
unconditionally**, before anything WebGL-related happens. This means: if
the overlay ever fails to disappear on tap, with *zero* visible change
anywhere on screen (no prompt bar, no status text), the tap handlers
themselves never ran — that's a client-side JS execution problem (browser
extension/content-blocker silently stripping scripts, or a CSP issue), not
a bug in this boot code. Verified during this session: a browser extension
was silently blocking all page JS in the normal profile; incognito (which
disables most extensions) let the primer dismiss correctly.

After dismissal, `loadFace()` dynamically `import()`s the fingerprinted
`face.js` bundle. That file is a *thin loader*, not the real renderer — it:
- imports 10 small `face_*.js` helper modules directly via `MASTER_ASSET_PATHS`
- fetches 5 `face.part*.txt` files, concatenates them, and imports the
  result as a `Blob` URL module (works because CSP's `script-src` already
  includes `blob:`)
- feature-detects WebGL with a throwaway `<canvas>` before paying the
  ~1.3MB THREE.js parse cost; falls back to a lighter "2D mode" path
  otherwise, which is why an unresponsive face on an unusual browser isn't
  automatically a bug — check for real WebGL support first.

Separately, `face_deferred_loader.js` waits for the `primer:ready` event
and loads a *second*, independent "vision" layer (`face_vision.bundle.js`,
`cognition_ecology.js`). Known-broken as of 2026-07-10 but non-fatal
(properly `.catch()`-guarded): `face_vision_c.js`/`face_vision_d.js` fetch
`/canvas/topology`, `/data/rules.yml`, `/viseme_packs.json` at hardcoded,
un-fingerprinted paths that don't resolve — the first has no matching
route at all, `rules.yml` lives outside `public/` in `MASTER/data/`, and
`viseme_packs.json` exists as a real fingerprinted asset but isn't read
from `MASTER_ASSET_PATHS` like everything else is. Left unfixed pending a
decision on whether `rules.yml` should even be servable to visitors.

## The asset-manifest footgun (bit us twice in one session)

Propshaft's dev-mode `public/assets/.manifest.json`, once present, is
consulted instead of the live filesystem — so adding a new asset without
regenerating the manifest 404s it, even though `assets:precompile` ran.
Worse in production: the *running* Falcon process's in-memory asset state
can go stale relative to what's actually on disk if a newer build lands
after the process booted. A file can exist, `curl` can 200 it directly,
and the app can still 404 trying to `asset_path()` it — until restarted.

This is why `master`'s `rc.d` script now runs `master_web_assets_gate.rb`
as a hard, load-bearing check before starting (added 2026-07-10, one retry
via forced `assets:precompile` before it actually refuses to start). If
`master` won't start and the log shows "assets gate failed", that's
telling you the truth — don't work around it, find out what's actually
missing.

## Deploy state

- `rcctl restart master` runs a real `rc_pre()`: kills stale processes,
  regenerates the face bundles if missing, precompiles assets if a content
  digest changed, runs the gate above, then starts Falcon and waits for
  `/up` before restarting `relayd` (relayd can keep routing to a dead
  backend connection after a restart until kicked).
- A `/home/dev/pub4/.deploying-<app>` lock file is touched for the
  duration of each app's `rc_pre()` — check for it before assuming any
  app's asset/db state is stable if you're debugging remotely while a
  restart might be in flight.
- **The canonical source for every `/etc/rc.d/<app>` script and
  `resource_guard.sh` is this repo** (`OPENBSD/etc/rc.d/*`,
  `OPENBSD/resource_guard.sh`) — not whatever is live on the VPS. If you
  edit the live file directly (as happened during tonight's incident
  response), **mirror the change back into the repo file**, or the next
  sync from repo → server will silently revert your fix.

## brgen is multi-domain, not multi-tenant-by-header

`brgen`'s app serves ~20 separate city domains (`brgen.no`, `oshlo.no`,
`lsangeles.com`, ...) plus per-city vertical subdomains (`tv.*`,
`dating.*`, `playlist.*`, `takeaway.*`, `marketplace.*` — the marketplace
subdomain name is itself localized per country, see
`Brgen::DomainRegistry::SUBAPP_ALIASES`). `Brgen::DomainRegistry.resolve(host)`
is the one true way to find "which city, which vertical" for the current
request — reuse it rather than re-deriving subdomain logic, and remember
a static `robots.txt`/`public/*` file can't vary per domain the way a
routed, dynamically-rendered response can.

## The VPS is genuinely small

1 vCPU, ~1GB RAM, running `master`, `brgen`, `amber`, `bsdports`,
`hjerterom` concurrently (`mytoonz` is not currently enabled). A load
average of 1.0 here means the single core is simply busy — not distress.
`resource_guard.sh` (cron, every 5 min) is meant to shed `amber`/
`bsdports`/`hjerterom` under real pressure, but as of 2026-07-10 it's
paused (via its own `/var/db/pub4_all_apps` flag) after a threshold
mismatch caused a brief full outage during a routine multi-app restart —
see `OPENBSD/resource_guard.sh`'s header comment for the full story before
re-enabling or retuning it. Restarting more than one or two of these apps
back-to-back will spike load into the 4-7 range for a few minutes purely
from cold-start warm-up; that's expected, not a crisis, as long as swap
isn't also climbing.
