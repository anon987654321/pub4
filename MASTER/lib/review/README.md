# Review

**Nothing MASTER writes reaches disk without passing through here.** Review is
the constitution scanner, the council that deliberates over what the scanner
found, the swarm that parallelises the work, and the crews that specialise it.

`scan/` holds the rules, the scanner, and constitution triage, reached by `rake
constitution` and `rake selftest`. `council/` is multi-agent deliberation and the
quality framework it argues within. `swarm/` is the coordinator, the vote engine,
and the worker roles. `review_crew/` is the set of review agents narrow enough to
name.

Enter through `MASTER/bin/audit`, `MASTER/bin/gate`, or `rake selftest`.
