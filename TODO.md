# TODO — pub4 operator backlog

Repository: local `/Users/mac/Documents/GitHub/pub4` (VPS: `/home/dev/pub4`), remote `anon987654321/pub4`, branch `main`.

**HEAD:** `5cd483230` — ReflexionLedger in `trace/`; wired in builder + ai_boot.

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
DEPLOY/rails/check_production_gate.rb
git ls-files 'DEPLOY/rails/*/config/master.key'
ruby -c DEPLOY/rails/check_production_gate.rb
git diff --check
bin/smoke
```

## VPS recovery (when `~/.ssh/id_ed25519_brgen` is on workstation)

```sh
ssh -p 31415 -i ~/.ssh/id_ed25519_brgen dev@server4.openbsd.amsterdam
vmctl console vm23
# login, then: doas pfctl -t bruteforce -T flush; exit ~.
ssh -i ~/.ssh/id_ed25519_brgen dev@46.23.89.226
doas rcctl restart master relayd
curl -fsS http://127.0.0.1:53187/up
curl -fsS https://ai.brgen.no/up
```

Hypervisor if VM SSH times out: `ssh -p 31415 -i ~/.ssh/id_ed25519_brgen dev@server4.openbsd.amsterdam` → `vmctl console vm23`.

## Next waves (sequential)

1. **Rails runtime gate** — Ruby 3.4 path (`bundle34` on VPS); per app: `bundle check`, `db:prepare`, `test`, brakeman, bundler-audit; wire into deploy scripts if not local.
2. **DEPLOY de-duplication** — compare Rails scaffold drift; move shared behavior into `DEPLOY/rails/shared` only where it reduces real drift.
3. **MASTER scanner accuracy** — re-run on erb/scss/html/css/js; fixture tests per changed rule.
4. **Frontend production pass** — syntax, a11y basics, responsive breakage, unsafe rendering.
5. **Security sweep** — no keys/tokens/db/malware tracked; virus museum inert.
6. **OpenBSD deploy smoke** — relayd routes, TLS, `/up`, logs, db writes, jobs, restart; Rails sees forwarded HTTPS via `assume_ssl`.
7. **Production readiness decision** — update `DEPLOY/rails/PRODUCTION_READINESS.md` with dated pass/fail; no app marked ready until target-host checks pass.

## Critical (active)

- [ ] Verify face at `https://ai.brgen.no/`: fresh private window, tap primer, confirm WebGL face and ecology particles.
- [ ] Verify live `/etc/relayd.conf` uses `check http "/up" code 200` (repo `DEPLOY/openbsd/etc/relayd.conf` does; `openbsd.sh configure_relayd()` may emit weaker `check tcp` only).

## Operator philosophy

- MASTER: fewer dramatic findings, more precise findings, fixtures for every rule class.
- `check_production_gate.rb` is the first hard gate for Rails; grow only with real deployment invariants.
- OpenBSD + relayd are first-class architecture, not afterthought.
- Rails apps stay individually understandable; share deployment grammar, not app identity.
- Answer "Can I deploy this app today?" with commands, not confidence.

Former `HANDOFF.md` is merged here (operator context) and into `MASTER/TODO.md` / `DEPLOY/TODO.md` (itemized backlog). Do not recreate `HANDOFF.md`.