# Changelog

Written for whoever picks this tree up next — human or model — and reads
newest first. Entries record *what changed and why it mattered*, not what the
diff already shows.

Two conventions, both learned the hard way here:

- **A finding is a hypothesis until it is located.** Where something was
  reported and turned out not to be true, it stays in this file with the
  correction, because the retraction is as useful as the fix.
- **Numbers are re-derived, never remembered.** Every count below was measured
  at the moment of writing.

Commit subjects are the fine-grained record; `git log --oneline` is the index.
This file groups them into what actually landed.

---

## 2026-08-23

### Fixed — things that were broken and are not any more

**MASTER's release gate had been guaranteed-red for eleven days, twice over.**
`bin/ci` called `ROOT/core/spec/core_smoke.rb`; `core/` was folded into `lib/`
on 2026-08-12 and the file has been at `spec/core_smoke.rb` since, so that step
raised `LoadError` on every run. Because `bin/check --profile=full` is
`[bin/ci, bin/probe all, rake audit]`, the operator-grade gate could not pass at
all. Fixing it exposed a second defect underneath: `run_step` invoked rake
without bundler, so `rake test` died partway through on a gem clash and reported
**177 runs where the same task under bundler reports 1245** — and `bin/ci`
recorded that as its result. Both fixed; the gate is down from five failures to
three, and the three that remain are visible rather than phantom. (`ca98e564c`)

**A law written after a batch-delete incident could not read a shell script.**
`NEVER_BATCH_DELETE` declared `languages %i[ruby shell]`, and
`FILE_LANGUAGE_MAP` emits `"zsh"` — nothing produces `"shell"` — so all 73 shell
scripts were invisible to it, including both glob-`rm` sites in the tree.
`prove!` never caught it because it tested detectors and never tested reach; it
now refuses any law declaring a language nothing produces. Verified the guard
bites by reintroducing the bug: 0 failures becomes 7. (`742e091b5`)

**Three safety interlocks read as wired and were not.** `Review::Consensus` —
three models, quorum two, before an autofix lands — was constructed by
`Agent#consensus` and called by nothing; it is reachable from `RuleLoop` now,
behind `MASTER_CONSENSUS_FIXES`, because three model calls per fix is a spend to
opt into. `OutputGuard` dug `anti_simulation.require_evidence` from the top
level of `soul.yml`, which nests it under `absolute.`, so the evidence contract
was two hardcoded strings beside the read meant to supply them. And `min_lines`
was extracted with `/\d+/` from a sentence containing no digits, so the floor
was permanently its fallback. (`0fcaffc45`)

**The guard against inert law passed on coincidence.** `test_limits_split`
exists to stop unread law drifting back into enforced law, and verified "this
file reads this key" with a bare substring match — four of eleven claims were
false, with `zeitwerk` matching the gem's own `require` line. Both directions now
require the file to open `limits.yml` *and* name the key; the reverse guard
failed on the identical coincidence the moment the forward one was fixed.
`conflicts` and `sweep` had no reader anywhere and moved under `guidance:`.
(`0fcaffc45`)

**File-scope laws could not see a comment.** All eleven went through
`scan_file`, which — unlike `scan_lines` beside it — applied neither the comment
leaders nor the `scan: intentional` opt-out. That is how `RATE_LIMITING_MISSING`
fired at `:error` on a sixteen-line controller with no actions, on the word
"login" inside a comment. Since `file_processor` returns early on any `:error`
lexical finding, false positives of that shape were silently buying files out of
the semantic review pass: **87 files, re-measured at 10 across 731 after the
detectors were corrected.** (`a6ace545f`, `742e091b5`)

**dilla's dub rack was dead and the voyager lead rendered dry.** A comment
between two backslash-continued string fragments ends the literal, so
`delay_throw` returned only its last two lines, `[dt_dry]` was never defined,
and every `RACK=dub` render died. Separately `aphaser=speed=0.09` sits below
ffmpeg's floor of 0.1 and a refused filter takes the whole chain with it, so
that patch came back with no phaser, no lowpass and no EQ. Both are pure
failures, so fixing them restores an intended sound rather than choosing a new
one. Swept the other 357 filter parameters against their ranges: clean.
(`adecf23d0`)

**Three postpro effects ran, raised nothing, and changed no pixel.**
`print_film` never ran at all — `maplut` returns the LUT's `:matrix`
interpretation, so a `colourspace("b-w")` was a no-op and the bandjoin raised
into a rescue; cinematic, blockbuster and cinema_scan have never had a print
stage. `edge_aware_nr` computed a value plus its own negation, identically zero,
so it was a plain full-frame blur — `quality_uplift`, the preset that exists to
clean up detail, was destroying it. `--watch` graded its own output, producing
fourteen nested generations in thirty seconds on what defaults to a phone camera
roll. The guard is a new test asserting every one of the 82 recipe-allowed
effects moves a pixel; it took three tries to get the probe right.
(`a2a0a4294`)

**amber and bsdports: comment deletion never worked.** Both respond
`format.turbo_stream` and neither app has a `destroy.turbo_stream`, so the row
went and the comment stayed on the page. bsdports also wrote its activity row
*after* `destroy!`, against a deleted primary key, and called
`require_authentication` inside `watch`/`unwatch` where a redirect does not halt
the action. (`4f0da8a9c`)

**Two jobs raised before doing their work.** `belongs_to :user` is not covered
by `CascadingAssociationsLoad`, so `FingerprintGarmentJob` and
`DeclutterHygieneJob` raised on a bare `find`. Fixing that surfaced a live bug
underneath: the fingerprint job called `create_garment_embedding!` with no
arguments and then updated the row, but `provider` and `model` are required — so
it has never stored a fingerprint for an item without an existing embedding,
which is every item the first time. (`4f0da8a9c`, `4319bf103`)

**Opening an inbox issued one UPDATE per unread message.** `messages#index`
called `read!` inside `find_each`, turning a GET into an unbounded write burst.
(`3c06123ba`)

**The load guard's own installer swallowed its failure.** `install … || true`,
for the script the crontab runs every five minutes to keep a 1GB box standing.
`vm_resource.yml` also described a machine that does not exist — a load ceiling
of 1.2 against a measured p75 of 1.69, a memory floor of 12% against an observed
p50 of 13 — while the live guard quietly used 2.5/5.0 and 8. Three scripts ran
with neither `set -e` nor `pipefail`. (`2f8434281`, `1e16903a4`)

### Changed — structure

**`style:` was flattened and the reason it never mattered was found.**
Every category is one level under its topic now (46 renames), and `rails_stack`
— 58 leaf values reaching five deep — is its own root key, because Rails
versions are stack truth rather than a rule about writing Ruby. Done textually,
not by a YAML round-trip: the block carries 96 comment-bearing lines. Then the
discovery: `DATA_ALIASES` pointed `:ruby_style` at `style.ruby_style`, a key that
has never existed, so a defensive `is_a?(Hash)` guard turned the lookup into
"feature politely off" and **the entire style block reached no prompt at all.**
Two more of the same shape went with it. (`2f4684dc3`, `56e50a7b5`)

**The universal rules were filed under Ruby.** `style.ruby.line_order` declared
`applies_to: [ruby, yaml, erb, js, css, html, sh, md]` from inside the Ruby
bucket. Comment discipline, identifier naming and the blank-line limit are the
same shape; all move to `style.universal`. NN/g's ten heuristics had two homes —
written out under `style.nielsen_heuristics` while twelve registry entries
already carried them as scored rules — and only one of the two was enforced. The
data copy is gone and the prompt line derives from the rules that enforce it.
(`56e50a7b5`)

**150 lines of law nobody read were deleted.** `design_rules.pixel_field`
mandated ordered dithering, limited palettes and 320×180 internal resolutions,
with zero readers anywhere, while instructing anything that did read it to build
the IRIX/8-bit aesthetic dropped on 2026-07-18. `DECISIONS.md` records it.
(`aa918e617`)

**`lint:data_singularity` is clean.** `rules.yml` and `design_baseline.yml` both
declared a top-level `rules`; the law owns that name, so the other is
`rule_ceilings`. (`ca98e564c`)

### Added

- **`bin/pub4 snapshot`** regenerates the `snapshot_<TREE>.md` packs. The old
  `bin/snapshot` was deleted with the DEPLOY tree, leaving three ~5 MB mirrors
  stale at a commit no checkout still has and nothing able to refresh them.
  STUDIO now has one too. Policy is stated and honest: git-tracked text files
  inlined in full, binaries listed. Round-trip verified byte-identical.
- **One-click Vipps** on the marketplace buy bar — order created and payment
  started in the same request. The provider check is lane-scoped so the cart
  lanes keep reporting an empty cart before anything about payment providers.
  Hidden until the keys exist, because an unkeyed provider must be absent rather
  than a button over nothing. (`bc0b93ed9`, `b87a71352`)
- **Feeds and card grids are real lists.** Twelve containers became `ul`/`li`,
  including the city front page. The `li` carries `display: contents` so it
  generates no box and the container's own grid still sees the card as its item;
  proven on production against an unconverted control using the same class —
  identical on every geometric property. `Shared::InfiniteScrollReflex` takes
  `wrap_in:` so appended pages stay list items. (`11525bda3`, `94df5b035`)
- **Tests where there were none**: `DeclutterController` (money path and
  ownership scope included), the strict-loading job paths, and postpro's
  every-effect-moves-a-pixel guard.

### Corrected

**Five amber paths were reported as raising in production; four of them do
not.** `ApplicationRecord` sets `strict_loading_by_default`, but
`Shared::CascadingAssociationsLoad`, declared three lines below it, exempts
every association carrying a `:destroy` cascade — which `declutter_review`,
`declutter_challenges`, `sustainability_metric` and `garment_embedding` all are.
The declutter pages never 500'd. Found because the test written to prove the fix
passed just as happily with the fix reverted. `belongs_to :user` is not exempt,
so two of the five were real. (`4319bf103`)

**Five further candidate findings died on verification**, and are recorded so
nobody re-chases them: unindexed foreign keys whose hot columns are indexed; 58
"untested" controllers that all have tests named by topic rather than class;
nine "missing" Stimulus controllers vendored under `shared/vendor/javascript/`;
59 "unreachable" dilla constants that are all read; and a `PatchApplier` bug
fixed back at `4c9f513d2`. The standing lesson: naive pattern-matching over this
repo produces mostly false positives.

---

## 2026-08-22

Ninety-one commits across two days; the ones above are the durable half. Also
landed: the pixel sweep (a float-label rule was transforming the brand chrome,
because `:placeholder-shown` never applies to a checkbox); 87 duplicate `banner`
landmarks removed, so a twenty-post feed no longer announces twenty-one; the
marketplace order page stopped rendering Status/Total/Buyer in English on a
Norwegian site; four copies of the look-preset radios became one partial with
the fieldset three of them were missing; two fake tab widgets started telling
the truth; the duplicate census was priced at 51 and later given a `--list`, on
the grounds that a count nobody can act on is a ratchet rather than a finding.

---

## Before this

`git log --oneline` is the record. `MASTER/DECISIONS.md` and
`OPENBSD/DECISIONS.md` hold the standing decisions; `MASTER/DEBT.md` and
`OPENBSD/data/debt.yml` hold what is known and deliberately unfixed.
