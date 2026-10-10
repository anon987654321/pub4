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

The Rails tooling lives in `rails/`. The operator reaches it as `triangle` to
boot brgen, amber, bsdports and the MASTER face, as `premerge`, as `ci` and as
`coverage`. The same directory builds the stylesheets and the route manifest,
crawls the apps with a browser, and holds the lints that guard Rails
conventions. `agent_context.rb` prints the law and tree map an agent reads
before it works, and `snapshot.rb` backs `bin/operator snapshot`, which writes
one snapshot per tree for another model to read, or with `--mirror` the
byte-exact pack.

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
a fix, consider adding the gate that would have caught the fault.

Use Ruby and zsh, not GNU text tools. The repository deploys to OpenBSD, where
sed, awk, find, head, tail and wc behave differently, and perl and python are
banned in shell calls and committed scripts.

Tests here must prove something. `mutate.rb` changes a source, runs its test and
restores the file, because a test that stays green when the comparison it
covers is inverted proves nothing. Run the smallest check that proves the
work, and do not report done without its output.

## Checks

The Rakefile in this directory defines the checks. The test task runs the gate
and event-bus suites, the gate task parses and loads every tool, and the voice
quality task runs the speech regression harness without synthesizing anything.

```zsh
cd MASTER/tools && rake test
cd MASTER/tools && rake gate
cd MASTER/tools && rake voice_quality
```
