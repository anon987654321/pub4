# MASTER/bin

Two surfaces are sanctioned and the rest are stages beneath them. `pub4` is the
operator surface and `master` is the instruction surface; everything else in this
directory is either a stage one of them runs, a daemon, or a tool for one job.
Run from `MASTER/` unless noted. `MASTER/data/spine.yml` records how many
executables this directory is allowed to hold, so the next one has to argue for
itself instead of arriving unnoticed.

`bin/pub4 gate` is the chain. It runs, in order: the scanner over all four trees
with autofix on, every RAILS gate, every suite, the ratchets, the sprawl census,
and last the council — attributing the files each stage changed and refusing to
report a clean pass over a tier it could not reach. `bin/pub4 gate --explain`
prints the ladder without running it, and `--scan-only` measures without writing.

| Script | Purpose |
|--------|---------|
| `pub4` | The operator surface: `gate`, status, test, measure, lint, land, worktree, vps |
| `master` | The instruction surface: `bin/master "<instruction>"`, or bare for a session |
| `gate` | Stage of `pub4 gate`: scan → fix → scan → critique → review over all four trees |
| `check` | Stage of `pub4 gate`: profiled suites (`operator`, `contributor`, `agent`, `web`, `ci`, `full`) |
| `ci` | The name GitHub Actions and vm23 call; resolves to `check --profile=ci` |
| `probe` | Readiness probes (`smoke`, `selftest`, `core`, `all`, …) |
| `audit` | Pre-commit constitution scan on staged files |
| `cli` | Interactive MASTER CLI — the runtime `master` boots |
| `cleanup` | Session and artifact cleanup |
| `doctor` | Environment and wiring diagnostics |
| `dogfood` | CLI dogfood (boot + chitchat) |
| `handoff` | Agent handoff bundle writer |
| `master-core` | Core spine utilities |
| `nsaudit` | Namespace reference audit |
| `onboard` | New contributor onboarding checks |
| `playbook` | Playbook runner |
| `preflight` | Pre-deploy OpenBSD checks (zsh) |
| `provider-catalog` | Refresh provider model catalog |
| `reset-costs` | Reset local cost counters |
| `ruby` | Resolve pub4's preferred Ruby and exec the rest of the command line |
| `smoke` | Boot/wiring smoke |
| `smoke-web` | Face HTTP smoke |
| `sync-env` | Sync env files from templates |
| `tts-bootstrap` | Start TTS worker stack |
| `tts-e2e` | TTS end-to-end poll test |
| `tts-speak` | One-shot TTS speak |
| `tts-worker` | TTS worker process |
