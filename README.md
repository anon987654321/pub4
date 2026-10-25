# pub4

pub4 is one repository with four governed trees: **MASTER** controls the repair and reasoning runtime, **RAILS** holds the products, **OPENBSD** owns deployment and machine security, and **STUDIO** owns sound and media generation. Recovery material lives in `MASTER/data/recovery/` (restore ledgers) and `MASTER/docs/handoffs/legacy/` (the archived predecessor ledger), not in a fifth application tree.

Start with the repository's [agent contract](AGENTS.md) and the relevant tree or project `README.md`. Design constraints are specified in `MASTER/data/laws.yml` under the constitutional authority of `MASTER/data/soul.yml`; executable laws in `MASTER/law/` and scanner adapters enforce them. Each README is the human entry point for its boundary, while configuration and code remain authoritative for behavior. Do not call work complete without the command output that proves it.

## Visual identity

pub4's visual direction is **signal and stillness**: flat neutral structure,
decisive type, deliberate negative space, and a restrained mineral-lime signal
(`#C8F55F`) used only where it carries meaning. The contract is
`MASTER/data/laws.yml#visual_identity_contract`; values live in
`MASTER/data/tokens.yml#tokens.visual_identity`. Brgen keeps its deep-blue local
identity, Amber preserves garment colour, bsdports remains terminal-green,
OpenBSD output stays plain and explicit, and STUDIO never overrides operator-owned
grades. The reference is inspiration only: pub4 must retain original branding.

## Static repository index

The root-level Vercel project serves only `public/index.html`, using
`vercel.json` to select the `public` output directory and the Other framework
(no application runtime). This index points readers to the canonical source
trees; it does not boot MASTER, run Rails, deploy OPENBSD, or generate STUDIO
media. A successful build or HTTP response proves only that the static index was
delivered, not that an application or production host is healthy. Production
deployment remains governed by OPENBSD.

## The four trees

- [MASTER](MASTER/README.md) — constitutional Ruby runtime, `/fix`, laws, operator commands and verification.
- [RAILS](RAILS/README.md) — Brgen, Amber, shared product code and Rails contracts.
- [OPENBSD](OPENBSD/README.md) — production host, network, deployment, security and recovery.
- [STUDIO](STUDIO/README.md) — Dilla, visual tools, post-processing and media-provider workflows.

## Operator commands

Run the pinned MASTER operator from its own tree:

```zsh
cd MASTER
bin/operator status
bin/operator measure
bin/operator check --scan-only
```

The check's default mode can repair files; `--scan-only` is the read-only option. Use the tree's canonical test runner and record its real exit status. The main proof surfaces are `cd MASTER && rake test`, `ruby RAILS/test/run_all.rb`, `ruby OPENBSD/bin/check --profile=full`, and `cd STUDIO && rake test`. Browser, device, paid-provider, DNS, backup, and production checks require their respective real environments.

Agent-owned unfinished work is tracked in the single root [TODO.md](TODO.md). Work that only the
operator can finish is listed in [operator seams](MASTER/data/operator_seams.yml), each with its
required closure evidence. Decisions live beside the thing they decide; the two ledgers have
different owners and are intentionally not duplicates.

[MIT License](LICENSE).
