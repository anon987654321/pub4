# MASTER/bin

Operator entrypoints for the constitutional runtime. Run from `MASTER/` unless noted.

| Script | Purpose |
|--------|---------|
| `audit` | Pre-commit constitution scan on staged files |
| `check` | Profiled check runner (`operator`, `contributor`, `agent`, `web`, `full`) |
| `ci` | CI gate: rake test/core/selftest, core smoke, optional full/web profiles |
| `cleanup` | Session and artifact cleanup |
| `cli` | Interactive MASTER CLI |
| `doctor` | Environment and wiring diagnostics |
| `dogfood` | CLI dogfood (boot + chitchat) |
| `gate` | Deploy/runtime gate helper |
| `handoff` | Agent handoff bundle writer |
| `master` | Repo-wide instruction surface: `bin/master "<instruction>"`, or bare for a session |
| `master-core` | Core spine utilities |
| `nsaudit` | Namespace reference audit |
| `onboard` | New contributor onboarding checks |
| `playbook` | Playbook runner |
| `preflight` | Pre-deploy OpenBSD checks (zsh) |
| `probe` | Readiness probes (`smoke`, `selftest`, `core`, `all`, …) |
| `provider-catalog` | Refresh provider model catalog |
| `pub4` | Repo-wide operator surface: status, test, measure, worktree, vps |
| `reset-costs` | Reset local cost counters |
| `ruby` | Resolve pub4's preferred Ruby and exec the rest of the command line |
| `smoke` | Boot/wiring smoke |
| `smoke-web` | Face HTTP smoke |
| `sync-env` | Sync env files from templates |
| `test-safety` | Test harness safety checks |
| `tts-bootstrap` | Start TTS worker stack |
| `tts-e2e` | TTS end-to-end poll test |
| `tts-speak` | One-shot TTS speak |
| `tts-worker` | TTS worker process |
