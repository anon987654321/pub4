Read and follow `MASTER/CLAUDE.md` — the authoritative briefing for this repository.
It points to all MASTER data files (soul.yml, rules.yml, ruby_style.yml, workflow.yml).
Every code change must satisfy the axioms and rules defined there.

Run MASTER to validate changes:
```zsh
cd ~/pub4/MASTER && echo "/scan deep lib/" | bundle exec ruby exe/master
```
