# OPENBSD

**Production is one box, and this tree is everything that puts it there and keeps
it honest.** The box is vm23, and it runs every app behind relayd. This tree holds
the VPS configuration under `etc/`, `usr/` and `var/`, and the deploy tooling under
`bin/`, `lib/`, `checks/` and `test/`. The top of the tree keeps the installer,
`OPERATOR.sh`, the DNS helpers it sources, a few one-off Ruby tools, and two
scripts that vm23 still runs by their top-level paths, each of which says in its
header which line on the box pins it.

## Canonical operator path

Start with `RUNBOOK.md`, the single operational companion for live VPS work. Read it
before SSH, `doas`, deploy, DNS, relayd, NSD or recovery. `CLAUDE.md` holds the sharp
edges that have burned agents here, and `PATH_OWNERSHIP.yml` says what every path is
for. Read the man page for a file and its daemon before you change either.

## Visual identity

Operator output follows the shared contract in `MASTER/data/laws.yml`: plain,
quiet status text; an explicit location and phase; and concise, truthful failure
states. Colour is supplemental, never a replacement for written state. Keep the
prompt free of decorative banners and keep the actual 3D/ASCII face inside its
own renderer.

## Command entry points

**Redeploy production (one command, from a clean `origin/main` checkout):**

```zsh
./redeploy                 # wait until done, then state + canary
./redeploy brgen           # one app
./redeploy --follow        # attach to the box tmux session
./redeploy --detach        # start and return immediately
```

Hands-off path: local preflight, pin SHA, tmux on vm23, `vps-deploy` as root
(git as `dev`), stream progress until finished, then `vps-state` + public canary.
Log: `/home/dev/vps-deploy.log`. Session: `pub4-deploy`.

The commands live in one place. `data/operator.yml` is the source of the command
recipes, so do not write another catalogue. From the repository root, the operator
reaches the box with `MASTER/bin/operator vps state` and `MASTER/bin/operator vps
deploy`. In this tree `bin/check` is the local check, `bin/check-vps` checks vm23,
and `bin/vps-deploy` deploys. It deploys master, brgen, amber and bsdports in that
order, because every deploy sheds amber and bsdports and deploying them last
restores them in the same pass. `bin/vps_ci.sh` separately allowlists its three Rails
app targets before constructing any per-app path; it cannot be used with an arbitrary
name as a filesystem selector. The checks that guard the pipeline sit in `checks/`,
and the registry that runs them is `MASTER/checks/checks.yml`. Before a risky deploy,
`bin/rehearse` shows how the repository layout will map onto the box, which has a
different copy-tree layout.

## Privilege boundary

`OPENBSD/usr/local/sbin/pub4-admin` is the fixed-path root broker. It exposes
allowlisted service actions, atomic deploy receipts/secrets, a fixed CI lock, and
bounded Rails/CI task and sync verbs. CI and production Rails tree replacement run
with the selected app account; the CI runner has a wall-clock process-group deadline.
The deploy adapter verifies root-owned rc.d files rather than installing from the
checkout, and relay route verification is read-only. The progress records in
`/var/db/pub4/deploy_status` stay root-only; `vps-state` reads them through the
allowlisted `doas -n pub4-admin deploy-status-read <app>` verb. Missing status is
JSON `null`; unreadable or malformed status is reported as corrupt rather than
silently shown as no deploy.

The Bundler content-addressed cache now uses fixed broker verbs, a bounded Ruby-version
key and immutable SHA-256 objects; the app copies cache objects rather than sharing
root-owned inodes through hard links. The CI and `vps-deploy` entrypoints now fail closed without the reviewed broker; direct root-shell, service-control and receipt-write fallbacks were removed from those paths. The MASTER web deploy now uses fixed broker verbs for assets and daemon runtime directories, and refuses to install a checkout-owned `rc.d/master` as root. `deploy-smoke` checks services through the broker first. The fresh-box `vps_install_all.sh` keeps a direct `rcctl` fallback only until the broker is installed. The remaining privilege cut is the wider operator/recovery surface and any installer helpers that still invoke `doas` directly. Keep the existing `/etc/doas.conf` rule and `wheel` membership unchanged until every privileged path is inventoried, migrated, and tested in a real OpenBSD checkout on vm23.

## Configuration ownership and secrets

Domains and DNS come from one source. `RAILS/apps.yml` lists the owned domains, and
the files in `data/` and the zone helpers derive from it. What is in `var/nsd/` is a
mirror of the NSD configuration templates and nothing more. The live signed zones
sit on vm23 under `/var/nsd/` and are deliberately not in git, because a signed zone
in a shared checkout is a key in a shared checkout. Service secrets live in `/etc/*.env` on
the box and never in this tree. The interactive operator shell loads provider
credentials, when configured, from the user's `~/.config/pub4/operator.env`; keep
that file host-local with owner-only permissions, outside this checkout.

## Backups, alerts and what the public sees

Nothing on the box backs itself up off the box. `bin/dr-pull` runs nightly on the
operator's Mac, brings back a checksummed snapshot of every production database and
the uploaded files, and `bin/dr-pull --drill` restores the newest pull into a
scratch directory and reads it back. A healed symptom must not stay quiet, so
`usr/local/bin/pub4-alert` records a recurring fault once per six hours in
`/var/log/pub4-alerts.log`, and `bin/vps-state` prints the last few next to each
deploy stamp. `bin/domain_watch.rb` asks the registries which domains are still
ours, and with `--tls` it asks every public host for its certificate and a
health answer, the way a visitor would.

## Local manual pages

The deploy and privileged-broker references are under `man/man8/`. From the
repository root, use:

```zsh
MANPATH="$PWD/OPENBSD/man" man vps-deploy
MANPATH="$PWD/OPENBSD/man" man pub4-admin
```

Read `RUNBOOK.md` before live production work. The manual pages do not replace
preflight, approval, health verification or recovery procedures.
