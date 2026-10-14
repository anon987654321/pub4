# OPENBSD

**Production is one box, and this tree is everything that puts it there and keeps
it honest.** The box is vm23, and it runs every app behind relayd. This tree holds
the VPS configuration under `etc/`, `usr/` and `var/`, and the deploy tooling under
`bin/`, `lib/`, `gates/` and `test/`. The top of the tree keeps the installer,
`OPERATOR.sh`, the DNS helpers it sources, a few one-off Ruby tools, and two
scripts that vm23 still runs by their top-level paths, each of which says in its
header which line on the box pins it.

## Canonical operator path

Start with `RUNBOOK.md`, the single operational companion for live VPS work. Read it
before SSH, `doas`, deploy, DNS, relayd, NSD or recovery. `CLAUDE.md` holds the sharp
edges that have burned agents here, and `PATH_OWNERSHIP.yml` says what every path is
for. Read the man page for a file and its daemon before you change either.

## Command entry points

The commands live in one place. `data/operator.yml` is the source of the command
recipes, so do not write another catalogue. From the repository root, the operator
reaches the box with `MASTER/bin/operator vps state` and `MASTER/bin/operator vps
deploy`. In this tree `bin/check` is the local gate, `bin/check-vps` checks vm23,
and `bin/vps-deploy` deploys. It deploys master, brgen, amber and bsdports in that
order, because every deploy sheds amber and bsdports and deploying them last
restores them in the same pass. `bin/vps_ci.sh` separately allowlists its three Rails
app targets before constructing any per-app path; it cannot be used with an arbitrary
name as a filesystem selector. The gates that guard the pipeline sit in `gates/`,
and the registry that runs them is `MASTER/gates/gates.yml`. Before a risky deploy,
`bin/rehearse` shows how the repository layout will map onto the box, which has a
different copy-tree layout.

## Privilege boundary

`OPENBSD/usr/local/sbin/pub4-admin` is the staged fixed-path root broker for deploy service actions, receipts, the CI lock and two trusted helper scripts. `OPENBSD/bin/vps-deploy` uses it when the installed `root:wheel` copy exists. CI's installed copy-tree path now synchronizes as the selected app user and the runner has a wall-clock process-group deadline. The first-rollout fallback, `RAILS/_deploy.sh`, and other app install paths still contain direct `doas` calls. The runbook records the rollout boundary; do not narrow `/etc/doas.conf` or remove `dev` from `wheel` until those paths have been migrated and tested on vm23.

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
