# Tools

**MASTER keeps its instruments in plain sight and holds them to the same
standard as the code they measure, because a measurement nobody has checked is
only an opinion that happens to carry a number.**

This directory holds the operators, scanners, audits and censuses that govern
the repository. They are small Ruby scripts, most with one question each. Which
methods in the runtime does nothing call? Which keys in the data files does
nothing read? Which files are exact copies, and which are one concept under
several names? Which exemptions still excuse a finding, and which excuse
nothing? Which prose claims a number that the design system already owns? The
operator reaches most of them. Run
`bin/operator measure` to see the ratchets they feed, `bin/operator lint` to
judge files by the laws with no model, and `bin/operator doctor` to check the
environment's known traps. `sweep.rb` runs the census instruments in one pass
and reports them in dmesg form. It measures and proposes, and it never edits.

Substantive registry, reachability and hygiene audits live in `audit/`; stable one-command endpoints whose implementations already live in `lib/` stay at the top level. The former root paths for moved audit tools remain compatibility entrypoints.

Repository maintenance tools live in `repo/`: tracked-tree inventory, entrypoint reachability and structural migration planning. Their former `tools/` root paths remain compatibility entrypoints. `snapshot.rb` stays a top-level operator command until its reader/writer contracts are verified independently.

Research and benchmarking tools live in `research/`: cognition outcome benchmarking, mutation-oriented challenge checks, and LLM trajectory reporting. Their former `tools/` root paths remain compatibility entrypoints for existing invocations.

Design baseline measurement lives in `audit/` alongside the other repository-wide checks. The former `tools/design_baseline.rb` path remains a command-compatible entrypoint; the canonical baseline is `tools/audit/design_baseline.rb`.

Voice tooling is grouped in `voice/`: `voice_benchmark.rb`, `voice_measure.rb` and `voice_quality.rb` are canonical there. Their former `tools/` root paths remain thin command-compatible entrypoints for existing invocations. Runtime speech and TTS implementations remain in `lib/voice/`.

The Rails tooling lives in `rails/`. The operator reaches it as `triangle` to
boot brgen, amber, bsdports and the MASTER face, as `premerge`, as `ci` and as
`coverage`. The same directory builds the stylesheets and the route manifest,
crawls the apps with a browser, and holds the lints that guard Rails
conventions. `agent_context.rb` prints the law and tree map an agent reads
before it works — `--json` serializes the same standing context (conduct,
blocking rules, coverage, shell contract, and with `--tree` the tree map) as
one JSON document for harnesses and session handoffs that consume data rather
than prose. `coverage_reconciliation.rb` computes the census the repo kept
finding by hand — files the trees hold that no instrument in
`checks/data/coverage_map.yml` claims to see; it reports inconclusive while
that map declares itself partial and fails on uncovered files once it is
complete. `diff_routes.rb` answers the question before an edit rather than
after it: given paths, a `--diff` base or `--stdin`, it prints the
`PATH_OWNERSHIP.yml` rows that govern each path and the check each row
declares, and exits 1 naming any path no row claims. It adds no
path-to-check table — the ownership file stays the only one.
`snapshot.rb` backs `bin/operator snapshot`, which writes
one snapshot per tree for another model to read, or with `--mirror` the
byte-exact pack. `gap_discipline.rb` checks the one chain that turns absence
into work: `data/gaps.yml` (what the suite is missing, which no scanner can
see) -> `data/ideations/*.yml` (candidates attacked one by one, a winner
picked with the losers' reasons kept) -> `convergence.yml` workstreams. It
fails on a pick whose critique did not keep it, a gap with fewer candidates
than a real choice needs, a "picked" ledger row with no workstream, and any
workstream name that exists nowhere.

Media work is no longer implemented here. The tools named dilla, lora, postpro
and replicate are symbolic links into `STUDIO/`, which owns that code and its
contracts. Their READMEs carry the detail, and the links remain so that older
callers still find them. Add nothing to a link target from this side.

## Read this part first

The instrument is wrong more often than the reasoning. Measurement code in this
repository has misread the code it measured more often than the code has
misread the world, so before you believe a finding, check the finding's source
against a case whose answer you already know. A probe can be the confound, as
when a greyscale test image made a color effect look dead. A reading can be
unstable while the thing read is steady, as when a parallel sum changed in its
last digit. Hash the output instead.

Declarations with no reader are the dominant defect. A preset names a setting
that no effect consults, a call passes an argument that the callee does not
accept and a rescue hides the error, and the feature never runs while every
report says it did. Before you trust a setting, find its reader. Before you add
a fix, consider adding the check that would have caught the fault.

Use Ruby and zsh, not GNU text tools. The repository deploys to OpenBSD, where
sed, awk, find, head, tail and wc behave differently, and perl and python are
banned in shell calls and committed scripts.

Tests here must prove something. `mutate.rb` changes a source, runs its test and
restores the file, because a test that stays green when the comparison it
covers is inverted proves nothing. Run the smallest check that proves the
work, and do not report done without its output.

## Checks

The Rakefile in this directory defines the checks. The test task runs the check
and event-bus suites, the check task parses and loads every tool, and the voice
quality task runs the speech regression harness without synthesizing anything.

```zsh
cd MASTER/tools && rake test
cd MASTER/tools && rake check
cd MASTER/tools && rake voice_quality
```
