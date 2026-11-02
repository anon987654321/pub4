# Data freeze — one cycle, and what it buys

## The freeze (draft law text, to enter the catalogue by the normal pipeline —
translate into a `Law.define` in `law/meta.rb` or the laws.yml catalogue with
your usual message/detail/reach fields; do not hand-edit the YAML around it)

> **DATA_FREEZE_ONE_CYCLE** — For one convergence cycle, `MASTER/data/` gains
> no new top-level files. New configuration joins an existing data file
> through its existing loader; if no file fits, the need is argued to the
> operator, not filed into a new name. History does not return under `data/`:
> archived corpora stay in `docs/history/`. The reader-singularity ceiling
> ("one data file, one loader; the ceiling only ever goes down") continues
> down during the freeze. The freeze lifts by recorded decision, the way it
> entered.

Scope note: this freezes *files*, not values — thresholds, models, prompts
and laws keep changing inside the files they already live in. The freeze
targets the growth pattern the audit measured: the fifteen largest data
files grew to ~17.7k lines while `restructure_assessment.md` recorded
`laws.yml` at 2,170 lines — it is 4,289 now. The corpus doubled between the
assessment and this snapshot, which is exactly the drift F10/F11 exist for.

## Why one cycle, and of what

One convergence cycle (a `convergence.yml` workstream generation — weeks, not
quarters). The freeze is a budget with a sponsor, like every other ceiling in
the tree: it exists to force the alternative ("which existing file owns
this?") to be tried before a new name exists.

## Where the released budget goes

The freeze alone does not shrink anything; it stops the inflow while two
outflows run:

1. **The archaeology eviction** — `p2-hygiene/archive-recovery.sh` moves
   11.9k lines to `docs/history/` (gated, dry-run first).
2. **The cognition time-box (below).**

## Cognition time-box

`lib/cognition/` (11 files: Mind, State, Intelligence 435L, OutcomeModel,
SelfModel, Prediction, Affect, DiscourseObserver…) is speculative weight
inside the ratcheted `lib/` body, with no row in `maturity.yml` and no
workstream in `convergence.yml`. Give it the portfolio treatment the paid
plans got: one number, one horizon, decided in advance.

- **The number:** one subsystem (suggested: `OutcomeModel` prediction
  accuracy, which the schema already tracks) must appear in a landed,
  rendered surface — a dmesg line, a `/status` row, anything an operator
  actually reads — within the cycle.
- **If it does not:** the directory folds into a compat alias shim for one
  cycle (the `Fix::Kernel` pattern), then deletes. ~250+ lines return to the
  `lib/` budget, and the spine history records the fall the way it recorded
  `unified_diff_editor.rb`.
- **If it does:** it earns its lines the way everything else does, and
  `maturity.yml` gets its first cognition row with evidence.

Either outcome is a win; the only losing move is the current one — lines
spent, no surface, no decision date.
