# Tree contracts

The one tree-contract file for pub4. RAILS, RAILS/master, and OPENBSD keep
their sharp edges here; STUDIO reads its project READMEs. The harness doors
at the repo root route here. The content moved out of the per-tree
`CLAUDE.md` files; git history holds the originals.

## RAILS
RAILS/README.md is the maintained long-form reference (check tables,
rendered-check semantics, deploy blockers, subdomain map) and
`RAILS/apps.yml` is feature truth — do not restate either in this file.

### The deploy script layer

`RAILS/_*.sh` files (`_assets`, `_bundle`, `_core`, `_database`,
`_deploy`, `_runtime_check`, `_service`) are libraries of sourced shell
functions, not entrypoints. Each app's `deploy.sh` sources them; root
`redeploy` is the operator's workstation entry; `apps.yml` is the
canonical matrix and `apps.horizon.yml` the planned one — the two must
not drift without a session note. An app counts as first-class when it
has an `apps.yml` entry, a `deploy_root` and (when it reaches the VPS) a
`deploy_script`; `mrdamascy` is first-class as of 2026-11-02 with its
deploy lane still pending.

### Commands

```zsh
ruby MASTER/checks/runner.rb --all          # every registered check
ruby MASTER/checks/runner.rb --list         # check names
ruby MASTER/checks/runner.rb production     # one check, or a composite
ruby RAILS/test/<name>_test.rb            # one contract test — bare ruby, no bundle
cd RAILS/<app> && bin/ci                  # per-app RuboCop, Brakeman, bundler-audit, tests
cd RAILS/<app> && bin/rails test test/models/item_test.rb:42   # one app test
MASTER/bin/operator triangle up                     # boot all 4 surfaces on the ports checks probe
npm ci && npm run build:pwa               # rebuild the Workbox service worker
```

`RAILS/test/*.rb` are standalone Minitest files run under bare `ruby` — they
read source as text and never boot Rails. App tests under
`RAILS/<app>/test/` need the app bundle. Ruby 4.0.5 is pinned by
`.ruby-version` at the repo root and in each app directory, so app commands
resolve the same interpreter from any cwd.

Which check proves the work: source change → the check that owns it
(`runner.rb --list`); app code → that app's `bin/ci`; anything measuring
rendered layout → `MASTER/bin/operator triangle up` first, or the live half
silently passes having measured nothing.

### Architecture

**One engine, three apps.** `shared/` is the `pub4-shared` gem, mounted by
`path: '../shared'` in each app's Gemfile. It carries models, controllers,
views, Stimulus controllers, policies and lints that all three apps share.
Concerns come in through `Shared.concern(:Votable)`, routes through an
`instance_eval` of `__shared/config/routes/social.rb` in each app's
`routes.rb`. A change in `shared/` lands in three apps at once — check all
three before assuming a fix is local.

**Shared deploys as a sibling, not a subdirectory.** The copy-tree deploy
puts the tracked app at `/home/<app>/app` and its own copy of the engine at
`/home/<app>/shared`. Every app vendors a separate copy; syncing to the
wrong one makes precompile a silent no-op. `MASTER/contracts/studio.rb`
resolves the canonical STUDIO media entrypoints from the source or deployed
tree; callers do not reach into sibling implementation directories.

**brgen's verticals are mountable engines**, not namespaced controllers.
Marketplace contains the food-ordering Takeaway engine as a nested package;
it is exposed at `/food` on the marketplace host. Subdomain constraints in
`brgen/config/routes.rb` via `Brgen::DomainRegistry` map `markedsplass`,
`dating`, `tv` and the rest onto them. Messenger and the MASTER relay are
not engines. Tooling that globs `<app>/app/**` misses engine code — four
scanners stopped seeing 57 views when the verticals moved, and the falling
finding count read as improvement rather than blindness.

**Checks are declared once.** Every check is a row in
`MASTER/checks/checks.yml` carrying its `require`, `Deploy::*` class, pass
line, and parent composite; `runner.rb` and
`OPENBSD/lib/check_environment.rb` both read that file by check name. Adding
a check is one row — not a new script. Most run in-process returning a
`Deploy::CheckResult`; only `release`, `rails_runtime` and `visual_contract`
subprocess.

**Source checks read text; rendered checks measure Chrome.** The
`rendered_suite` family drives real Chrome over CDP through
`checks/support/cdp_session.rb` — stdlib only, no ferrum/selenium, because
checks run under bare `ruby` outside any app bundle. Without Chrome they
degrade to warnings rather than failing, so a green run does not prove a
measurement happened.

**MASTER governs this tree.** `cd MASTER && ruby bin/check --ladder` runs
the same `/scan → /fix → /critique → /review` chain over `RAILS/` that
MASTER runs on itself, and `/fix` mutates the working tree.
`MASTER_CHECK_SCAN_ONLY=1` for preflight.

### Traps

- **Visual/CSS work:** read `__shared/README.md` first: the visual design
  system and the layout chrome contract every surface shares are there. Tokens
  live in `__shared/app/assets/stylesheets/_dialect_tokens.scss`; flat only,
  no shadow/blur/glow. Most layout "bugs" here are stale deployed CSS — diff
  live against source before changing anything.
- **Stale fragment caches:** `update_column` skips `updated_at`, so
  `[record, …]` cache keys do not bust and a page keeps rendering the old
  value while the console shows the new one.
- **`browser_diagnostics` runs through the same CDP session as the rendered
  checks.** It records console/runtime exceptions, HTTP/resource failures and
  a screenshot for every reachable route/viewport in `geometry_surfaces.yml`;
  artifacts live outside the repo under the system temp directory. Console
  warnings/errors remain soft until `CHECK_STRICT_SOFT=1`; uncaught
  exceptions, document/server errors, and missing first-party
  scripts/stylesheets fail. It is part of `rendered_suite`.
- **`visual_contract` is a compatibility route matrix over the canonical CDP
  browser session.** `layout_snapshot` holds the committed structural
  baseline. `browser_diagnostics` also compares approved PNG references in
  `MASTER/checks/data/visual_baselines/` for opted-in surfaces and writes diff
  heatmaps with pixel counts. Missing pixel baselines are soft until
  `CHECK_PIXEL_BASELINE_STRICT=1`. Approval is a separate operator action
  using `MASTER/tools/approve_visual_baselines.rb`, which promotes the exact
  reviewed artifact and protects existing references unless `--replace` is
  explicit. Structural baselines still require `CHECK_SNAPSHOT_UPDATE=1`.
- **Deploy sheds amber and bsdports**, and TLS keeps answering, so the
  outage looks like `curl 000` rather than a 5xx. Check ports 61352 and 47312
  directly.
- **App suites run in the checkout.**
  `cd RAILS/<app> && RBENV_VERSION=4.0.5 rbenv exec bundle exec rails test`
  prepares its own sqlite from the checked-in schema. The local fleet
  (`bin/operator triangle up`) serves this checkout, so a view change shows in
  the rendered checks as soon as it is saved.
- **Horizon features** in `RAILS/apps.horizon.yml` are `agent: ignore` — do
  not implement unprompted.

### Editing frontend code

Stimulus packages are vendored, never fetched from a CDN;
`__shared/README.md` explains the check that holds it and why a `pin` costs
a `modulepreload`.

The visual design and product dialect are operator-owned. By default,
restore or ask; never invent a layout fix. The explicit campaign in
`RAILS/visual_completion.yml` authorizes `/fix RAILS` to complete measured
layout, type-scale, leading, and spacing-rhythm defects in app frontend
files, using existing primitives and tokens. It does not authorize palette
or semantic colour changes, font-family changes, canonical token edits, or a
new visual identity. Browser evidence, functional/accessibility checks, and
focused tests are required. Structural snapshots may be promoted only after
the rendered quality check passes and the snapshot joins the same
rollback-safe `/fix` transaction. Missing baselines or inconclusive
measurements remain blockers.

Hidden swipe-reveal navigation is intended.

Split large mixed HTML/CSS/JS documents before editing them, and never ask a
model to rewrite one unless the output is a minimal unified diff. Structure
goes in `app/views`, styles in `app/assets/stylesheets`, Stimulus
controllers in `app/javascript/controllers` (or `shared/frontend/` when more
than one app uses them), and chart config, animations, fonts and SVG icons
each in their own file.

Extract styling verbatim. Do not normalize, minify, rename classes, drop
vendor prefixes, collapse custom animations into generic transitions, or
replace CSS custom properties with literals while moving code. Do not alter
chart options while editing chart data. Prefer an additive class over
changing an existing one, and leave `PROTECTED` sections alone unless the
task names them.

Scanners hold the parts of this that one file can show: `NO_JQUERY`,
`NO_INLINE_ASSETS_IN_SHELL`, `NO_MULTIPLE_LANGUAGES`, `NO_INLINE_STYLES`,
`MAGIC_COLOR`. The rest are properties of a diff, so they are checked by
reading one. The laws in `MASTER/data/laws.yml` govern visual decisions;
rendered token values come from `MASTER/data/tokens.yml` through
`Operator::MasterDesign`. Do not duplicate palettes, rhythm scales, or
viewport values in app code.

## RAILS/master

Written 2026-07-10 after a live debugging session that traced a "tap to
continue does nothing" bug through the full stack to a production asset
mismatch, then on to a VPS-wide resource crisis. Read this before touching
the boot sequence or the deploy path — it'll save you re-deriving all of it.

### Overview

The web tier is Rails 8 on Falcon, bound to loopback port 53187 and
published at https://ai.brgen.no through relayd. The chat surface at `GET /`
combines the assistant stream and the face runtime. Liveness is `GET /up`,
which relayd and rc.d poll because it answers before the container boots;
`GET /health` reports TTS, git and the container and is the deploy smoke
check. Streaming endpoints include `POST /chat/message` (the face's
assistant stream; there is no GET route, because a turn spends model
budget), `GET /chat/metrics` (session metrics), and `GET /events/stream`
(event bus). rc.d and `bin/smoke-web` wait for the container by GETting
`/` until it renders the face canvas instead of the warming page.

The MASTER law API is the one paid surface: `/api` sells keys through Stripe
Checkout (plans in `RAILS/__shared/config/plans.yml`, loaded by
`config/initializers/shared_billing.rb`), and `POST /api/v1/lint` judges
source text in memory with `bin/operator lint`'s rules
(`app/services/law_check.rb`). Its controllers skip `ApplicationController`,
so it needs no container.

The single HTML entrypoint is `app/views/chat/index.html.erb` via
`ChatController#index`. Runtime assets live under `public/`: `face.js` for
the THREE.js wireframe mesh, `cognition_ecology.js` for the ecology particle
layer above the face canvas, `particle_kernel.js` for the typed cell pool,
and `topology_registry.js` for topology dispatch. Topology configuration is
in `MASTER/data/topologies.yml`, not a path relative to the web app root.

Authentication accepts Bearer tokens, `X-Token`, or a `master_session`
cookie; visitors receive chat only without full tool access (see `AuthTier`
in `app/middleware/auth_tier.rb`).

After deploying web changes on the VPS, restart with
`doas rcctl restart master` and confirm with `curl` against
`http://127.0.0.1:53187/up`.

### Boot contract (high-risk path)

The chat face boot path is high-risk. The recurring regression class is:
"tap to start does nothing" — 30+ commits across this repo's history are
titled some variant of "fix primer tap/dead tap/boot," so treat any fix here
as provisional until it survives a real-browser tap test, not just a code
read.

**Invariants:**
- The face surface is the fullscreen UI: `#face` owns the entire dynamic
  viewport (`100dvw` × `100dvh`) from `inset: 0`; do not reintroduce a
  viewport-sized stage, card, or `vh`-limited face canvas.
- The installed PWA uses `display: fullscreen` and the document viewport
  keeps `viewport-fit=cover`; preserve safe-area insets for controls without
  shrinking the face surface.
- The primer markup and prompt shell must exist before renderer work starts.
- No WebGL context may be created before `go()` sets `_primerFired` true.
- `three.face.module.js` must not be compiled during initial page load.
- `face.js` is imported only after `go()` activates the renderer. The
  default `data-primer="auto"` path queues `go()` with a zero-delay timer;
  `?primer=1` and `data-primer="keep"` retain explicit primer activation.
- The prompt must become visible even if face loading fails.
- The boot manifest must keep `particle_kernel.js` before face/runtime
  consumers.
- SSE may remain open; tests must not wait for network idle on the face
  page.
- `MASTER_FACE` is the public face runtime global; do not add new
  `MASTERFace` call sites.
- `MASTERChat.startChatStream()` is the face's only chat transport. When
  `chat_actions.js` has not loaded, a send fails visibly and logs
  `face_runtime:chat_transport_missing`; there is no GET `EventSource`
  fallback to mask it. Preserve the named SSE face reactions (`mood`, `model`,
  `verdict`, `council:speech`, `confidence`, `felt`, `content_kind`) in
  `handleFaceNamedEvent()`.
- Web TTS style is unlocked by default (`auto`) so the server can infer
  style. Only send `style` with `style_locked=1` after an explicit user style
  choice.
- Server TTS is the only speech backend. Keep playback, visemes,
  cancellation, and microphone ducking on that one audio path; a server
  failure is visible as unavailable rather than silently switching to an
  OS/browser narrator.

**Files:**
- `config/face_assets.yml`: **the** manifest — every face asset the shell
  loads, grouped by load phase, order within a group being the boot contract.
  The view renders `MASTER_ASSET_PATHS` and the deferred
  `javascript_include_tag` from it (`FaceAssets`), and `/etc/rc.d/master`'s
  precompile digest reads it through `script/face_asset_paths.rb`. Adding a
  face module means adding it here.
- `app/views/chat/index.html.erb`: primer, WebGL guard, boot manifest; it
  loads `public/face_primer.js` synchronously right after `#primer` and hands
  it the digested `face.js` URL in `data-face-module`.
- `public/face_primer.js`: the primer and boot path (`go()`, `loadFace()`,
  the lazy `import()` of `face.js`, the watchdog). A classic synchronous
  script, never `defer` or `async`; listed in `face_assets.yml#shell_boot`.
- `public/face.js`: deferred face loader.
- `public/face.part*.txt`, `public/face_speech_*.js`: the six sources
  concatenated into `face.runtime.js` at build time. Not fetched at runtime.
  They stay in `public/` although nothing requests them: they hold nothing the
  served runtime does not, and a build directory would move the rake task,
  `/etc/rc.d/master`'s precompile digest, the scanner's path keys and the
  runtime-matches-sources test for no measured cost.
- `public/three.face.module.js`: heavy WebGL module, imported after `go()`
  activates the renderer and WebGL feature detection passes. **Generated, not
  vendored by hand**: `script/build_three_face.sh` npm-installs `three`
  (pinned in `script/three_build/package.json`, currently 0.184.0) and
  esbuild-bundles only the ~17 symbols `script/three_face_entry.js`
  re-exports. To change the three version, edit that package.json and re-run
  the script — do not patch the output. The tracked bundle is the build
  artifact; it is committed so the 1GB VPS never has to run npm at boot.

Until 2026-07-28 a second file, `public/three.module.js`, was also tracked:
a full unminified three r160 (Dec 2023), 53k lines, over half of everything
tracked under `web/`. Nothing imported it — `MASTER_ASSET_PATHS.threeModule`
points at `three.face.module.js`, and the only textual match for its name
was a license comment inside that bundle. Deleted. If you find yourself
adding a raw three build back, check whether the entry-point re-export list
is what you actually want to extend instead.
- `public/visual_bridge.js`: runtime event/SSE bridge.
- `public/cognition_ecology*.js`: 2D canvas ecology, allowed before primer.

**Checks:**
- `bin/check --profile=web` (there is no `bin/check-web`; the profile
  replaced it)
-
  `ruby -Ilib:test test/test_web_ui.rb --name test_public_asset_manifest_matches_source_files`
- Manual real-browser boot test after boot changes (see below) — headless
  CDP tools have shown false hangs in sandboxed environments in this repo's
  history, so a real browser is the trustworthy signal, not a scripted one.

**Manual boot test:**
1. Start the web app on a local port.
2. Open the default chat URL in a real browser — and on iOS Safari when boot
   assets change materially, because nothing in CI drives a real touch event.
3. Confirm the page autostarts without a blocking primer, the prompt becomes
   usable, and the face starts or reports failure visibly.
4. Confirm a first tap or typed message is accepted on the default path.
5. Open `?primer=1`; confirm the primer responds to tap and Enter, the
   prompt is hidden before activation, and no WebGL context starts before
   `go()`.
6. Confirm the prompt remains usable if face loading fails and inspect
   console errors for eager WebGL or THREE.js boot before `_primerFired`.

### Runtime contract (chat, face, TTS)
Fullscreen invariant: the face surface owns the entire dynamic viewport.
`canvas#face` and the face shell must remain edge-to-edge at `100dvw` ×
`100dvh`; the installed PWA manifest prefers `fullscreen`. Do not
reintroduce a viewport-sized frame, card, inset canvas, or
`min-height: 44vh` face root. Safe-area insets belong to the chrome
controls, not to the face canvas. The renderer remains fixed at the viewport
origin while prompt, captions, microphone state, and other controls consume
`env(safe-area-inset-*)` through the existing inset tokens.

`chat_actions.js` owns the preferred POST streaming transport and SSE block
parser. `face.part5.txt` / `face.runtime.js` own the face-specific reaction
layer: token chunks drive chat text and TTS; named events drive mood, model
badges, verdict pulses, council mouth offsets, confidence, and felt state.
When adding a named SSE event, decide deliberately whether it belongs in the
generic `sse_contract.js` handlers, the face-specific
`handleFaceNamedEvent()`, or both.

`face.runtime.js` is generated by `rails assets:build_face_runtime` (which
`assets:precompile` enhances, so a deploy rebuilds it). Edit a source and
run the task; a hand edit to the built file survives only until the next
precompile.

Its sources are six files in load order, and two of them are **not** part
files:

    face.part1.txt  face.part2.txt  face.part3.txt
    face_speech_runtime.js  face_speech_playback.js
    face.part5.txt

There is no `face.part4.txt` — the two speech files sit in its place, and
that is where TTS, the browser-voice default and the STT duck live. Reading
this list as `face.part*.txt` sends you looking for that code in a part file
that does not contain it.
`RAILS/test/master_web_ascii_face_contract_test.rb` checks that
`face.runtime.js` names each of the six by its current digest and fails on
any drift, naming the task to run.

### The browser defaults to the 3D point-cloud face; ASCII stays supported

The browser's absent `face_mode` parameter (and `face_mode=auto`) selects
the 3D particle head. Use `?face_mode=ascii` to request the plain-ASCII
renderer explicitly. The CLI remains ASCII-first. The runtime probes WebGL
on a disposable canvas only after `go()` activates the face; it never binds
`#face` to 2D and later attempts WebGL on that same canvas. If WebGL is
unavailable or the THREE module cannot import, the runtime waits briefly for
the shared ASCII renderer and uses it on `#face`. If both paths are
unavailable, the runtime reports that state and the independent
`face_2d_fallback.js` canvas remains available instead of treating the
failure as success.

`public/face_ascii.js` remains the renderer ported from
`MASTER/lib/cli/face/`. It reads the face contract in
`MASTER/data/tokens.yml`, reconstructs the head from the depth map and
morphology, rasterises and lights it on the CPU, and draws characters on
`#face` with a 2D context. The Ruby renderer and browser renderer share the
fixture `MASTER/test/fixtures/face_ascii_frames.json`;
`RAILS/master/test/face_ascii.test.mjs` holds browser frames to it character
for character. `face_2d_fallback.js` draws the same head at rest on its own
canvas until the runtime takes over. The primary 3D head remains a single
crisp point-cloud surface: one-pixel points, neutral grayscale depth and
normal-driven sculpting, with no wireframe edges or added glow. Secondary
orbit particles are deterministic and dimmer than the face, so the identity
remains the focal point.

The face's slow transitions are its timing, not debt. `face.css` fades a
reveal over 1.2s, and `chat_upload.css` steps over .42s;
`NO_LONG_TRANSITION` caps UI transitions at 300ms and reads only `ms`, so it
never sees these. Do not snap them to satisfy a rule that widens.

TTS requests should omit `style` unless the user explicitly locks one
through the UI or `/voice ... <style>`. Server TTS failures may temporarily
use browser speech, but the cooldown must expire so the Edge/server voice
can recover without a page reload.

Web wiring can be correct while synthesis is unavailable, because audio
depends on host binaries. `GET /health` `deploy.tts_socket` is a capability
check, not proof the box writes an MP3. There is no `edge-tts` executable to
look for: MASTER runs `bin/tts-worker` under its own bundle, and the gem is
spelled `rb-edge-tts` in the Gemfile and `rb_edge_tts` in the require, so a
grep for one misses the other. The ground truth is
`echo hi | ruby bin/tts-worker en-GB-RyanNeural +0% +0Hz /tmp/x.mp3`. Any
post-synthesis step that falls back when ffmpeg is missing calls
`report_missing_ffmpeg` in `lib/voice/engines.rb` rather than returning
quietly.

The face's `mood` listener (the tint through `fadeColorTo`) and
`chat_service.rb`'s `agent:mood` subscription now have a producer:
`Homeostat#observe` publishes `agent:mood` only when the derived mood
changes. `felt:sense` remains separate — it echoes the browser's own posted
state.

### RESOLVED 2026-07-11: the real "dead tap" root cause was a MutationObserver loop

After 30+ provisional "fix primer tap" commits, the actual cause of the
slow-page / infinite-loading-spinner / dead-tap triad was found and fixed:
`public/face_state.js`'s `observe()` watched `attributes: true` on the same
elements (`#status`, `#ui-status`, `#pipeline-stage`) whose
`data-runtime-status` attribute its own callback writes via `applyFrom()`.
Each write re-fired the observer → wrote again → an infinite
mutation→observe→mutate **microtask** loop that permanently starved the main
thread. Because it's a microtask flood (not a plain `while` loop), the
thread never yields to rendering or input — so the page load event never
fires (spinner), and the primer's tap listeners never get a slot (dead tap).
Fix: drop `attributes` from the observe options; `runtimeStatus` is only
ever written by this file, so there was no external attribute change worth
observing. The real external signal (status text) still fires via
`childList`/`characterData`.

Two things this exposed, both worth heeding:
- **Headless bisection *did* find it**, contradicting the "false hangs"
  caution below. The trustworthy method was a *controlled A/B*:
  intercept-and-block one script at a time (via ferrum/Playwright request
  interception) and probe main- thread responsiveness with a short-timeout
  `evaluate`. Blocking *only* `face_state.js` flipped the page from wedged to
  responsive; a sandbox false- hang can't produce that selective result. A raw
  "it hangs" from one load is untrustworthy; a bisect is not.
- **The rc.d precompile-skip digest used to be incomplete.**
  `/etc/rc.d/master`'s `_digest=$(cksum …)` named its inputs by hand, so
  editing a face module it did not list **silently skipped precompile** on
  restart and kept the stale fingerprint live. A `face_*.js` glob later fixed
  that for the face_-prefixed half and still left 15 of 38 uncovered — among
  them `particle_kernel.js`, `face.runtime.js` and `three.face.module.js`.
  Since 2026-07-28 the digest reads `config/face_assets.yml` via
  `script/face_asset_paths.rb`, so a module is covered the moment it is
  declared. **Declare new face assets in that manifest** — not doing so is now
  the only way to reproduce the old failure.

### The primer → face boot sequence

The page loads with a black `#primer` overlay ("tap to start"). Two
independent mechanisms can dismiss it:

1. An early inline `<script>` in `<head>` (`armPrimer()`) attaches
   pointerdown/click/touchend/keydown listeners as soon as the DOM is ready.
   It's a **fallback** — if the fuller boot script below hasn't defined
   `window.__MASTER_PRIMER_GO__` yet, it does a minimal dismiss itself.
2. A later inline `<script>` (non-deferred, so it runs synchronously at
   parse time, before `DOMContentLoaded`) defines the real `go()` function,
   assigns it to `window.__MASTER_PRIMER_GO__`, and attaches its own listeners
   directly to `#primer`. In practice this one wins essentially every time,
   since it's parsed before any real user tap can occur.

`go()` calls `dismissPrimer()` and `revealPrompt()` **synchronously and
unconditionally**, before anything WebGL-related happens. This means: if the
overlay ever fails to disappear on tap, with *zero* visible change anywhere
on screen (no prompt bar, no status text), the tap handlers themselves never
ran — that's a client-side JS execution problem (browser
extension/content-blocker silently stripping scripts, or a CSP issue), not a
bug in this boot code. Verified during this session: a browser extension was
silently blocking all page JS in the normal profile; incognito (which
disables most extensions) let the primer dismiss correctly.

After dismissal, `loadFace()` dynamically `import()`s the fingerprinted
`face.js` bundle. That file is a *thin loader*, not the real renderer — it:
- imports 10 small `face_*.js` helper modules directly via
  `MASTER_ASSET_PATHS`
- fetches the single prebuilt `face.runtime.js` and imports it as a `Blob`
  URL module (works because CSP's `script-src` already includes `blob:`). It
  does not fetch the sources; concatenation happens at build time, not in the
  browser
- feature-detects WebGL with a throwaway `<canvas>` before paying the ~1.3MB
  THREE.js parse cost; falls back to a lighter "2D mode" path otherwise, which
  is why an unresponsive face on an unusual browser isn't automatically a bug
  — check for real WebGL support first.

Separately, `face_deferred_loader.js` waits for the `primer:ready` event and
loads a *second*, independent "vision" layer (`face_vision.bundle.js`,
`cognition_ecology.js`). The core face runtime dispatches
`master:face-ready` from `markFaceReady()`; the vision modules use that
event for boot metrics and deferred hooks. `/canvas/topology` is a Rails
route, and the viseme-pack loader must keep using
`MASTER_ASSET_PATHS.visemePacks` rather than hardcoded asset URLs. Do not
expose `MASTER/data/laws.yml` directly to visitors unless there is an
explicit product/security decision to make those rules public.

### The asset-manifest footgun (bit us twice in one session)

Propshaft's dev-mode `public/assets/.manifest.json`, once present, is
consulted instead of the live filesystem — so adding a new asset without
regenerating the manifest 404s it, even though `assets:precompile` ran.
Worse in production: the *running* Falcon process's in-memory asset state
can go stale relative to what's actually on disk if a newer build lands
after the process booted. A file can exist, `curl` can 200 it directly, and
the app can still 404 trying to `asset_path()` it — until restarted.

This is why `master`'s `rc.d` script now runs `master_web_assets_check.rb`
as a hard, load-bearing check before starting (added 2026-07-10, one retry
via forced `assets:precompile` before it actually refuses to start). If
`master` won't start and the log shows "assets check failed", that's telling
you the truth — don't work around it, find out what's actually missing.

### Deploy state

- `RAILS/apps.yml` registers master beside brgen, amber and bsdports, with
  its port and domain. It is not a copy-tree app:
  `zsh OPENBSD/bin/vps-deploy master` runs `OPENBSD/bin/vps_deploy_master.sh`,
  which pulls and restarts it in place under `/home/dev/pub4/RAILS/master`.
- `rcctl restart master` runs a real `rc_pre()`: kills stale processes,
  regenerates the face bundles if missing, precompiles assets if a content
  digest changed, runs the check above, then starts Falcon and waits for `/up`
  before restarting `relayd` (relayd can keep routing to a dead backend
  connection after a restart until kicked).
- A `/home/dev/pub4/.deploying-<app>` lock file is touched for the duration
  of each app's `rc_pre()` — check for it before assuming any app's asset/db
  state is stable if you're debugging remotely while a restart might be in
  flight.
- **The canonical source for every `/etc/rc.d/<app>` script and
  `resource_guard.sh` is this repo** (`OPENBSD/etc/rc.d/*`,
  `OPENBSD/bin/resource_guard.sh`) — not whatever is live on the VPS. If you
  edit the live file directly (as happened during tonight's incident
  response), **mirror the change back into the repo file**, or the next sync
  from repo → server will silently revert your fix.

### brgen is multi-domain, not multi-tenant-by-header

`brgen`'s app serves ~20 separate city domains (`brgen.no`, `oshlo.no`,
`lsangeles.com`, …) plus per-city vertical subdomains (`tv.*`, `dating.*`,
`playlist.*`, `takeaway.*`, `marketplace.*` — the marketplace subdomain name
is itself localized per country, see
`Brgen::DomainRegistry::SUBAPP_ALIASES`).
`Brgen::DomainRegistry.resolve(host)` is the one true way to find "which
city, which vertical" for the current request — reuse it rather than
re-deriving subdomain logic, and remember a static `robots.txt`/`public/*`
file can't vary per domain the way a routed, dynamically-rendered response
can.

### The VPS is genuinely small

1 vCPU, ~1GB RAM, running `master`, `brgen`, `amber`, `bsdports`
concurrently. A load average of 1.0 here means the single core is busy — not
distress. `resource_guard.sh` (cron, every 5 min) sheds `amber` then
`bsdports` under sustained pressure and restores them when it clears. It is
armed: the pause flag `/var/db/pub4_all_apps` is absent on vm23, and this
paragraph described the flag as paused for two months after that stopped
being true. The operator recalibrated it twice since, each time against the
history log rather than a guess, so read the thresholds from the script and
never from prose — the OPENBSD section below explains which log answers
which question. Restarting more than one or two of these apps back-to-back
spikes load into the 4–7 range for a few minutes purely from cold-start
warm-up; that's expected, not a crisis, as long as swap isn't also climbing.

## OPENBSD

Operator-facing docs live in `README.md` and `RUNBOOK.md`, and the recipes
in `OPENBSD/data/operator.yml`. This section is the sharp edges that have
burned agents in this repo — read it before touching the deploy pipeline,
not after.

### The fleet is four, and master is the one that gets dropped

`bin/vps-deploy all` deploys `master brgen amber bsdports`, in that order,
halting the pass on the first failure. Prefer it over four hand-typed runs.

Until it existed there was no way to say "deploy everything", so the set
lived in whoever was typing — and master is not under `/home/*/app`, so an
operator enumerating the Rails apps does not see it and leaves it behind. A
pull moves the checkout for everything; only a deploy makes any of it live.

The order is load-bearing, not alphabetical. Every deploy sheds amber and
bsdports: they land in `rcctl failed` with ports 61352/47312 closed while
relayd keeps answering TLS, so the outage reads as a hang rather than a 5xx
and nothing reports it. Deploying those two last folds the restore into the
same pass, and the top-level run's exit trap restores every service that was
up when the deploy began, one at a time, so a halt no longer leaves
production down. Since 2026-10-12 the pass also pins one SHA, refuses a
commit that fails `MASTER/lib/operator/canary.rb`, and puts master first
only when the apps are up and memory allows; `RUNBOOK.md`, "The deploy
sequence and its recovery", has the steps.

Related, and worth knowing before you diagnose a deploy: **a shed and a
relayd failure look nothing alike once you check.** A shed leaves 443
answering with the app port closed. If **443** refuses in ~30 ms while sshd
is up and the app answers on its own port from the box, the front door is
down, not a backend — and if something you did not deploy (ai.brgen.no) is
down too, that is the diagnosis rather than collateral.

Do not read port 80 as part of that test, but not for the reason this
section gave until 2026-08-25. It said port 80 "always refuses", that
`relayd.conf` declares the only listener, and that "there is no HTTP
listener to lose". That is wrong: `httpd` runs as `www` and holds `*.80`,
and `fstat` on vm23 shows three of its processes there. relayd does declare
exactly one relay — `listen on 0.0.0.0 port 443 tls` — but relayd is not the
only daemon on the box.

What port 80 answers is a 301 to HTTPS, plus ACME HTTP-01 challenges out of
`/acme`; the first server block in `/etc/httpd.conf` says so. So a request
to 80 returns 301 whether or not a single Rails app is running, which is why
it carries no information about a shed or a relayd failure — the same
conclusion the old paragraph reached from a false premise, and it is worth
keeping the distinction because the premise has a consequence the conclusion
does not: if port 80 ever *does* refuse, that is a real finding. Certificate
renewal goes through it, so httpd being down means the certs stop renewing
silently and the site fails ~90 days later for a reason nothing will connect
to this.

The original note is still true of the mistake that produced it:
`curl http://brgen.no:443/up` speaks plain HTTP at a TLS port and returns
000, so a check written that way reports both ports refusing and looks
exactly like the outage it is inventing.

`httpd.conf`'s second server block serves `/postpro` — personal photographs
— with no TLS and no auth, on `127.0.0.1 port 6666`. Reach it over an ssh
tunnel. It listened on `*` until pf's default deny was the only thing
keeping it private; if anyone widens that listener again, pf becomes the
exposure's only guard.

### `SKIP_CI=1` does not mean "skip CI"

`bin/vps-deploy <app>` takes one of two branches:

- **Default** (`SKIP_CI` unset): `vps_ci.sh <app>` syncs the repo into a CI
  mirror and runs `bin/ci` (see below) against a throwaway test DB.
- **`SKIP_CI=1`**: skips `vps_ci.sh` and runs `RAILS/<app>/<app>.sh`, which
  calls `deploy_tracked_app` → `rails_runtime_check`. That check bundles,
  prepares the databases, precompiles assets and runs `bin/ci` inside the
  deployed `/home/<app>/app` tree. CI still runs, in a different place.

The fast hotfix path uses `SKIP_RUNTIME_CHECK=1` and `SKIP_CI=1`, but the
runtime skip is now protected by the human-only `I_UNDERSTAND_FAST_DEPLOY=1`
acknowledgement. Without that exact acknowledgement, `rails_runtime_check`
refuses to bypass CI. When the acknowledgement is supplied, the hotfix path
runs no `bin/ci`; only the loopback checks `vps-deploy` runs after each
restart.

### `bin/ci`'s `Setup` step behaves differently locally vs. on the VPS

`RAILS/__shared/config/ci.rb` checks several steps on `vps_host` (true when
`PUB4_CI_GUARD=1`, `/var/db/pub4_vps` exists, or `/etc/relayd.conf` exists):

- `Security: Importmap audit` and `Tests: System (a11y)` — **skipped on the
  VPS**, required locally. A local `bin/ci` failure in those two is real; it
  does not mean the VPS run will also fail. Both need something the box does
  not have on hand (a booted environment, a browser).
- `Style: Ruby` (RuboCop) — **runs on the VPS too**, and this list said
  otherwise until 2026-08-25. `ci.rb` carries the reason next to the step:
  vm23 is where the deploy check actually runs, so skipping it there left
  enforcement to a local `bin/ci` that nothing runs automatically. It is a
  source-text check needing no browser and no database, so the reasons the
  other two are skipped do not apply. A RuboCop failure on the box is a real
  deploy blocker — do not read it as a local-only bucket, which is exactly
  what this file used to say.
- `Tests: Seeds` — runs with `SKIP_BERGEN_DEMO=1` on the VPS, without it
  locally. A local seed failure about a duplicate Bergen demo email is a
  local-DB-state artifact, not a real blocker — don't chase it.
- `Setup` (`bin/setup --skip-server`, includes `db:prepare`) replays the
  full migration history. A stale local dev DB can hit a legacy FK-naming
  mismatch that only existed mid-history and was never a bug in current
  schema.rb. Confirm against a fresh DB (or the VPS run) before treating this
  as real.

**Decision test:** a local `bin/ci` failure is only actionable if you can
name which of the above buckets it's *not* in. When in doubt, read
`RAILS/__shared/config/ci.rb` directly rather than assuming.

### Two layouts: the repo and the box's copy-tree

Code runs in two shapes of the same tree, and a path that is right in one is
wrong in the other. Nearly every deploy failure of 2026-10-09 was this,
found one at a time over a forty-minute CI loop.

The repo checkout has `RAILS/<app>`, `RAILS/__shared`, `RAILS/brgen_*`,
`MASTER`, `OPENBSD` and `STUDIO` side by side. On vm23 an app's user sees
only `/home/<app>/app` (the contents of `RAILS/<app>`, so the directory is
called `app`, never `brgen`), `/home/<app>/__shared`, and for brgen the
`/home/brgen/brgen_*` siblings. MASTER is not in it. `PUB4_ROOT`, exported
by `rc.d` and by `vps_ci.sh`, names the full checkout at `/home/dev/pub4`,
which holds MASTER and `RAILS/apps.yml`.

What to write, so both layouts work:

- An app file: `Rails.root`, never `File.expand_path` with a fixed run of
  `..`, and never a literal `brgen/` path segment.
- A sibling engine: `Rails.root.join("..", "brgen_marketplace")`. It
  resolves in both, because the engines are siblings of the app in both.
- Anything in MASTER or the repo root: `Shared::Contracts.root`, `.dir` and
  `.tool_path` (`RAILS/__shared/lib/shared/contracts.rb`). They honour
  `PUB4_ROOT` and fall back to walking up from the checkout.
- Never `engines/<x>` under the app root (the directory is gone), and never
  `RAILS/shared` (it is `RAILS/__shared`).

Three static guards enforce this without a Rails boot, and
`ruby OPENBSD/bin/rehearse` runs them in seconds before any deploy:
`test_deploy_paths_exist.rb` (every repo path a deploy script names exists),
`RAILS/test/test_path_idioms_test.rb` (the walk-up and `brgen/` idioms), and
`RAILS/test/require_relative_targets_test.rb`. Run it before `vps-deploy`;
the box's `rails_test` is where only the failures it cannot see survive, and
that step takes about 80 minutes on one vCPU.

### Copy-tree sync must delete before it extracts

`vps_ci.sh`'s `sync_from_repo()`/`sync_ci_rails_root()` sync the repo to
each app's copy-tree via `tar` extraction. Tar extraction only *overlays* —
it never deletes destination files that are absent from the source. A file
deleted from git therefore survived indefinitely on the VPS's copy-tree
checkout, invisibly, until something referenced it and broke at runtime.

Adding `doas rm -rf` before each `tar xf -` extraction fixed this (both in
`sync_from_repo()`'s per-directory loop and in `sync_ci_rails_root()`). If
you're debugging a VPS-only failure where a file "shouldn't exist anymore"
but the error implies it does, first check whether your local `vps_ci.sh` is
current — this exact bug reappearing (e.g. via a revert) would look like
ghost files coming back from the dead.

### `rcctl check` can report "failed" while the service is still booting

Falcon takes ~30-40s to fully boot under VPS load (1 vCPU, shared with other
apps). `doas rcctl check <app>` polled a few seconds after `rcctl restart`
can report `failed` even though the process is healthy and mid-startup —
this is not a crash. Before treating a post-deploy `rcctl check` failure as
real:

- `tail /var/log/daemon` for the app — look for a normal "Waiting for
  startup..." progression vs. an actual stack trace/exit.
- `ps ax | grep <app>` — is the Falcon process actually running?
- Retry `rcctl check` after ~30s before escalating.

A "completed (exit code 0)" notification from a background deploy command is
**not** proof the deploy succeeded either — it reflects the SSH wrapper's
exit, not the deployed script's outcome. Always verify independently via:

1. The deploy stamp: `/var/db/pub4/last_deploy_<app>.json` (`status: "ok"`
   and the expected SHA).
2. `doas rcctl check <app>`.
3. A live `curl` against the app's actual URL, not just `/up`.

### `resource_guard.sh` shedding amber/bsdports — check it actually recovers

Under load, the VPS's `resource_guard.sh` cron sheds `amber`/`bsdports`
(tracked in `/var/db/resource_guard_shed`). Check that file first to confirm
a down app is the guard and not a real crash.

But do not stop there and call it self-recovering, which is what this
section used to say. Shed and restore are separate checks and they can drift
one way. Measured on 2026-07-29 over 916 ticks: shedding fired on 48% of
ticks while the restore check opened on 19%, and restore only releases one
service per tick — so amber and bsdports had been down for days, not
oscillating. `MEM_RESTORE` was 20% against a median availability of 13%,
i.e. the window sat outside the box's operating range, so that pass set 8/14
and `LOAD_RESTORE` 2.0.

The operator recalibrated it once more since, and this paragraph said 8/14
for a month after it stopped being true. `MEM_RESTORE` is **10**, set on
2026-08-14 from 1550 ticks: availability had moved from p50 13 to p50 9, so
14 had drifted back above p75 — the same condition the 2026-07-29 pass
existed to fix, arriving a second time from the other direction. `MEM_WARN`
is 8 and `LOAD_RESTORE` 2.0.

Read the numbers from `resource_guard.sh`, which carries each recalibration
with the dataset that justified it. A threshold copied into prose is a
threshold that goes stale the next time the box changes.

The check that distinguishes the two cases is
`/var/log/resource_guard_history.log`, which records `load=`, `mem_avail=`
and `shed=` per tick. If shed ticks vastly outnumber ticks that satisfy
`shed=0 && mem_avail >= MEM_RESTORE && load < LOAD_RESTORE`, the guard is
parking those apps, not cycling them, and the thresholds need recalibrating
against that log rather than against a guess.

### Refused, and why

Each of these went through a proposal and a measurement against the tree. A
reason tied to one file sits in a comment on that file; these have no single
file to sit on.

- **No fourth public Rails app** beyond brgen, amber and bsdports until
  brgen's high-churn verticals are engines with their own migrations and
  tests, money and identity primitives live in `RAILS/__shared` with more than
  one consumer, and CI runs the layout suite and `/up` smoke for all three
  apps. Every restart before pub4 grew surface before its boundaries held;
  horizon ideas wait in `RAILS/apps.horizon.yml`.
- **No staging environment.** vm23 is one vCPU and 1 GB and already sheds
  apps under load. A staging copy arrives with a second box, not as a second
  set of services on this one.
- **No second reference platform.** OpenBSD's behaviour wins over the Mac's
  for package names, services, relayd, pf, nsd and Ruby command names.
  Production is one host family with one Ruby pin, so a platform matrix or a
  Linux runner cannot reproduce what differs: the Mac and box locks disagree
  because `rb-kqueue` resolves only on BSD, and the fix is the `install_if`
  entry in the Gemfile.
- **No repair-plan command, no dry run on every mutating command, and no
  deploy that fails closed on revision drift.** A deploy is the only mutation
  and halts on its first failure. Revisions disagree between deploys by
  design, which is why `health_check.rb` warns on commits behind, and failing
  closed blocks the deploy that fixes the drift. A planning surface beside
  `vps-deploy` is a third surface where the root contract allows two.
- **No automated rollback.** Rolling back is deploying the previous SHA
  through `vps-deploy`. A second path that runs once a year is untested on the
  day it is needed, the same argument the three unrun recovery scripts carry
  in their headers.
- **No pledge or unveil for the Rails daemons.** A Ruby interpreter that
  loads native extensions and forks workers cannot name a useful promise set.
  MASTER's `Ground::Pledge` covers the one process that can, and each app runs
  as its own user with its env file and storage closed to others, which
  `health_check.rb` checks.
- **No speed work on deploy or health tooling without a symptom.** The box's
  measured problem is memory, which is why `core-reclaim.sh` and
  `keep-warm.sh` exist, not the cost of a check's system calls. A health check
  made faster by proving less is a regression. Latency work starts from a
  symptom a visitor or a log names, and is measured on vm23.
- **No idempotency keys, cart expiry, stuck-order alarms or edit locks for
  takeaway and marketplace while no vendor is live.** Turbo disables a submit
  in flight and the order state machine refuses illegal transitions under
  test. The first duplicate order from a real kitchen is the measurement they
  wait for.
- **No per-component screenshot baselines, density tests or control-distance
  rules.** `layout_snapshot` commits reviewable geometry for the surfaces, and
  how dense a screen is stays the operator's call about how it looks.
- **Keep four hand-run scripts that nothing calls, and delete orphans that
  nothing names.** `bin/manual_master_deploy.ksh` (the fallback when
  `vps_deploy_master.sh` stalls), `bin/vps_production_push.sh` (the
  acknowledged hotfix path), `ptr_openbsd_amsterdam.rb` (the only door to the
  PTR record) and `bin/amber_queue_sweep.sh` (the backlog sweep
  `RAILS/amber/README.md` names) have no cron or script caller because their
  caller is a person, and RUNBOOK, "Occasional operator tools", lists each. A
  zero-caller census measures the wrong thing for them. `dr-restore-check` and
  `uptime-probe` had neither a caller nor a name anywhere, and
  `dr-pull --drill` and `domain_watch.rb --tls` now do what they were for, so
  the operator deleted them. `bin/vps-deploy` stays the one serial deploy
  entrypoint. `entrypoints.openbsd` was 46 against a ceiling of 34 on
  2026-10-12; the ceiling does not move, and the number falls by folding a
  script into `bin/check` or `bin/vps-deploy`, never by deleting a recovery
  door.
- **No sweep of `|| true`.** Most are idempotence on `rcctl`, `pkill`,
  `chmod`, `install` and `rm -f`. Read the exit path before removing one.
- **No deleting the four documented fallback scripts.**
  `manual_master_deploy.ksh`, `vps_production_push.sh`,
  `ptr_openbsd_amsterdam.rb` and `amber_queue_sweep.sh` look unused because
  `vps-deploy` and cron cover the ordinary case. Each is the documented answer
  to a failure that case cannot reach: a stalled MASTER deploy, a push from
  the box, a changed IP needing a new PTR, a stale Solid Queue backlog.
  `RUNBOOK.md` lists them, so removing one removes a recovery step an operator
  reads at the worst time.

## Repository mechanics

**One branch.** `main` is the only branch; work lands as path-scoped
commits straight to it, per the agent contract. The topic-branch and PR
era ended on 2026-11-02: all fifteen remote branches were folded into
`main` and deleted, all open PRs were resolved, and GitHub auto-deletes
a branch when its PR merges. Tags mark the archaeology:
`consolidation-20261102` is the fold point; `v0.1`, `v1.0`,
`dilla-v0.1` and `dilla-engine-final` predate the current lineage.

**Never force-push.** The pre-consolidation re-cut era is over. A bad
landing is reverted with a commit, not rewritten away.

**Generated artifacts are not tracked.** `FULL.yml` (retired
2026-11-02) was the last generated corpus kept in git; snapshots under
`snapshot_*.md` stay untracked by the same rule.

**Vendorables trend out of git.** The ML binaries under
`RAILS/master/public/` (~28 MB: onnxruntime WASM, smart-turn model,
face mask, webfonts) are the remaining weight; prefer fetching at
deploy time with checksums before ever considering LFS.
