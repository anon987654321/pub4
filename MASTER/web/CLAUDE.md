# MASTER/web — architecture notes and known gotchas

Written 2026-07-10 after a live debugging session that traced a "tap to
continue does nothing" bug through the full stack to a production asset
mismatch, then on to a VPS-wide resource crisis. Read this before touching
the boot sequence or the deploy path — it'll save you re-deriving all of it.

## Overview

The web tier is Rails 8 on Falcon, bound to loopback port 53187 and published
at https://ai.brgen.no through relayd. The chat surface at `GET /` combines
the assistant stream and the face runtime. Health is at `GET /up`. Streaming
endpoints include `POST /chat/message` (preferred assistant stream),
`GET /chat/message` (legacy fallback), `GET /chat/metrics` (session metrics),
and `GET /events/stream` (event bus).

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
- `MASTER_FACE` is the public face runtime global; do not add new
  `MASTERFace` call sites.
- `MASTERChat.startChatStream()` is the preferred chat transport. Keep the
  old `EventSource` GET path only as fallback, and preserve named SSE face
  reactions (`mood`, `model`, `verdict`, `council:speech`, `confidence`,
  `felt`) on the POST path.
- Web TTS style is unlocked by default (`auto`) so the server can infer style.
  Only send `style` with `style_locked=1` after an explicit user style choice.
- Browser `speechSynthesis` fallback must be recoverable; do not make one
  failed server-TTS request permanently downgrade the session.

**Files:**
- `config/face_assets.yml`: **the** manifest — every face asset the shell loads,
  grouped by load phase, order within a group being the boot contract. The view
  renders `MASTER_ASSET_PATHS` and the deferred `javascript_include_tag` from it
  (`FaceAssets`), and `/etc/rc.d/master`'s precompile digest reads it through
  `script/face_asset_paths.rb`. Adding a face module means adding it here.
- `app/views/chat/index.html.erb`: primer, WebGL guard, boot manifest, lazy `import("face.js")`.
- `public/face.js`: deferred face loader.
- `public/face.part*.txt`, `public/face_speech_*.js`: the six sources
  concatenated into `face.runtime.js` at build time. Not fetched at runtime.
- `public/three.face.module.js`: heavy WebGL module, imported only after the
  primer tap and WebGL feature detection. **Generated, not vendored by hand**:
  `script/build_three_face.sh` npm-installs `three` (pinned in
  `script/three_build/package.json`, currently 0.184.0) and esbuild-bundles
  only the ~17 symbols `script/three_face_entry.js` re-exports. To change the
  three version, edit that package.json and re-run the script — do not patch
  the output. The tracked bundle is the build artifact; it is committed so the
  1GB VPS never has to run npm at boot.

  Until 2026-07-28 a second file, `public/three.module.js`, was also tracked:
  a full unminified three r160 (Dec 2023), 53k lines, over half of everything
  tracked under `web/`. Nothing imported it — `MASTER_ASSET_PATHS.threeModule`
  points at `three.face.module.js`, and the only textual match for its name was
  a license comment inside that bundle. Deleted. If you find yourself adding a
  raw three build back, check whether the entry-point re-export list is what
  you actually want to extend instead.
- `public/visual_bridge.js`: runtime event/SSE bridge.
- `public/cognition_ecology*.js`: 2D canvas ecology, allowed before primer.

**Checks:**
- `bin/check --profile=web` (there is no `bin/check-web`; the profile replaced it)
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

## Runtime contract (chat, face, TTS)

`chat_actions.js` owns the preferred POST streaming transport and SSE block
parser. `face.part5.txt` / `face.runtime.js` own the face-specific reaction
layer: token chunks drive chat text and TTS; named events drive mood, model
badges, verdict pulses, council mouth offsets, confidence, and felt state.
When adding a named SSE event, decide deliberately whether it belongs in the
generic `sse_contract.js` handlers, the face-specific `handleFaceNamedEvent()`,
or both.

`face.runtime.js` is generated by `rails assets:build_face_runtime` (which
`assets:precompile` enhances, so a deploy rebuilds it). Edit a source and run the
task; a hand edit to the built file survives only until the next precompile.

Its sources are six files in load order, and two of them are **not** part files:

    face.part1.txt  face.part2.txt  face.part3.txt
    face_speech_runtime.js  face_speech_playback.js
    face.part5.txt

There is no `face.part4.txt` — the two speech files sit in its place, and that is
where TTS, the browser-voice default and the STT duck live. Reading this list as
`face.part*.txt` sends you looking for that code in a part file that does not
contain it. `test_face_runtime_matches_its_sources` rebuilds the concatenation
and fails on any drift, naming the task to run.

TTS requests should omit `style` unless the user explicitly locks one through
the UI or `/voice ... <style>`. Server TTS failures may temporarily use browser
speech, but the cooldown must expire so the Edge/server voice can recover
without a page reload.

## RESOLVED 2026-07-11: the real "dead tap" root cause was a MutationObserver loop

After 30+ provisional "fix primer tap" commits, the actual cause of the
slow-page / infinite-loading-spinner / dead-tap triad was found and fixed:
`public/face_state.js`'s `observe()` watched `attributes: true` on the same
elements (`#status`, `#ui-status`, `#pipeline-stage`) whose `data-runtime-status`
attribute its own callback writes via `applyFrom()`. Each write re-fired the
observer → wrote again → an infinite mutation→observe→mutate **microtask** loop
that permanently starved the main thread. Because it's a microtask flood (not a
plain `while` loop), the thread never yields to rendering or input — so the page
load event never fires (spinner), and the primer's tap listeners never get a
slot (dead tap). Fix: drop `attributes` from the observe options; `runtimeStatus`
is only ever written by this file, so there was no external attribute change
worth observing. The real external signal (status text) still fires via
`childList`/`characterData`.

Two things this exposed, both worth heeding:
- **Headless bisection *did* find it**, contradicting the "false hangs" caution
  below. The trustworthy method was a *controlled A/B*: intercept-and-block one
  script at a time (via ferrum/Playwright request interception) and probe main-
  thread responsiveness with a short-timeout `evaluate`. Blocking *only*
  `face_state.js` flipped the page from wedged to responsive; a sandbox false-
  hang can't produce that selective result. A raw "it hangs" from one load is
  untrustworthy; a bisect is not.
- **The rc.d precompile-skip digest used to be incomplete.** `/etc/rc.d/master`'s
  `_digest=$(cksum …)` named its inputs by hand, so editing a face module it did
  not list **silently skipped precompile** on restart and kept the stale
  fingerprint live. A `face_*.js` glob later fixed that for the face_-prefixed
  half and still left 15 of 38 uncovered — among them `particle_kernel.js`,
  `face.runtime.js` and `three.face.module.js`. Since 2026-07-28 the digest
  reads `config/face_assets.yml` via `script/face_asset_paths.rb`, so a module is
  covered the moment it is declared. **Declare new face assets in that manifest**
  — not doing so is now the only way to reproduce the old failure.

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
- fetches the single prebuilt `face.runtime.js` and imports it as a `Blob` URL
  module (works because CSP's `script-src` already includes `blob:`). It does
  not fetch the sources; concatenation happens at build time, not in the browser
- feature-detects WebGL with a throwaway `<canvas>` before paying the
  ~1.3MB THREE.js parse cost; falls back to a lighter "2D mode" path
  otherwise, which is why an unresponsive face on an unusual browser isn't
  automatically a bug — check for real WebGL support first.

Separately, `face_deferred_loader.js` waits for the `primer:ready` event
and loads a *second*, independent "vision" layer (`face_vision.bundle.js`,
`cognition_ecology.js`). The core face runtime dispatches
`master:face-ready` from `markFaceReady()`; the vision modules use that event
for boot metrics and deferred hooks. `/canvas/topology` is a Rails route, and
the viseme-pack loader must keep using `MASTER_ASSET_PATHS.visemePacks` rather
than hardcoded asset URLs. Do not expose `MASTER/data/rules.yml` directly to
visitors unless there is an explicit product/security decision to make those
rules public.

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

1 vCPU, ~1GB RAM, running `master`, `brgen`, `amber`, `bsdports`
concurrently. A load average of 1.0 here means the single core is simply busy — not distress.
`resource_guard.sh` (cron, every 5 min) is meant to shed `amber`/
`bsdports` under real pressure, but as of 2026-07-10 it's
paused (via its own `/var/db/pub4_all_apps` flag) after a threshold
mismatch caused a brief full outage during a routine multi-app restart —
see `OPENBSD/resource_guard.sh`'s header comment for the full story before
re-enabling or retuning it. Restarting more than one or two of these apps
back-to-back will spike load into the 4-7 range for a few minutes purely
from cold-start warm-up; that's expected, not a crisis, as long as swap
isn't also climbing.
