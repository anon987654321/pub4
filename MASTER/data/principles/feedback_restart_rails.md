---
name: Restart MASTER service after every web/* edit
description: Whenever I update any file under MASTER/web/ on the VPS, restart the master rc.d service so the change takes effect; do not batch updates and restart at the end
type: feedback
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
After every scp of any file under `MASTER/web/` (controllers, views, initializers, config), immediately run `doas rcctl restart master 2>&1` on the VPS before moving on. Falcon does not hot-reload code in production mode — without a restart, the deployed app still serves the prior bytecode and the user sees stale behavior.

**Why:** User correction 2026-05-06 ("restart the rails app every time you update it"). I had been batching multiple web edits and restarting once at the end, which left the user staring at unchanged behavior between scps.

**How to apply:**
- Edit one web file → scp → `doas rcctl restart master` → next edit, even if more edits to that same file are coming.
- Allow ~2 seconds after restart before any verification curl, since Falcon cold-starts the container.
- Lib edits (`MASTER/lib/`) follow the same rule when they're in the live require path.
- Data file edits (`MASTER/data/*.yml`) load at boot too — restart for those as well.
- CLI-only changes (`exe/master`, `lib/master/cli/*`) don't need a restart unless the operator is also using the web surface.
