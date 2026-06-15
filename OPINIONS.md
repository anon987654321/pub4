# Opinions — MASTER and DEPLOY

External-style reviews of the pub4 runtime (MASTER) and deployment surface (DEPLOY). Written 2026-06-15 after consolidating to `main`.

Contract backlogs live in `MASTER/TODO.md` and `DEPLOY/TODO.md`. Full historical ledgers: `MASTER/docs/archive/TODO-full-2026-06-15.md`, `DEPLOY/docs/archive/TODO-full-2026-06-15.md`.

---

## MASTER

### Constitutional architect — impressed, wary of scope creep

MASTER’s core idea is strong and unusual: **rules are data, enforcement is code, convergence is a loop**. The split into `now / loop / judge / voice / ground / reach / trace` is coherent. `Result` monads through the pipeline, tiered soul protection, deploy gates with evidence scoring, and self-scan are the right primitives for “AI that can’t lie about what it did.”

The worry is **constitutional inflation**. `rules.yml` has 173 rules; the archived TODO had ~1,985 items across sections A–AM plus BF–PH. That was a second constitution — a museum of every good idea, not a product spec.

**Verdict:** Architecturally sound kernel; needs ruthless product boundary. Contract TODO is now F–N only.

### Pragmatic Ruby engineer — good craft, uneven finish

**Positives:** ~313 lib files, largest ~305 lines, Zeitwerk, explicit `Result` categories, semantic cache, OpenBSD `vmstat` pressure, `scan_since` including `lib/`, `OutputGuard` for G09/G10.

**Gaps:** ~57 tests for ~30k LOC (~1:540). Web surface rule compliance was marked done in contract but needs OpenBSD re-verification. `OutputGuard` sanitizes renderer output; it does not yet block mutating tools that lack diffs in the event bus.

**Verdict:** Disciplined Ruby. Trustworthiness still outruns automated proof.

### Operator on OpenBSD — right machine, fragile dev loop

Built for OpenBSD: `vmstat` memory, `relayd`, `ruby34`, `doas`, no swap assumptions. macOS Ruby 2.6 cannot run the suite. **N01** (QUICKSTART on 7.9 + ruby34) is the single highest-leverage doc task.

**Verdict:** Production-shaped, development-fragile. One VPS smoke script beats 200 research TODOs.

### Product — powerful engine, unclear end user

| Surface | Audience | Maturity |
|---------|----------|----------|
| `bin/cli` REPL | Operator | Strong |
| Web face (53187) | Visitor multimodal chat | Medium |
| Scan/fix on DEPLOY | Rails family hygiene | Strong |
| Face particles / PH* / FA* | Art direction | Speculative |

Live wedge today: **`master scan DEPLOY/rails` + production gate + terse unix voice**. Not a general Grok/Cursor competitor.

### Security — serious intent, tool blast radius

Good: governor tiers, secret redaction, path guards, session fixation exported to Rails.

Watch: `Shell` + `WebFetch` with auto-allow history; Open3 string-form calls (O804); visitor photo upload boundary must stay tight.

### Maintainer — next moves

1. Run contract TODO only (F–N); never resurrect O–AM as checkboxes.
2. OpenBSD CI smoke: self-scan + pipeline + output_guard tests on ruby34.
3. Re-verify F on every release (`/self` zero violations).
4. Decouple face/photography backlog from core runtime.

---

## DEPLOY

### Platform architect — best part of the repo

DEPLOY is further along than MASTER in **shipping shape**:

- Six Rails 8 apps on Solid Stack (Queue, Cache, Cable) — no Redis dependency on VPS.
- `pub4-shared` engine gem replaces copy-paste concerns; `WIRING_NOTES.md` documents the model.
- `check_production_gate.rb` gives a single pre-ship command.
- `relayd` health checks, Litestream, `assume_ssl`, TLS at edge — correct OpenBSD pattern.
- Live search (BS01–BS14) wired with FTS5, Turbo Frames, analytics, LLM suggestions.
- Auth stack (AN202–AN212) wired: rate limit, remember-me, 2FA, OAuth hooks, Pundit on marketplace, account deletion.

This is a **real multi-app family**, not six hello-world repos.

**Verdict:** Architecture matches the “one city graph + shared spine” vision. Engine-ize was the right call.

### Pragmatic Rails engineer — wide surface, thin tests

~407 app Ruby files across 6 apps; **one** brgen live-search test added recently. CI section (CI05–CI08) is entirely open. AN208 marked done but Pundit is only proven on `Marketplace::Listing` — other controllers still need policies.

AN201 (Rails 8 `authentication` generator baseline) remains open because custom auth + guest users + brgen domain registry are **already working** — migrating to scaffold is churn, not capability.

**Gaps that matter:**

| Item | Risk |
|------|------|
| BU01–BU07 | Production config drift (hosts, SMTP, `/up` depth, solid_queue) |
| BQ07 | query_log_tags warnings in gate — N+1 blind in prod |
| CG04–CG05 | CSP / Permissions-Policy not unified |
| BV03–BV29 | Product features (dating calendar, paywall, OSRM) — not infra |

**Verdict:** Deployable skeleton with strong shared layer; production hardening and tests lag feature count.

### Operator on OpenBSD — scripts exist, VPS truth unknown

`openbsd.sh` two-stage deploy, `rc.d`, `relayd`, Litestream, backup cron — documented. Contract section **M** (M01–M07) is mostly unchecked because they require **on-VM verification**, not more code.

BW01–BW09 are marked done in code/scripts; M06/M07 duplicate sshd/PTR checks — consolidate at next VPS login.

**Verdict:** Runbook-quality deploy scripts. Honest state is “works on last successful deploy”; contract M items are the acceptance checklist.

### Product — brgen is the hub; others are satellites

**brgen** carries marketplace, dating, TV, playlist, takeaway, maps, global search, city switcher, activity graph — justified as canonical UI (X-style 3-column per WIRING_NOTES).

**amber / blognet / baibl / bsdports / hjerterom** are thinner verticals sharing engine + live search but with BV backlog still open (wardrobe AI, paywall, ports import, beneficiary matching).

Risk: **six apps × six deploy scripts × six SQLite DBs** on a 1GB VPS — memory and ops complexity. Solid Stack helps; Falcon per-app on distinct ports is correct but not free.

**Verdict:** Ship brgen + MASTER face first; treat other apps as beta surfaces until BV items have owners.

### Security — auth improved; headers and edge still open

Recent wins: session fixation, rate limiting, device fingerprint, suspicious login mail, 2FA for sellers, GDPR deletion flow.

Still open: CG01 duplicates AN205 (Rack::Attack vs Solid Cache rate limit — pick one). CG04 CSP nonce rollout is the biggest remaining web hardening step. CG08–CG10 (pledge/unveil on MASTER, pf bruteforce table) are VPS ops, not app code.

**Verdict:** Auth layer is credible; defense-in-depth (CSP, edge monitoring) is the next tier.

### Maintainer — DEPLOY contract priorities

Order of execution:

1. **BU + BQ** — production.rb parity, `/up` + `/health`, query_log_tags, recurring.yml gaps.
2. **CI** — system tests for brgen auth gate + city isolation; expand from one live_search test.
3. **M** — VPS checklist on next deploy (rc.d master, master.env, PTR, sshd).
4. **CG04–CG05** — shared CSP initializer in engine.
5. **Archive BV** — product roadmap, not deploy contract (already excluded from trimmed TODO).

Do **not** reopen AO–BE design ideation as blocking deploy.

---

## Cross-cutting

MASTER and DEPLOY are designed as **mutual enforcement**: MASTER scans DEPLOY; DEPLOY gate blocks ship. That loop is the product.

Weak link: **verification runs on OpenBSD only**, while editing happens on macOS. Fix: one `doas zsh DEPLOY/bin/verify` on VPS (or ruby34 container) before every push.

**Bottom line**

| Layer | Grade | One-line |
|-------|-------|----------|
| MASTER kernel | A− | Rare constitutional runtime; shrink ambition, grow tests |
| DEPLOY spine | B+ | Real shared engine + Solid Stack; harden prod + CI |
| Combined loop | B | Scan/gate works in principle; needs VPS smoke as law |

---

*Archived research TODOs remain readable for ideas; they are not commitments.*