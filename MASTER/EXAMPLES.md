# Examples

Examples are part of the contract. Prefer matching these shapes over inventing a new ritual.

## Good Patch Shape

- Reads the target and nearby tests first.
- Changes one concern.
- Keeps existing naming and error style.
- Adds or updates the smallest relevant test.
- Reports exact checks run.

Closeout:

```text
Changed the YAML singularity lint to parse top-level keys with Psych nodes, so aliases do not materialize during the check. Added a regression test.

Checks: ruby -Ilib:test test/test_self_test.rb; rake lint:data_singularity.
Known debt: rake selftest still fails on existing ROBUSTNESS/LINEARITY/ABSTRACTION/DENSITY findings.
```

## Bad Patch Shape

- Renames several registries because they look similar.
- Moves `knowledge/` without updating `SearchKnowledge`.
- Runs no checks because the edit was "docs only" while changing executable guidance.
- Marks TODO items complete without evidence.

Closeout to avoid:

```text
Cleaned things up. Should be good.
```

## Good Scan Triage

```text
SINGULARITY: true duplicate in data/providers.yml; merged keys.
ROBUSTNESS: timeout findings remain known debt; no unrelated edits.
Scanner false positive: SQL detector flagged as SQL injection; needs scanner exemption, not code removal.
```

## Good TODO Update

```markdown
- [x] Fold the four rule shards into `data/rules.yml`.
      Verified by reading live consumers in `lib/review/output_check.rb`,
      `lib/fix/fix_loop/rule_order.rb`, and `lib/boot/data.rb`, then proving
      `Master.load_rules` deep-equal to its pre-fold output before deleting them.
```

## Bad TODO Update

```markdown
- [x] Fix constitution scan.
```

This hides the count, the command, and whether findings were fixed or merely reclassified.

## Good Refusal To Refactor

```text
I am folding `data/design_rules.yml` into `data/rules.yml`. It has a distinct consumer, which argues for keeping it; it also defines `typography` a second time with numbers that disagree with `style.yml`, which argues louder. One definition beats proximity.
```

## Bad Refactor

```text
Merged all rule-like YAML into one file for simplicity.
```

This violates PROXIMITY unless each live consumer was changed deliberately and tested.
