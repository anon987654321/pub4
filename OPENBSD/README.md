# OPENBSD

**Production is one box, and this tree is everything that puts it there and keeps
it honest.** It holds the VPS configuration under `etc/`, `usr/` and `var/`, and
the deploy tooling under `bin/`, `lib/`, `sh/` and the gates beside them.

Start at `START_HERE.md`. The full runbook, the one to read before touching the
box, is `RUNBOOK.md`, and `RECIPES.md` is the copy-paste companion for paths you
would otherwise get wrong. Each app deploys through its own script at
`RAILS/<app>/<app>.sh`, and `RAILS/apps.yml` is the inventory of which apps
exist.

Three checks answer most questions: `MASTER/bin/pub4 status` for the trees,
`OPENBSD/bin/check` for this one locally, and `OPENBSD/bin/check-vps` against the
live vm23.

What is in `var/nsd/` is a mirror of the NSD configuration templates and nothing
more. The live signed zones sit on vm23 under `/var/nsd/` and are deliberately
not in git, because a signed zone in a shared checkout is a key in a shared
checkout.
