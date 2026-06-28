---
name: MASTER project context
description: pub4/MASTER — constitutional AI coding agent on OpenBSD VPS dev@brgen.no
type: project
originSessionId: 84fcf91d-46ea-43a5-8efa-3d33b065e6a5
---

The MASTER project runs on VPS dev@brgen.no (46.23.89.226), OpenBSD 7.8, 1GB RAM, with passwordless doas. SSH uses `sshpass -p '<pass>' ssh -o StrictHostKeyChecking=no dev@46.23.89.226 'cmd'`—password per session; see `DEPLOY/OPERATOR.md`. The codebase lives at `~/pub4/MASTER/`—roughly six thousand lines of Ruby, Zeitwerk-autoloaded.

MASTER is a constitutional AI agent replacing the Claude Code CLI. OpenRouter runs through `ruby_llm` with default model `nvidia/nemotron-3-super-120b-a12b:free`. Fallback order is qwen3-coder:free, then minimax-m2.5:free, then gpt-oss-120b:free, then gemini-2.0-flash.

All coding happens on the VPS via sshpass SSH—never local edits. Patches go through `~/pub4/tmp/patch.rb`. Shell work uses zsh builtins only; no sed, awk, grep, find, head, or tail.

The pipeline is Intake → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render. Pipe commands with `echo "cmd" | bundle exec ruby bin/cli`. Startup YAML includes `state.yml`, `limits.yml`, `rules.yml`, `voice.yml`, `style.yml`, and `models.yml`. The web tier is Rails 8 with Falcon on port 53187; relayd terminates TLS at `https://ai.brgen.no` on 443.