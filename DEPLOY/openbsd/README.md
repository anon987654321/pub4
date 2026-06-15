# OpenBSD deploy

Two-stage VPS installer for pub4. Target: OpenBSD 7.8+, vm23 (`46.23.89.226`).

## VM provisioning (OpenBSD Amsterdam)

Provider welcome email from Mischa, 2026-05-17. Operator record — not secrets.

| Field | Value |
|-------|-------|
| VMM host | `server4.openbsd.amsterdam` |
| VM name | `vm23` |
| SSH user | `dev` |
| SSH key | `~/.ssh/id_ed25519_brgen` (same key on VM and hypervisor) |

**IPv4**

| | |
|-|-|
| Address | `46.23.89.226` |
| Subnet | `255.255.255.192` (`/26`) |
| Gateway | `46.23.89.193` |

**IPv6**

| | |
|-|-|
| Address | `2a03:6000:6e64:623::226` |
| Prefix | `/64` |
| Gateway | `2a03:6000:6e64:623::1` |

**Access**

```zsh
# VM (app host) — direct once unbanned
ssh dev@46.23.89.226

# Hypervisor (for pf bruteforce ban, wedged networking, or console)
ssh -p 31415 -i ~/.ssh/id_ed25519_brgen -o VerifyHostKeyDNS=yes dev@server4.openbsd.amsterdam
vmctl status vm23
vmctl console vm23          # inside: login, pfctl -t bruteforce -T flush ; exit with ~.
```

See DEPLOY/openbsd/unban_pf.sh for a one-shot helper that drops you straight into the console with the exact pfctl command.

**Operator docs** (read 2026-06-15)

- [Onboarding](https://openbsd.amsterdam/onboard.html) — console via vmctl/cu(1), ~. to exit, doas setup, syspatch, initial root password from authorized_keys
- [Backup](https://openbsd.amsterdam/backup.html) — wingman1 (s4vm23@wingman1.openbsd.amsterdam, same port/key, openrsync recommended; 10G free)
- [PTR / rDNS](https://openbsd.amsterdam/ptr.html) — set from inside VM only (token + ftp/http to ptr4/ptr6); protect endpoint
- [Upgrade](https://openbsd.amsterdam/upgrade.html) — sysupgrade or manual bsd.rd
- [Known issues](https://openbsd.amsterdam/known.html) — mostly resolved in 7.3+ (use ping cron to gateway only if needed)

**Notes** (strict rules.yml + VPS-ready + LLM-friendly docs)

**Fictive Seed Data (Faker + Web via Ferrum):**
- Base seeds use ruby-faker for rich, connected data across brgen (core + marketplace, dating, playlist, takeaway, tv, maps, messages) and amber (items, outfits, posts, etc.).
- Optional web augmentation (for more "realistic" fictive data sourced from public web):
  - `SEED_FROM_WEB=1 OPENROUTER_API_KEY=... bin/rails db:seed:replant` (or run rakes first).
  - Rakes (in brgen/lib/tasks/ and amber/lib/tasks/):
    - `scrape:reddit_seed` → creates Posts, Marketplace listings, Takeaway restaurants, Dating profiles, Playlist/Tv entries, Places, etc. from Reddit subs (routed by keywords/sub).
    - `scrape:x_seed` → similar from X searches (adds maps places, messages convos).
    - `scrape:fashion_seed` (amber) → Items, Outfits, Posts from fashion subs.
  - Uses shared `app/services/scrape.rb` (Ferrum headless + vision LLM on screenshot+HTML for robust extraction; schema + hints per vertical).
  - Data is fictivized (anonymized titles, mixed with Faker, activity/notif via shared concerns).
  - Why: Gives "authentic" demo data without real user content. Pure Faker always works as fallback. See per-app db/seeds.rb for the if-blocks and comments.
- **For other LLMs/agents:** This is the canonical pattern here — base generative seeds + optional web-sourced fictive augmentation via browser+LLM. The rakes produce model-ready hashes that get turned into real records. Check seeds.rb + rake files first when analyzing data layer.

**VPS run (light, no CPU/mem spikes):**
- Source of truth: /home/dev/pub4 (git repo).
- `cd /home/dev/pub4 && git pull --ff-only`
- Light sync: `doas zsh DEPLOY/openbsd/openbsd.sh --sync-configs` (runs MASTER scan gate + health).
- Per-app (brgen subapps, amber, ...): `doas zsh DEPLOY/rails/brgen/brgen.sh` (or just `doas rcctl restart brgen_rails` after pull if no bundle changes). All .sh now have pre-apply MASTER /scan DEPLOY (blocks on rules violations) + /up guards + sleeps.
- Recovery (if direct ssh blocked by pf): `ssh -p 31415 ... dev@server4.openbsd.amsterdam ; vmctl console vm23` (then `doas pfctl -t bruteforce -T flush` or use unban_pf.sh from your workstation).
- Always tmux. Use host console for anything wedged. Health: curl /up + ruby health_check.rb.
- Web seeds on VPS: only when needed (resource-heavy due to Ferrum+LLM); prefer locally then git push/pull. Final wave: full integration (rake *_seed + optional in seeds.rb) for brgen subapps + amber.

- Rapid reconnects trip pf — use tmux; unban via host console (unban_pf.sh).
- FDE only if OK with no cold-start help from provider.
- Billing: include "server4 vm23" in description.
- Same key for VM + host + backup (wingman1 via openrsync).

**For other LLMs/agents (explicitly):** Read this file + root README + DEPLOY/rails/apps.yml + openbsd/pf.conf first. The system is built for recursive self-application (rules.yml enforced via scans in deploys, ground_truth, evidence_scoring, veto/anti-patterns, tier1 priorities). Seed data is the "Faker base + optional Ferrum web" pattern above (rakes produce model-ready fictive records routed to verticals; SEED_FROM_WEB for augmentation). Deploys are intentionally light and gated (MASTER scan + /up health before restarts). All changes must be committed back here. Host access is the out-of-band path. See also unban_pf.sh, the per-app .sh (with scan gates), and db/seeds.rb for the data generation logic. Last minute: all optimized for VPS light run, documented for LLM pickup.

## Run

```zsh
cd ~/pub4/DEPLOY/openbsd
tmux new-session -d -s deploy "doas zsh openbsd.sh 2>&1 | tee /tmp/deploy.log"
tmux attach -t deploy
```

```zsh
doas zsh openbsd.sh --sync-configs    # mirror repo etc/ → /etc, restart services
doas zsh openbsd.sh --resume          # continue interrupted stage run
doas ksh emergency_cpu.sh             # stop crash-looping Rails services (CPU relief)
```

## Stages

**Stage 1** — NSD + DNSSEC, acme-client TLS, httpd ACME, base pf, packages.

**Stage 2** — Rails app trees, relayd SNI, smtpd, final pf, rc.d services, health_check.

## Rules

- Public ingress: SSH, SMTP, 80, 443 only. App ports bind loopback; relayd terminates TLS.
- SQLite + Solid Queue/Cache by default. No PostgreSQL/Redis unless explicitly added.
- Secrets in `/etc/master.env`, `/etc/<app>.env` — never in git. Operator secrets in `~/priv/`.
- Any file installed on VPS must be copied back to `DEPLOY/openbsd/` and committed.

## Post-deploy

```zsh
doas rcctl check master relayd pf
curl -fsS http://127.0.0.1:53187/up
curl -sk https://ai.brgen.no/up
doas tail -f /var/log/openbsd_setup.log
```

## MASTER review

Before changing live infra:

```zsh
cd ~/pub4/MASTER && bundle exec ruby bin/cli
# /scan DEPLOY/openbsd
# /sweep DEPLOY/openbsd
```

Reject changes that open raw app ports, weaken pf/relayd validation, or drop backup/idempotence.