# Web Boot Contract

The chat face boot path is high-risk. The recurring regression class is: "tap to start does nothing."

## Invariants

- The page must render the primer before heavy face work starts.
- No WebGL context may be created before `_primerFired` is true.
- `three.face.module.js` must not be compiled during initial page load.
- `face.js` must be imported only after the primer tap.
- The prompt must become visible even if face loading fails.
- The boot manifest must keep `particle_kernel.js` before face/runtime consumers.
- SSE may remain open; tests must not wait for network idle on the face page.

## Files

- `app/views/chat/index.html.erb`: primer, WebGL guard, boot manifest, lazy `import("face.js")`.
- `public/face.js`: deferred face loader.
- `public/face.part*.txt`: split face runtime payload.
- `public/three.face.module.js`: heavy WebGL module, warmed by prefetch only.
- `public/visual_bridge.js`: runtime event/SSE bridge.
- `public/cognition_ecology*.js`: 2D canvas ecology, allowed before primer.

## Checks

- `bin/check-web`
- `ruby -Ilib:test test/test_web_ui.rb --name test_public_asset_manifest_matches_source_files`
- Manual real-browser tap test after boot changes.

## Manual Tap Test

1. Start the web app on a local port.
2. Open the chat page in a real browser.
3. Before tapping, confirm the primer is responsive and the prompt is hidden.
4. Tap or press Enter.
5. Confirm the primer dismisses, prompt appears, and the face either starts or fails visibly.
6. Confirm console errors do not indicate eager WebGL or THREE.js boot before tap.
