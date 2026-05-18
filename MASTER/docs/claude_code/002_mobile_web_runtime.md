# Claude Code Handoff: Mobile Web Runtime

## Goal

Turn `MASTER/data/mobile_web_opportunities.yml` into an actionable mobile-web/PWA implementation path for MASTER.

The target is not a full native app. Start with a robust installable mobile web runtime that improves offline behavior, mobile interaction, and preview-gated Face3D performance.

## Existing source files

Read first:

- `MASTER/data/mobile_web_opportunities.yml`
- `MASTER/web/app/views/chat/index.html.erb`
- `MASTER/web/public/manifest.json`
- `MASTER/web/public/face.js`
- `MASTER/web/public/face3d_engine.js`
- `MASTER/web/public/face3d_renderer.js`
- `MASTER/web/public/face3d_preview.js`
- `MASTER/web/public/visual_bridge.js`
- `MASTER/web/public/cluster_miner.js`

## Implementation tasks

### 1. Audit installability

Create a short doc or test checklist for:

- manifest validity
- service worker presence/absence
- offline shell behavior
- icons/theme color
- viewport/mobile safe-area handling
- standalone display behavior
- touch target sizes
- reduced motion support

### 2. Add service worker strategy if missing

If no service worker exists, add a minimal one that caches only the safe static shell assets first:

- CSS
- JS modules
- manifest
- icons

Do not cache chat responses or private conversations yet.

### 3. Add mobile performance guardrails

Face3D and retro face should respect:

- low battery / battery saver if available
- coarse pointer/mobile device
- reduced motion
- thermal/fps degradation by observed frame time

Prefer using existing `QualityController` in `face3d_engine.js` where possible.

### 4. Add mobile attention UI hook

Expose current `attention:context` and `master:clusters` in a minimal non-intrusive mobile UI affordance, for example:

- tiny breadcrumb overlay in debug mode only
- hidden by default
- activated with `?debug=1` or `?attention=1`

### 5. Add offline event queue design

Do not implement full sync yet unless easy. Add a structured doc/spec for:

- queued local events
- retry policy
- what must never be queued privately without encryption
- how provider/network failures degrade into browser-local or offline mode

## Acceptance criteria

- MASTER has a documented mobile installability checklist.
- If a service worker is added, it caches only static shell assets.
- Face3D preview remains gated behind `?face3d=1`.
- Mobile/reduced-motion/battery constraints are respected.
- No private chat logs are cached by default.
- A clear follow-up path exists for offline-first memory/sync.

## Non-goals

- Do not add native Capacitor/Tauri shell yet.
- Do not add push notifications yet.
- Do not cache user conversations by default.
- Do not replace the live `face.js` renderer.
- Do not require WebGPU for baseline mobile use.

## Suggested PR title after implementation

`Add mobile PWA runtime guardrails`
