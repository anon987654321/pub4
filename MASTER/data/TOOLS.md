# TOOLS

TOOLS.md is the human-editable registry for local tools, skills, and MCP endpoints that MASTER may invoke. It documents what exists on the machine, how to reach it, and any availability constraints so operators and agents share the same factual surface.

On the VPS, base tooling follows OpenBSD conventions. Deploy and service operations rely on rcctl, relayd, httpd, pf, doas, and openrsync. Keep availability notes factual and current so stale entries do not send callers at broken paths.