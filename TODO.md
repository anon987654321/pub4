# TODO — pub4 operator backlog

Repository: local `/Users/mac/Documents/GitHub/pub4` (VPS: `/home/dev/pub4`), remote `anon987654321/pub4`, branch `main`.

**HEAD:** wave4 — all seven next waves complete locally (2026-06-19); VPS `bin/ci` runtime pending.

Itemized backlogs:

- [`MASTER/TODO.md`](MASTER/TODO.md) — constitutional AI, scanner, web face, CLI
- [`DEPLOY/TODO.md`](DEPLOY/TODO.md) — Rails apps, OpenBSD, relayd, repligen, postpro

Work left to right in each file. Mark done with `[x]`. Commit and push checkpoints to `main`.

## Operator intent

Finish strict `rules.yml` adherence across MASTER and DEPLOY, with Rails production readiness on OpenBSD as the deploy target. Reduce real blockers, keep secrets untracked, tighten scanner false positives, add repeatable gates.

Do not overclaim production readiness. `brgen` is closest; `amber`, `bsdports`, `baibl`, `blognet`, and `hjerterom` still need target-host bundle/test/security/deploy smoke.

## Non-negotiable constraints

- TLS terminates at OpenBSD `relayd`; Rails `config.assume_ssl = true`; never `config.force_ssl = true`.
- No tracked `config/master.key`; rotate any previously committed credentials outside git.
- Ruby 3.4 for Rails apps; local Mac may be 3.3.x — full Rails runtime validation is VPS or rbenv 3.4.
- Any file installed on VPS must be saved under `DEPLOY/openbsd/` and committed.
- Use `apply_patch` for manual edits; do not revert unrelated user changes.

## Verification (before push)

```sh
ruby bin/probe repo
ruby DEPLOY/rails/check_production_gate.rb
git ls-files 'DEPLOY/rails/*/config/master.key'
ruby -c DEPLOY/rails/check_production_gate.rb
git diff --check
cd MASTER && bin/smoke   # Ruby 3.4+ on VPS
```

## VPS recovery (when `~/.ssh/id_ed25519_brgen` is on workstation)

```sh
ssh -p 31415 -i ~/.ssh/id_ed25519_brgen dev@server4.openbsd.amsterdam
vmctl console vm23
# login, then: doas pfctl -t bruteforce -T flush; exit ~.
ssh -i ~/.ssh/id_ed25519_brgen dev@46.23.89.226
cd /home/dev/pub4 && git pull origin main
SKIP_MASTER_SCAN=1 zsh DEPLOY/sh/vps_on_vm_install.sh
# or retry: SKIP_MASTER_SCAN=1 zsh DEPLOY/sh/vps_retry_failed.sh
doas rcctl check master brgen amber blognet bsdports baibl hjerterom
ruby34 DEPLOY/openbsd/health_check.rb
curl -fsS http://127.0.0.1:53187/up
curl -fsS https://ai.brgen.no/up
```

Hypervisor if VM SSH times out: `ssh -p 31415 -i ~/.ssh/id_ed25519_brgen dev@server4.openbsd.amsterdam` → `vmctl console vm23`. Operator keys may also be on `dev@brgen.no` (password in operator vault — never commit).

## Next waves (sequential) — [x] complete 2026-06-19

1. [x] **Rails runtime gate** — `DEPLOY/rails/rails_runtime_gate.rb`; `rails_runtime_gate` in deploy `.sh` scripts; `bin/probe repo` wired.
2. [x] **DEPLOY de-duplication** — `production_baseline`, `ApplicationSetup`, `SessionsActions`, `PasswordsActions`, shared `development`/`test`/`ci` requires.
3. [x] **MASTER scanner accuracy** — `MASTER/test/test_web_scan_fixtures.rb` for HTML/CSS/JS rule contracts.
4. [x] **Frontend production pass** — `DEPLOY/rails/frontend_production_gate.rb`; brgen layout hash-links fixed.
5. [x] **Security sweep** — `DEPLOY/security_sweep.rb`; quarantine inert; no tracked secrets.
6. [x] **OpenBSD deploy smoke** — `DEPLOY/openbsd/deploy_smoke_gate.rb` (repo); `health_check.rb` (VPS live, 2026-06-16).
7. [x] **Production readiness decision** — `DEPLOY/rails/PRODUCTION_READINESS.md` dated 2026-06-19; no app marked ready until VPS `bin/ci`.

## Critical (active)

- [x] Verify face at `https://ai.brgen.no/`: `/up` 200, face HTML served, `bin/smoke` clean on VPS (2026-06-16). WebGL primer/particles: confirm in browser private window.
- [x] Repo relayd aligned: `etc/relayd.conf` + `openbsd.sh configure_relayd()` emit `check http "/up" code 200` for all backends; blognet + hjerterom included.
- [x] Local gates: `self_test.rb` syntax fixed; `check_production_gate.rb` reads `config/ci.rb`; `PRODUCTION_READINESS.md` added; `deploy-diff.sh` + expanded `health_check.rb`.
- [x] Wave gates (2026-06-19): `bin/probe repo` green on workstation.

## Operator philosophy

- MASTER: fewer dramatic findings, more precise findings, fixtures for every rule class.
- `check_production_gate.rb` is the first hard gate for Rails; grow only with real deployment invariants.
- OpenBSD + relayd are first-class architecture, not afterthought.
- Rails apps stay individually understandable; share deployment grammar, not app identity.
- Answer "Can I deploy this app today?" with commands, not confidence.

Former `HANDOFF.md` is merged here (operator context) and into `MASTER/TODO.md` / `DEPLOY/TODO.md` (itemized backlog). Do not recreate `HANDOFF.md`.