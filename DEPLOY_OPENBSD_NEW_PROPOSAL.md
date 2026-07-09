# DEPLOY_OPENBSD_NEW_PROPOSAL.md

Implementation plan for an external agent (Grok/GPT). Written 2026-07-09 after reading
every file under `DEPLOY/openbsd/` at commit `ab91c21b7` **and** each parent daemon's
manpage at man.openbsd.org. Every defect below is verified against the manpage cited.

## Ground rules

- vm23 = 46.23.89.226, OpenBSD, 1 GB RAM. `etc/ usr/ var/` are exact config mirrors
  installed onto `/` by `DEPLOY.sh` (`install_root_configs` does `cp -R`, **no
  templating** — whatever is in the repo lands verbatim on the VPS).
- Never run `--stage-1` casually; it rewrites DNS material and is gated by
  `I_UNDERSTAND_DNS_WIPE=1`.
- Tooling: pure Ruby or zsh. No `find`/`sed`/`awk` edits.
- Acceptance for the whole proposal: `pfctl -nf etc/pf.conf` ok, `relayd -n` ok,
  `nsd-checkconf` ok, `config-drift-check` clean, `health_check.rb` and
  `deploy_smoke_gate.rb` green, `drill @127.0.0.1 brgen.no SOA` answers.

## Verified defects (fix in this order)

### O1 — `etc/newsyslog.conf` lines cannot parse as written
Current: `/var/log/openbsd_setup.log root:wheel 640 12 $W0D0 ZN` (three lines like this).
newsyslog(8) format is `logfile owner:group mode count SIZE when flags`; the **size column
is missing** (must be `*` or `0` for schedule-only rotation) and OpenBSD documents flags
`Z B M F` only — **there is no `N` flag** (that is FreeBSD's "no signal").
Fix each line to: `/var/log/openbsd_setup.log root:wheel 640 12 * $W0D0 Z` (same for
`openbsd_transactions.log` and `cert-renewal.log`). `$W0D0` (weekly, Sunday 00:00) is valid.

### O2 — `var/nsd/etc/nsd.conf` serves unsigned zones despite DNSSEC pipeline
Every zone block says `zonefile: "X.zone"`, but the generator template
(`var/nsd/etc/nsd-zone.tmpl`) and the re-signer (`usr/local/bin/nsd-resign`) produce and
reload `X.zone.signed`. Per nsd.conf(5), `zonefile` is what NSD serves — so RRSIGs are
never served for any zone registered by the tracked config, while DS records exist
upstream (`.ds` files in `var/nsd/zones/master/`). Validating resolvers will return
SERVFAIL for those zones.
Fix: point every `zonefile:` at `X.zone.signed` (write a small Ruby migration that
rewrites the file and verifies with `nsd-checkconf`). Also reconcile the tmpl/nsd.conf
divergence: tmpl uses `$HYP_IP` substitution and `.zone.signed`; regenerate `nsd.conf`
zone blocks from the tmpl rather than hand-maintaining both (ONE_SOURCE).

### O3 — `etc/pf.stage1.conf` cannot load
Lines 8–12 contain literal `\$ext_if` / `\$brgen_ip` backslash escapes (leftovers from a
shell heredoc), and lines 3–4 assign `"$BRGEN_IP"` / `"$HYP_IP"` — undefined pf macros.
pf.conf(5) has no backslash escaping, and `install_template` in `DEPLOY.sh` is a plain
`cp`, so `pfctl -f` fails during `--stage-1`.
Fix: remove the backslashes and either hardcode the two IPs (they are stable:
46.23.89.226 / hyp.net secondary) or have `stage_1` substitute them before install.
Add `pfctl -nf` validation to `--stage-1` the same way `deploy_live` validates pf.

### O4 — `etc/login.conf` `rails` class is dead configuration
rc.subr(8): a daemon's login class is looked up as *a login.conf class named after the
rc.d script itself*, falling back to `daemon`. Our scripts are named `brgen`, `amber`,
`bsdports`, `hjerterom` — so the carefully tuned `rails` class (datasize 4096M,
openfiles 4096/2048, maxproc 512/256) never applies; the apps run under `daemon`
(openfiles-cur **128**). This is a plausible root cause for Falcon fd exhaustion under load.
Fix: add four thin classes to `login.conf`:
`brgen:\ :tc=rails:` (and same for amber, bsdports, hjerterom). Verify on the VPS with
`getcap -f /etc/login.conf brgen`.

### O5 — `usr/local/bin/renew-certs.sh` TLSA/DNSSEC re-sign is broken
`generate_tlsa_record` signs with `K$domain.+013+zsk.key` and `K$domain.+013+ksk.key`,
but real key files carry numeric keytags (e.g. `Kamber.brgen.no.+013+07825.key` — see
`var/nsd/zones/master/`). `ldns-signzone` therefore fails on every renewed domain, and
with `set -euo pipefail` the failure aborts the remaining renewals mid-loop.
Fix: reuse the glob approach from `nsd-resign` (`K#{zone}.+*.key`), or better — move
TLSA record insertion into `nsd-resign` (single signer, item O6) and reduce
`renew-certs.sh` to: renew via acme-client, then `rcctl reload relayd`.

### O6 — Two signers with divergent semantics
`renew-certs.sh` signs NSEC3 (`ldns-signzone -n -p -s <salt>`); `nsd-resign` signs plain
NSEC with a 30-day expiry window. Whichever ran last determines zone semantics — flapping
between NSEC3 and NSEC on every cert renewal vs daily re-sign.
Fix: one signer, `nsd-resign` (it already handles expiry windows, reload, notify).
Delete the signing path from `renew-certs.sh` per O5.

### O7 — `etc/rc.d/brgen_tv` is a retired-app fossil
It references user `brgen_tv` (not in `apps.yml` active set), uses `bundle` instead of
`bundle34`, hardcodes a redacted `SECRET_KEY_BASE` literal, and binds port 10012 which
appears in no relayd table. Delete the file; `port_inventory_gate.rb` already polices
retired names.

### O8 — `etc/rc.d/master.tmpl` drifted from the live `etc/rc.d/master`
The tmpl uses `daemon="/usr/local/bin/bundle"` with `pexp="ruby34..."` and lacks the
digest-stamped precompile / `/up` wait / relayd restart that the live script gained
(and the `daemon_timeout=300` bump from commit `5ccd7514`). Either regenerate the tmpl
from the live script or delete it and make the live file the only source (ONE_SOURCE).

### O9 — `etc/doas.conf` rule 1 makes rules 2–4 dead
doas.conf(5): last matching rule wins; `permit nopass keepenv dev as root` (no cmd)
matches everything, so the three specific `cmd` rules change nothing. Two options:
(a) minimal cleanup — delete the three redundant lines; or (b) least privilege — replace
the blanket rule with enumerated grants per `doas.conf.example`. Note before choosing (b):
deploy flows genuinely run `cp -R etc usr var /`, `rcctl` on nsd/httpd/relayd/smtpd/master
and the app scripts, `crontab`, and `pkg_add`; enumerate all of them or deploys break.
Recommend (a) now, (b) as a follow-up with a tested allowlist.

### O10 — `config-drift-check` scope is too narrow to catch O2-class drift
It compares relayd Host routes against acme SANs **only for `.brgen.no`** (regex is
brgen-specific), and checks zone files against nsd.conf registration — but not
(1) SAN drift for the ~45 other apex domains, (2) zone A/CAA records vs relayd hosts
(e.g. `baibl` and `blognet` have A records in `brgen.no.zone` but no SAN and no relayd
route), (3) `zonefile:` pointing at `.zone.signed` when key material exists.
Extend the script (it is already pure Ruby) with those three checks.

### O11 — Litestream replicas are same-disk only
`etc/litestream.yml` replicates all four apps to `file:///var/backups/litestream/...` on
the same VPS disk. That protects against app-level corruption, not disk loss. Add an
off-host replica (Litestream supports sftp/s3; it is a port, documented upstream — not on
man.openbsd.org) or document the accepted RPO in `DEPLOY/VPS_SAFETY.md`. The per-app paths
are correct as-is (brgen really uses `db/`, the others `storage/` — see the Rails proposal
R7 for the unification; **update this file in the same commit if R7 lands**).

## Verified-correct (do not churn)

Confirmed against manpages; leave these alone:
- `etc/httpd.conf`: chroot-relative `root` (`/acme`, `/postpro` under `/var/www`),
  `request strip 2`, `block return 301 "https://$HTTP_HOST$REQUEST_URI"` — all valid
  per httpd.conf(5). Port 6666 postpro server is loopback-only (pf blocks it externally).
- `etc/acme-client.conf`: `challengedir "/var/www/acme"` matches the documented default;
  listing the apex in `alternative names` is harmless per acme-client.conf(5).
- `etc/mail/smtpd.conf`: matches the documented OpenBSD default local+outbound pattern.
- `etc/ssh/sshd_config`: three overrides valid; sshd_config(5) first-obtained-value-wins,
  defaults tightened (prohibit-password→no, yes→no, 6→3).
- `etc/pf.conf` (main): bruteforce overload table, `max-src-conn-rate`, `flush global`,
  icmp-type sets — all confirmed per pf.conf(5).
- `var/nsd/etc/nsd.conf` server section: `rrl-*` options valid (silently ignored if RRL
  not compiled in, per nsd.conf(5)); `NOKEY` = no TSIG required on xfr/notify.
- `etc/rc.conf.local`: empty `*_flags` = enable with defaults, `NO` = disable,
  `pkg_scripts` order significant — all per rc.conf(8).
- `etc/daily.local`: runs first inside daily(8) as root via cron, output mailed to root.

## Sequencing

O1, O3, O7, O8, O9(a) are mechanical and independent — land first, one commit each.
O2+O6+O5 form the DNSSEC repair series — land together, verify with `drill -D` against
127.0.0.1 before and after. O4 next (needs a service restart window). O10, O11 last.
Apply on vm23 with `cd ~/pub4/DEPLOY/openbsd && doas zsh DEPLOY.sh` (the no-flag default
validates pf and relayd and runs the MASTER pre-apply scan; do not set SKIP_MASTER_SCAN).
