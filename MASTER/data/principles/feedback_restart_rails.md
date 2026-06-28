---
name: Restart MASTER service after every web/* edit
description: Whenever I update any file under MASTER/web/ on the VPS, restart the master rc.d service so the change takes effect; do not batch updates and restart at the end
type: feedback
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
After every scp of MASTER/web/, live MASTER/lib/, or MASTER/data YAML on the VPS, run doas rcctl restart master—one file, one restart. Falcon does not hot-reload; wait about two seconds before curl checks.

CLI-only edits skip restart unless the web layer is in use. Do not batch multiple web edits and restart only at the end.