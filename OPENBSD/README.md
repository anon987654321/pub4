# OPENBSD

**Production is one box, and this tree is everything that puts it there and keeps
it honest.** It holds the VPS configuration under `etc/`, `usr/` and `var/`, and
the deploy tooling under `bin/`, `lib/` and `gates/`. The top of the tree keeps
the installer, `OPERATOR.sh`, the DNS helpers it sources, a few one-off Ruby
tools, and two scripts vm23 still runs by their top-level paths, each of which
says in its header which line on the box pins it.

Start here. `RUNBOOK.md` is the single operational companion for live VPS work;
read it before SSH, `doas`, deploy, DNS, relayd, NSD or recovery.
`OPENBSD/bin/check` is the local gate and `OPENBSD/bin/check-vps` checks vm23.
`OPENBSD/data/operator.yml` is the command and recipe source, so do not create
another command catalogue. `CLAUDE.md` holds the sharp edges that have burned
agents here, and `PATH_OWNERSHIP.yml` says what every path is for.

What is in `var/nsd/` is a mirror of the NSD configuration templates and nothing
more. The live signed zones sit on vm23 under `/var/nsd/` and are deliberately
not in git, because a signed zone in a shared checkout is a key in a shared
checkout.
