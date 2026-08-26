# RAILS deploy blockers

The four things that stop a RAILS deploy from being a one-command operation,
each with what actually happens today, what would have to change, and what
already checks it.

This file is the single home for these. `README.md` used to carry the list as
five unowned sentences under "Media integration"; two of them had gone stale
without anyone noticing, which is the argument for giving them a file with
enough structure that staleness shows. Operator-side debt is **not** duplicated
here — that lives in `OPENBSD/data/debt.yml` and stays there.

A blocker leaves this file when its unblock criteria are met, not when it stops
being mentioned.

---

## 1. City vanity TLS

**Status:** blocks first install of a new city apex; does not block day-to-day
deploys of the three live apps.

`OPERATOR.sh` stage 1 issues an acme certificate for every apex in
`ALL_DOMAINS`. relayd can only load a keypair for a certificate that exists on
disk, so an apex without a cert is an apex relayd will not serve — and
`OPENBSD/etc/relayd.conf` has held a keypair line for a certificate that did not
exist, which is worse than missing: installing that file downs every site on the
box.

**Owner:** operator. Requires registrar action (DNS delegation), which an agent
must not perform.

**Unblock criteria**

- Every apex in `OPERATOR.sh#ALL_DOMAINS` resolves and serves its own cert.
- `relayd -n` passes against the repo copy of `relayd.conf` on the box before
  install, not after.

**Checked by:** `domain_alignment` compares `ALL_DOMAINS` against
`Brgen::DomainRegistry` and asserts a keypair exists for the four live apexes.
Nothing checks the city apexes are actually reachable — that is deliberate, see
the city-domain entry in `OPENBSD/data/debt.yml`.

---

## 2. relayd restart after route changes

**Status:** the missing half is built; the entry stays open until a real deploy
has exercised it on vm23.

A route change in `relayd.conf` needs `rcctl restart relayd`, and that restart
is not free. On 2026-08-10 relayd's `ca` process died during a restart
(`ca_dispatch_relay: invalid relay hash` → `lost child` → `parent terminating`)
and took every site on the box down for nine minutes. The deploy that triggered
it had logged `relayd(ok)` seconds earlier, because the check ran before the
restart.

**Owner:** operator.

**Unblock criteria**

- Post-restart verification is a separate step from pre-restart validation, and
  a deploy cannot report success on the earlier one.
- The failure signature is distinguishable from an app shed: relayd death
  refuses on **443** in ~30ms with sshd still up and the app answering on its own
  port from the box; a shed app leaves TLS answering and only the app port
  closed. Not port 80 — relayd declares one relay, `listen on 0.0.0.0 port 443
  tls`, so 80 refuses on a healthy box and tests nothing.

**Checked by:** `deploy_smoke_gate` validates relayd config content, and
`relayd_confirm_live` in `RAILS/_service.sh` re-checks 443 for 20s after the
restart, before the deploy is allowed to report success. It names which of the
two failure shapes happened: 443 refused while the app port still answers is
relayd down; both refused is the app, not relayd.

---

## 3. Production seeds are opt-in — under two different names

**Status:** open. The README named one variable; the deploy path reads two
others.

- `OPERATOR.sh` gates its seeding on `RUN_PRODUCTION_SEEDS=1`.
- `RAILS/_deploy.sh` gates its two seed steps on `SEED_ON_DEPLOY=1` and
  `DEMO_SEED_ON_DEPLOY=1`.

`RAILS/_deploy.sh` now treats `RUN_PRODUCTION_SEEDS=1` as an alias for
`SEED_ON_DEPLOY=1`, so the name the README documents is no longer inert.
The two paths still exist: OPERATOR seeds once on first install, deploy.sh
seeds on each deploy that asks. That split is deliberate.

**Owner:** RAILS.

**Unblock criteria**

- One name, or a documented reason the two paths seed differently. The
  alias is the documented reason.

**Checked by:** `RAILS/_deploy.sh` reads `RUN_PRODUCTION_SEEDS`.

---

## 4. openrsync on vm23

**Status:** the README entry was wrong. Corrected here.

The README said "openrsync broken on vm23 — deploy uses git pull". Those are two
different operations and only one of them is a workaround:

- **Repo update** on the box is `git pull`, and always was. That is the design,
  not a fallback.
- **Tree sync** into `/home/<app>/app` is `sync_tree` in `RAILS/_sync.sh`, which
  calls `openrsync -a --delete` first, retries without `--delete`, and only then
  falls back to a `tar cf - | tar xf -` copy, logging `openrsync failed; falling
  back to tar copy`.

So openrsync is used on every deploy, with a working fallback. The bundle-cache
bootstrap in `_deploy.sh` called it too, with no fallback at all; it goes through
`sync_tree` now, so all four calls have one.

**Owner:** operations, low priority.

**Unblock criteria**

- If openrsync is genuinely unreliable on this release, the bundle-cache calls
  need the same fallback the tree sync has.
- If it is reliable, the fallback stays as insurance and this entry closes.

**Checked by:** the bundle-cache bootstrap now goes through `sync_tree` like
the tree sync does, so all four calls have the openrsync -> tar fallback. The
remaining half of this entry stands: the fallback is still silent apart from a
log line, so a box where openrsync never works deploys correctly and slowly
forever without anyone learning.
