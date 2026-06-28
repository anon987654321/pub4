---
name: Restart MASTER service after every web/* edit
description: Whenever I update any file under MASTER/web/ on the VPS, restart the master rc.d service so the change takes effect; do not batch updates and restart at the end
type: feedback
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
After every scp under `MASTER/web/`, live `MASTER/lib/`, or `MASTER/data/*.yml`, run `doas rcctl restart master` on VPS — one file, one restart. Falcon won't hot-reload. Wait ~2s before curl checks. CLI-only edits skip restart unless web is in use.