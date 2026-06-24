# TODO — pub4 operator handoff

Repository: local `/Users/mac/Documents/GitHub/pub4` (VPS: `/home/dev/pub4`), remote `anon987654321/pub4`, branch `main`.

Itemized backlogs were retired 2026-06-24 (all CG items closed; section checkboxes archived in git history). Use git log, `MASTER/QUICKSTART.md`, and `DEPLOY/rails/PRODUCTION_READINESS.md` for architecture context.

## Operator intent

Finish strict `rules.yml` adherence across MASTER and DEPLOY, with Rails production readiness on OpenBSD as the deploy target. Reduce real blockers, keep secrets untracked, tighten scanner false positives, add repeatable gates.

Do not overclaim production readiness. `brgen` is closest; other Rails apps need target-host `bin/ci` proof after each sync.

## Non-negotiable constraints

- TLS terminates at OpenBSD `relayd`; Rails `config.assume_ssl = true`; never `config.force_ssl = true`.
- No tracked `config/master.key`; rotate any previously committed credentials outside git.
- Ruby 3.4 for Rails apps; local Mac may be 3.3.x — full Rails runtime validation is VPS or rbenv 3.4.
- Any file installed on VPS must be saved under `DEPLOY/openbsd/` and committed.

## Verification (before push)

```sh
ruby bin/probe repo
ruby DEPLOY/rails/check_production_gate.rb
git ls-files 'DEPLOY/rails/*/config/master.key'
ruby -c DEPLOY/rails/check_production_gate.rb
git diff --check
cd MASTER && bundle exec rake test
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
doas rcctl restart master
doas rcctl check master brgen amber blognet bsdports baibl hjerterom
ruby34 DEPLOY/openbsd/health_check.rb
curl -fsS http://127.0.0.1:53187/up
curl -fsS https://ai.brgen.no/up
```

## VPS operator proof (post-sync checklist)

- `bundle34 exec bin/ci` per Rails app
- `bundle34 exec bin/smoke` in MASTER
- `ruby34 DEPLOY/openbsd/health_check.rb` + HTTPS `/up` sweep
- PTR + sshd hardening verification on vm23

## Active work (open)

- [ ] VPS `bin/ci` green on all six Rails apps after latest pull
- [ ] `doas rcctl restart master` after web face deploy
- [ ] Browser smoke on `https://ai.brgen.no/` (WebGL primer, palette, history sidebar)