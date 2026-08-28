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
| `master-core` | Core spine utilities |
| `nsaudit` | Namespace reference audit |
| `onboard` | New contributor onboarding checks |
| `playbook` | Playbook runner |
| `preflight` | Pre-deploy OpenBSD checks (zsh) |
| `probe` | Readiness probes (`smoke`, `selftest`, `core`, `all`, …) |
| `probe_selfscan` | Scanner self-reference probe |
| `provider-catalog` | Refresh provider model catalog |
| `reset-costs` | Reset local cost counters |
| `smoke` | Boot/wiring smoke |
| `smoke-web` | Face HTTP smoke |
| `snapshot` | Workspace snapshot |
| `sync-env` | Sync env files from templates |
| `test-safety` | Test harness safety checks |
| `tts-bootstrap` | Start TTS worker stack |
| `tts-e2e` | TTS end-to-end poll test |
| `tts-speak` | One-shot TTS speak |
| `tts-worker` | TTS worker process |
| `web-screenshot` | Capture face UI screenshot |
