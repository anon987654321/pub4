# pub4 backlog

The single backlog for the whole repo. One file, at the root, replacing the
per-tree lists that used to drift out of sight of one another: `MASTER/DEBT.md`,
`RAILS/TODO.md`, `RAILS/BLOCKERS.md`, and the `OPENBSD/data/debt.yml` register.

Authority order is unchanged: `MASTER/data/soul.yml` > `MASTER/data/rules.yml` >
the root `CLAUDE.md` > the per-tree contract. Feature truth is still
`RAILS/apps.yml`; horizon (aspirational, agent: ignore) is still
`RAILS/apps.horizon.yml`. The decision records — `MASTER/DECISIONS.md` and
`OPENBSD/DECISIONS.md` — are rationale, not backlog, and stay where they are.

How to read this file. Each tree has its own top-level section, and everything
in it is open. **A record is deleted when it closes** — `git log` holds the
history, and a backlog that keeps every item it ever had teaches the reader to
skim. What survives a close is the false positive worth not re-discovering:
those live under "Debt — resolved records" and are guards, not history.

One habit this repo learned the hard way, and it governs every finding below:
**a finding is a hypothesis; re-measure before working from one.** Naive
pattern-matching over this tree produces mostly false positives, and several of
the entries here were themselves stale when written. Verify the instrument
before the finding.

An item leaves this file when a check proves it, not when it stops being
mentioned.

**Forward work is the last section of this file**, merged from `WISHLIST.md` on
2026-09-06.
---

## MASTER

### Survey of MASTER — 2026-09-08

A read-only survey of `MASTER/`, ranked by value. Nothing here was fixed. What
was run: `cd MASTER && rake audit`, then each of its twenty remaining gates
individually; `bin/pub4 measure`; `tools/cohesion.rb --census --list` and
per-directory; `lib/review/scan/cross_file_analysis.rb` over `lib/**/*.rb`; and
four purpose-built probes whose self-checks are stated with each finding. Every
item names a file and a line. The last two subsections say what is not worth
chasing and which findings are least certain.

The headline is that the payment for `spine.lib_body_ceiling` already exists.
`lib/` is 38110 body lines against a ceiling of 37464, and 167 unreferenced
methods in it account for 649 of those lines.

**`rake audit` stops at its third gate, so seventeen gates never run.** The task
list is `dogfood constitution selftest studio core_smoke security_sweep lint:*
loc_budget` (`MASTER/Rakefile:742`). `selftest` aborts on three violations
(`Rakefile:160`), and the process ends there. Running each remaining gate by
hand found sixteen green and four red: `studio`, `lint:data_singularity`,
`lint:spine` and `loc_budget`. None of the four was visible from the audit's own
output. The Rakefile already carries the comment that a gate nobody calls has
stopped measuring without anyone deciding it should; a gate behind an early abort
is the same condition with a different cause. The fix is not to make the audit
lenient — it is to clear the two blockers below, and meanwhile to say in the
audit's failure line how many gates it did not reach.

**Two of `selftest`'s three violations are the SINGULARITY law firing on three
generated ceiling files.** `MASTER/data/cohesion_census.yml:1` and
`MASTER/data/data_reach.yml:1` are reported for a top-level `members` key that
`MASTER/data/code_reach.yml` also defines. All three are committed ratchet files
written by `tools/cohesion.rb:310`, `tools/data_reach.rb` and
`tools/code_reach.rb:39`, and in each one `members` is the *subject* of a finding
— the list of families, unnamed keys or unreached files — not a configuration
value with two sources. That is exactly the case `SINGULARITY_EXEMPT_REGISTERS`
was created for at `MASTER/lib/review/scan/self_test.rb:240`, where
`doc_baselines.yml` is exempted with that reasoning written out. Add the three
census files there, or rename each key to `family_members`, `unnamed_members` and
`unreached_members` so no exemption is needed. Either unblocks seventeen gates.
The third violation is real and small: `parse_through_flags` at
`MASTER/lib/cli/command_registry/work_commands_extra.rb:60` is 26 code lines
against a limit of 20.

**`FILE_LAYOUT` reports the convention it exists to enforce as a violation.**
`MASTER/lib/review/scan/rules/structural_rules.rb:23` finds the first bare
`private` line in the file and then, at line 25, takes the first `def` after it
that is not `def self.`, `initialize`, `to_s` or `inspect` — with no notion of
visibility or scope. The first private method of every class therefore matches.
Verified by instantiating `FileLayoutRule` and running it over
`MASTER/lib/cli/pipeline/through.rb`, a file whose order is exemplary: it
reported line 96, `def build_sections`, the first method under the `private` at
line 94. Over all 428 files in `lib/` it produces 233 findings; a Prism walk that
tracks visibility per class says 227 of them are private instance defs, and the
six it disagreed about are all inside `class << self` blocks my walker skipped,
so the true rate is 233 of 233. `FILE_LAYOUT` is on `RULE_RETUNE_IDS`
(`MASTER/lib/review/scan/constitution_triage.rb:46`), which is where a broken
detector goes to be forgotten: the entry is correct that the rule is noisy and
wrong that the answer is retuning. The fix is a scope-aware check — a def below
`private` is public only after an explicit `public`, or inside a nested scope —
after which the id comes off the retune list.

**167 methods in `lib/` are named nowhere in the repo, and they carry 649 body
lines.** The instrument is token frequency, not a call matcher: every
identifier-shaped token in every text file across all four trees is counted, and
a method whose name occurs only on its own `def` line is unreferenced. Counting
bare tokens has no boundary to get wrong, which matters because all three
recorded matcher bugs here are boundary bugs — `\b` after an escaped `foo?`, a
lookbehind excluding `.`, a lookbehind excluding `:`. It errs toward calling a
method live. Removing a dead method removes the references its body made, so the
pass iterates; four rounds settled. Protected from the census, because the
instrument cannot see them: names reached by an interpolated `send` (the prefixes
`do_`, `section_` and `visit_` were harvested from `lib/` itself), setters, Ruby
and Prism hooks, and any name defined more than once. Self-check: `Expression.
for_council` at `MASTER/lib/voice/expression.rb:49` reads dead while
`for_council_persona` at `:303` reads live, which is the distinction a
lookbehind-based matcher loses. The two largest clusters are the next two
findings; the rest is a long tail of one- and two-line methods, and the full list
is reproducible from the probe described here.

**The `Session` slash-command surface is a previous dispatch mechanism left
standing.** `MASTER/lib/cli/session/command_ops.rb` holds twenty unreferenced
private methods worth 103 body lines — `run_rails_pwa_fix` at `:68`,
`run_rails_pwa_audit` at `:50`, `run_propose` at `:231`, `run_why` at `:148`,
`run_phase` at `:179` and down to the endless `run_rollback` at `:101` and
`run_redo` at `:103`. `MASTER/lib/cli/session/repl_flow.rb:99` is the only thing
that routes a slash command inside the session, and it handles four —
`help`, `exit`/`quit`, `undo`/`rollback`, `clear` — before falling through to
`run_input`, which goes to `CommandRegistry`. `NL_DISPATCH` at
`repl_flow.rb:81` sends to two methods by symbol, and `toggle_chips` at
`command_ops.rb:215` is the twin of the `toggle_focus` it names — the pair
`cross_file_analysis.rb` reports as one shared structure, one half of which is
dead. Delete the twenty.

**The swarm coordinator is constructed and never called.**
`MASTER/lib/builder/ai_boot.rb:32` builds `Review::Swarm::Coordinator` (only when
`MASTER_FULL_BOOT=1`) and `ai_boot.rb:20` puts it in the bundle as `swarm:`.
Grepping `lib`, `bin` and `web/app` for `:swarm]`, `.swarm` and `swarm:` finds
the two constructions and three event names, and no read of the key. Its whole
public surface is therefore unreached: `dispatch` at
`MASTER/lib/review/swarm/coordinator.rb:174`, `analyse_and_review` at `:180`,
`fan_out` at `:191`, `dispatch_parallel` at `:212`, `worker_roles` at `:222` and
`swarm_vote` at `:228`, plus the private thread machinery beneath them — 99 body
lines of 278. `MASTER/test/test_swarm.rb` exercises `build_swarm_result` through
`send` and `WORKER_CLASSES`, so the tests do not contradict this. Decide whether
the swarm is a feature: wire it to a caller, or delete it. Leaving a
parallel-review engine in the container with no reader is the inert-wiring shape
this repo keeps paying for.

**`control_commands` is never merged, so `/orders` and `/soul` are not
commands.** `MASTER/lib/cli/command_registry.rb:157` builds a table with
`"orders"` and `"soul"` in it, and the name `control_commands` occurs exactly
once in all four trees — its own `def`. Every other builder in the registry
(`agent_commands`, `core_commands`, `domain_commands`, `media_commands`,
`memory_commands`, `reach_commands`, `system_commands`) is called from
`command_registry.rb`; this one is not. Twenty-eight body lines hang off it:
`dispatch_orders` at `:164`, `run_due_orders` at `:177`, `dispatch_soul` at
`:183`, and downstream `Voice::Soul#propose_from_violations` at
`MASTER/lib/voice/soul.rb:53`. The scheduler itself is live —
`ai[:standing].wire_container` runs at `MASTER/lib/builder.rb:225` — so what is
missing is only the operator surface for 222 body lines of standing orders. Merge
`control_commands` into `build`, or delete it and say in `data/state.yml` that
orders are event-driven only; that file's comment currently claims they run "via
/orders".

**Twenty-five registered `dispatch_*` methods are not named by any command
table.** In `MASTER/lib/cli/command_registry{,/*}.rb` there are 73 `dispatch_*`
definitions and 37 distinct symbols passed to `command(`. Diffing them, then
keeping only names whose token count across the repo is one, leaves 25 methods and
98 body lines with no route: `dispatch_rules` at
`MASTER/lib/cli/command_registry/work_commands.rb:191` (19 lines),
`dispatch_tail` at `work_commands_status.rb:137`, `dispatch_map` at
`work_commands.rb:90`, `dispatch_topic` at `work_commands_extra.rb:255`, and on
down to the endless `dispatch_rollback` and `dispatch_redo` at
`command_registry.rb:90` and `:92`, both superseded by `"rollback" =>
command(:dispatch_undo, undo)` at `:42`. `dispatch_map` alone strands six
`map_*_report` helpers at `work_commands.rb:104-132`; the transitive closure is
what the 649-line figure counts.

**Sixteen LLM tool wrappers write one `execute` sixteen times.**
`MASTER/lib/io/llm.rb` is 234 lines of which the great majority is the same
method: `result = @tool.call(<coerced params>)` then `result.ok? ? <format> :
"Error: #{result.message}"`. See `:30`, `:42`, `:55`, `:67`, `:80`, `:91`,
`:104`, `:115`, `:127`, `:140`, `:157`, `:172`, `:186`, `:200`, `:212` and
`:224`. `cross_file_analysis.rb` reports three of these as structural clones; the
file itself already shows the fix it wants, because `ToolInitializer` at `:17`
was extracted from the same repetition one method earlier. Give that module an
`execute` driven by the declared `param` names, with a class-level success
formatter for the three variants (`result.value!`, `"Written: …"`, `"Replaced in:
…"`) and a per-class hook for the two that differ — `SearchFiles` at `:80`
renames `path` to `glob` and `context` to `context_lines`, and `DynamicHttp` at
`:224` parses JSON and rescues. Worth roughly forty body lines and, more, one
place to change when the error convention changes.

**Four rule builders in the constitution are one shape written four times.**
`MASTER/lib/core/constitution.rb` pairs a `*_reason` predicate with a `*_rule`
wrapper that is identical every time but for two names: `batch_delete_rule` at
`:219`, `forbidden_file_rule` at `:233`, `scope_creep_rule` at `:251` and
`new_path_rule` at `:382`, with `two_hats_rule` at `:267` the same plus one
guard. `cross_file_analysis.rb` reports them as two structural-clone pairs, and
locating them needed a local probe because that class builds every finding at
line 1 of a virtual path (`cross_file_analysis.rb:315`). A private
`reason_rule(id, verbs:) { |effect, memory| … }` collapses the four to four
blocks. `lib/core` is 769 body lines against a 682 budget, so this is 87 lines
overdue in the one subsystem whose file count is a ratcheted invariant and cannot
absorb the overage by splitting.

**`cohesion.rb`'s constant column is wrong wherever a directory's files reopen
one module, and the census does not say so.** `ruby MASTER/tools/cohesion.rb
MASTER/lib/cli/command_registry` proposes `agent_commands.rb ->
commands/agent.rb   CommandRegistry -> Commands::Agent` and seven more like it.
All ten files in that directory declare `module Master / module CLI / module
CommandRegistry` — one module reopened ten times, verified by listing every
`module`/`class` line in each — so there is no per-file constant to rename and
the proposal would split one module into eight, breaking every call site.
`MASTER/data/autoload.yml` states this explicitly under
`reopens_a_constant_defined_elsewhere`, and names all ten files, with
`rake lint:autoload` proving each entry still necessary. `cohesion.rb` never
reads it. The fix is to teach the tool that file: a family whose members are on
the ignore list gets a merge proposal or nothing, never a rename. By contrast its
`MASTER/tools` proposals are sound on that axis — `autofix_reach.rb` really does
declare `Pub4::AutofixReach`, and `tools/` is under no loader — but the two
families it prints there overlap on `rule_reach.rb`, so they are mutually
exclusive and the output does not say which to take. That is a second thing to
fix in the tool, not in the tree.

**Thirty-one files in `lib/` are below the sprawl threshold, and the merge is not
free.** `FileSprawlRule` (`MASTER/lib/review/scan/rules/meta_rules.rb:284`) run
over `lib/` names 31, of which two are lone-file directories —
`MASTER/lib/cli/propose/candidate_sources.rb` and
`MASTER/lib/review/repo_ecology/co_change_graph.rb` — and the rest are under 25
code lines. The cheapest are the ones whose constant nothing outside names:
`MASTER/lib/security_error.rb` at 3 code lines, `MASTER/lib/ground/antigravity.rb`
at 9, `MASTER/lib/review/review_crew/agents.rb` at 8 (already an autoload ignore,
so a pure require aggregator), `MASTER/lib/fix/constants.rb` at 10. But `lib/` is
under `Zeitwerk::Loader.push_dir(lib, namespace: Master)`
(`MASTER/lib/master.rb:149`), so every other merge moves a constant and needs
either a caller rename or a new `data/autoload.yml` entry that
`rake lint:autoload` will then hold to account. Do these one at a time with the
constant rename in the same commit; do not sweep them.

**`loc_budget` has ten of sixteen subjects over budget and is not in
`measure`.** `bin/pub4 measure` reports one row off, `spine.lib_body_ceiling`,
and that is true of the ratchet register. `rake loc_budget` is a separate gate
and reports `law 1613/852`, `lib/pub4 692/470`, `lib/review 10282/9765`,
`lib/voice 3395/3181`, `lib/ground 6086/5899`, `lib/core 769/682`, `lib/boot
276/227`, `lib/trace 2037/1999`, `lib/cli 6086/6080` and `lib/fix 2646/2643`
over. Recounted independently with `CodeMetrics.body_lines_in`, every figure
agrees — including the `6086` that `lib/cli` and `lib/ground` share, which is a
coincidence and not a bug. Separately, the sixteen `loc_body_budgets` keys in
`MASTER/data/limits.yml` cover 37398 of `lib/`'s 38110 body lines: the seven files
at `lib/*.rb` are in no budget at all, the largest being `lib/builder.rb` at 215,
`lib/master.rb` at 136, `lib/pressure_engine.rb` at 115 and `lib/unwrap_error.rb`
at 103. Add a `lib` root key or fold those files into subsystems; an unbudgeted
712 lines is where growth goes to hide.

**Declaration order in `lib/` is already right, and the residual is constants,
not methods.** A Prism walk over all 428 files, tracking visibility per
class/module/singleton scope, finds **zero** scopes where any def precedes the
first public non-`initialize` def. The known-negative was
`MASTER/lib/cli/pipeline/through.rb`, whose scope dump reads constants, `Result`,
`initialize`, constants, `call`, `private`, helpers — the convention exactly. A
second probe counted backward call edges (a callee declared above its only
caller) and found 276 across 155 files, but hand-reading the top of that list
killed most of them: `MASTER/lib/cli/session/command_handlers.rb:70` "calls"
`run_rebuild` only inside a `%w[]` list at `:77`, and
`MASTER/lib/fix/diff_stager.rb:176` "calls" `apply` only in a comment at `:178`.
Two survive reading and are worth doing.

`MASTER/lib/pub4/gate_chain.rb` is the clearest. It is `module_function` at `:52`
with no `private` marker anywhere, its sole entry point is `run` at `:224`, and
its only caller is `MASTER/bin/pub4:74`. A reader of the repo's most-used command
meets twenty helpers — `stages` at `:61`, `council`, `act_on`, `picks_in`,
`gate`, `rails_gates`, `suites`, `sprawl`, `capture`, `dirty`, `verdict`,
`classify` — before the six-line method that calls them. Move `run`, `explain`
and `report` up under `module_function` and mark the rest
`private_class_method`. Second, `MASTER/lib/fix/fix_loop/background_runner.rb:10`
puts the 18-line thread body `run_forever` above `start_background!` at `:31`,
its only caller; swap them, or make `run_forever` private.

The measurable residual is constants: 153 constants in `lib/` have exactly one
use 80 or more lines below their declaration. The worst are
`MASTER/lib/voice/speech.rb:27-28` (`WORKER_TIMEOUT_PER_CHAR` and
`WORKER_TIMEOUT_MAX`, used only at `:611`),
`MASTER/lib/voice/personality_prompt_builder.rb:20` (`CORE_SECTIONS`, used only
at `:585`), and `MASTER/lib/review/llm_dispatcher.rb:15`, `:18` and `:20`
(`COST_PER_TOKEN`, `CACHE_WINDOW`, `MS_PER_SECOND`, used only at `:370`, `:365`
and `:375`). Move each next to its one reader. This is cosmetic and safe, and it
is what the convention means by constants used only deep inside going last.

**`TRAILING_COMMAS` and `DOUBLE_QUOTES_RUBY` are the same kind of broken as
`FILE_LAYOUT`, at 264 and 233 findings.** `TRAILING_COMMAS`
(`MASTER/lib/review/scan/rules/ruby_rules.rb:228`) matches any line that is only
a double-quoted string, in or out of a collection. Reproducing the rule body over
`lib/` gives 273 hits, of which 34 sit on the last line of a `# pub4 backlog

The single backlog for the whole repo. One file, at the root, replacing the
per-tree lists that used to drift out of sight of one another: `MASTER/DEBT.md`,
`RAILS/TODO.md`, `RAILS/BLOCKERS.md`, and the `OPENBSD/data/debt.yml` register.

Authority order is unchanged: `MASTER/data/soul.yml` > `MASTER/data/rules.yml` >
the root `CLAUDE.md` > the per-tree contract. Feature truth is still
`RAILS/apps.yml`; horizon (aspirational, agent: ignore) is still
`RAILS/apps.horizon.yml`. The decision records — `MASTER/DECISIONS.md` and
`OPENBSD/DECISIONS.md` — are rationale, not backlog, and stay where they are.

How to read this file. Each tree has its own top-level section, and everything
in it is open. **A record is deleted when it closes** — `git log` holds the
history, and a backlog that keeps every item it ever had teaches the reader to
skim. What survives a close is the false positive worth not re-discovering:
those live under "Debt — resolved records" and are guards, not history.

One habit this repo learned the hard way, and it governs every finding below:
**a finding is a hypothesis; re-measure before working from one.** Naive
pattern-matching over this tree produces mostly false positives, and several of
the entries here were themselves stale when written. Verify the instrument
before the finding.

An item leaves this file when a check proves it, not when it stops being
mentioned.

**Forward work is the last section of this file**, merged from `WISHLIST.md` on
2026-09-06.
---

-continued string
— `MASTER/lib/boot/runtime.rb:158` is one — where adding the comma the message
asks for is a SyntaxError. It declares no autofix, so this is noise rather than a
hazard, but a rule whose advice would break the file cannot be gated on.
`DOUBLE_QUOTES_RUBY` (`MASTER/lib/review/scan/rules/cosmetic_rules.rb:125`) gives
268 hits of which 148 are single quotes nested inside a `#{}` interpolation of a
double-quoted string, where double quotes are impossible:
`MASTER/lib/builder.rb:130` and
`MASTER/lib/cli/command_registry/agent_commands.rb:48` are the pattern. Both need
the same treatment as `FILE_LAYOUT` — fix the detector, then take the id off
`RULE_RETUNE_IDS` — and both should be fixed in the same sitting, since the three
together are 730 of the 2195 findings in the retune bucket.

**The biggest subjects in `lib/`, and whether each absorbs.** Ranked by
`CodeMetrics.body_lines`: `MASTER/lib/review/scan/rules/surface_rules.rb` 518,
`structural_rules.rb` 473, `MASTER/lib/voice/speech.rb` 471,
`MASTER/lib/voice/personality_prompt_builder.rb` 386,
`MASTER/lib/cli/command_registry/work_commands.rb` 367,
`MASTER/lib/voice/expression.rb` 306, `MASTER/lib/review/repo_ecology.rb` 298,
`MASTER/lib/voice/engines.rb` 296, `MASTER/lib/review/llm_dispatcher.rb` 296,
`MASTER/lib/review/scan/self_test.rb` 294. The four rules files are registries of
`RuleDSL.rule` calls and already carry `SMALL_FILES` findings; splitting them
moves lines rather than removing them, so they pay nothing toward the ceiling and
should be left alone until someone wants them split for reading.
`work_commands.rb` is the one that absorbs: 83 of its 367 body lines are the
unrouted `dispatch_*` methods and their stranded helpers above. `speech.rb` and
`expression.rb` each shed a little to the dead-method list (9 lines in
`expression.rb`) and a little more to the late-constant move. By directory, counting only the files directly in each, `lib/ground` is the largest subject at 4387 body lines over 64 files, then `lib/io` at 3450 over 46 and `lib/review/scan/rules` at 3239 over 16.

**`/help` documents ten of the thirty-nine registered commands.** `HELP_TOPICS`
at `MASTER/lib/cli/command_registry/help.rb:8` holds `through status undo commit
model pair doctor help clear why`. Enumerating the string keys of every
`command(`/`Command.new` table in `lib/cli/command_registry{,/*}.rb` gives 39,
so `help_text` at `:67` answers "help: unknown command /dilla" for a command that
works, and `Session#unknown_command`
(`MASTER/lib/cli/session/command_handlers.rb:17`) prints that answer. The
twenty-nine undocumented are `brgen btw capture context diag diff dilla domain
dreams fold memory music orders photograph plan postpro propose rebuild reload
repligen rollback rtk security-audit shell snapshot soul tools tree verify` —
`orders` and `soul` among them only because `control_commands` never merges. Note
that `command_registry.rb:33` calls this a "closed public surface", so the
divergence may be deliberate; if it is, the wrong half is `help_text`'s wording,
not the table.

**The remaining named findings from `rake constitution`, already located by the
scanner.** `ABC_SIZE` fires three times over its ratchet of 40:
`MASTER/lib/voice/emotion.rb:20` `#analyze` at 74.7,
`MASTER/lib/cli/session/command_ops.rb:264` `#run_critique` at 42.2, and
`MASTER/lib/ground/phase_gates.rb:103` `#automatic_gate_met?` at 41.4. The first
is the only one worth a sitting. `FILE_VAGUE_NAME` has one finding,
`MASTER/lib/cli/routing/provider_quarantine_manager.rb:1` — "manager" is a
category, and but it is not one of the three the sprawl census counts. Those are `MASTER/lib/boot/data.rb`, `MASTER/lib/ground/orders/base.rb` and `MASTER/lib/io/base.rb` (`ruby MASTER/tools/sprawl_census.rb --list`), so `FILE_VAGUE_NAME` and `sprawl.vague_names` measure different things and neither number is the other. `NO_PUTS` fires
eleven times, all in `MASTER/lib/pub4/gate_chain.rb` (`:234`, `:242`, `:247` and
on), which is a command-line reporter and arguably the rule's exemption rather
than its subject; check the rule's statement before acting.

#### Not worth chasing

Measured, and rejected, so the next reader does not spend a day on it.

`code_reach` is at 0 of 0 and correct: no file in `lib/` is unreached. The
file-level question is closed; the method-level one above is the live version of
it, and re-running `tools/code_reach.rb` answers nothing new.

There are no oversized methods. The largest body in `lib/` is 26 code lines
(`parse_through_flags`, `MASTER/lib/cli/command_registry/work_commands_extra.rb:60`),
the next is 20, and the `DENSITY` limit is 20. `SMALL_FUNCTIONS`-style sweeps have
nothing left to find here; the high `ABC_SIZE` rows above are branch density in
short methods, not length.

`MAGIC_NUMBER_SPREAD` from `cross_file_analysis.rb` reports fourteen literals
recurring across files — `100` in 24 files, `200` in 20, `120` in 16. These are
limits, widths and percentages that mean different things in each file; the rule's
own comment records that an earlier version of it fired on the named constants it
was recommending. Naming them centrally would couple unrelated subsystems.
Likewise its `SPRAWL` rows (`cost` in 13 files, `cache` in 19, `provider` in 17)
and `SCATTERED_CONFIG` rows (`ENV PATH` in 9 files) are namespaces, not sprawl.

`COPY_PASTE_BLOCK` finds one group in all of `lib/`, and the `DRY`
structural-clone rule finds three cross-file groups, of which one —
`MASTER/lib/review/repo_ecology.rb:231` `#grade_for` and
`MASTER/lib/trace/context_pressure.rb:21` `#band_for` — is two banding functions
over different domains that happen to share a `case` shape. Extracting a shared
band helper for two callers buys nothing.

`lint:dedup` reports two known cross-file duplicates and zero new, `dup_census`
is at 30 of 30, and `lint:reader_singularity`, `lint:doc_citations`,
`lint:instruments`, `lint:constant_collisions`, `lint:capability`,
`lint:scan_coverage`, `lint:autoload`, `lint:frozen`, `lint:rule_reach`,
`lint:models`, `lint:cohesion`, `lint:principle_trace`, `core_smoke` and
`security_sweep` are all green when run individually. Do not re-audit them; audit
why they were unreachable instead.

`rake studio` fails locally because `ruby-vips` and `libvips` are not installed
on this Mac, so `STUDIO/postpro/postpro.rb` does not boot. That is an environment
condition, not a MASTER finding, and it is the fourth prerequisite of `rake
audit` — so clearing the `selftest` blocker above will hand the audit straight to
this one on any machine without vips. Worth knowing before someone reads it as a
regression.

#### Least certain of the above

The `/help` divergence is the one most likely to be intended; the "closed public
surface" comment argues both ways.

The 649-line dead-method figure is the aggregate I trust least at the margins.
The two largest clusters and five individual entries were hand-verified and the
instrument's self-check distinguishes `for_council` from `for_council_persona`
correctly, but the long tail of one-line methods has not been read one by one,
and a name reached through a `send` form my prefix harvest missed would be a
false positive. Verify each entry against its own call graph before deleting it,
not the total.

`NO_PUTS` in `gate_chain.rb` may be the rule's exemption rather than a finding; I
did not read the rule's statement closely enough to say.

### Rule and AST-detector backlog

Deterministic detectors in `MASTER/lib/review/scan/rules/`, following the
`MiddleManRule` / `NOISE_NAME` pattern. Six were listed and four are built:
`BOOLEAN_TRAP`, `DATA_CLUMPS`, `TYPE_IN_NAME` and `NUMBERED_NAME`. Their records
are deleted rather than kept, because each rule's own comment carries the
measurement that earned its exemptions and `MASTER/test/test_smell_detectors.rb`
holds each one twice — a source it must flag and a source it must not.
`violation_priors["DATA_CLUMPS"]` and `PRIMITIVE_OBSESSION after: [DATA_CLUMPS]`
both resolve to the third of them, which is why the plural spelling was chosen.

**Already exist — do not re-list these as todo:** `LONG_PARAMETER_LIST`,
`PRIMITIVE_OBSESSION`, `FEATURE_ENVY`, `COUPLER_SMELLS`, `LAZY_CLASS`,
`SPECULATIVE_GENERALITY`, `NO_SHOTGUN_SURGERY`, `TEMPORAL_COUPLING`.

The other two were drafted, run over the tree, and are blocked on the cross-file
index below. Neither is a guess.

- **`LAYER_CAKE`** — a chain of sibling methods each of which only forwards. At
  three links, the honest reading, this tree has **none**, and a rule that fires
  on nothing joins `rule_audit.silent`, which is at its ceiling. At two links it
  finds 9, and reading them says why that threshold is wrong: three are
  `rescue_handlers.rb` naming one exception each before forwarding to
  `render_http_error`, the shape `rescue_from` requires, and the rest (`ok? ->
  ok`, `unwrap -> value!`) are aliases. A two-link forward is an alias, not a
  cake. A real layer cake spans files — controller to service to repository —
  and no per-file rule can see it.
- **`DEAD_ABSTRACTION`** — the class half is precise and almost empty: 4 classes
  declare a body that is only `raise NotImplementedError`, and exactly **1** has
  no implementer. The module half is a false-positive machine and must not ship
  as written: 367 of 419 modules that define methods are included at most once,
  because nearly every module here is a `module_function` namespace rather than
  a mixin, so the census measures Zeitwerk's file-to-constant mapping and calls
  it a dead abstraction. One finding does not pay for a rule.

  That one finding is open and wants a hand rather than a detector.
  `Master::Io::Gateway::Adapter` declares `render`, raises, and nothing in the
  repo includes it — while `Gateway#render_to_adapter` duck-types straight past
  it on `adapter.respond_to?(:render)`. The contract is a comment with a raise
  in it.

#### Larger AST work — multi-session projects

These are not single detectors; each is its own sitting, with an owner and a
design, not a sweep.

- **A cross-file AST / symbol index.** Every rule that needs to know "who
  implements this" or "who calls this" (`DEAD_ABSTRACTION`, `LAYER_CAKE`,
  feature-envy across files) currently cannot see past the file it is in.
- **An incremental scan cache keyed on file SHA.** Re-parse only what changed;
  a full scan re-walks the whole tree every run.
- **tree-sitter for real JS / SCSS ASTs.** The JS and SCSS rules are lexical
  because there is no real parse tree for those languages here; a real AST
  retires whole classes of false positive.
- **Prose / CSS / audio "AST" rules.** The same deterministic-detector idea
  applied to non-Ruby artifacts — documents, stylesheets, and dilla's render
  graph — each of which currently has only lexical or no checks.
- **A clone → extract-method autofix.** `DUPLICATE_CODE` detects; nothing
  extracts. The autofix that turns a detected clone into a shared method.

### Debt — resolved records

Closed records are deleted when they close, and `git log` holds them. A finding
that is fixed is not a backlog item, and a file that keeps every one it ever had
teaches the reader to skim. What stays here is forward work and the false
positives worth not re-discovering — those are guards, not history.

### Still open after this session

- **`data/rules.yml` is under its budget as of 2026-09-04** — 3690 against a
  ceiling ratcheted from 3944 in `72a8cfae8`, which removed 254 body lines of
  declaration no reader consults. The record below is kept for its method, which
  is the part that transfers: a field whose removal moves no measurement was
  measuring nothing, and the proof is three censuses reading identically across
  the change. The `pwa:` question it ends on is answered — the block stayed and
  the room was found elsewhere.

  What it said at the time: **`data/rules.yml` is 35 body lines over its budget**, and the 35 have a name.
  102 lines came out: a row whose id `law/` owns is rejected by
  `YamlDeclarativeRule` before any detector field is read, so the `languages`,
  `path_match`, `requires_absent` and `whole_file` those rows carried scoped a
  detector that is not there — the scope is stated once more, correctly, in the
  law file. Removal only, and proved by the three censuses that read this file
  reporting identical numbers after it: a field whose removal moves no
  measurement was measuring nothing.

  That leaves 3714 against 3679, and the remainder is the 37-line `pwa:` block
  `3f5447c17` added to `design_rules` an hour earlier. So the file was at its
  ceiling once the dead declarations went, and what is over is one deliberate
  addition rather than accumulated fat. `limits.yml` says "Measured once at the
  rename. Down only from here", so this is an owner's call between shrinking the
  `pwa:` block and moving a ceiling that predates a consolidation it never
  measured — not something to settle by finding 35 more lines to cut.

  Two more duplications sit in the same rows and were left: `fix` and `source`
  repeat what the law file declares, but `/why <RULE_ID>` reads both out of
  `rules.yml` rather than out of `law/`. Converging `WhyExplainer` onto the law
  is the move that makes those safe to remove; doing it in the other order
  empties a live surface.
- **Four ratchets are over, re-measured 2026-09-05 after `lib/autonomy` went**:
  `spine.lib_body_ceiling` 38253/37464, `growth.master` 1050/1047,
  `growth.rails` 2371/2358 and `growth.studio` 155/138. Every one that is left
  counts size, which is the shape worth knowing: what remains is folding, and
  folding is a sitting rather than a fix.

  `growth.master` is three files over and one of those three is the test that
  came with the hooks wiring, named rather than absorbed. A constant-name census
  over `lib/` offered three files to fold and all three were wrong:
  `HashDigCompat` is required by path and called by method name,
  `RubyRuleSupport` is used inside its own multi-class file, and `Trace::Hooks`
  was three-quarters wired. Two files is exactly the distance at which a census
  stops being a measurement and starts being a shopping list.

  **Extraction cannot pay `spine.lib_body_ceiling`, and this file said it could.**
  The counter is non-blank non-comment lines across `lib/**/*.rb` minus the
  Zeitwerk wrappers, so splitting `speech.rb` into two files under `lib/voice`
  moves the lines and adds a `def` and an `end` — the number goes up. Only three
  things move it: deleting code nothing reaches, collapsing a real duplicate, or
  a sponsored raise, which `spine.yml` allows "in a commit that names what the
  lines buy" and caps with `consecutive_raises_allowed`.

  What de-duplication is actually worth here was measured rather than guessed.
  `CrossFileAnalysis` over `lib/` names six DRY pairs; three are collapsed (the
  finding-shape accessor written four times, a dead `mtimes`/`quiescent?` pair,
  and `load_data` written twice) for **31 lines against an overage of 1,162**.
  The other three are judgement: `read_js` is byte-identical in two `lib/rails`
  files and the only home is a new mixin, which costs `growth.master` a file to
  save four lines; `grade_for`/`band_for` and `markdown_files`/`files` match on
  shape and not on meaning. `CROSS_FILE_DRY`'s 22-file `File.read` and the
  `MAGIC_NUMBER_SPREAD` rows save nothing at all — a shared reader is still one
  call per site.

  So the arithmetic is: this is not a de-duplication problem. The only
  line-counts of the right order are `lib/autonomy` at 400 (the wire-or-delete
  decision above) and `lib/review` at 622 over its own budget, and neither is a
  sitting somebody finishes in an afternoon.

  Six of the ten rows that were over closed the same day. `self_findings` is at
  151 from 165 — two findings were in the scanner itself, and the other twelve
  were a frozen-literal comment that sat under a `require` and so declared
  nothing, six dilla files that had none, and a broadcast script that says in a
  marker why strict mode would end the broadcast. `data_reach` is at 35 because
  `doc_baselines.yml#doc_paths` gained the reader it never had. The three RAILS
  rows — `model_contract.uninferrable_inverse` 54, `model_contract.no_validations`
  9 and `destructive_action.unconfirmed_destroy` 29 — are 0 against floors of 0.

  `spine.lib_body_ceiling` fell 636 net: 695 back from the antigravity collapse,
  59 spent on rule fixtures. `growth.master` fell six files. Read the live figures
  from `MASTER/bin/pub4 measure`; the list here has been three, then five, then
  six on three consecutive readings, so its value is the shape and not the
  numbers. `data_reach` fell 37 to 36 when `three_mirror_redundancy` gained a
  reader, and the remaining 36 were read once: most are the false-positive
  classes this file's own 2026-08-12 entry names. `topologies.yml`'s eight and
  `runtime.yml`'s five are served whole through `RuntimeCatalog` and
  `/runtime/topologies`, and the browser picks the sections by name;
  `personas.yml` and `models.yml`'s ollama rows are registry entries selected by
  a config value. `rules.yml#schema_metadata` is the same shape read once more
  on 2026-09-05 and is a third class again: nothing loads the key, and the block
  under it documents two fields — `reversibility` and `blast_radius` — that
  `semantic_rules.rb` and `meta_rules.rb` do pass to `Finding.build`. It is a
  schema note, not config, and deleting it would delete the only statement of
  what those two fields may hold. Do not delete from this list without finding the reader —
  that entry says why a stricter version of the tool is not buildable, and this
  is what its error looks like from the inside.
### `/scan`'s autofix corrupts code — opened 2026-08-31, do not run it on a tree

Trialled on `RAILS/gates` alone before turning it loose on RAILS's 2,326 files.
It wrote three files and **two of the three are damage**:

    RAILS/gates/support/design_metrics.rb
    -  brgen/engines/*/app/assets/stylesheets/*.scss
    +  brgen/engines/*/app/assets/stylesheets/*.scss,

`TRAILING_COMMAS` fired inside a `%w[]` array, where a comma is a literal
character and not a separator. The glob now ends in a comma and matches nothing,
so `light_only_vertical_keys` would report a clean tree having read no file.

    RAILS/gates/support/geometry_probe/walk.js
    -  return seen[sel] === 1 ? sel : sel + '[' + seen[sel] + ']';
    +  return seen[sel] === 1 ? sel : `${sel}[${seen}`[sel] + ']';

The template-literal rewrite mangled a three-term concatenation: it closes the
template early, then indexes the resulting string by `sel`. Every duplicate
selector key becomes `"undefined]"`. **`node --check` passes** — a silent
semantic corruption that survives a syntax check is the worst shape this has,
and it is the shape a tree-wide unattended run would have written everywhere.

Both reverted. The third change, a blank line in `webgl_surfaces.rb`, was
harmless. One in three.

The `%w[]` trailing-comma rewrite is pinned: `percent_word_array_close?` skips
`%w %W %i %I`, and `test_trailing_commas_skip_percent_word_arrays` holds both
directions. The template-literal call-site corruption was already closed
(`convert_string_concat` declines a chain followed by `(`). Other autofix
transforms can still mangle; `--no-autofix` remains the safe default on an
unattended tree until each transform has that shape of test.

Pipe mode used to ignore ARGV, so `bin/cli /scan RAILS` with no TTY printed
nothing and exited 0. It honors the argument now, then stdin. Paths still
resolve after `bin/master` chdirs into MASTER, so a sibling tree is `../RAILS`
or the `rails` alias.

### Tag Legend

- **agent-ignore** — do not chase during narrow patches (constitution scan noise, horizon features).
- **operator-priority** — humans should fix before declaring deploy healthy.

### Spine Ceiling

**Not open.** The number, its full raise/ratchet log and the reasoning behind every
move live in `data/spine.yml`, which is the file `rake lint:spine` reads. This
section held a copy and the copy drifted — it read "38,294, allowance 1 of 2" while
`spine.yml` had ratcheted to 38,285 and cleared the log, which is the two-source
failure this register warns about elsewhere in its own words.

Worth knowing without becoming a second copy: the ceiling has ended each of the
last two days exactly at `lib/`, no headroom, so the next line added breaks the
ratchet and the paragraph below about paying a breach out of `lib/` is not
hypothetical. Read the current number from the task, never from here — the
figure this paragraph used to quote was stale within a day, twice.

What belongs here is the rule the ratchet taught, because it is not in the
mechanism:

**Ratchet once, at the end of a session, on a settled tree.** An intermediate
ratchet has already locked in a state that was not clean and blocked the work that
would have made it so (2026-08-03). And on 2026-08-12 a ratchet taken while three
other sessions had uncommitted `lib/` edits recorded a low that was not the
ratcheting session's to hold — in a shared checkout the honest moment is after the
tree stops moving, not after your own part of it does.

**A breach is paid out of `lib/`, not out of this file.** Three of the four breaches
so far were closed by deleting code nothing referenced; the fourth was a raise, and
it needed the operator to sponsor it because the orphan account was empty. That
sequence is the mechanism working. `rake lint:spine RATCHET=1` clears the raise log
when `lib/` genuinely falls, which is what makes the allowance a budget and not a
countdown.

**Measure in a clean worktree, never in the shared checkout.** On 2026-08-14 the
same change read `39251/39258` here and `39298/39295` at `origin/main` — 47 lines
of skew, entirely other sessions' uncommitted `lib/` edits. The shared-tree number
is not wrong about that tree; it is a reading of a tree nobody is going to commit.
`git worktree add --detach <path> origin/main` and run the task there.

#### Three raises, no ratchet, in one day — 2026-08-14

Not a complaint about any of them. Each was argued in `spine.yml` and each bought
something: +3 for per-visitor chat conversations, +44 and +10 for design-gate rules
that could not pass on correct markup, retiring 381 and then 434 findings. Net +57,
zero reductions, and `lib/` closed the day at exactly its ceiling again.

What that costs is legibility rather than lines. The header of `spine.yml` already
says it — "a ceiling that rises whenever a day's work pushes against it measures
nothing" — and the 2026-08-01 note already asked that the next raise not be granted
on "it was only a bug fix". A note left that same morning asking the following
session to ratchet rather than raise was read and raised past, twice, by sessions
doing legitimate work. So the honest reading is not that anyone misbehaved: it is
that the mechanism currently has no move available except assent.

**The orphan account is empty, verified rather than assumed.** Hunted before asking
for the +3: zero dead private methods across `lib/`, zero unreferenced constants,
and the fourteen classes a conservative sweep flagged are all false positives —
scanner rules reached through `RuleDSL`, `RubyRunner` called from `RAILS`.
`RiskClassifier`, the orphan the last audit named, was already deleted. Same
conclusion as 2026-08-12.

So "make `lib/` fall back first" no longer names a cleanup anybody can do on the way
past. It needs a decision that some subsystem is worth deleting or absorbing, which
is design work with an owner, not a sweep. Until someone takes that decision, expect
every feature to arrive as a raise, and read a green `lint:spine` as "the ceiling was
moved to meet it" rather than as "the spine held".

#### A 977-line breach, paid down to 634 by collapse — 2026-09-08

`lib/` stood at 38,441 against 37,464. Collapse took 343 of it. The ceiling is
untouched and stays at 37,464: the tree is still above it, and a number written
to meet the measurement is the raise this section refuses.

Four things merged. Forty-two scan rules opened with the same eight-line
constructor — `super()` and five instance variables holding literals, which
`cross_file_analysis` reported as twenty-three identical structures — and now
declare their identity at the class level, the way `RuleDSL` already declares the
rules it generates. Twenty-one files opened their own scaffold two, three or four
times over, `module Master ... end` written again below itself in one file, and
now open it once. Six method families were one move written twice or three times:
undo and redo, the watcher's three metric probes, the undo/rollback/redo reporters
in the session and in the registry, the two git questions the prompt asks, the
three runtime loop guards, and the review crew's two style checks. The remaining
DRY findings over `lib/` are all worth five lines or fewer.

One thing looked collapsible and is not, and one turned out to be the rule.
`propose.rb` and `repo_ecology.rb` repeated their scaffold because
`NO_GOD_CLASS` counted methods per class node, so a second `class X ... end`
block halved the count it saw and merging them turned `rake selfcheck` red.
Both were god classes either way: the rule was reading source layout rather
than the class, it was corrected the next day, and both files are split. And
`PARALLEL_HIERARCHY` reports `FixLoop spans 12 class/module hierarchies`, with
`ModelRouter`, `LLMDispatcher`, `PassRunner`, `AstFixer` and `Builder` behind it.
All twelve are `class FixLoop` reopened by the parts of one class under
`lib/fix/fix_loop/`. The rule already exempts a stem it has seen written as a
qualifier; a class split across files is the same shape and is not exempt yet.

The orphan account reads the same as it did on 2026-08-14. Nothing in `lib/` is
dead, no two files are near-duplicates — line Jaccard peaks at 0.17, on two files
that share a grading helper — and exactly one method body appears twice in the
whole of `lib/`. The remaining 634 is not a sweep; it is the subsystem decision
this section already names.

### Self-Test Debt

**agent-ignore** — triage only when the task explicitly targets scan rules.

`rake selftest` reports **12 findings, re-measured 2026-09-04** — 1 LINEARITY, 2
ABSTRACTION, 9 DENSITY, and 0 for every other law. It was 0 on 2026-08-19, and
six of the twelve are in `lib/ground/antigravity/`, a directory that did not
exist when that measurement was taken. The table and the reasoning are under
"From the 2026-09-04 MASTER audit" below; this section keeps the history of how
the count was driven to 0 the first time, because the method is what transfers.

The 1 of 2026-08-18 — `god class Constitution is 348 lines` — closed the way the
2026-08-12 idiom findings did: the count was the instrument, not the design.
NO_GOD_CLASS's line branch measured raw AST span, charging for rationale
comments — the counter DENSITY and lint:spine each already retired for the
same reason — so Constitution read 348 while holding 250 code lines against
the 300 limit. The branch now counts code lines through CodeMetrics, pinned
in both directions in `test_scan_rule_false_positives.rb`, and all 79 core
tests hold: no split, no exemption, and `rm -rf` stays blocked. The reverted
split (`972894e70`) stays reverted; nobody owes one. The day of
`self_violation` halting every `/through` fix stage ended with the unit
correction, not with anyone deleting the law's own reasoning to appease its
counter. Treat any count here as
true for the commit that carries it and no further: it has been 0, 1, 2, 3, 6 and
7 on different days of the same fortnight, and a "clean since" claim in
`START_HERE.md` was already stale once.

`test/test_heartbeat.rb` passes at the count above — 7 runs, 12 assertions, 0
failures on 2026-09-04. The note here that
`self_test_heartbeat_publishes_clean_scan_metrics` fails *because* the count is
non-zero no longer holds, so the count is not gated by that test and a
non-zero `selftest` is currently visible only to whoever runs the task.

Triage each new finding as: true violation to fix / scanner false positive / rule
exemption needed / rule threshold too strict / known debt to leave alone.

### The fold spine had never been scanned — opened 2026-08-12

**operator-priority** — this is a decision to make, not noise to chase.

`SelfCheck#run` scans `File.join(@root, "lib")`. So does `selftest`. For the
three weeks `core/` existed as a sibling of `lib/`, **every gate MASTER points at
its own source skipped the constitutional fold entirely** — the six files that
judge every effect before it touches the world were the only ones exempt from the
law they enforce. Nothing declared that exemption; it fell out of a path.

Merging the spine into `lib/` on 2026-08-12 subjected it, and it fails:

```
[ABSTRACTION] lib/core/constitution.rb:16  Constitution — 16 public methods (max 10)
[ABSTRACTION] lib/core/memory.rb:10        Memory       — 17 public methods (max 10)
[DENSITY]     lib/core/fold.rb:28          run          — 24 code lines (max 20)
```

`rake selfcheck` independently gains `NO_GOD_CLASS` 2 and `SILENT_RESCUE` 1 from
the same files. Measured twice, because attribution in a shared tree is a guess
otherwise: 19 → 22 on a clean HEAD worktree with only the move applied, and
17 → 20 in the working tree against the "Scanner noise" baseline below. Same +3,
same three files, from two different starting points.

**Two of the three are closed, by option 2 — 2026-08-12.** Nothing was
exempted, no threshold moved, and `core_files` was still 6 at that point.

- **`Constitution` 16 → 4.** Twelve of the sixteen are rule factories that only
  `default_rules` calls, verified against `lib/`, `test/`, `spec/`, `tools/`,
  `bin/` and `web/`. They are `def self.` — and `private` marks a position in the
  instance-method stream that class methods never enter, so the class read as
  fully public however it was arranged. They are now
  `private_class_method`, and `CodeMetrics.public_method_count` honours that
  declaration, pinned by `tools/fixtures/class_methods.rb`. ABSTRACTION was
  measuring the idiom, not the surface.
- **`Fold#run` 24 → 14 code lines.** The admitted half moved to a private
  `apply`. A private method is not a new concept, so `core_files` never came
  into it — the conflict below was real for decomposition into *files*, not for
  decomposition inside one.

`rake selftest` 3 findings → 1. `rake selfcheck` 20 → 19, `NO_GOD_CLASS` 2 → 1.
The +16 code lines this cost are accounted line by line in `data/spine.yml`;
they spent the second and last raise of the allowance.

**`Memory` closed by option 3 — 2026-08-12, operator-sponsored.** Option 2 could
not reach it: only `detect_host_memory_mb` was internal, and every other method
had a caller. That was the count telling the truth rather than measuring an
idiom. `Memory` was **three jobs in one object** — a transcript, an evidence
ledger, and the risk gates — and the Constitution reached straight past the first
to ask the other two.

`lib/core/proof.rb` is the second and third of those: what has been shown, and
what must be shown before `done`. `core_files` 6 → 7, the first raise since the
spine was written, argued in `data/spine.yml`. Memory 16 public methods → 7,
Proof 8, Constitution 4, Fold 2.

Two things were deliberate. Nothing forwards: the Constitution and the CLI reach
`memory.proof.*` directly, because a delegator would have kept the public count
where it was and hidden the seam the count existed to point at. And the +10 code
lines were **absorbed rather than raised for** — the raise allowance was spent,
`spine.yml` says the next line into `lib/` comes out of `lib/`, and a sweep found
no `lib/` file with a declared constant nothing else references. They came out of
the new code instead, leaving `lib/` net 0.

**`rake selftest` 3 findings → 0. `rake selfcheck` 20 → 18.** The fold is clean
under its own law for the first time since it was subjected to it.

What must not happen, and did not: the count being driven to zero by re-exempting
the fold, which would restore the invisible hole and lose the one thing the merge
bought — the fold is measured by the law it applies to everything else.

### Constitution Scan Debt

**agent-ignore** — `rake constitution` is broader than `rake selftest` and still
reports thousands of self-scan findings. Do not chase zero. Track the count down
by removing false positives and fixing high-signal violations.

#### Two copies found by reading the buckets — 2026-08-12

**3,602 findings / 125 actionable → 3,166 / 20**, without fixing a single line of
the code being scanned. Both were duplicate detections, found the way the veto
audit found its 119: by reading the findings instead of the count.

- **`NO_PUTS` 105 → 5.** Its exemption read `/now/cli`, and `lib/now/` was renamed
  to `lib/cli/` in `693d2630d`. The exemption kept pointing at the old address, so
  105 findings appeared in the largest *actionable* bucket — every one in
  `lib/cli/`, 100 of them in `lib/cli/cli/`, all of them decisions the rule's own
  author had already made and the rename silently undid. This is the
  exemption-outliving-its-subject defect inverted: the subject moved out from
  under the exemption, and a gate began firing on exactly what it exempted.
- **`learned_smells` 10 → 8.** `long_line` restated the registered `LONG_LINE` as
  a raw regex: 334 findings, of which **3** landed on a line no other rule
  reports — and all 3 in `lib/io/llm.rb`, which `LONG_LINE` deliberately exempts.
  So 331 duplicates plus a quiet override of an exemption, at `:warning` where the
  real rule says `:info`, with the id as its whole message. `debug_output` carried
  the *same* id as the registered rule, making its findings indistinguishable
  rather than merely doubled; its `autofix: remove_debug_call` names nothing that
  exists anywhere.

The other eight learned smells pass the test the EMPTY_RESCUE deletion used —
`magic_number`, `future_tense`, `duplicate_code`, `sycophancy` and `todo_comment`
are the only implementation of what they detect. Two entries went, not the layer.

Both pinned in `test/test_scan_rule_false_positives.rb`, and generalised: no
learned smell may share an id with a registered rule, and no two rules may report
the same long line.

### Scanner noise

**`rake selfcheck` is clean, and it gates one severity more than it used to.**
`QUICK_SEVERITIES` held `error` and `critical`, so a `:veto` — the severity
`WriteGuard::BLOCKING` refuses a write for, and the one `rules.yml#veto_patterns`
calls an unconditional merge blocker — passed the fast gate unseen. Four stood
under `lib/` and `law/` while the banner read clean. The set is
`veto/critical/error` now, the same three WriteGuard holds, and the banner prints
the constant rather than a sentence free to drift from it.

All four were the scanner reading its own worked examples. `VetoPatternRule` was
the only rule in the population with no exemption of any kind, while every
registered twin of those patterns — `SQL_INJECTION`, `TODO_FIXME`,
`NO_TODO_IN_VIEWS` — skips `/review/scan/rules/` by name and says why. It blanks
`fires:` and `does_not_fire:` lines in that directory now, which is
`Law.conduct`'s argument for `law/` in the registry's own spelling. The directory
is not skipped, so a real secret or an interpolated shell string in a rule file
still vetoes.

Three more of the same shape, each a rule reading prose or a pattern as conduct:

- **`RESCUE_EXCEPTION`** fired on the paragraph in `lexical_rules.rb` explaining
  which rescue shape each rule owns. It blanks comment lines now, and does not
  skip the directory: a real `rescue Exception` in a scanner rule is worth
  catching, which is why `SILENT_RESCUE` beside it carries no path exemption.
- **`NO_ASCII_LINE_ART`** fired on its own `fires:` divider. Its subject is
  decoration inside comments, so it cannot blank them; the line carries the
  `scan: intentional` marker instead, as `RESCUE_EXCEPTION`'s positive example
  already did.
- **`TODO_FIXME`** read two detectors as markers — `personal_workspace` greps a
  MEMORY.md for what an operator left, `history_valuables` lists the markers
  among the patterns worth recovering from git. Both spell the words inside a
  regex literal, where they are tokens in a pattern. `SourceMasking` blanks
  regex literals for it, as `COMPLETION_THEATER` learned to spare `etc` inside
  an alternation.

Two cross-file rules were grading layout rather than code:

- **`PARALLEL_HIERARCHY` was wrong on every finding it had.** Zeitwerk lays a
  class split across files out as `fix_loop.rb` beside `fix_loop/`, and the rule
  read each such split as parallel hierarchies — `FixLoop` over 12 files,
  `ModelRouter` 6, `LLMDispatcher`, `PassRunner` and `AstFixer` 4 each, `Builder`
  3. The namespace guard it already carried cannot see them, because a part
  reopens `class FixLoop` and never writes `FixLoop::`. A stem whose files all
  sit at or under its own slug is exempt now; a stem shared by unrelated trees
  still fires. 6 → 0.
- **`NO_GOD_CLASS` counted per class node, not per class**, so a class written as
  a scaffold and reopened was measured twice at half its size. It graded source
  layout, and backwards: the more scattered the file, the more lenient the
  verdict, and merging two blocks made a class breach without a method being
  added. It sums the blocks by the class's full lexical name now — two `Same`
  under two modules stay two classes.

Two law findings landed on real MASTER code, one a rule and one a line:

- **`NEVER_BATCH_DELETE`** flagged the TTS controller test's teardown. Its other
  three branches all ask whether the set of files is known at read time — a
  glob, a bare `$var` and a `Dir[]` are unbounded by construction — and the
  `.each { rm }` branch asked only whether there was a loop, so a receiver
  spelled out in full read as the same hazard. A `%w[]` or `[...]` receiver is
  spared; `Dir[...]`, `Array(old)` and `snapshots[0...-KEEP].to_a` still fire,
  because the bracket there follows a word character and is an index.
- **`FAIL_VISIBLY`** flagged `master_container.rb`'s `rescue Exception`, which
  re-raises `SystemExit` and `SignalException` on the next line and logs the
  rest. A line-scoped law sees neither. The line carries `scan: intentional`
  beside the `rubocop:disable` naming the same decision — for a linter
  `.rubocop.yml` excludes `web/**` from, so that half was already inert.

`self_findings.law` fell 292 → 290. Every narrowing is pinned both directions in
`test_scan_rule_false_positives.rb` and `test_scan_rule_contracts.rb`: the false
positive is gone and the real violation still fires.

#### `rake selfcheck` was red on two real god classes — closed 2026-09-08

Correcting `NO_GOD_CLASS` surfaced two classes the old count could not see, and
they were true: `Master::CLI::Propose` measured **447 code lines** across two
blocks in `lib/cli/propose.rb`, and `Master::Review::RepoEcology` **354** across
three in `lib/review/repo_ecology.rb`, against a limit of 300. Neither block
breached alone, which is why the rule passed them for as long as it judged
blocks rather than classes.

That mattered beyond the count. `rake selfcheck` is a binary gate, and
`SelfCheck#gate!` publishes `self_violation`, which `FixLoop#halt!` reacts to —
so background autofix was halted for every session while it stood.

**Both seams were already drawn, as nested modules the host included.**
`CandidateSources` is the fourteen `from_*` sources a proposal can come from;
`CoChangeGraph` is the pair counting behind the ecology map. Each now sits at
the path Zeitwerk maps its constant to — `lib/cli/propose/candidate_sources.rb`
and `lib/review/repo_ecology/co_change_graph.rb` — and the empty scaffold each
host was left holding is gone. Propose falls to 225 code lines, RepoEcology to
312. `growth.master` 1053 → 1055, both named in `spine.yml`;
`self_findings.registry` records 54 again rather than the 56 the findings
bought, and `sprawl.lone_dirs` and `cohesion_census` are unmoved.

**The rule was right and the classes were large, which is the whole reading.**
The collapse pass a day earlier had recorded these same two files as "looked
collapsible and are not", because merging their repeated scaffolds turned
`selfcheck` red. That was the rule reading source layout rather than the class.
Fixing the rule made the scaffold pointless and the split obvious, in that
order.

**What is left is not noise.** `SILENT_RESCUE` 26 and `NO_GOD_CLASS` 28, all 54
outside MASTER and already itemised under `self_findings.registry` below.
`GUARD_EXPENSIVE_OPS` finds nothing anywhere and is right to: narrowed
2026-08-21 to a delete with a bare constant receiver, and the tree has none. It
still fires on `Session.delete_all` and `drop_table`.

#### Two of the three false positives are closed — 2026-09-08

The section this replaces said each fix needed a number in `data/rules.yml`,
which is `paths.immutable`, and waited on whoever may move it. Two of the three
did not need that file at all, and the third needed it in the way the file
itself documents.

**`UNBOUNDED_RETRY` is scoped to Ruby.** `languages` is a `law/` DSL verb, used
sixty times across the domain laws, so nothing about this was blocked. `retry`
is a Ruby keyword and nothing else, and the law's one standing finding was the
word in a sentence on `406-unsupported-browser.html` — English prose in HTML, at
`:error`. Every narrowing the law already carried is about telling the keyword
from the word; declaring the language does the same job at the file rather than
at the line.

**`rule_audit` reads `law/` the way the runtime does.** A law file necessarily
contains the pattern it forbids, and `FileProcessor#law_conducted` neutralizes
those lines at the one read site so a law does not judge itself. The audit read
them raw, so a law matching nothing in the tree except its own `detect` line
counted as having found a subject. **24 raw against 38 conducted** — fourteen
rules were silent and reported as live, `FAIL_VISIBLY`, `GUARD_EXPENSIVE_OPS`,
`NULL_BLINDNESS` and `SAFE_NAVIGATION` among them, each reading itself.

`rule_audit.silent` is 39: the fourteen plus `UNBOUNDED_RETRY`. The ceiling did
move in `data/rules.yml`, and that is not a breach of `paths.immutable` — the
clause forbids an *effect* writing the constitution, and this number's own
comment history is a record of authored moves, 19 to 24, 25 to 23, 23 to 24,
each naming what moved. This one names all fifteen.

**The heredoc cost a restore.** Writing that note with a squiggly heredoc
stripped the four-space indent off every line, which turned the ceiling into a
top-level key and made `rules.yml` unparseable — `data_reach`, `self_findings`
and all three `rule_audit` rows read *unreadable* in the same breath.
`git checkout --` put it back exactly and the note went in through an
exact-match edit instead. **In a data file the indentation is the syntax**, and
a squiggly heredoc exists to remove it. This is the seventh time it has cost
something in this tree.

**The third is still open.** Two learned smells fail the uniqueness test that
deleted five others: `future_tense` reads 12 where `SIMULATION` reads 3, and all
nine extra are lines `SIMULATION` deliberately spares, five of them inside the
directory it exempts. `frozen_string` reads 2, both of them a percent-literal
string in a file that already declares `frozen_string_literal: true`, where such
a literal is frozen anyway. Both want deleting rather than narrowing, which is a
decision about the learned-smell mechanism rather than about two detectors.

#### The law had 72 registry twins, and they drifted — opened 2026-08-19, closed 2026-08-21

Closed in three sittings. The first eleven retired with the reverse-doctrine
discovery: the richer implementation wins, whichever side it lives on. The
final 42 (cdc7f7141): 28 registry blocks retired into their laws with the
narrowing ported and fixture-pinned, 14 laws retired into their richer
registry twins (Prism, tag_source, shebang awareness, indent walking), and
KEYWORD_ARGS folded into FEW_ARGUMENTS on both sides. The census also caught
the constitution's own inert config: law/rails.rb declared `languages
%i[rails]`, which FILE_LANGUAGE_MAP has never produced — four laws that had
never matched a file. Twin census reads zero; the twin-census check is the
regression guard.


#### The data layer's duplicate census — opened 2026-08-19, line-level collapses done 2026-08-21

`rake lint:dedup` (ContentDedupScan's first-ever reader) holds the line-level
census. The three recorded collapses landed 2026-08-21, each with its reader
traced first:

- **soul `absolute.anti_simulation`** — the voice.yml shadow (already one
  word drifted) is deleted, the fallback arm removed, and
  test_rules pins that the constitution accessor still carries the list.
- **The openrouter default** — providers.yml is the one source;
  `Master.openrouter_default` / `Master.free_primary_model` (boot/runtime.rb)
  are readers through the sanctioned loaders, the soul negotiable copy is
  deleted, and the reader-singularity ratchet is what forced the accessor
  shape.
- **Replicate env vars** — models.yml `media_providers` had **no reader at
  all**: the slugs live in voice/engines.rb and repligen, the env in
  providers.yml. The whole block was a declaration claiming a routing that
  never existed; deleted.

Both structural ones — the pairs the line-matcher cannot see, because one half
is Ruby — are closed 2026-09-05.

- **`Consensus::DEFAULT_MODELS`** restated models.yml's `three_mirror_redundancy.pool`
  under a comment asking the next reader to keep the two in step by hand, which
  is how a model swapped in one place leaves the consensus voting with one
  nothing else routes to. `Master.three_mirror_pool` is the reader now and
  `test_consensus.rb` pins the pool against the file, the quorum against the
  pool's size, and the injection point that keeps an explicit list winning.
- **`operator_principles` vs `principle_map`** was two vocabularies with nothing
  naming the authoritative one, and it settled itself: `operator_principles` is
  no longer a section of `rules.yml` at all — its 47 entries went to
  `law/practice.rb`, where each declares how it is checked. What was left were
  three references to the dead section, and the worst of them was a live gate.
  `RUNTIME_DOCS_YAML` sent an operator to `rules.yml#operator_principles` and,
  at error severity, told them to **delete** any `data/principles/*.md` — which
  is exactly what `Ground::Constitution` globs and parses. A rule forbidding
  what a live loader requires, invisible only because the directory is empty.
  That location is allowed now, one level deeper still fires, and the `/principles`
  empty message names the directory rather than the vanished section.


Worth naming: `SelfCheck#gate!` — the method that would halt background
autofix on this count — has **no caller** (verified 2026-08-19), so this
number gates nothing. The halt that stopped every /through fix stage on
2026-08-18 was SelfTest's laws count via ai_boot's `self_violation`
subscription, cleared when NO_GOD_CLASS switched to code lines.

The 13 is not the 11 of 2026-08-13 plus the exemption lifted below. Measured both
ways on one tree: the same 13 sites outside `lib/review/scan/rules/` are reported
by the old predicate and the new one, so the two that arrived since are drift in
`lib/`, and every finding the exemption had been hiding is fixed rather than
counted.

#### The rescue rules exempted the scanner from itself — closed 2026-08-15

`SILENT_RESCUE` and `NARROW_SILENT_RESCUE` both carried
`next [] if path.to_s.include?("/review/scan/rules/")`, with no comment, no gate
and no false positive to justify it: all **11 findings it suppressed were real
code**, none a comment or a regex literal. The directory it excused is the one
where a swallowed error does the most damage, because a rule that returns `[]`
reports the file it failed on as clean.

Two of the 11 were law failing open rather than ordinary swallowing.
`VetoPatternRule#load_patterns` rescued to `{}` and `#check` returns `[]` on an
empty pattern set, so an unreadable `data/rules.yml` retired every veto pattern
in silence; `YamlDeclarativeRule` dropped any declared rule whose
`detect_lexical` would not compile, which is inert law arriving by exception.
Both now report through `Swallow.log(..., severity: :load_bearing)`, as does
`Rule#check`, the shared AST default whose `rescue → []` made a bug in any
`check_ast` indistinguishable from a clean tree.

Three `rules_mtime` methods rescued `File.mtime` to `nil`; they ask
`File.exist?` now, since a missing file was the only failure they meant. One
inner rescue in `NestingDepthRule#scan_depth` was deleted outright rather than
made to report: it duplicated the base-class rescue one frame down, and two
layers of swallowing over the same call is how the first one stays invisible.

**An empty rescue body is a discard again.** `EMPTY_RESCUE` was deleted on
2026-08-12 as a pure duplicate, and "coverage is unchanged by construction" held
for every shape but one: `discard_body?` walked to the first non-blank line,
found `end`, and called it neither handled nor discarded. Probed rather than
argued, which is the only reason it was found. `lib/pub4/check_runner.rb` held
the single live instance.

It read 17 with `SILENT_RESCUE` 10 on 2026-08-12. The +1 arrived without a new
`rescue` anywhere in `lib/` — `git log -p` over the range shows zero added rescue
lines and the tree is clean — so it came from a rule moving under the code rather
than code moving under the rule, most likely the scan narrowing in `fca0883e5`.
Left as measured rather than explained away, which is what the caveat below is
for.

It was 34 across 6 the day before, and 17 of the 17 that went were the rules
misreading their own tree rather than code getting fixed:

- `EMPTY_RESCUE` 11 → **deleted.** It shared `SilentRescue.discard_body?` with
  `SILENT_RESCUE` and `NARROW_SILENT_RESCUE` and differed only in which `rescue`
  lines it matched, so across MASTER it produced 37 findings and **0 unique**. Its
  own comment claimed it "doesn't re-flag what those already catch"; it re-flagged
  all 37, 8 of them at both `:error` and `:warning` at once. It also made severity
  depend on comma count — `rescue Errno::ESRCH` was an error, the identical
  `rescue Errno::ESRCH, Errno::EPERM` only a warning — because its naked-class
  branch matched one whitespace-delimited token.
- `bare_rescue` 1 → 0 and `fail_visibly` 1 → 0. Both were the entry above:
  "the autofixer that repairs bare rescues flagging its own source" was
  `@transforms << :bare_rescue`, a symbol, matched by `rescue\s*$`. Recorded here
  as noise for weeks; it was one lookbehind.
- `guard_expensive_ops` 9 → 5. The four that went were prose about truncation and
  `rm -rf`. `detect_lexical` is a raw regex over raw lines, so the YAML bridge read
  comments as code — the same defect as `DEBUG_OUTPUT` reading `p << "…"` as a
  `Kernel#p` call. Comment-only lines are blanked in the bridge now; `scan_lines`
  itself is untouched, because several rules mean to read comments.

The five surviving `guard_expensive_ops` are still false positives — a `truncate`
string helper, a policy regex *listing* the forbidden verbs, a `CONFIRM` array of
symbols, a fixture string — and were verified line by line as code rather than
prose, which is why they stay counted. Narrowing further needs its own reasoning.

It was 71 before `STALE_NAMESPACE` (25 → 0) and `COMPLETION_THEATER` (12 → 0) were
narrowed on 2026-08-01.

Every narrowing on this list is pinned in both directions by
`test/test_scan_rule_false_positives.rb`: the false positive is gone *and* the real
violation still fires. Copy that shape — a rule whose false positives are removed
without a test asserting it still fires has been turned off, not fixed. The
2026-08-12 pass added the two cases that shape does not cover on its own: a test
that fails if `EMPTY_RESCUE` is ever re-registered, and one that asks *every*
registered rule how many of them call a given `rescue` line a discard, where the
answer must be one. A comparison between the two survivors would have passed
before the deletion, since those two were already disjoint — which is why a
duplicate rule can sit in a tree this heavily tested for as long as it did.

#### The veto patterns had never been read — audited 2026-08-12

`selfcheck` is error/critical only, so `:veto` findings never reached it, and
`rake constitution` sorts them into a bucket outside the actionable budget.
Nobody had opened either. All five patterns, every finding across `lib/` read
and classified: **229 findings, 4 real.**

| pattern | before | after | what it was matching |
|---|---|---|---|
| `sql_injection` | 87 | 0 | `execute\|query.*#\{` binds as `(execute)\|(query.*#\{)`, so the bare word `execute` was a merge blocker — `execute_job`, `pre_execute?`, and the parameterized form the rule prescribes |
| `unfinished` | 119 | 0 | `pending` (an order state, and inside *depending*), prose ellipsis, and Ruby's exclusive range `[0...-1]` |
| `unsafe_calls` | 23 | 3 | markdown fences and code spans inside Ruby strings; `Shellwords.escape`'d backticks and the Open3 arg-array form, both of which are the fix this rule prescribes |
| `race_conditions` | 0 | — | **deleted.** `if.*\n.*=.*\n.*if` needs three lines and `scan_lines` matches one at a time. It could never fire, at `:veto`, since it was written |
| `secrets` | 0 | 0 | correct, and the only one that was |

The three surviving `unsafe_calls` are real shell-outs with interpolation
(`ground/host_budget.rb`, `trace/snapshot_collector.rb`, `voice/engines.rb`);
two take their value from `ENV`.

Two gaps left open rather than papered over, both needing an AST rule instead of
a lexical veto — `scan_lines` is per line and cannot see across one:

- **SQL built in a heredoc.** `@db.execute(<<~SQL, args)` puts the interpolation
  on a later line than the call. The one instance in `lib/` is parameterized and
  safe; the rule cannot tell, and would not catch a real one.
- **Check-then-act.** What `race_conditions` was reaching for. If the concern is
  wanted it needs a real rule class; a three-line regex was never going to be it.

Also fixed here: `VetoPatternRule` scanned raw source, so a comment describing a
shell interpolation vetoed the file explaining it — the same defect
`without_comment_lines` was written for on the declarative side, which the veto
path never got. It is now per-pattern: `unfinished` declares `reads_comments`
because a work marker lives in a comment, and nothing else does.
`without_comment_lines` moved to the shared `Rule` base rather than being copied.

### Three principles with no scanner rule — evidence pinned, coverage not faked

`pledge_unveil`, `secrets_rotation` and `audit_logging` still have empty
`rule_ids` in `data/principle_map.yml`. Linking them to `LEAST_PRIVILEGE` or
`SECRET_PROXIMITY` would close the map gap without measuring the thing the
row names. `test/test_principle_evidence.rb` pins the sources that exist:

- `pledge_unveil` — `lib/ground/pledge.rb` applied from `lib/boot/master_boot.rb`
- `audit_logging` — `lib/trace/log/audit.rb` append-only `tool:before` log
- `secrets_rotation` — no rotator. Keys live in `/etc/*.env` on vm23.

A registered rule that actually detects a process skipping pledge, a tool
that is not audited, or a credential that never expires is still the gap.
Do not point `rule_ids` at a neighbour.

### Inert law and config

The dominant defect class in this tree: a declaration with no reader. Both named
instances are closed and both closures are worth copying rather than the fixes
themselves.

- `data/limits.yml` — **closed.** 29 of 38 keys had no reader and the generic
  accessors made them look reachable. The file is now split into enforced keys and
  a `guidance:` block, with `test/test_limits_split.rb` failing in both
  directions: an enforced key that loses its reader, and a guidance key that grows
  one. `/orient limits` still serves the file whole, so the split relabels rather
  than hides.
- `data/security.yml` (then `data/security/defaults.yml`) — **closed** the same way, by
  `test/test_security_defaults.rb`. Its worst case was worse than inert: the
  ingress rate limit was *also* hardcoded in `IngressController`, so file and code
  could disagree in silence.
- `data/patterns.yml` — **closed** for three keys. `gh`, `sweep_techniques` and
  `vocabulary` had no reader and are gone; `violation_priors` and
  `stale_namespaces` had one and were in the wrong file, so they sit in
  `rules.yml` beside the rules that read them. `data_reach` drops 49 to 46 and
  holds there. A first pass by grep called six keys dead: `prompt_archaeology`,
  `repo_topics` and `refusal_templates` have readers that the pattern missed,
  which is why `data_reach` is the instrument and grep is not.

- `data/tts.yml` — **closed 2026-09-06, and it was inert in the other
  direction.** The file's own header said "NOTHING RUNNING READS THIS … every
  key below, the engine chain included, is inert", from a caller trace that
  stopped one frame short of `Voice::Playback`. `Transcendent.load_config`
  reads it, `enabled` and `default_mode` are what `Speech.synthesis_mode`
  consults, and `Speech.synthesize` hands the text to `Transcendent.synthesize`
  whenever that mode is transcendent — which is what the file asks for. The
  path is `Cli::Session::ResultDisplay` → `Playback.speak` →
  `Playback.synthesize` → `Speech.synthesize`, so it runs on every spoken CLI
  reply. **A config that governs how MASTER sounds told its next reader it
  governed nothing**, which is the same defect as an unread key and costs more.

  What stands: the web half never reaches it — `health_controller`,
  `tts_controller` and `TtsJob` all enter through
  `synthesize_streaming_to_file` (socket → oneshot → espeak), and
  `DECISIONS.md` records why. On OpenBSD, `enabled` alone forces transcendent
  mode and `engine_chain` is overridden by `MASTER_TTS_ENGINE_CHAIN` or
  `Engines::OPENBSD_CHAIN`. `synthesize_bytes` is called by tests and nothing
  else — one method, not a subsystem.

  **Do not use this entry as a source for the `lib/voice` budget.** A name-based
  census over `lib/voice` reports seven files with no `Voice::`-qualified
  reference outside the directory — `Enrich`, `ProductionDna`, `StrunkPass` and
  the four `Renderer::` mixins, 601 lines — and every one of them is reached
  from inside it, three of them by `include`. The instrument was the prefix.

What is open is the class, not an instance. When you find one: find the reader
before trusting a config key, and **add the gate, not just the fix** — a
two-direction test is what stops the two halves blurring back together.

The `data/tts.yml` instance is also a warning about *when* to trace: it was found
after three fixes had already been written against that subsystem, not before.
Trace the caller first — the fixes were real, and their reach was not what the
config implied.

#### A general "every data key has a reader" gate does not work here — tried 2026-08-12

It is the obvious next gate and it is not buildable statically. Measured before
building, which is the only reason it was not built:

- **At the key level: 607 of 1173 second-level keys** across `data/**/*.yml` have
  no literal mention in first-party code. 52% — a checker wrong more often than
  right, which is what the veto audit spent the same day deleting.
- **At the section level: 49 of 238 top-level sections.** Better, and legible,
  but still holding whole classes of false positive: `personas.yml`'s persona
  names and `models.yml`'s model rows are registry entries selected by a config
  value at runtime, and `doc_paths_baseline.yml` is keyed by the very document
  paths it exists to list.

The reason is that this tree reaches its data four ways a grep cannot follow:
interpolated filenames (`review/modes.rb` opens `data/prompts/mode_#{mode}.yml`),
directory globs, the `DATA_ALIASES` table, and generic section loaders like
`RuntimeCatalog.load(section)`. All four are legitimate.

Two things worth keeping from the attempt:

- **`loc_budgets` looked dead and is not.** It is read by the `loc_budget` task
  in the Rakefile, which a `lib/`-only search misses. Any search for readers has
  to include `Rakefile` and `bin/`.
- **The top remaining candidate, `limits.yml` `guidance` (29 keys), is the
  closure above working exactly as designed** — the deliberately unread half of
  the split, pinned in both directions by `test/test_limits_split.rb`. An
  unread-key gate would have reported the fix as the defect.

So the honest scope is per-file and by hand, with a two-direction test, the way
`limits.yml` and `security.yml` were each closed. A repo-wide gate would
need a baseline carrying a written reason for all 49, which is a decision about
49 sections rather than a mechanical step.

### The shape of the tree

`sprawl_census` counts three things over every tracked file in all four trees,
and `bin/pub4 measure` carries them: a directory holding one file, a name that
repeats its parent, and a name that says nothing on its own. `FILE_SPRAWL` in
the scan registry measures the first two for MASTER's `.rb` files and skips
`law/`, `core/`, `test/` and `spec/`, so it reports zero here and means only
that.

Priced rather than fixed, because a ceiling that prices a known cost is what
makes the next arrival a `+1`:

- **20 one-file directories**, against a ceiling of 20, after the 2026-09-05
  hoist of one-file spec, data, test and support dirs. What remains is mandated:
  OS install paths, Zeitwerk, Rails `test/system`, ports fixtures, OmniAuth,
  PWA, and dilla vocal/render takes. Read the live figure from
  `MASTER/bin/pub4 measure`, not from here — the number in this paragraph is
  the kind that goes stale in a day. The map is `TREE.md`.
- **3 uninformative names**, all Zeitwerk: `lib/io/base.rb` is named after the
  constant it defines, so the finding is that the *concept* is called `Base`,
  which is a design decision and not a rename. The three that were actionable —
  `STUDIO/test/helper.rb`, `STUDIO/test/dilla/helper.rb` and
  `STUDIO/test/tools/helper.rb` — were flattened to `studio_helper.rb`,
  `dilla_helper.rb` and `tools_helper.rb`. Checked 2026-08-29:
  `Dir["STUDIO/**/helper.rb"]` is empty and the three new names are in place.

Calibrate a new kind against a real file before adding it. The first pass
called 130 RAILS paths too deep and 26 names vague, and every one was the rule
misreading a path Zeitwerk requires — the same way 596 of 981 design findings
died. Stutter took three attempts before it separated `dilla/dilla.rb`, which
reads correctly at a command line, from `lib/cli/cli.rb`, which held
`Master::CLI::CLI`. What tells them apart is whether the file declares the name
twice.

### Top-level ROOT

**25 files across the repo define a bare top-level `ROOT`**, each pointing at a
different tree — `MASTER/tools/*` at the repo root, `OPENBSD/*.rb` at `OPENBSD/`,
`STUDIO/dilla/dilla.rb` at the dilla directory, `RAILS/tools/*` at `RAILS/`.

In their own processes that is harmless, which is why it has stood. It stops
being harmless the moment two of them are loaded together: Ruby warns
`already initialized constant ROOT`, lets the **second assignment win**, and the
loser then reads the wrong tree with no further complaint.

That happened in `rake test`, where `test_security_sweep.rb` requires
`tools/security_sweep.rb` and `test_dilla.rb` loads `STUDIO/dilla/dilla.rb`.
Depending on load order, the security sweep would have run `git ls-files` against
`STUDIO/dilla` and reported the repo clean having scanned a music directory. The
warning in `bin/check`'s output was the only thing standing between that and a
silent pass, and it read as cosmetic noise.

Closed for that pair on 2026-08-12 by renaming MASTER's to `SWEEP_ROOT`, and the
class is closed with it: **`rake lint:constant_collisions`** asserts that no two
files reachable by a `require_relative` define the same top-level constant. 362
requirable files of 2,094 first-party Ruby, currently 0 collisions — the gate
lands green because the one live instance was fixed, and it flags the pair again
if either file goes back to a bare `ROOT`.

The remaining 24 bare `ROOT` definitions stay, deliberately. A standalone script
run as `ruby thing.rb` never shares an interpreter with another, so the constant
is only a hazard once something requires the file. Only `require_relative` is
followed: a plain `require` resolves against `$LOAD_PATH`, which depends on how
the process was started, and guessing at it would produce a gate that is wrong
in both directions.

**The cross-tree test is closed — 2026-09-05.** `MASTER/test/test_radio_bergen_study.rb`
required `../../STUDIO/dilla/dilla` and through it read
`RAILS/brgen/config/radio_bergen/tracks.yml` — one test file reaching into two
other trees. It had already broken the way this entry predicted: it asserted
`assert_equal 9, local_count` while the manifest had grown to 30 rows when radio
bergen started serving its own catalogue, so `rake test` in MASTER was red for a
change made in RAILS, naming the growth as the regression. That half was fixed
by asserting the invariant instead of the instance — the study covers every row
the manifest holds, counted from the manifest.

The coupling is now fixed too. The file is
`STUDIO/test/test_dilla_radio_bergen_study.rb`, beside the module it exercises,
loading the engine through `dilla_helper` like its neighbours and named so the
`test/test_dilla_*.rb` glob reaches it. `RadioBergenStudy` reading RAILS's
manifest is the engine's own coupling and is unchanged; what has gone is a
MASTER test that broke when any of three trees moved.

Found on the way: **`Pub4::Runs` never looked at STUDIO at all** — 23 test files
outside every question the "a test nothing runs" gate asks, which is why moving
a file out of MASTER would have quietly removed it from that gate. STUDIO is in
the census now, and the extractor reads a runner's exact path literals as well as
its globs, because `STUDIO/Rakefile` names `test_studio_gate.rb` outright and a
glob-only reader called it an orphan. 743 test files across four trees, 0
orphans.

### Test coverage

**163 of 445 `lib/` files have no test or spec naming their innermost class or
module** (measured 2026-08-11; the earlier record of 188 of ~400 used the same
method against a smaller tree).

The argument for closing the gap is what happened when eight named constants got
their first tests on 2026-08-01: four live defects fell out, all in code that
looked fine.

- `io/ssrf_guard.rb` never required `uri`. `safe_uri?` does `uri.is_a?(URI::HTTP)`
  inside a blanket rescue, so in any process that had not already loaded `uri` the
  NameError was swallowed and the guard answered false for every URL — web_fetch
  silently disabled, one `Swallow.log` line, no other symptom.
- `Permissions.blocked?` matched its blocklist with bare `include?`, so "sudo"
  inside "pseudo" and "halt" inside "shalt" made `grep -rn pseudocode lib` refuse
  as dangerous.
- `PatchApplier` kept only stderr, but `patch(1)` reports a failed hunk on stdout,
  so the most common real failure produced an empty reason.
- `GitOperations#dirty_count` counts status *lines*, not files — git collapses a
  wholly-untracked directory to one `?? lib/` line.

`rake test:subsystems` runs in the `operator` and `contributor` profiles, so
`test/{cli,io,fix,lib}/` is no longer skipped by the gate `START_HERE.md` sends
contributors to.

### Web Face Verification

**operator-priority.** Voice Mode and boot contracts are covered by
`web/test/face_boot.test.mjs` (static assertions on `face.runtime.js`), and the
WebGL primer guard has the same pattern. **Manual iOS Safari tap-testing remains
operator work when boot assets change materially** — nothing in CI drives a real
touch event.

### Host TTS Binaries

**operator-priority.** End-to-end TTS audio depends on host binaries
(`edge-tts`, `espeak`, `ffmpeg`). Web wiring can be correct while synthesis is
unavailable, and `pkg_add` succeeding at install time is not evidence a binary is
on the box now. Check `GET /health` `deploy.tts_socket` and
`test -S .master/tts.sock` on vm23.

`lib/voice/engines.rb`'s two ffmpeg fallbacks used to return quietly, so a host
without ffmpeg served un-concatenated audio with nothing logged. They now report
through `Swallow.log(..., severity: :load_bearing)` naming the consequence. **Any
future post-synthesis DSP must call `report_missing_ffmpeg` on its own fallback
path** rather than returning silently.

Measured on vm23 2026-08-17: ffmpeg 6.1.3 and ffprobe are both in
`/usr/local/bin`, and `Engines.ffmpeg?` evaluates true inside MASTER's own bundle
there — so the PATH the daemon actually runs with resolves it, which the cron
PATH lesson elsewhere in this file says not to assume.

#### One-shot Edge worker on vm23 — code path matched, box not re-probed

**operator-priority.** Production TTS is the daemon; the fallback is
`synthesize_edge_oneshot`. The one-shot path used to call `synth()` in-process
while the daemon used `synth_forked`, and it did not set `SSL_CERT_FILE` the
way `worker_env` does for a subprocess. Both of those are now the daemon's
path. That does not prove the box writes a non-empty MP3: `/health` is still a
capability check. Re-probe on vm23 with a real oneshot before calling the
fallback healthy.

### Live gotchas

Three facts with no home of their own, kept because each was expensive to find.

- **A council pass looks exactly like a hang.** On a dev Mac the provider is the
  `claude` CLI (`send_claude_cli`), not an HTTP API, so a run with no
  `*_API_KEY` in the environment still reaches a model and `Master.any_api_key_present?`
  is not the question. `CLAUDE_CLI_TIMEOUT_S` is 300 and the council runs 26
  personas four at a time, capped by `TOTAL_BUDGET_S` at 600. Add four scans of
  ~90s each and `/through master` needs roughly sixteen minutes. It spends most
  of that at 0% CPU with an empty pipe, because the CLI buffers when stdout is
  not a TTY and every persona thread is blocked on `IO#read`. Two sessions have
  now killed it believing it was stuck. `ps` shows the truth: count the
  `claude --print` subprocesses before concluding anything.

- **Constructing a `CLI` object flips a process-wide flag.** `CLI#initialize`
  calls `set_visitor_mode_if_unauthenticated`, which sets
  `Fiber[:master_visitor] = true` whenever the config carries no `web_token`, and
  fiber storage outlives the test that set it. That was the "known flake" in
  `TurnRouterTest` (see `test/test_cli.rb`): a later test reaching `TurnRouter.call`
  took the visitor branch and errored inside a test about the Fold. Both CLI test
  files clear it in `teardown` now. Not a product defect — a real CLI reads a
  64-char `web_token` — but the web path sets and clears this per request while the
  CLI sets it for the life of the process.
- **An orphan sweep must include the repo-root `bin/` and must not filter by
  extension.** A 2026-08-03 sweep deleted `lib/pub4/status_report.rb` as an orphan
  and broke `MASTER/bin/pub4` for six days: the grep matched only `*.rb`/`*.yml`/`*.md`
  and `MASTER/bin/pub4` has no extension, and it ran from `MASTER/`, where `bin/` does not
  mean the repo-root `bin/` that holds the caller. Pinned by
  `test/test_entrypoint_requires.rb`, which checks requires rather than constants —
  a constant sweep can be fooled by an extension filter; a missing file cannot.

### Scanner Conventions

Seven shapes of one defect: **each converts the absence of a property into
evidence of it.** A gate, a test or a reader accepts something that merely looks
like the thing it was checking for, and the result is a defect that arrives
carrying its own certificate of compliance. Six were found in one week of
2026-08, in different subsystems, by different sessions; the seventh in RAILS on
2026-09-05, and it had been costing a thousand assertions a run.

#### 1. A comment outlives the rule it explains

Any check that greps source for a string must strip comments first. A rule and the
paragraph explaining the rule contain the same words, so a raw `include?` /
`refute_includes` matches the prose about a thing as readily as the thing. This
fired four times on 2026-08-10 alone: a test refused a partial for containing
`popover` where the match was the comment recording the popover's removal; a
weight test counted three Stimulus controllers in a partial rendering two, having
read the comment quoting the markup it replaced; and the `nbsp_entity` and
pagy-helper rules each flagged the comment explaining themselves. A fifth, one
layer out: a CSS pass "confirmed" a rule had been deleted from three bundles when
sass had preserved the `/* */` comment naming it.

The fix is one line at the read site, and it differs per language:

```ruby
source.gsub(/<%#.*?%>/m, "")          # ERB
source.gsub(%r{/\*.*?\*/}m, "")       # CSS/SCSS block comments
source.lines.reject { |l| l.strip.start_with?("#") }.join   # Ruby, YAML
```

The failure mode is asymmetric, which is why it matters: a `refute_includes` that
reads comments produces a *false alarm* the next author "fixes" by deleting the
explanation. That is how a codebase loses the reasons for its own decisions.

#### 2. An exemption outlives its subject

When a gate carries an allow-list — exempt paths, baseline numbers, known
offenders — the entries must be **checked against reality, not merely consulted.**
An exemption whose subject no longer exists is a hole in the gate that nobody can
see, precisely because the thing it excuses is invisible.

When `RAILS/FINAL_TODO.md` was deleted it surfaced two immediately, because both
tests named the file the moment it went: `doc_numbers` was still granting it dimension
exemptions and `doc_paths` was still excusing a generated schema path on its
behalf. Neither had had a subject for as long as it took to notice.

`rake lint:autoload` is the shape to copy: it does not merely read its ignores, it
asserts each one is still necessary and fails naming any that is not. Cheap check
when adding one: every path in an allow-list should resolve, and every numeric
exemption should name the file it was granted for. Note that "resolve" needs the
right base directory — a probe that assumed repo root reported 89 phantom stale
entries in `data/autoload.yml`, whose paths are relative to `MASTER/lib/`. Verify
the instrument before believing the finding.

#### 3. A build artifact outlives the source it was built from

The one that hides best, because while the source stays correct every reader who
checks the source concludes the tree is fine. Found in amber: `public/assets` held
a precompile from before a rename, and in development Rack::Static serves
`public/` *ahead of* propshaft, so the stale bundle won its own route — the
browser got July's JavaScript while the repo held August's. It was noticed only
because that copy happened to be *corrupt* and took every Stimulus controller down
with it.

That detail is the warning, not the incident. A corrupt stale artifact announces
itself; a merely outdated one serves last month's behaviour in silence,
indefinitely.

- When behaviour contradicts source, check what is being served before re-reading
  the source. `curl` the asset path and diff it against the file it claims to be.
- `public/assets` is gitignored, so this never ships — it is a local-only trap,
  which also means CI cannot catch it for you.
- The same shape reaches production by a different road: `web/face.runtime.js` is
  generated from `face.part*.txt`, and a commit that edits a part without
  regenerating leaves a stale artifact tracked in git. That is why
  `rake assets:precompile` belongs in the same commit as any face-source edit.

#### 4. A staleness alarm silenced by regenerating the artifact

Corollary to 3, and it cost four broken JavaScript call sites in `e7e48eed1`.
`AstFixer`'s `template_literals` transform converted a `+`-chain ending in a
*call* by taking only the callee, producing a template literal invoked as a
function: a `TypeError` on every execution, and **valid syntax**, so
`node --check` and the commit's own "All parse" claim were both satisfied.

Two of the four were caught only indirectly, by
`test_public_asset_manifest_matches_source_files`, whose message reads "generated
asset drifted" — a *staleness* message. Running `assets:precompile` to clear it
copies the broken source over the good digested asset and turns the alarm off
without fixing anything, which is exactly what happened first.

Closed three ways: the call sites restored; the transform now declines any chain
followed by `(`; and `test_public_js_has_no_template_literal_called_as_a_function`
fails on the *shape*, in the tree, rather than through a drift message. When a
test reports drift, ask what the drift is evidence of before regenerating.

#### 5. A test that punishes the improvement it exists to detect

A gate that watches for a finding must be written so that fixing the finding is
not a failure. `RAILS/test/gate_live_and_css_budget_test.rb` asserted that one
specific colour pair measured *below* the AA contrast threshold, with the message
"the finding this pairing exists to surface has gone". Anyone who improved that
accent would have been met with a red test naming their fix as the regression.
Nobody was, because it was already failing for an unrelated reason, so the trap
sat armed and invisible behind another red.

1. **Assert the invariant, not the instance.** `refute_empty findings` survives
   every legitimate fix; `assert specific_pair.ratio < threshold` survives none.
2. **Read a name from the constant that owns it.** A test that spells out a value
   the code already names cannot tell a rename from a regression.

The tell is a test whose failure message describes something good happening.
Invert it and ask what a successful fix looks like in CI; if the answer is "red",
the assertion points the wrong way.

#### 6. A writer that reports an edit it did not make

`rake lint:spine RATCHET=1` printed "raise log cleared" and cleared nothing. Its
substitution matched continuation lines only (`    .*`), deliberately, after an
earlier version matched dashed lines only and left the file unparseable — the
fix for a loud failure introduced a silent one, and the comment above it
explained the reasoning for a pattern that had stopped matching anything. The
allowance was therefore a countdown to permanent failure rather than the budget
`spine.yml` describes, and nothing could show it: a cleared log and a log that
was never touched look identical from outside.

The fix is not the regex. It is that the task now **reads back what it wrote**
and aborts if `raised` is not empty. A writer that can claim an edit it did not
make belongs to the same family as the four above — the absence of a property
reported as evidence of it — and the remedy is the same: assert the outcome, not
the attempt.

#### 7. A root constant that resolves one level too high

`RAILS/brgen/test/source_reader.rb` computed the tree as
`File.expand_path("../../..", __dir__)`. The file is at `RAILS/brgen/test/`, so
that is the repo root and not `RAILS/`. Two guards in the same expression were
supposed to catch it — the chain only accepts a candidate holding `shared/app`,
then one holding `shared` — and both missed, so it fell through to
`candidates.last`, which is the wrong path it had just rejected. A fallback that
ends in "use the last one anyway" is not a fallback.

The cost was 39 errors and one failure in brgen's suite, and the number that
matters is the other one: **974 runs carrying 3,486 assertions became 974 runs
carrying 4,529**. A thousand assertions had never run on any checkout that is
not `/home/dev/pub4`, which is the first candidate and why the box never saw it.
The suite is green now, and the two verticals it re-armed —
`InfiniteScrollWiringTest` and `DeployBacklogTest` — are the ones that read
source rather than exercise it.

Same family as `Pub4::OperatorDocs::ROOT`, recorded above at four levels instead
of three, and the remedy is the one that entry named: **assert the resolution,
not the reads.** `test_root_resolves_to_the_rails_tree` checks that ROOT holds
`shared/app` and `brgen/app` and is called `RAILS`, because a wrong root fails as
a missing file and reads as a missing file.

#### What follows from all seven

- **A new gate's first run must be against a known-bad input, not a clean tree.**
  A green first run is the least informative outcome available: it is equally
  consistent with "nothing is wrong" and "nothing is measured". Every check added
  on 2026-08-10 was mutated six ways and watched to fail before being believed —
  and two of them did not fail, and were wrong.
- **Registration is not execution.** `rendered_invariants` shipped with an
  instance `run` and no class-level `.run`, which is how `runner.rb` invokes a
  gate: it was a row in `gates.yml`, listed by `--list`, counted as coverage, and
  never once executed. It is the gate written to catch declarations with no reader.
- **A gate must read the source of truth, not restate it.** `domain_alignment` —
  whose whole purpose is proving the fleet's domains and ports agree — held its own
  literal table of the three domain/port pairs. Edit `apps.yml` and it keeps
  asserting the old numbers, and passes.
- **When writing a check that recognises a pattern, name the cases you already
  know and pin them through it first.** An ownership-guard sweep found its own
  regex matching the *fixed* branch, because after `user` comes a dot rather than
  `_id`.

### Not Debt

- The fold spine living inside `lib/`. Merged 2026-08-12 on operator
  instruction; `DECISIONS.md` records the reversal and what was kept (the
  no-backedges test, and the `core_files` invariant). Not a regression to undo.
- One rule registry. The four `data/rules/*.yml` shards were folded into
  `data/rules.yml` on the same instruction. Their single consumer was
  `load_rules`, which merged them back before any scanner saw them.
- Local `knowledge/` corpus and generated `output/` artifacts.
- Deferred WebGL boot.
- **The gap between the registry classes and the declared rules.** Checked
  2026-08-12 on the theory that the difference was inert law — declared rules
  nothing implements, which would be this file's dominant defect class at the
  constitutional layer. It is not: every declared rule has a detection path, in
  the corpus, in `law/`, or by `folded_into` naming the rule that reports for it.
  `RuleRegistryAudit` measures the split, `SelfTest` reads it, and
  `test_rule_registry_audit.rb` pins it. Re-measured 2026-09-04 at 228 declared
  and 145 built, with the split now 141 semantic, 15 structural, 78 carrying no
  detector field and resolving through `law/` or a fold. **The "7 lexical-only
  through the YAML bridge" in the original wording is 0** — see the audit section
  above; that half is a live question, the no-inert-law conclusion is not.
- Media-generation severance: re-severed 2026-07-14 (`76b11fec4`), confirmed
  permanent 2026-07-15. `docs/SEVERANCE.md` is the source of truth. If the LoRA
  training loop needs generation capability again, express it as
  `lib/core/world.rb` handlers per the original absorption plan — do not restore
  the deleted `io/lora_pipeline.rb` / `video_chain.rb`.

### From the 2026-09-04 MASTER audit

Opened by reading `data/rules.yml` end to end and asking, for each declaration,
which line of Ruby consults it. Everything below was measured against this tree
rather than inferred, and the command that measured it is named so the next
reader can re-run it instead of re-deriving it. The cleanup that came out of the
same sitting is `72a8cfae8`; what is here is what that commit did **not** close.

#### `self_findings.registry`: 52 findings the tree owns

The row was opened 2026-09-06, when `self_findings` turned out to count the 122
laws and call itself "what our own rules find in our own trees" — the 145 rules
the registry builds were counted by nothing. It measures through
`InfraHelpers.build_scanner` and `Scanner#findings` at error severity, over the
same corpus as the law row, dropping ids that reach the scanner through
`LawBridgeRule` so one fix moves one ratchet. `data/self_findings.yml` carries
every finding with its file and line.

It opened at 108 and three passes took it to 52, and almost all of what fell
was the instrument rather than the tree — `SQL_INJECTION` flagging the
`quote_table_name` that is its own fix, `COMPLETION_THEATER` reading `/etc` as
an abbreviation thirty times, `DEBUG_OUTPUT` reading dilla's `p < 0.5` phase
local as a debug print. Each rule carries its own evidence now; the lesson is
the one this file opens with.

**What is left is real, and it is two rules.** `SILENT_RESCUE` 26, every one in
STUDIO and nineteen in dilla, where a `rescue StandardError` around an optional
gem call is load-bearing for a render — narrowing one on my own judgement is
the change this repo's own rules say not to make, so that half wants dilla's
owner. `NO_GOD_CLASS` 26: more than ten public methods or more than three
hundred code lines, led by `Conversation` 28, `User` 27, `Takeaway::Order` 26
and `BergenDemoSeeder` at 834 lines. Nothing there is instrument; it is
twenty-six decompositions in three trees, most of them live Rails models.

#### The census had never read `MASTER/web` — widened 2026-09-07

`self_findings` walked eleven trees and `MASTER/web` was not one of them. The
face is 164 tracked files, and five laws have their only subject there:
`FOR_OF`, `TEMPLATE_LITERALS`, `ASYNC_AWAIT`, `FACE_POINT_IS_ONE_PIXEL` and
`NO_JQUERY` read as silent because nothing they govern was ever handed to them.
Adding the tree took the law row from 147 to 293 and the registry row from 51
to 54, and `data/self_findings.yml` carries that reasoning beside the ceilings.

The face’s generated bundles are third party for this purpose.
`face.runtime.js`, `face.modules.bundle.js`, `face_vision.bundle.js` and
`three.face.module.js` are 12,019 lines built from `face.part1-5.txt`, so
counting them measures the generator’s output rather than anything a person
wrote.

Two of the new findings were the instrument. `STALE_NAMESPACE` read a comment
saying a `Master::CLI` is built as a use of the retired constant; it blanks
comment lines before scanning now. `COMPLETION_THEATER` read `/* … (mood
changes etc) */` in the face’s CSS as a placeholder, and extending its comment
stripper to `//` and `/* */` for every language then mangled
`OPENBSD/installed_targets_gate.rb`’s `CONFIG_GLOBS = ["etc/crontab*",
"etc/*.local", "etc/rc.d/*"]` — the strip ran from `/*` to the end of the line
and left `"etc` behind, which is the abbreviation the rule flags. The ratchet
caught it as registry 0 → 1 in the same sitting. The stripper picks its pattern
from the file’s extension now: `#` everywhere, `//` and `/* */` only for `.js`,
`.mjs`, `.ts`, `.jsx`, `.tsx`, `.css` and `.scss`.

**A rule that fires on nothing may have no subject rather than no defects.**
Before believing a silent law, check that the census reads the tree its subject
lives in.

#### The constitution's seven hooks — closed 2026-09-06

`soul.yml` had declared seven hooks since it was written and none had ever
fired. `Trace::Hooks` turns five bus events the tree already publishes into the
`on_*` names the constitution uses and runs what `soul.yml` declared for each;
nothing called `attach`, while its three `Trace::Ledger` siblings are each
attached in the same boot phase.

Deleting it was the alternative and it was the wrong call — the shape is worth
keeping, because a constant-name census and a file count both said delete.
All three halves were built: the declarations, the class, and the events.
`scan:complete` comes from `file_processor` at two sites,
`rule_loop:fix_applied` from `rule_loop`, `llm:cost` from `ruby_llm_sender`,
`phase:advanced` from `phase_gates`, `fix_loop:clean` from `pass_runner`. What
was missing was one line. **A subsystem three-quarters wired reads exactly like
a dead one from the outside, and the difference is whether the events it wants
are already on the bus.** Ask that before deleting.

`.constitutional_violations.jsonl` — the file `soul.yml` has always said a
violation is appended to — is written now, proved by a real scan rather than
asserted. It is gitignored.

`test_trace_hooks.rb` boots `TraceBoot` for real rather than grepping
`boot_phases.rb` for the word `attach`, which would pass against a method body
of `raise`. Its last test walks `soul.yml` and fails if any declared hook
produces no effect, so the state this record described cannot return quietly.

#### The tier2 ordering guarantee — closed 2026-09-05

`TIER2_QUALITY_RULE_IDS` is now `%w[NO_GOD_CLASS FEATURE_ENVY FEW_ARGUMENTS]`,
the scanner ids that actually exist. The test asserts those ids are on the live
scanner, not on a Struct it constructed.

#### The YAML lexical bridge now compiles nothing — closed 2026-09-05

`YamlDeclarativeRule` remains the escape hatch for a `detect_lexical` with no
Ruby class, and `rake lint:rule_reach` still counts on the category. The
corpus carries 0 such rows. `RuleRegistryAudit` now prints `lexical hatch
empty` when both wired and unwired are 0, so the idle hatch is a named
finding rather than two zeros a reader has to add up. The hatch stays; what
was missing was saying it is idle.

#### A `languages:` scope on a semantic rule was inert — closed 2026-09-05

`SemanticRule` builds a prompt frame per language now and `parse_findings` reads
the scope the file was asked about, so a reply naming a rule outside it is
discarded rather than accepted. Empty still means every language, as it does for
`Law::Rule#applies?`.

One thing came out of wiring it that is worth keeping. Thirteen rows declared a
language `FILE_LANGUAGE_MAP` never produces — `rails` on four, `prose` on eight,
`erb` on one — which aims a rule at no file at all. `Law::Rule#prove!` has
refused that on the law population since `NEVER_BATCH_DELETE` declared `shell`
and could read no script; `test_semantic_rule_scope` now asks the same of this
one. `rails` became `ruby`, which is what those four detectors already declare;
`prose` and `erb` went, each beside a real sibling that covers the same files.

#### Rule-corpus debt the ratchets already price, listed so it is one place

Each is the current output of a gate that passes because its ceiling accommodates
the number. None is new; what is new is that they are together.

**Half of it was the instrument, closed 2026-09-05.** The two gates that report
this debt were each asking a question their own data could not answer, and the
corrections are worth more than the counts were.

`autofix_reach` decided whether a rule can be *found* by counting the three
`detect_*` columns in `rules.yml`, so it named twelve autofix claims
undetectable and was wrong about all twelve: ten have a live detector in `law/`
or the RuleDSL registry, and `WHITESPACE_PUNCTUATION` and `MESSAGE_CHAIN` carry
`folded_into:`. It asks `RuleReach.mechanical` now, which knows all three
populations and loads the laws rather than grepping for `Law.define(:ID)`.
Corrected, it found six the old count could not see — `PRECOMPUTE_MATH`,
`ANALOG_WARMTH`, `PURE_FUNCTIONS`, `SPECULATIVE_GENERALITY`, `SYSTEM_STATUS`,
`CACHE_LLM` — each a semantic-only detector at info severity, which
`SemanticRule`'s info filter drops, so nothing ever reported them and no fix
could ever be reached. All six are `autofix: false` now and `bare_true` is 25.

`rule_hygiene` walked every hash in the file carrying an `"id"`, so the eight
check names inside `AUTOMATED_CSS_ANALYSIS`'s `config:` counted as eight rules
with no metadata and one of them, `eight_px_rhythm`, collided by case with the
real `EIGHT_PX_RHYTHM`. It reads the two declared populations now. What was left
after that was real and is closed: the `bare_rescue` smell went (see **Scanner
noise**), the five surviving smells declare a severity, and DRY's
`duplicate_code` alias went rather than the live rule it named. All three
counters read 0, and 0 is the recorded floor.

Still open, and each is a decision rather than a sweep:

- **`autofix: true` naming no transform — closed 2026-09-06, 25 to 0.** Three
  kinds, and the kinds are the reason the tool asked for. Four name the
  transform that already fixes them (`HTML_LANG` `add_html_lang`,
  `LAZY_IMAGES` `add_lazy_loading`, `TRAILING_COMMAS` `add_trailing_commas`,
  `DEAD_CODE` `remove_immediate_dead_code`), so `named` is 4 where the corpus
  named none at all. Sixteen are design judgements where no single edit is
  correct and `false` is what they always meant. Five are mechanical in
  principle and unwritten in fact — `EN_DASH_RANGE`, `NO_UPDATE_ATTRIBUTE`,
  `QUOTE_VARIABLES`, `DOUBLE_BRACKET`, `WHITESPACE_PUNCTUATION` — and those
  five are the forward work: **the transforms are worth writing, and naming one
  before writing it is how the dangling counter filled up last time.**

  One behavioural consequence, named rather than discovered. `MechanicalAutofix`
  selects a file when any finding carries a truthy `autofix`, so a file whose
  only findings are judgement rules no longer gets `AstFixer`'s universal
  cosmetic passes as a side effect — a scan should not rewrite a file because
  of a finding it cannot fix.
- **24 rules fire on nothing in this corpus** (ceiling 24, so the gate is at its
  limit). The header in `rule_ratchets.audit` is right that silence is usually a
  property of the sample — but `FROZEN_STRING_LITERAL`, `MEANINGFUL_NAMES` and
  `WHY_NOT_WHAT` are in the list *and* in the 78 rules that carry no detector
  field at all, which is a different reason for silence and worth separating.
- **20 cross-population duplicates** — one id defined in two places in two
  wordings, with no way for a reader to tell which governs. Resolving one means
  keeping the wording where the detector is, which is a judgement per pair.
  Ratcheted at 20 now, where it had a ceiling of 21 and no row in
  `bin/pub4 measure`.
- **133 registry rules sit outside `rule_deps`.** No longer ungated: it is a
  ratchet row, `rule_deps.ungraphed`, floor 133 and down only. A rule outside
  the graph is one `RuleOrder` cannot sequence.

#### `zsh` reference tables — closed 2026-09-05

`zsh_style_lines` now reaches `forbidden_commands`, `native_patterns`,
`ssh_reading` and `token_economics` as well as `banned_commands`.
`banned_commands` is still the only list `Io::Shell` warns on.

#### Nine of sixteen line budgets are over, and `law/` is nearly double

`rake loc_budget`, re-measured 2026-09-06: `law` 1610/852, `lib/pub4` 692/470,
`lib/ground` 6098/5899, `lib/core` 769/682, `lib/boot` 276/227, `lib/trace`
2055/1999, `lib/voice` 3408/3181, `lib/review` 10493/9765, `lib/fix` 2661/2643.
`limits.yml` says a breach is paid by extraction or deletion and never by a
bigger number.

One of the nine has been paid down and it is the largest single fold this file
records. `lib/ground` fell 730 — 6842 to 6112, from 943 over to 213 — when the
seven unreached antigravity subsystems and the Coordinator that eagerly built
them went, which is the whole of what that directory's overage had been.
`lib/review` moved the other way and keeps moving: 36 back when ten
byte-identical copies of a five-line `visit` moved onto `Rule#walk`, then 59
out on the twenty-nine rule fixtures below and 67 more on the last thirty,
which closed `rule_fixture_debt` at 0. That is the trade the fixture ratchet
asks for — a worked example per rule against a line of budget — and it is named
here rather than buried.

`law/` at 89% over is the one to open next: the twin census closed in 2026-08
retired 42 duplicated rules and the file set has grown back past where the
budget was set.

#### `rake selfcheck` locations and three silent rescues — closed 2026-09-05

`SelfCheck::Report` now carries `findings` with path and line, and the task
prints that summary once (the `selfcheck: selfcheck:` prefix is gone).
`Scanner#findings(paths)` is the flat API; `tools/example_scan.rb` uses it.

Three of the four `SILENT_RESCUE` sites now report through
`Swallow.log(..., severity: :load_bearing)`: `PathPurposeRule#owned`,
`antigravity/skills.rb#load_usage`, `Session#quarantine_corrupt_session!`. The
fourth, `voice/renderer/system_info.rb`, no longer reports at all — re-scanned
2026-09-05, the rule finds nothing there. Do not re-open it from this line.

**`rake selfcheck` is 1 finding, 2026-09-05.** Two of the three went:

- `COMPLETION_THEATER` on `ast_fixer.rb:75` was the rule reading its own subject.
  `PLACEHOLDER_ETC` already excluded a path segment; it excludes a regex
  alternation now, so `%r{/OPENBSD/(?:etc|usr|var)/}` — the verbatim-mirror
  guard, at error severity, so the fast gate was red on the rule that protects
  `/etc` — reads as the pattern it is. Measured over all four trees: two lines
  retire, 57 findings stay, and `(etc.)` in prose still fires, which is why `(`
  and `)` stay out of the exclusion.
- `NO_GOD_CLASS` on `LlmDispatcher` was the count measuring an idiom, the way it
  read `Core::Constitution` at 16. Three of its eleven public methods —
  `redact_secrets`, `forced_model`, `vision_capable?` — have no caller anywhere
  in the repo and sat above `private`. Moved below it: 11 public → 8. The eight
  model-shape predicates that do have callers stay public.

`NO_GOD_CLASS` on `EventStore` closed with `lib/autonomy` on 2026-09-05, and
what it took to close is the part worth keeping. The record read it as a
decomposition question — fourteen public methods over four tables, each one
somebody's door — and privatising a repository's API to satisfy a counter is
what "driving the count to zero by re-exempting" means, so it sat. The question
was never how to split it. Nobody was at any of those doors, the subsystem was
reached by nothing but its own tests, and the counter was right in a way its own
message could not say. **`rake selfcheck` is clean and `rake selftest` is 0**,
both for the first time since 2026-08-19.

The fourth `SILENT_RESCUE` came back and is closed. `ProgressReporter`'s
`append_scan_hits_jsonl` swallowed every failure writing `.master/scan_hits.jsonl`
— the one record a sixteen-hour walk leaves behind, where an empty log and a
clean run look alike. It reports at `:load_bearing` now. `rake selfcheck` is 1.

`rake selfcheck` also printed its whole located summary twice on a failing run:
once to stdout and once as the abort message. `Report#line` is the headline on
its own and the task fails with that.

#### `edge_tts_available?` and the Mac `say` fallback — closed 2026-09-05

The cheap probe stays two preconditions (`worker_executable?` and
EventMachine SSL) because it gates a per-utterance path. `/health` asks
`edge_tts_ready?`, which spawns `tts-worker --selftest` and reports
`tts_blocker` when it is not. Classic `Speech.synthesize` now falls through
Edge, then espeak, then `Engines.synth_say`, so a Mac without a live Edge
socket still speaks.

#### Three test files have been erroring, and `rake test` cannot see them

Found 2026-09-05 by running every test file individually, which is not what
`rake test` does. **277 of 283 files pass; six fail, and all six fail identically
on an unmodified `origin/main`.** Three of the six share one cause and it is
worth a fix:

    test/test_ast_omission_rule.rb        3 errors
    test/test_co_change_coupling_rule.rb  3 errors
    test/test_veto_pattern_rule.rb        1 error

Each is `NameError: uninitialized constant …Rules::AstOmissionRule`, and the
class is not missing — `AstOmissionRule` is in `lib/review/scan/rules/meta_rules.rb:9`,
`CoChangeCouplingRule` in `graph_rules.rb:128`, `VetoPatternRule` in
`yaml_bridge_rules.rb:8`. Zeitwerk maps one file to one constant, so a class in
a multi-class rule file is only defined once something loads that file, and the
tests name the constant cold. Proved both directions:

```ruby
Master::Review::Scan::Rules::AstOmissionRule   # NameError
Master::Review::Scan::RuleDSL                  # what InfraHelpers touches
Master::Review::Scan::Rules::AstOmissionRule   # resolves
```

**Fixed 2026-09-05.** The load is one line per file, `require
"review/scan/rule_dsl"`, which is what `test_smell_detectors.rb` already does.
That is where the interesting part started rather than ended: two of the three
then passed while asserting only that the rule responds to `check` and returns
an Array, which every `Rule` subclass does by inheritance. Erroring files that
become green files measuring nothing are worse than erroring files, because they
now read as coverage.

So both were rewritten against what the rules actually decide, with the
collaborator injected so neither needs repository history:

- **`co_change_coupling`** — its judgement is three filters, and each is asserted
  in both directions: a cross-module peer at the threshold is reported with its
  weight, one below it is not, a same-module peer is never reported however
  heavy (that is cohesion, the thing it must not flag), and only the heaviest
  three are named. Any ecology answering `co_change_graph` will do.
- **`ast_omission`** — a fake guard supplies the omissions, so the mapping, the
  two guard clauses and the rescue are all pinned. One assertion is that a
  non-Ruby path does not cost a git call at all, because a guard clause that
  returns empty and one that never runs look identical from outside.

Both were mutation-checked before being believed, per "a green first run is the
least informative outcome available". Inverting the module filter, lowering the
weight threshold, taking four peers instead of three, reversing the sort,
dropping the `.rb` guard, passing the absolute path instead of the relative one,
reporting only the first omission, dropping the last-seen date, and making the
rescue re-raise — nine mutations, nine caught. The veto test was already real
and catches a neutered `secrets` pattern.

#### `rule_coverage` examines one of sixteen rule files and is wrong about it

Found while checking whether that gate had been reading the three broken files
as covered. It had not, because it never looked at them.

`RuleCoverageRule` exists so that "every Rule subclass has a matching test file;
gaps mean untested enforcement". Two lines decide what it sees
(`lib/review/scan/rules/meta_rules.rb:66,69`), and each is wrong for this tree:

- It returns early unless the path ends `_rule.rb`. **One file in
  `lib/review/scan/rules/` does**, `law_bridge_rule.rb`. The other fifteen are
  `*_rules.rb`, plural — `meta_rules.rb`, `graph_rules.rb`, `ruby_rules.rb` and
  the rest — and are never examined. They hold nearly every rule class there is.
- For the one file it does examine, it globs `test/**/<base>_test.rb`. MASTER's
  convention is `test_<base>.rb`: **283 files match `test_*.rb` and 1 matches
  `*_test.rb`.** So it looks for a name this tree does not use.

Run over all sixteen, it reports exactly one finding —
`rule_coverage: no test file found for law_bridge_rule` — and
`test/test_law_bridge_rule.rb` is right there. Fifteen skipped, one false
positive, nothing correct.

**Fixed 2026-09-05.** It examines every `.rb` under `lib/review/scan/rules/`,
finds each `class XxxRule < Rule` in it, and asks whether any file in `test/`
mentions that class or its rule id.

Coverage is a mention rather than a file named after the class, and that is the
load-bearing choice. The tests that exercise these rules mostly do it in bulk —
`test_smell_detectors.rb` and `test_scan_rule_false_positives.rb` reach rules by
id through the scanner — so demanding a file per class would report those as
uncovered and rebuild the same false-positive machine pointing the other way.
The matcher is deliberately loose for the same reason: class name, id, and the
id in either case all count, so what it still reports is a real gap.

Cross-checked before it was believed. A hand census written separately from the
rule agreed on the same 14 classes, and six mutations are caught by
`test/test_rule_coverage_rule.rb` — including the exact regression to
`_rule.rb`, which was the old behaviour.

#### Every rule class now has a test — `rule_coverage` reads 0

Closed 2026-09-05, from fourteen. `RuleCoverageRule` came with the gate fix, the
four SOLID proxies with `test_solid_rules.rb`, and the last nine in one pass:

    test_structural_shape_rules.rb  FileLayout, CyclomaticComplexity, DataClass, MiddleMan
    test_feature_envy_rule.rb       FeatureEnvy
    test_path_purpose_rule.rb       PathPurpose
    test_interconnect_rule.rb       Interconnect
    test_comment_drift_rule.rb      CommentDrift
    test_yaml_declarative_rule.rb   YamlDeclarative

All in the house shape — a source the rule must flag and a source it must not —
and every threshold pinned from both sides, because a boundary is where a rule
is most likely to be off by one.

**Three tests passed for the wrong reason and were caught by mutating the rule
they cover.** That is the entire value of the practice and it is worth keeping
the examples:

- `FEATURE_ENVY`'s counterweight test used four neighbour calls, which is below
  the rule's floor of five — so the floor exempted it and the counterweight was
  never consulted. Deleting `count > local` from the rule left the test green.
- `CYCLOMATIC_COMPLEXITY`'s boolean-operator test used ten terms, which is nine
  operators and lands exactly on the limit rather than over it. The rule was
  right and the test was wrong.
- `CommentDrift`'s invented-index test asserted that a bad index yields nothing,
  which is true either way: with the bounds check because the pair is nil,
  without it because the resulting `NoMethodError` is swallowed by the rule's own
  rescue and takes every finding in the file with it. Asserted now with a real
  index beside the invented one, which is what separates a guard from a crash.

**One mutation is knowingly uncaught.** Turning
`return [] if note_model_failure(e)` into a bare `return []` changes only a
quota trip and a log severity; both paths return no findings, and the difference
is invisible from outside. Asserting it would mean reaching into the rule's
internals. Recorded rather than faked.

`YamlDeclarativeRule` got the treatment its special case needed rather than a
test that passes because there is nothing to do. The mechanism is proved against
a rules corpus written for the purpose, and the live corpus's emptiness is a
separate, dated assertion: **the day somebody declares a `detect_lexical` again,
that test fails and asks whether the bridge is still wanted**, instead of the
rule staying a path nothing takes.

#### The four SOLID proxies fire on almost nothing, and one half of one could not fire at all

Measured 2026-09-05 over **2,470 Ruby files across all four trees**, which is a
wider corpus than `rule_audit`'s 713:

    OPEN_CLOSED            3     RAILS/brgen/app/helpers/application_helper.rb:400 and two others
    LISKOV                 0
    DEPENDENCY_INVERSION   0
    INTERFACE_SEGREGATION  0

Three of four silent, and until `test/test_solid_rules.rb` nothing could tell
which of the two readings was true — the tree has none of these shapes, or the
detectors cannot see them. A rule that cannot see its subject is indistinguishable
from a rule with nothing to report, which is the whole reason `rule_audit`
carries a `silent` ceiling. **Settled: all four fire on a source built to violate
them**, so the silence is the sample. `LISKOV`'s zero is largely structural — it
only sees a parent declared in the same file, and almost every subclass here
inherits across files. That limit is pinned as a test of its own so the silence
is never read as a clean bill of health.

**`OPEN_CLOSED`'s `is_a?` clause had never fired**, and could not. `TYPE_CHECK`
was `/\b(is_a\?|instance_of\?)\b/`, and a trailing `\b` needs a word character
beside it while `?` is not one — so it required a word character immediately
after the question mark, which no call site has. `is_a?(Header)` and `is_a? Header`
both continue with a non-word character and both failed. So half of what the
description promises, "case/when **or is_a? chains**", was dead from the start.

Fixed by dropping the trailing boundary, and the fix is free: repo-wide findings
go 3 → 3, because no `case` anywhere dispatches on `is_a?` across three or more
branches. The leading `\b` stays and does real work, keeping `foo_is_a?` out.

This is the same trap already recorded twice in this file — `TODO.md` read as a
work marker because `\b` holds between the `O` and the dot. **Any `\b` next to
punctuation is worth re-reading**; it is the third time it has cost something
here.

**`rake test` cannot complete on a dev Mac at all**, which is why three dead
test files went unnoticed. Its loader aborts on `cannot load such file --
rack/test` from `test/test_web_ui.rb` before running anything, because the web
Rails bundle is not installable here — `Could not find rails-8.1.3.1 …` in both
checkouts. So the local signal for "do the tests pass" has been a task that
stops before it starts. Run the files individually until that is fixed:

```zsh
for f in test/**/test_*.rb; do ruby -Ilib -Itest $f; done
```

The other three failures are separate and pre-existing: `test_reach_exec.rb`
(1 error), `test_security_sweep.rb` (1 failure), and `test_ratchets.rb`, which
is the record below.

**All but `test_ratchets.rb` are closed, 2026-09-05.** `test_reach_exec` was
`Io::Exec` calling `Swallow` without requiring it, so the timeout path raised
NameError instead of killing the process group it exists to kill — the same
defect `ground/swallow.rb`'s own header records for `replicate_client.rb`, on
the file next to it. `test_security_sweep` was the sweep reading
`$FLOW_AMBER_PASSWORD` in `RAILS/gates/data/flows.yml` as a leaked credential; a
value that is nothing but an indirection names where the secret lives. Two more
went red in the meantime and both were the test rather than the code —
`test_scanner`'s doubles spelled a `scan_one` signature that had gained three
keyword arguments, and `test_source_assertions` counted two additions its
pattern cannot tell from the thing it hunts. The suite reads 290 of 291 files —
three fewer than the morning because `lib/autonomy`'s three tests went with it.

One red file sat outside that glob and was not counted by it.
`spec/smoke/static_syntax_spec.rb` failed on
`data/radio_bergen_track_dossiers.yml`: it carried bare Ruby symbols
(`drum_preset: :madlib_dusty`), and `Boot::Data.load_yaml` permits only Date and
Time, so MASTER could not read a file in its own data directory and
`Master.validate_data!` warned about it on every boot.

**Closed 2026-09-07.** The blocker recorded here was that quoting the values
would be a lossy edit to dilla’ data by somebody who does not own it. It is not
lossy, and the reason is in dilla: `write_dossiers!` builds the file with
`stringify_keys`, which stringifies keys and leaves values alone, so the
`drum_preset` symbols in the `RADIO_BERGEN_TRACKS` table reached YAML by
omission rather than by intent. Nothing reads the dossier back — `DOSSIERS_PATH`
appears twice in `dilla.rb`, at the constant and at the writer — so a symbol
there carries nothing a string does not. The writer deep-stringifies now, and
`write!` beside it is deliberately left alone: its output *is* read back, with
`permitted_classes: [Symbol]`.

`Master.validate_data!` is clean and `data_reach` reads the file. Reading it
costs two keys nothing names, `cross_track_learnings` and `tracks` — the dossier
is a report, not configuration. With three recorded members gone
(`agent_taxonomy.yml#toolset_groups`, `doc_baselines.yml#doc_paths`,
`models.yml#three_mirror_redundancy`) and three arriving from
`pub_archive_restore.yml`, the ceiling is 35 → 37. **A census that cannot parse
a file reports it clean**, so the two keys are worth more than they cost.

#### The over-ratchet list is not stable, and that is the finding

`test/test_ratchets.rb` names them. It read three on 2026-09-04, five later the
same day, and six on 2026-09-05. The current list is in **Still open after this
session** above; do not read a count from any of them — read it from
`MASTER/bin/pub4 measure`, which prints every row with its ceiling and names the
slack ones too.

What is stable is the shape: `spine.lib_body_ceiling` and the four `growth.*`
rows move with every session in a shared checkout, and each needs a fold rather
than a raise.

Two ceilings were slack rather than over and are now at their number.
`autofix_reach.dangling` sat at 7 above a real 0 — room the next change grows
into silently — and was lowered when `efc96832f` emptied it. `reader_singularity`
carried `agent_taxonomy.yml: 2` after that file's three readers became one.

Two more rows joined the ratchets on 2026-09-05, both of them numbers that
already existed and gated nothing: `rule_hygiene.cross_population_duplicates`
(20) and `rule_deps.ungraphed` (133).

#### Three rules say one thing in `rules.yml` and another in `law/`

`rule_hygiene.statement_conflicts`, opened 2026-09-06 when
`cross_population_duplicates` turned out to be counting the architecture: an id
lives in the catalogue and in its implementation by construction, and thirteen
of the twenty it reported were a `detect_semantic` prompt beside a lexical
detector, which is one rule at two depths. Eleven of the fourteen conflicts it
found were a catalogue `fix` carrying an older draft of what its law enforces,
and those now carry the law's wording; three severities moved the other way,
to what the catalogue declares.

**The three left are the constitution's wording, which is the owner's.**
`BE_CONCISE`, `PRESERVE_FIRST` and `SIMPLEST_WORKS` each have a soul-derived
`practice` in `law/practice.rb` saying something other than the kernel rule of
the same name: `BE_CONCISE`'s practice is "minimal response", about the voice,
against "omit needless words, omit needless code", about the source;
`SIMPLEST_WORKS`' practice is "refuse to create god classes", which is
`NO_GOD_CLASS`' subject and severity. Resolving one deletes or renames a
statement that reaches the system prompt.

#### The three `growth.*` overages, itemised — 2026-09-06

`spine.yml` says a raise must name each file it makes room for, and the rows
have been red for days with nobody naming anything. Each tree is diffed
against the commit that last set its ceiling, so the overage arrives as a list
instead of a number:

    ruby -e 'EXCLUDE = %r{/(\.git|node_modules|tmp|log|renders|[\w.-]*stems|samples|scratch|project|crate|venv|\.venv|site-packages|vendor|storage|\.cache|builds|coverage|\.master|knowledge|output)/|/public/assets/|\.wav\.quality\.json\z}
      EXT = %w[.rb .rake .erb .scss .css .js .mjs .yml .yaml .md .sh .ksh .exp .html .json]
      now = Dir.glob("STUDIO/**/*").select { |p| File.file?(p) && !p.match?(EXCLUDE) && EXT.include?(File.extname(p)) }
      was = `git ls-tree -r --name-only 9ea74b3d7 STUDIO`.split("\n").select { |p| !p.match?(EXCLUDE) && EXT.include?(File.extname(p)) }
      puts (now.sort - was.sort)'

**`growth.studio` 150/138, twelve over.** Fifteen files arrived and three
left. Ten of the fifteen are `dilla/live/` — `rack.rb`, `recall.rb`,
`dig_crate.rb` and `dig_crate.sh`, `broadcast.sh`, three `*.als.rb` Ableton
writers, plus `lib/sample_worth.rb` and `scripts/generate_tts.rb`. Three are
tests (`test_dilla_crate_dig.rb`, `test_dilla_radio_bergen_study.rb`,
`test_dilla_take_write.rb`), one is `STUDIO/isolation.rb` moved up from
`tools/`, and one is `lora/_toolkit/toolkit.sh` replacing `lib.sh`. A live
performance surface is a coherent thing to have grown; it wants one named
raise from whoever built it, not twelve arguments.

**`growth.rails` 2371/2358, thirteen over.** Thirty-three arrived and twenty
left, and most of both sides are the same files: the test trees were flattened
(`test/helpers/x_test.rb` to `test/x_test.rb`) across amber, brgen, bsdports
and shared. What is genuinely new is thirteen — `authorization_matrix_test` in
two apps, `deal_test`, `city_seed_test`, `mention_test`, four
`RAILS/test/*_lint_test.rb` gate tests, `gates/lib/source/scale_ratchet.rb`,
`gates/support/css_spacing_scans.rb` and `css_weight.rb`, and
`shared/lib/pub4/master_design.rb`. Every one of them is a test or a gate
support file, which is the shape `spine.yml` has raised for before.

**`growth.master` 1050/1047, three over.** Twenty-four arrived against thirty
gone since `a931c5f0f`, so the tree is six files smaller than when the ceiling
was set and still three over the number — the ceiling was lowered below the
measurement on purpose, and the note in `spine.yml` says so.

One instrument fix landed with this: `TREE_EXCLUDE` matched a directory named
exactly `stems` and dilla names them after the render, so `demo_stems/` and
`loop_stems/` put five `session.json` and `motifs.json` sidecars into
`growth.studio` — a stems render raised a source-file ceiling, and 155 was
really 150. The same five files are now ignored where they are written, beside
the sidecar rule `dilla/.gitignore` already states and had not generalised.

**Closed 2026-09-07, and the count now asks git.** `TREE_EXCLUDE` had been
growing one clause per incident — `renders`, a stems glob, the
`.wav.quality.json` sidecar — and a name-shaped regex cannot catch a sidecar
sitting at a tree’s root, which is where the next one landed.
`tree_source_count` runs one batched `git check-ignore` per tree now: the
repository already declares every generated and scratch path, so the census
reads that declaration instead of guessing at directory names. The regex stays
for what git tracks and we still should not count — vendored JavaScript,
compiled asset builds, dilla’s `project/` state and its committed renders.

Two things fell out of it. `growth.master`’s long-standing +1 was
`MASTER/runtime/rtk_stats.json`, untracked runtime state `MASTER/.gitignore`
has always listed — the census was counting a file the repository had already
disowned. And the `log` clause, written for Rails log directories, had been
hiding three tracked Ruby files at `lib/trace/log/`: `audit.rb`, `event.rb`
and `evidence.rb` were invisible to the sprawl census for as long as it has
existed. Every clause added to catch generated output had shadowed something
real, which is the argument for asking git rather than adding a fourth.

The three ceilings are raised with each file named in `spine.yml`: MASTER
1047 → 1050 (the three the regex hid, a correction rather than growth), RAILS
2358 → 2371, STUDIO 138 → 150. All four `growth.*` rows read `at`.

**`growth.rails` taxes a test at the rate it taxes sprawl.** Eleven of the
thirteen RAILS files are tests, and the row cannot tell one from a new god
class. The fix is two rows per tree, source and test, so sprawl stays resisted
while coverage is free to grow. Forward work, not made here: splitting a
ratchet re-bases four ceilings and wants its own sitting.

**`dilla/live/` is eight files and reads like one subject** — `rack.rb`,
`recall.rb`, `dig_crate.rb`, `dig_crate.sh`, `broadcast.sh` and three
`*.als.rb` Ableton writers. Folding it is the obvious win and it is not mine
to take: these render real audio, and this repo says not to reshape a
rendering tool on an outsider’s judgement. It belongs to dilla’s owner.

#### The spine budget cannot be paid by deletion — measured 2026-09-08

`spine.lib_body_ceiling` is 977 over and has been for weeks. Before arguing
about a raise, the question worth asking is whether any of `lib/` is dead.
**None of it is.** `tools/code_reach.rb` asks of a file what `data_reach` asks
of a declaration: under Zeitwerk a file runs when its constant is named, so a
constant nothing names is a file nothing runs. It reads 0 of 426, and the row
exists to hold it there.

**The census was wrong twice before it was right, and both were the same
family of mistake this file already records.** The first version whitelisted
file extensions, so `bin/cli` and the `Rakefile` were invisible and two live
files read as dead. The second excluded `:` from its lookbehind, so every
caller writing `Ground::BootChecks` was invisible and it reported thirteen
files — 975 lines, against a 977-line overage, which is exactly the kind of
coincidence that should stop you. The tree was quarantined to test it and the
runtime refused to boot on `Ground::BootChecks.run(root:)`, a call the census
had just declared absent. `\b` after a `?`, a lookbehind excluding `.`, a
lookbehind excluding `:` — three now, all the same shape.

Both traps are fixtures in `test_code_reach.rb` and both go red under mutation.

So the 977 is real work in real files, and the payment is collapse or a
sponsored raise. `spine.yml` allows one more raise before a fall must earn the
budget back, and no single change can name what 977 lines buy — which is why
this row stays red rather than being priced.

#### `cohesion_census` was the last census recording a bare integer — 2026-09-07

`rake lint:cohesion` read 33 against a ceiling of 30 and said *a new family
appeared*. It could not say which. `data_reach`, `self_findings` and
`dup_census` all record their members beside the count; this one recorded
`families: 30` and nothing else, so naming the arrival meant checking out
`3e4afd50b`, running the whole census again, and diffing by hand. It now
records `dir#family` members, seeds them at parity as well as on a fall, and
prints what arrived and what left when it goes over.

**The overage is closed, three families at a time.** Two were `MASTER/lib/cli`,
and the tool had written the plan: `scan_live.rb + scan_report.rb +
scan_request.rb` regrouped into `cli/scan/` as `Scan::Live`, `Scan::Report` and
`Scan::Request`, and `through_pipeline.rb + turn_pipeline.rb` into
`cli/pipeline/` under the class that was already their parent. Fifty-four
references across fifteen files, and the suite is the proof.

The third was `RAILS/gates/support#design`, and it was made by a hoist.
`5f3580ec9` lifted `design_metrics/contrast.rb` to the top level because the
directory held one file — correct by the lone-directory rule, and it put a
third `design_metrics*` file beside `design_metrics.rb` and
`design_metrics_contrast_checks.rb`, which is a family. **The two censuses pull
against each other**, and `code_metrics.rb` already says so about spine and
cohesion. The answer here was not the tool’s plan — it proposed
`Contrast -> Design::MetricsContrast`, which breaks `DesignMetrics.extend
Contrast` and stutters — but the directory the hoist emptied: `contrast.rb` and
`contrast_checks.rb` go back into `design_metrics/`, where the constants
`Deploy::DesignMetrics::Contrast` already match the path, and the directory now
holds two files rather than one.

`cohesion_census` reads 30 against 30 with its members recorded, so the next
arrival names itself.

**The regroup cost four body lines to a budget already 973 over**, and they are
charged here rather than hidden. `code_metrics.rb` excludes a `module` wrapping
one module or class as loader ceremony and deliberately does not excuse a
`class` doing it — `Pipeline` is a class, so `pipeline/through.rb` and
`pipeline/turn.rb` pay two lines each. That is the tension the file describes,
not a leak in it.

Two indentation faults went with it: `roots_for` and `census_dirs` sat at
column zero inside the module, and seventeen lines of `test_cohesion.rb` sat
one level out of the class.

#### The TTS probe fix is paid for out of two budgets that were already over

Named rather than buried, because `limits.yml` says a breach is paid by
extraction or deletion and this one is not. `edge_tts_ready?`, the memo and the
worker probe add **35 body lines to `lib/voice`** (3330 → 3365 against 3181) and
the same 35 to `spine.lib_body_ceiling`. No ceiling was raised.

The honest reason it is not paid, corrected 2026-09-05: it is not a Transcendent
deletion waiting for an owner. That reading came from the **Inert law and config**
entry, which has been re-measured and no longer supports it — `Playback` calls
`Speech.synthesize` for every spoken CLI reply and `bin/tts-speak` calls
`Transcendent.synthesize`, so the "1,500 unreached lines" are the code MASTER
speaks with. `synthesize_bytes` is the one method tests reach and nothing else
does.

So `lib/voice` is over its budget with no dead weight in it, which makes this an
extraction rather than a deletion, and a real sitting rather than a decision
somebody can make in a sentence. `speech.rb` at 475 and
`personality_prompt_builder.rb` at 390 are where to open it. Taking 35 lines out
of somewhere unrelated to make the number look right would be the accounting the
budget exists to prevent.

#### The 2026-09-05 pass costs `growth.master` two files and `growth.studio` one

Same accounting, named for the same reason. Five gates gained the tests this
file kept asking for — `rule_hygiene`, `autofix_reach`, `SemanticRule`'s
language scope, the registry audit's shipped-rule filter, and `Consensus`'s
model pool — and the two tool tests were written as one file rather than two,
because they read one subject. `test_semantic_rule_scope.rb` and
`test_consensus.rb` are the net additions to MASTER. STUDIO's is
`test_dilla_radio_bergen_study.rb`, which MASTER lost in the same move, so the
repo total is unchanged and the two trees traded a file.

`lib/` came out level: the `visit` extraction returned 33 lines and the fifteen
rule fixtures, the `three_mirror_pool` accessor and the language scope spent 35,
so `spine.lib_body_ceiling` reads 2 above where the session opened and
`lib/review` 5 below.

#### Instrument notes

- **There is no `edge-tts` binary to look for, and the gem is spelled with
  hyphens.** MASTER never shells out to an `edge-tts` executable — it runs
  `bin/tts-worker` under its own bundle, and the dependency is the Ruby gem
  `rb-edge-tts`, pinned to a git source in the root `Gemfile` at 1.0.1. Two
  checks said TTS was unavailable here and both were the instrument: `command -v
  edge-tts` looks for something that never existed, and a grep for
  `rb_edge_tts` misses `gem "rb-edge-tts"` because the require spells it with
  underscores and the Gemfile with hyphens. The ground truth is one command —
  `echo hi | ruby bin/tts-worker en-GB-RyanNeural +0% +0Hz /tmp/x.mp3` — and it
  writes a real MP3.
- **A lint that checks a basename cannot see a namespace.** `rake autoload` was
  red and `rake lint:autoload` called the same file clean. The three files under
  `lib/review/scan/engines/` declare `Master::Review::Scan::PathFilter` and the
  directory implies `Scan::Engines::PathFilter`, so eager loading raised on a
  name the lint approved: it matched `module <Basename>` anywhere in the file
  and never asked at what nesting. It compares the whole path-implied constant
  now. All 45 ignores still measure as necessary under the stricter reading,
  which is the check that the fix did not just widen the hole.
- **`rake mutate` chose its candidates with a regex over the file text**, so it
  read a numbered list in a comment and the 8 in `"UTF-8"` as integers, and
  `sub` then rewrote the first match anywhere rather than the one in the code.
  Three well-documented files reported eight survivors for mutations no test
  could see. It walks Prism's token stream now and names the line each mutation
  is on. Same shape as every other entry here: the instrument, not the finding.
- **`rake selfcheck` reports a count with no locations.** `SelfCheck::Report`
  exposes `total`, `by_rule`, `by_severity` and `error` and no findings list, so
  the gate can say "7 violations across 3 rules" and cannot say where. Acting on
  it means re-running the scanner by hand. `ERROR_CONTEXT` is the rule it fails:
  an error must carry enough context to locate its origin. The task also prints
  its own label twice — `selfcheck: selfcheck: 7 violation(s)`.
- **Getting the locations by hand needs two unwraps and a Hash.** `Scanner#scan_dir`
  returns `Result::Ok([[path, Result::Ok([...])], ...])` and the findings inside
  are plain Hashes with symbol keys, not `Finding` objects — `f.rule` raises,
  `h[:rule]` works. Three attempts died on that before the count matched the
  gate's. Anyone writing a one-off census over the scanner should start from:

  ```ruby
  pairs = sc.scan_dir(File.join(Master::ROOT, "lib")).value
  all = pairs.flat_map { |path, res| Array(res.value).map { |h| h.merge(path:) } }
  ```

- **`tools/data_reach.rb` cannot tell which file a reader opened.** Its test is
  whether the key name appears anywhere in first-party code, so `success_criteria`
  counted as reached for as long as it existed — `lib/ground/phase_gates.rb:133`
  names it, reading session state rather than `rules.yml`. The 35 at the ceiling
  is a floor on the real number, not the number. The 2026-08-12 entry above
  already explains why a stricter version is not buildable; this is the direction
  of its error, which that entry does not state.
- **Two sweeps for the bug shapes `style.ruby.bugs_to_avoid` names found
  nothing, and one instrument was wrong.** No `@bus&.publish(...) || value` in
  `lib`, `bin`, `web` or `tools`. The only `Dir.chdir` is `bin/master:74`, which
  is the documented cause of the `/scan RAILS` path trap already recorded above.
  Four `next if` inside a `flat_map` turned out to be four `filter_map`s
  (`graph_retriever.rb:37`, `repo_ecology.rb:373`, `command_guard.rb:25`,
  `snapshot/collector.rb:99`) — `filter_map` drops the nil correctly, and a
  proximity-based grep cannot tell the two apart. Do not re-list them.
- **"A test that never names a `Master::` constant" is not a hollow-test
  detector.** It flags 38 files, and the bulk are gates that legitimately read
  files rather than constants — `doc_paths`, `doc_numbers`,
  `constant_collisions`, `security_sweep`. Same false-positive rate as the dead
  file census. The one hollow test found this session was found by reading the
  subject, not by a pattern: `test_fix_loop_priorities.rb` above.
- **The rule-id census is settled, and the earlier three answers are all
  explainable.** Build the scanner and read `@rules` — that is the collection
  `RuleOrder` receives from `ai_boot.rb:122`, and `r.id` is a `String`. It holds
  145 ids. A `Rule.registry` walk gives 142 because bridge classes are rejected;
  a regex over `law/*.rb` and `lib/review/scan/rules/*.rb` for `Law.define(:X)`
  and `RuleDSL.rule :x` gives 215 with mixed case, which is what
  `tools/rule_hygiene.rb` uses and why its numbers differ. All three are correct
  for their own question. For "does this key weight anything", only the first is.
- **Five rules carry no detector and no obvious class, and all five are
  accounted for** — do not re-list them. `WHITESPACE_PUNCTUATION`,
  `KEYWORD_ARGS`, `BARE_RESCUE` and `MESSAGE_CHAIN` each carry `folded_into:`
  naming the rule that reports for them, and `PROSE_OMIT_QUALIFIERS` is generated
  by `law/prose.rb` from the `prose.en.ids` mapping rather than declared.
- **`success_criteria` looked live and was not.** `lib/ground/phase_gates.rb:133`
  reads `@state["success_criteria"]`, and `@state` is loaded session state, not
  `rules.yml`. A grep for the key name finds the file and says nothing about
  which document it came from.

### MASTER cannot be asked to read a file — closed 2026-09-05

Two causes, both closed. `IntentRouter` classifies `read CLAUDE.md` as
`inspect_repo`, so it is not casual. Local CLI is the operator surface and no
longer sets `Fiber[:master_visitor]` for a missing `web_token` — that flag is
web-request only. Pipe mode honors ARGV. `Tool::Profile` reads
`agent_taxonomy.yml#toolset_groups`. Visitors on ai.brgen.no still cannot reach
the Fold.

### Tooling I wanted while doing the work above — 2026-09-05

Written from one long session spent inside the rule system: the rules file, the
fix loop's ordering, the coverage gate, the TTS probe, and tests for fifteen rule
classes. Every item is something that cost time in that session rather than
something that sounds good, and each says what it cost. Two candidates were cut
on checking, which is the point of checking: `bin/pub4 measure` already prints
every ratchet with its ceiling **and** names slack beneath one, so both wishes I
had about ratchets were already built. Read that command before wishing for
anything in its neighbourhood.

They are ordered by how much time each would have saved.

**1. A mutation harness — done.** `rake mutate[lib/foo.rb,test/test_foo.rb]`
flips comparators, nudges integers, inverts reject/select, runs the test,
restores. Survivors fail the task.

**2. One documented way to get findings out of the scanner — done.**
`Scanner#findings(paths)` returns a flat array of hashes with `:path`.
`tools/example_scan.rb` is the worked example. `scan`/`scan_dir` still return
the nested Result shape.

**3. `rake test` that runs on a dev Mac — done.** `test_web_ui.rb` sits with
`test_browser.rb` and `test_web_http.rb` behind `rake test:web_ui`. The default
glob no longer aborts on `rack/test`.

**4. Locations in every gate's output — done for selfcheck.** The report carries
findings with path and line, and the task prints that summary once.

**5. `bin/pub4 rule <ID>` — done.** `--corpus MASTER|all` and optional paths.

**6. A lint over the rule corpus's own regexes — done.** `rake lint:word_boundary`
flags `\b` glued to escaped punctuation. Currently clean.

**7. Every registry rule proves it can fire — closed 2026-09-06, 91 to 0.**
`law/` has always refused to load a rule without worked fixtures and the
registry accepted one without; `rule_fixture_debt` is the row that closed the
gap, and `test_rule_fixtures.rb` fails when the count rises, so a new RuleDSL
rule must carry `fires:`/`does_not_fire:`.

Two lessons are worth keeping, and both are in the rules themselves. A fixture
that passes for the wrong reason is what this ratchet exists to stop —
`TYPOGRAPHIC_EXCELLENCE`'s first draft, `warn "loading..."`, did not fire,
because the rule reads a bare quoted ellipsis and that is prose containing
dots. And a rule whose subject is a forbidden shape can still hold its own
example: `SILENT_RESCUE` reads a line that *starts* with `rescue`, so an
escaped one-line string is a worked example everywhere and a finding nowhere.
This file twice recorded that as impossible.

**8. One class per rule file — documented.** `AGENTS.md` now says
`require "review/scan/rule_dsl"` is the load that defines a class in a
multi-class rule file. Zeitwerk still maps one file to one constant.

**9. A finish-the-worktree command — done.** `bin/pub4 worktree finish` rebases
onto origin/main and pushes the branch. It does not merge to local main and
does not push main.

**10. A gate on the test-naming convention — done.** `rake lint:test_naming`
asserts MASTER/test is `test_*.rb`, not `*_test.rb`.

**11. Progress on the long gates — done for the two long runners.**
`RAILS/gates/runner.rb --all` prints `N/M name`. `bin/pub4 gate` prints
`gate: N/M stage`. Individual suites inside a stage are still silent.

**12. `data_reach` same-file check — done.** It reports keys named in code that
never mentions their yaml file, separately from the unnamed ceiling.

**13. Facts that are not rules — done.** They live in `MASTER/AGENTS.md` under
Working alone: scanner findings hashes, bundler/setup rewriting the lock,
Zeitwerk multi-class.

## RAILS
### Parity gaps — forward work

What brgen would need to read as a peer of TikTok, Snapchat, Mastodon, x.com,
Reddit, Craigslist and Facebook, and its verticals as peers of
Amazon/Temu, Tinder/Hinge, DoorDash/Foodora and Messenger. The former
`RAILS/TODO.md`.

This is **not** a second feature inventory — `apps.yml` is feature truth and
the horizon subsection below holds the aspirational items. Everything here is a
gap those two do not record. It carries its own caveat, which still stands:
several entries were stale within a day of being written (price-drop alerts,
takeaway push, the courier/event/story map layers were all built while this
list still called them open). **A finding is a hypothesis; re-measure before
working from one.**


Scope is brgen and its engines. amber and bsdports are not measured against
consumer apps, and their planned work stays in `apps.horizon.yml`. Paths below
are relative to `RAILS/`.

Verified against the tree on 2026-08-19. The reason a gap can exist at all is
that `apps.yml` records a feature as `done` when the model exists, and several
of those models exist with nothing reading or writing them.

---

### Cross-tree session records, filed here by mistake

Four of the five records below belong to MASTER, STUDIO and OPENBSD, not to
RAILS. They were appended under the Tier 1 heading, which promises a schema
nothing reads, and they describe census tools, a STUDIO gate, nine expired
domains and the `/through` stages instead. Only the `constitutional_scan`
budget record is a RAILS gate's. Moving them means editing three other trees'
sections while their agents are in this file, so they are named here and left
where they sit.

#### A census of the census tools: two of thirty-six were reaching nothing — 2026-09-07

Asked of every `MASTER/tools/*.rb`: does anything in the repo name it? Twenty-nine
are named by a Rakefile task, a test, a gate, `bin/pub4` or a workflow. The
first pass called eleven unreferenced and **that pass was wrong about five of
them** — it searched for the string `tools/<name>` and the Rakefile spells its
shell-outs `File.join(__dir__, "tools", "<name>.rb")`. Verify the instrument
before the finding, again, and this file's own rule paid for itself inside ten
minutes.

Two were real:

- **`tools/load_order.rb` — deleted.** It guarded dilla's `ENGINE_PARTS`, an
  81-file manifest whose order was load-bearing. The engine is one file now,
  and `engine_sources.rb` says so in its own comment: "Two ways the list could
  lie went with the split … Neither is expressible any more." The tool's regex
  finds no manifest, so it reported "0 manifest entries, every load-time
  constant is defined above its reader" — a clean verdict over an empty set,
  which is the shape STUDIO's own gate test was failing on an hour earlier.
- **`tools/agent_context.rb` — wired.** It prints the law in force in 691
  bytes: the 29 rules that can refuse a write, and how many run without a
  model. That is wish 45 of the list below, already built and named by
  nothing, so it is now in the agent contract every harness file is generated
  from.

`growth.master` is **1048/1047** after this and the doc_paths deletion — one
file over, from three this morning, and both deletions were of instruments
whose subject had retired rather than of anything anyone reads.

#### Two censuses over one subject, and the copy was the unrun one — 2026-09-07

`MASTER/tools/doc_paths.rb` and `MASTER/test/test_doc_paths.rb` both asked
whether a repo path a document cites still exists. The test is run by
`rake test` and by `tools/todo.rb`; **nothing ran the tool** — no Rakefile
task, no gate, no bin script names it — and it carried no baseline, so it
reported eight dead paths of which seven were exemptions the test already
holds in `data/doc_baselines.yml`, each with its argument written out.

The tool is deleted. Its wider sweep is kept where it belongs: the three
documents it covered and the test did not — `MASTER/EXAMPLES.md`,
`OPENBSD/DECISIONS.md` and `OPENBSD/SSH_ACCESS.md` — are in the test's `DOCS`
list now, and all three are clean under it.

The eighth finding was real and is fixed. `OPENBSD/DECISIONS.md` said legacy
path strings "still resolve via `MASTER/lib/pub4/paths.rb`", in the present
tense, about a file that does not exist; they resolve through
`RAILS/shared/lib/pub4/deploy_paths.rb`, which is what `Pub4::DeployPaths` is.
A decision record making a live claim about a missing file is the shape this
guard exists for, and it took an unrun tool to find it.

`growth.master` 1050 → 1049 and `self_findings.registry` 52 → 51 come with the
deletion: one fewer file, one fewer `NO_GOD_CLASS` subject.

#### The STUDIO and OPENBSD suites, run and read — 2026-09-07

Both were run end to end for the first time in this session's memory. They are
the two trees whose tests nothing in MASTER's `rake test` reaches.

**STUDIO's gate declared a tree that no longer exists — fixed.** `gate.rb`'s
`TREES` carried `tools/**/*.rb`, and `STUDIO/tools/` went away at `5a18c40d7`
when `isolation.rb` was hoisted to the STUDIO root. Its own test says what that
costs — "a glob that matches nothing passes every check in the file while
covering nothing" — and it was failing on exactly that. The `gate` entry's
`*.rb` already covers both root files; the dead entry is gone and the owner
line names them.

That unblocked the rest of the suite, because `rake test` aborts at the first
failing sub-suite. What it reached next is real and is dilla's owner's:

**124 hand-cut sample loops have no track preset, so nothing renders them.**
`test_every_hand_cut_sample_loop_is_reachable_as_a_track_preset` says why it is
a test rather than a comment: a loop reaches a render only when a TRACK name
resolves to it, so one with no preset and no alias is selectable by typing
`TRACK=<slug>` by hand and never appears in the medley or the rotation. Nothing
errors. The test was written when three of four measured loops were in that
state; the crate has grown since. Naming 124 presets is authoring, not repair —
it is a musical decision per loop, and this repo's own rule is that a
rendered-sound default is never changed on an agent's judgement.

**OPENBSD is nine suites green and one red for money.** `test_domain_expiry`
fails on nine domains past their expiry date, measured 2026-09-07: brmingham.uk
and glasgw.uk 75 days, lverpool.uk and mnchester.uk 74, dnver.us 66, cardff.uk,
denvr.us and edinbrgh.uk 25, wshingtondc.com 16. Renew at the registrar, then
`OPENBSD/bin/domain_watch.rb --update` refreshes the snapshot. Nothing in the
repo can close this one.

#### One verb with named stages, and all four trees under it — 2026-09-06

Two changes, one subject: what the runtime offers and what it reads.

**The verb.** `command_registry.rb` has carried a closed public surface for
months — its own comment says "Scan/fix/critique stay as methods
ThroughPipeline calls; they are not slash verbs" — so the fold was already
done and nobody could tell, because `TurnRouter.rewrite_slash` mapped every one
of those words to a bare `/through`. Asking to scan ran the fix loop, the
council and the principle map.

Each word now carries the stage it names. `/scan` is `/through --only scan`,
`/critique` and `/council` are `--only critique`, and the words that mean the
whole pass still mean the whole pass. **The scan stage fixes what it finds, on
the spot**, which is why `/scan` and `/fix` name the same stage: a finding is
cheapest to repair at the moment it is found, and a fix loop with no scan in
front of it has nothing to act on. `--no-autofix` and `--dry-run` still hold it
back, which is what `bin/gate` and the RAILS gate pass.

An unknown stage runs nothing and says so. Silently widening a pass because a
flag was misspelled is the failure the flag exists to prevent, and silently
narrowing one is the same failure wearing the other coat.

**The trees.** `constitutional_scan` scanned the Rails half only, so STUDIO's
155 source files and OPENBSD's 107 were governed by a law that never opened
them. It runs all seven targets now — brgen, amber, bsdports, shared, STUDIO,
OPENBSD, MASTER — in **184 seconds**, which is the same gate that cost 48
minutes for one app this morning.

Recording the three new ceilings turned up the instrument defect underneath
them. The gate reads the first `scan: done` line, and that line has two
spellings: `6 violations` and `clean -- no violations`. The count regex knew
only the digits, so a target whose aesthetic pass is clean fell through to the
**deep** pass's number — STUDIO read 317 and OPENBSD 72 against ceilings
measured at 0 in the same run that printed "clean". A target was being judged
on a different profile than its neighbour depending on whether its first pass
found anything. Both spellings count now, and the budget file says in its own
head that every number in it is the aesthetic profile.

Where the seven stand: STUDIO 0/0, OPENBSD 0/0, MASTER 15/15, brgen 15/27,
amber 4/28, and the two that were already over — bsdports 6/3 and shared 15/8,
whose findings are spacing and colour values in a design its owner drew.

#### `constitutional_scan` was unaffordable, and two of its four budgets are over

The gate shells `/scan` at `MASTER/bin/cli` once per app, and `SAFE_ENV`
disabled autofix, background, watch and heartbeat but never asked for the
deterministic tier — so the runtime handed the scan an agent and every file
cost a model round trip. Measured 2026-09-06: **brgen alone ran 48 minutes of
wall clock against 35 seconds of CPU**, idle in a TLS read, which is the exact
stall `MASTER_SCAN_DETERMINISTIC` was added to MASTER for. `capture2e` has no
timeout, so there was no bound on it either. With the flag and a
`GATE_SCAN_TIMEOUT_S` bound, all four targets finish in **113 seconds**.

What that uncovers is the part that matters. The gate has been failing, and
nobody could see it because nobody could run it:

    brgen      15 / 27   under
    amber       4 / 28   under
    bsdports    6 / 3    OVER +3
    shared     15 / 8    OVER +7

Verified against `2e2e464c2` — the same numbers before this session's rule
changes, so the overage is the tree's, not the instrument's.

**The findings are CSS and this repo says not to touch them on my own
judgement.** bsdports is `EIGHT_PX_RHYTHM` ×4, `CHOICE_OVERLOAD` and
`SIGNAL_NOISE`; shared is `EIGHT_PX_RHYTHM` ×6, `MAGIC_COLOR` ×3,
`NO_DECORATIVE_FX`, `TOUCH_TARGET_MIN`, `CONTRAST_TOKENS`, `RAMS_UNOBTRUSIVE`,
`REDUCED_MOTION` and `WHITESPACE_RHYTHM`. Every one is a spacing, colour or
motion value in a design its owner is a trained architect of, and
`RAILS/CLAUDE.md` says restore or ask, never invent a layout fix.

One thing to know before acting on the number: the gate reads the **first**
`scan: done` line, which is the aesthetic profile. The full profile in the same
run reports 60 for bsdports and 187 for shared. The budgets were recorded
against the aesthetic number, so the row is consistent — but it is a narrower
claim than "constitutional preflight" sounds, and re-basing it against the full
profile is a separate decision with four new ceilings in it.

### Tier 1 — closed, verified 2026-09-08

Five entries here named a schema and a model that nothing read or wrote. All
five were wired, and every reader was found again on 2026-09-08 rather than
taken from the note: repost through `RepostsController`, the `button_to` in
`shared/_action_bar` and the `Current.reposted_post_ids` memo; watch time
through `Tv::ViewEvent#record_progress!`, the `tv/view_events` endpoint, the
`tv-player` video target and `Tv::Video::WATCH_TIME_SQL`; saved-search alerts
through `SavedSearchAlertJob`, scheduled every thirty minutes in
`brgen/config/recurring.yml`; courier dispatch through
`Takeaway::Order#transition_to!` calling `DeliveryDriver.nearest_free`, drawn
by `Maps::HomeController#courier_layer`; and mentions through
`Shared::Mentionable` on `Post`. The seven test files those entries name run
sixty-seven tests, all green. The records are deleted; `git log` holds the
reasoning.

One line of 1.5 was wrong when it was written, and it is the finding worth
keeping. It said `Stream` still has no writer and that the table stays. No
`Stream` model and no `streams` table exist anywhere in `RAILS/`.
`Tv::LiveStream` is the table it meant, and it has a full writer —
`Tv::LiveStreamsController` creates, updates, destroys, `go_live!` and
`end_live!` — with `vertical_forms_test.rb` posting the real form and
asserting the row. What is absent is the media half: `apps.yml` records the
model done and notes "no WebRTC/RTMP", so ingest is Tier 2 work rather than an
unwired column.

One gap the closing left is forward work, not debt. `Shared::Mentionable` is
polymorphic and `Comment` does not include it, so an `@username` in a reply
notifies nobody. `Post` is the only model in any of the three apps that
includes the concern.

---

### Tier 2 — structurally absent

#### 2.1 No federation (Mastodon) — **done, outbound half**

A brgen account can now be followed from anywhere in the fediverse and its
public posts deliver outward. WebFinger, NodeInfo, actor documents, outbox,
followers, a verified inbox, HTTP signatures, per-inbox delivery with retry.

The city partitioning does the work: `@kari@brgen.no` and `@kari@oshlo.no` are
different accounts because the cities are already different origins with
different populations, which is the same shape as two Mastodon instances. Every
lookup resolves against the *requested host* — answering for the wrong city
would hand a stranger's posts to whoever asked.

Security decisions, since the inbox is where an unverified string becomes an
action:

- **The signer and the claimed author must match.** Without that check a valid
  signature from any actor authorises an activity attributed to any other, and
  every account is forgeable by anyone with an account anywhere.
- **Partial coverage fails closed.** A signature over nothing but `Date` is a
  valid signature that proves nothing about the request, so
  `(request-target)`, `host`, `date` and `digest` are all required.
- **The Digest header is checked**, or a signed request can carry any body.
- **Signatures expire** (5 minutes), so a captured request cannot be replayed.
- **Delete only removes what its sender owns.** A verified signature proves who
  is asking, not what they may ask for.
- Bodies are capped before parsing; keys are cached, because re-fetching an
  actor per inbox POST makes our inbox an amplifier pointed at whoever is being
  impersonated.
- The followers collection reports a count and lists nobody. Who follows a
  small-city account is worth more to a scraper than to anyone else, and the
  protocol does not require publishing it.

Keys are RSA-2048 generated on first use, not at signup — brgen mints a real
`User` row for every cookieless visitor and almost none of them federate.

**Check:** `brgen/test/lib/fediverse_signature_test.rb` (10, every way
verification can be got wrong), `brgen/test/controllers/fediverse_test.rb` (10,
discovery and the city boundary), `brgen/test/controllers/fediverse_inbox_test.rb`
(12, including impersonation, body-swap, replay and duplicate delivery).

**Still open — the inbound half.** Remote `Create`, `Announce` and `Like` are
verified, recorded as seen and then dropped: brgen does not store remote posts.
That is deliberate rather than unfinished — ingesting them means remote media
proxying, remote content moderation (`ModerationReport` has no model for
content whose author is not local) and a blocklist story, each of which is
larger than everything above. The handler says so instead of pretending.

Also open: outbound *following* (a brgen user following a remote account),
instance-level blocklists, and `Update` on edit.

#### 2.2 No `Event` model (Facebook) — **done**

The largest missing noun on the list, and the one with the most already sitting
underneath it: `Place`, `PlaceCheckIn`, `Neighborhood`, the maps engine, and a
city-strip on the home page that now carries `EventCreated`.

`Event` + `EventRsvp`, with the decisions worth keeping:

- **Location is two-sided.** An event either points at a `Place` (which fills in
  coordinates, venue name and neighbourhood at validation) or carries free text.
  Requiring a Place means nobody can post a party in their own flat; requiring
  coordinates means nobody can post before the venue is settled.
- **`upcoming` means "has not finished", not "has not started"** — a three-day
  festival is still on during day two, and dropping it at the opening minute is
  how a what's-on page lies.
- **RSVP is three-way.** "Interested" is the majority answer on every event
  platform; collapsing it into going/not-going both overstates attendance and
  loses the reminder signal. Pressing the answer you hold withdraws it.
- **The counts are recounted, not counter-cached.** Rails increments on create
  and decrements on destroy, and a status moving from going to interested is
  neither. `update_columns` writes `updated_at` by hand, because the card is
  fragment-cached on `[event]`.
- **Cancelling is not deleting.** People have it in their calendar; `cancel!`
  notifies everyone who said they were coming and the event stays readable.
- `capacity` nil means unlimited, and `places_left` returns nil rather than 0 so
  it cannot render as "0 places left". A full event still takes "interested".

**Check:** `brgen/test/models/event_test.rb` (12) and
`brgen/test/controllers/events_controller_test.rb` (9).

**The map pin is built, and was already checked.** `Maps::HomeController#events_layer`
draws every published event that has not finished, has coordinates, and starts
inside a seven-day horizon — a map that reaches further ahead is a wall of pins
rather than an answer to "what is on near me".

**Check:** `brgen/test/controllers/maps_layers_test.rb` (6), which covers all
four layers: an event with coordinates is pinned, one beyond the horizon is
not, a place carries its own name rather than the string "Map point", an
expired story is gone, and a courier is drawn for the customer waiting on that
order and for nobody else.

Recorded because closing this line cost a wrong turn worth more than the line:
the check was hunted for by grepping the test tree for `events_layer` and
`points_json`, neither of which a test that reads `data-map-points-value` off
the rendered page contains. Searching for the implementation's vocabulary
inside a test that speaks the browser's is the same instrument error as
searching for the noun when only the verb is written — 1.2 above records the
first instance of it, in this same subsystem.

**Still open:** recurring events, and ticketing beyond an external link.

#### 2.3 No Story / ephemeral media (Snapchat) — **done**

Ephemerality existed only inside DMs. `Story` + `StoryView` put it on a public
surface.

- **The lifetime is a column, not a computation.** `expires_at` is stored, so
  the `alive` scope, the countdown label and the sweep all read one value rather
  than each re-deriving 24 hours and eventually disagreeing.
- **`alive` hides an expired story before the sweep runs**, so a link stops
  working the moment it should rather than whenever the job catches up. The
  sweep is about the bytes: `destroy`, not `delete_all`, so the Active Storage
  blobs go with the rows on a 1 GB VPS.
- **Seen is a set, not a log.** Opening twice is one view and the author's
  viewer list never repeats a name. `create_or_find_by!` was wrong here — it
  rescues the *database's* uniqueness error, and the model validation fires
  first, so a second open raised instead of reading as "already seen".
- **Camera-first**: the file field carries `capture="environment"`, which opens
  the rear camera on a phone and degrades to a file picker on a desktop.
- **The area comes from the position the app already has.** `locations#update`
  stores it coarsened to ~1 km; the compose form opts in rather than taking a
  fresh GPS read. The existing `geolocation` Stimulus controller POSTs to that
  endpoint and has no form-field targets, so hidden inputs wired to it would
  have been controls that do nothing.
- A ring is a person, not a photo: grouped by author, followed authors first.

**Check:** `brgen/test/models/story_test.rb` (10) and
`brgen/test/controllers/stories_controller_test.rb` (7).

**Closed 2026-08-19.** The Snap-Map is `Maps::HomeController#stories_layer`,
which is only acceptable because the coordinates are coarsened to ~1 km on write
— a pin says "around here", not "at this address".

A reply is a direct message carrying the story it answers, so it stays readable
after the 24 hours are up; only `alive` stories take one, because a reply box
that still works after the sweep is a promise broken quietly.

`StoryStreak` counts days running that two people have answered *each other* —
mutual, because a streak one person can hold up alone is a posting counter
rather than a pair still talking. Whether it is over is computed on read: a
sweep that has not run yet would leave a dead streak on the page, and the answer
is one date comparison.

**Found while wiring the reply box, and fixed:** `Conversation.direct_between`
read `for_user(a).for_user(b)`, which looks like an intersection and is not —
both scopes join the same association, Rails collapses them, and the predicates
AND on one participant row. It always answered nil, so `find_or_create_direct`
always created, and **every pair of people got a new DM thread each time they
opened one from a different button**.

#### 2.4 `Community` was eight columns (Reddit) — **done**

Roles on `community_memberships` (member / moderator / owner), plus rules,
flair, privacy, icon, banner, `members_count` and an archive flag on
`communities`. A community can now be run by its own members.

- **Owner is a membership row, not just `communities.user_id`.** The creator
  gets one on create, and the migration backfills every existing community —
  otherwise each one predating today has an empty moderator list and nobody who
  can appoint anyone.
- **The last owner cannot be demoted.** Nothing else in the app creates an
  owner, so that is not a state to recover from later.
- **Only an owner appoints.** If a moderator could change roles, one could
  demote the person who made the community, and there is nothing above them to
  appeal to. Moderators may edit rules and flair; only an owner may delete.
- **Reading and posting are separate questions.** Restricted is the interesting
  case: the whole city reads it, only members post. Enforced in the controller,
  because a hidden compose link is not a permission check.
- **The queue is derived, not denormalised.** `ModerationReport` is polymorphic
  and carries no `community_id`; `Community#moderation_queue` reaches it through
  the community's posts and their comments, so there is no column to backfill
  and keep true.
- Flair is the label itself on `posts.flair`, not an id — flairs are edited as a
  text list, so an id would dangle the moment a community renamed one.

**Found while wiring it, and fixed:** `ModerationWorkflow#transition!` read the
polymorphic `report.reportable` on a report loaded by `find`, raising under
strict loading *after* the status had been written — **`Admin::Reports#update`
has been on that path the whole time**, so resolving any report from the admin
queue 500'd. And `communities#show` compared `Current.user != @community.user`,
a lazy read that raised for every signed-in visitor while rendering fine for
guests — the same shape as the tv video page.

**Check:** `brgen/test/models/community_governance_test.rb` (9) and
`brgen/test/controllers/community_moderation_test.rb` (9).

**Bans are built.** A mod queue that can resolve a report but not stop the
person who caused it is half a tool: resolving takes the content down and the
same account posts the same thing a minute later.

`CommunityBan` is its own table, not a flag on `community_memberships`, because
a public community takes posts from anyone — the person to ban usually has no
membership row, and inventing one to hold the ban would make them a member and
bump `members_count` in the act of banning them. Checked before privacy in
`postable_by?`, since a public community is exactly where a ban has to bite.

Scoped to the community and nowhere else: one community's moderator silencing
someone across the whole city is not a lever that should exist. Temporary bans
lapse on their own; a moderator cannot be banned without being demoted first (a
fight the app should not settle); any moderator can lift any ban, because a mod
team that cannot undo each other's mistakes escalates everything to the owner;
and the banned person is told with the reason, because a ban nobody is informed
of reads as the site being broken.

**Check:** `brgen/test/models/community_ban_test.rb` (10) and
`brgen/test/controllers/community_bans_controller_test.rb` (6).

**Crossposts and the wiki are built (2026-08-18).** A crosspost is a `Post` in a
second community with its own comment thread, not a join row — a repost boosts
into followers' timelines and belongs to no community, which is the other act. A
crosspost of a crosspost points at the original, or "seen in four communities"
cannot be answered without walking a chain. `postable_by?` is the whole
permission check, so a community that banned an account cannot be reached
through a crosspost either.

The wiki is `CommunityWikiPage` plus `CommunityWikiRevision`: moderators write,
whoever can read the community reads. Writing goes through `revise!` rather than
`update!`, so no caller can save a page and forget the revision, and a revert is
a new revision rather than a deletion of the ones after it — a wiki whose
history can be edited is a wiki nobody can audit.

**Check:** `brgen/test/controllers/crossposts_controller_test.rb` (5),
`test/models/community_wiki_page_test.rb` (5),
`test/models/community_wiki_revision_test.rb` (4),
`test/controllers/communities/wiki_controller_test.rb` (5).

**Still open:** nothing in this entry.

#### 2.5 No vertical video surface (TikTok) — **done**

`tv.­*/feed`: one video per screen, ranked by watch time. `home#index` stays as
it was — the grid is the YouTube answer to "what is there", and this is the
other question.

Only possible because 1.2 records watch time. Ranking a feed on `views_count`
would have served whatever got the most accidental clicks, since that counter
is incremented on page load.

- **Snapping is CSS, not JS.** The browser already does momentum,
  rubber-banding and keyboard paging correctly; a hand-rolled scroller gets at
  least one of those wrong on some device. Stimulus only decides what plays and
  what gets recorded.
- **`100dvh`, not `vh`** — mobile browser chrome collapses on scroll, and `vh`
  leaves a strip of the next video showing under the address bar all the way
  down.
- **No `autoplay`, `preload="none"`.** Ten videos preloading at once is a few
  hundred megabytes on a phone; the controller plays the visible one and pauses
  the rest. `muted` + `playsinline` because iOS refuses to autoplay anything
  else, and sound is opt-in.
- **Watch time is the furthest point reached, sampled while it plays** — a
  looping video's `currentTime` returns to zero, so the max is the only honest
  number. Reported with `sendBeacon` on scroll-away and unload.
- A video with no file is not in the feed at all: a blank screen you cannot
  scroll past is worse than a shorter feed.
- **Logged-out viewers count.** brgen mints a real `User` per visitor, so their
  watch time ranks too — for video that is the point, since most viewers are
  never signed in. `PruneGuestUsersJob` `destroy_all`s those users and the view
  events are `dependent: :destroy`, so the rows go with them.

**Found while wiring it:** the nested view-events path carries the video's slug
(`Sluggable#to_param`) and the create action looked up by `id` — the third time
that trap has appeared today, after `post_vote_path` and `post_repost_path`.

**Check:** `brgen/test/controllers/tv_feed_test.rb` (6), including that one
viewer who watched a clip through outranks 500 page opens.

Live streaming stays blocked — see "Blocked" below.

**Closed, and the line here was the last to know.** `Sequencing` below has
recorded tv sounds as done since 2026-08-20 while this paragraph still called
them open — two statements about the same subject in one file, disagreeing.
`Tv::Sound` is the audio identity: a clip that names no
sound becomes the origin of its own, a second clip reuses it and the count
follows, and the sound page is the "more of this" surface. A duet names its
original and inherits its sound, and a video may refuse answers. Deleting the
source clip leaves the sound, or every remix loses its parent with it.

**Check:** `brgen/test/controllers/tv_sounds_and_duets_test.rb` (6).

---

### Tier 3 — per-surface parity

#### Marketplace (Amazon / Temu) — **basket done**

`Marketplace::Order` is a per-listing *offer* with its own payment, which is the
right shape for classifieds: a bike from a stranger is negotiated, not added to
a cart. It was the wrong shape for a shop — four things meant four payments,
four PSP round trips and four card charges, with nowhere to put an address.

So `Marketplace::Checkout` sits **above** the orders rather than replacing them,
and both shapes keep working. One basket, one payment, one address, many orders,
split by seller for fulfilment.

- **`Marketplace::Address` is its own record**, so a second purchase does not
  mean typing it again and a later edit does not rewrite the address printed on
  last month's label.
- **Fulfilment is a separate axis from payment.** A paid order that has not
  shipped and a shipped order awaiting payment are both real states; collapsing
  them into one column is why "where is my parcel" goes unanswered. `ship!`
  carries a tracking code and tells the buyer.
- **`stock` is nil for one-of-a-kind**, a number for a shop. Defaulting to 1
  would have made every private sale read as a shop with one left.
- **Paying is all-or-nothing** — a half-paid basket, one card charged, is the
  state nobody can resolve.
- The payment services stopped reading `order.listing.currency`/`.title` and now
  ask the payable for them, so a basket goes through the *same* guarded path
  (including the sk_test_-key-in-production guard) rather than a second one.
- Check order in `checkouts#create` is the order a buyer should meet it in:
  nothing to pay for → provider unconfigured → no address → then a basket.
  Getting this wrong produced a `DoubleRenderError`, i.e. a 500 for a buyer who
  had simply not saved an address.

**Check:** `brgen/test/models/marketplace_checkout_test.rb` (8) and
`brgen/test/controllers/marketplace_basket_test.rb` (5).

**Listing Q&A is built (2026-08-19).** Asking went through the offer thread, so
the seller answered "is it still available" once per buyer and the answer left
with them. `Marketplace::Question` is public on the listing, answered by the
seller, notifying both ways as kind `alert` (which is pushable). Answered
questions sort first; an unanswered one still shows, because it is the question
the next buyer has too.

**Check:** `brgen/test/controllers/marketplace_questions_test.rb` (3).

**Depth is built.** `Marketplace::Variant` + `VariantOption` are the real
schema this entry asked for rather than a column; `Marketplace::Return` and
`Marketplace::Payout` are the money half, and the payout rules are the part
worth keeping: paying does not enqueue a payout, delivery does, a release with
no Stripe stays pending rather than reading as sent, and a received return
voids a pending payout without claiming a refund Stripe has not confirmed.
`ListingFacets` counts what remains once a facet is picked — ignoring its own
filter, respecting the others — and the saved list is `/wishlist`, not
`/saved`, because the host declares `saved` before it mounts the engine.

**Check:** `brgen/test/controllers/marketplace_variants_test.rb`,
`marketplace_returns_test.rb`, `marketplace_saved_and_facets_test.rb`, and
`brgen/test/models/marketplace_payout_test.rb` (5).

**Countdown is built.** `Deal#ends_in` is the remaining seconds, or nil with no
end or after it; the card and the show page render `marketplace.deals.ends_in`
through `distance_of_time_in_words`. No extra Stimulus.

**Still open:** coupons, referral credit and bundle pricing have no model at all.

Solidus remains blocked — see below — so all of this is native-path work.

#### Dating (Tinder / Hinge) — **ranking and prompts done**

The deck was `ORDER BY RANDOM()`: orientation, neighbourhood and a 20 km radius
filtered the pool and nothing ranked it, so someone last seen in March sat
beside someone online now — and every reload reshuffled, so a profile you had
just passed could not be found again.

`Dating::Profile.ranked_for` orders by three things, in this order:

1. **recency** — who is actually around; a deck full of dormant accounts is a
   dating app nobody matches on;
2. **effort** — profiles with prompts answered, because that is what gives the
   viewer something to reply to;
3. **a per-viewer, per-day shuffle** — stable while someone browses, different
   tomorrow, and different between two people.

Deliberately *not* attractiveness, engagement, or any like-count feedback loop:
ranking people by the attention they already receive is how these products end
up with a handful of accounts getting everything.

The shuffle is a per-viewer **multiplier** over a prime modulus, not an offset.
The first version added a per-viewer salt, which shifts every id equally and
leaves the order identical — the test that two viewers see different decks is
what caught it.

`Dating::Prompt` is the Hinge half: a fixed question list (free text becomes a
second bio), three per profile, and a like that points at one answer and says
something about it. Plain likes still work — a product that refuses one is a
product people stop using at 1am. Prompt ids are scoped to the liked person's
own profile, or a like could point at a stranger's answer.

Who-liked-you is its own page, not folded into the deck: people who have already
said yes are a different decision from people who have not seen you.

**Check:** `brgen/test/models/dating_ranking_test.rb` (8) and
`brgen/test/controllers/dating_likes_test.rb` (5).

**Unmatch is built.** `Dating::Match#unmatch!` writes `unmatched`, drops the
mutual likes so the pair can like again, and rematch flips the same row back
to `matched` rather than inserting a second pair. The matches list is still
`active` (matched only); destroy is scoped to a participant.

**Check:** `engines/dating/test/models/dating/match_test.rb` (likes cleared,
rematch, strict loading) and `brgen/test/controllers/dating_unmatch_test.rb`
(participant can, stranger 404s).

**Rewind is built.** Last pass only: `Dating::Dislike.rewind!` destroys the
most recent dislike and the deck query already excludes dislikes, so that
profile comes back. A like is a different decision (it may have created a
match) and is left alone. Empty rewind is a flash, not a 404.

**Check:** `brgen/test/controllers/dating_rewind_test.rb` (last pass undone,
a like is not).

**Verification and daily picks are built.** `Dating::Verification` asks for a
named pose and carries it into the review, requires a selfie, and allows one
open request at a time; only the configured admin reviews, and a blank admin
address makes nobody a reviewer rather than everybody. `Dating::DailyPick`
draws once and stays put for the day, and does not repeat a face already shown
this week — a picks list that reshuffles on reload is the same defect the deck
had before it was ranked.

**Check:** `brgen/test/controllers/dating_verification_and_picks_test.rb` (6).

**Still open:** super-like and boost, both purchases — `apps.horizon.yml` has
them as `agent: ignore`.

#### Takeaway (DoorDash / Foodora) — **hours, tips, scheduling done**

`Takeaway::OpeningHour` is a row per weekday, not a JSON blob: "is this open
now" is a query, and a blob turns the restaurant list into a Ruby loop over
every row on the page. Minutes past midnight rather than a `Time` (which
carries a date and a zone that mean nothing here), and `closes_minute` may
exceed 1440 — because closing after midnight is normal for a kitchen, and
reading only today's row says a place open until 02:00 is shut at 00:30.

- **No hours recorded = open.** Most restaurants have none yet and defaulting
  to closed would empty the listing; `active` stays the "not trading" switch.
- **A closed kitchen still takes a scheduled order** — that is most of what
  scheduling is for. Enforced in the controller, because a hidden button is not
  a closing time.
- The tip is in the total from `calculate_totals!`, not added somewhere later.
- A scheduled order estimates from **when it was asked for**, or it is
  permanently late for having been placed that morning.

**Check:** `brgen/test/models/takeaway_hours_test.rb` (8).

**Order-again is built.** `orders#again` copies available items at current
prices onto a new pending ticket with the same address. Items that left the
menu are skipped; if none remain, the diner is sent to the restaurant rather
than placing an empty order. Tip and scheduled_for stay off — those are
per-ticket. The show-page "reorder" control is a POST, not a link at the
menu.

**Check:** `engines/takeaway/test/models/takeaway/order_test.rb` (`build_reorder`)
and `brgen/test/controllers/takeaway_order_again_test.rb` (copy, skip-empty).

**The live courier map is built** — see 1.4; the maps engine draws the viewer's
own courier while the order is out for delivery.

**Group orders are built.** The host opens the ticket and gets a token rather
than an id — a numeric id in a link people forward around is an invitation to
read the next table's order — anyone with the link adds their own line, a line
can be taken back only by whoever added it, and a confirmed ticket takes no
more. Shares name what each person owes without the delivery fee, because
splitting a fee four ways is a decision the host makes, not one the app makes
for them.

**Check:** `brgen/test/controllers/takeaway_group_orders_test.rb` (6).

Web push on each `transition_to!` is on the path too: `order` is in
`PUSHABLE_KINDS`, so a transition reaches a lock screen rather than only the
in-app list.

**Still open:** nothing in this entry.

#### Messenger — **reply, edit and unsend done**

Typing indicators, read receipts, reactions, presence, disappearing messages and
attachments were already there.

- **Reply-to**: in a channel with several conversations at once, a message with
  no referent is one nobody can follow.
- **Editing is bounded to 15 minutes.** A message that can be rewritten hours
  later is one a reader cannot trust, and the receipt saying they read it is
  already gone.
- **Unsending has no window at all** — a message sent to the wrong room, on a
  chat where people post real addresses, is a safety problem rather than a typo.
- **The unsend is soft.** The row stays and the body goes, because a hard delete
  leaves a hole in a thread and orphans whatever replied to it. That required
  exempting deleted messages from the content presence validation, or the record
  is permanently invalid and every later save on it — a receipt, a reaction —
  fails.

**Check:** `brgen/test/models/message_edit_test.rb` (7).

**Closed 2026-08-18, except the calls.** Voice messages, forwarding, link
previews, message search, group naming with admin roles, and pinned
conversations are built.

The recorder writes into the composer's own file field, so a voice note goes
through the same create path as a photo — `duration_seconds` and `Message#voice?`
had shipped and nothing in the tree could produce an audio message. An
attachment is now a message on its own: a voice note has no words in it by
definition.

Forwarding is a copy, not a pointer: the copy has to outlive the original being
unsent, it belongs to the forwarder, and its readers usually cannot open the
thread it came from. Both ends are scoped to the reader's own conversations.

Link previews carry title, site and summary and **no image**: hotlinking one
tells that server the IP of everyone in the thread, and proxying it is remote
media hosting — the problem 2.1 defers. One row per URL, so the same article in
twenty rooms is one fetch rather than twenty pointed at whoever was linked.

Search reads `visible.unexpired` like every render does, or ephemerality would
be a rendering choice rather than a promise.

A group DM is a `Conversation` with a name and no slug (a #channel is one with a
slug), and roles reuse the IRC ladder already on the participant row. Ops rename
and remove; any member may add, because a group where only the founder can bring
someone in is one people work around by starting a second group. The last op
leaving hands the room to the longest-standing member rather than trapping them
in it.

Pinning is per-participant and a timestamp: a pin on the shared row would let
either side reorder the other's inbox, and pinned threads order among
themselves.

**Found while wiring the controls, and fixed:** reply, edit and unsend had a
route, a model method, a test each — and no control on any page. A backend
nobody can reach is not a feature.

**Check:** `brgen/test/controllers/{conversation_pins_controller,conversation_search,message_forward,group_conversations_controller,voice_message}_test.rb`
and `test/models/link_preview_test.rb`.

**Still open:** no WebRTC anywhere, so still no voice or video calls.

#### Craigslist — **expiry, renewal and the non-goods verticals done**

Geo listings, categories, city subdomains, casual (no-store) listings,
buyer–seller chat and FTS were already there. Listings now expire after 45 days
and can be renewed.

**Expiry is a scope, not a state change.** `live` (active *and* unexpired) is
what the policy scope resolves for public surfaces; `active` still includes a
lapsed listing, which is what lets its owner see and renew it. A listing that
silently vanished from its own seller's account would read as a bug rather than
a policy. Renewing restarts the window from now, so renewing late does not
immediately expire again, and it clears the notice flag so the next lapse is
announced too.

**Check:** `brgen/test/models/listing_expiry_test.rb` (5).

**A listing has a kind.** `goods`, `job`, `housing` or `gig`, with three detail
tables behind the three new ones — employment type and a salary range, rent and
deposit and rooms, gig pay and start time. Price is required only where a price
means anything, so a job advert no longer has to name one. The index filters by
kind and defaults to goods, and the top-offers strip filters with it: it drew
from every listing there is, so the moment a second kind existed a bicycle
search carried a job advert above it.

**Check:** `brgen/test/controllers/marketplace_kinds_test.rb` (8), which also
pins the 2FA guard reached from inside an engine — `two_factor_required?` turns
on once an account has an active listing, so every seller's second listing was
a `UrlGenerationError` 500 against a host path the engine's route set does not
hold.

**Still open:** the anonymised contact relay — it needs mail infrastructure
(inbound routing and per-listing addresses), which is an operator change on
vm23 rather than app code, and `brgen.no` mail is only outbound-verified today.

---

### Blocked — do not chase

These are recorded in `RAILS/apps.yml` with verified blockers. Repeated here
only so nothing above reads as available.

- **Live streaming (tv).** Needs a media server (nginx-rtmp / MediaMTX / SRS)
  plus transcoding. ffmpeg is not installed on vm23. Infrastructure, not app
  code — `Tv::Broadcast` already models `stream_key`/`go_live!`/`end_live!`.
- **Solidus marketplace.** `brgen/config/database.yml` is sqlite3 in all four environments
  and Solidus supports Postgres/MySQL in production. This is a database
  migration first, not a gem install.
- **pgvector-backed recommendations.** Same Postgres dependency.

---

### Sequencing

Tier 1 and Tier 2 closed on 2026-08-19, apart from the inbound half of
federation, which is deliberate rather than unfinished. Tier 3 and the WebGL
blind spot closed on 2026-08-20: marketplace depth (variants, returns,
wishlist, facets), the verticals' own gaps (dating verification and daily
picks, tv sounds, takeaway group orders, the Craigslist kinds), outbound
federation's remaining half, and a gate that can see a WebGL surface.

What is left is what an app cannot close on its own, and every item is recorded
with its blocker rather than left implied:

1. **Inbound federation** — accepting remote posts, which is a moderation and
   spam problem before it is a code one.
2. **Seller payouts and PSP refund transfer** — the code half landed:
   `Marketplace::Payout` and `Payments::StripeTransfer` enqueue on delivery and
   fail closed, so a payout with no Connect account or no key stays pending with
   a reason rather than reading as sent. What is left is not code — it is a
   Stripe Connect account per seller and a platform balance to transfer from.
3. **The anonymised contact relay** — inbound mail routing on vm23.
4. **Live streaming, Solidus, pgvector** — infrastructure, listed under Blocked.

### Three files over their length ceilings

`RAILS/test/file_length_ratchet_test.rb`, the one red file in the standalone
suite. `limits.yml`'s rule holds here too: a breach is paid by extraction or
deletion, never by a bigger number.

    shared/app/assets/stylesheets/_zen_shell.scss  502 / 477  (+25)
    gates/lib/live/user_flow.rb               320 / 313  (+7)
    gates/lib/rendered/rendered_geometry.rb   450 / 449  (+1)

33 lines between them. The counterpart half of that test is green: no ceiling
is slack any more.

**`_zen_shell.scss` is not an extraction, and that is the finding.** Its rules
reach the apps through one `@forward` in `_stack_brgen.scss`, so source order
is cascade order, and Sass allows `@use`/`@forward` only at the top of a file.
A partial lifted out of the middle lands after everything that followed it. The
only order-preserving split is head/forms/tail — three files, two of which are
named for a position rather than a subject. The forms block (`.input-group`,
`.field--float`, `.dropzone`, the direct-upload and error families, `fieldset`)
is the subject that is there; taking it needs the owner, because this repo says
restore or ask and never invent a layout change.

The other two are +7 and +1 against a booted fleet. A one-line overage does not
want a file of its own, so the payment there is deletion, and the four-file
census on 2026-09-06 found nothing dead in either.

**The deadlock that kept this list alive is gone.** It read: `file_length` is
per file and wants a split, `growth.rails` counts files and was thirteen over,
so every split deepened an overage nobody could account for; a raise was
forbidden by both. `growth.rails` is at its ceiling now, with each of the
thirteen named in `spine.yml`, so a split costs one nameable line instead. Two
were paid that way on 2026-09-08 and left the list:

- `deploy_backlog_test.rb` 631 → 557. Playlist import, track ownership, hosted
  tracks and set likes are `playlist_wiring_test.rb` — four contracts that
  arrived one at a time and read as one subject, out of a bundle of forty.
- `gates/support/cdp_session.rb` 339 → 288, off the list outright. Finding
  Chrome, launching it, waiting for `DevToolsActivePort`, discovering the page
  target and reaping the process are `chrome_process.rb`; what is left speaks
  CDP to a browser that is already running. The first split, in August, took
  the RFC 6455 half. Verified against a real Chrome — viewport, headers,
  cookies, navigate, status, evaluate, a computed style, a bounding rect, a key
  press, console capture, a screenshot and a thrown `JsError` — identical
  before and after, and both timeout paths driven to prove `CdpSession::Timeout`
  rather than the stdlib `Timeout` the first split had to learn about.
- `gates/lib/research/design_metrics.rb` 462 → 345. Input size, heading
  hierarchy, the weight ladder, font families and lowercase tracking are
  `design_metrics/type_checks.rb`, a module included back into the gate like
  `ContrastChecks` beside it. Every one of them reads a font declaration out
  of the SCSS and judges it against typography.

**The diff standard this file set is what caught the real defect**, and it was
not in either split. Running the gate's whole sorted output against the tree
before the change showed one extra line — `no ceiling recorded in
css_budget.yml`. Moving `contrast_checks.rb` into `design_metrics/` the day
before had broken `File.expand_path("../data/css_budget.yml", __dir__)` for the
second time, in the same method whose comment records the first: the gate ran
unbudgeted and still reported ok. The path is anchored on the gates root now,
and `gate_live_and_css_budget_test` asserts that all four budget readers —
design_metrics contrast, css_constitution rules, css_constitution weight,
constitutional_scan targets — return something. **The ceilings existing in the
YAML and the gate reaching them are two facts, and only the first was ever
asserted.** Proved by mutation: restore the old path and the test goes red.

Two left the list on 2026-09-06, and only one of them by extraction.
`page_inventory.rb` went 444 → 288 by **deletion**, which is the note worth
keeping: it carried five filename ladders for resolving a view's URL, under a
comment inviting their removal "when the route table proves it redundant, not
before". Counted rather than assumed — the ladders were reached three times in
a full 204-page run, twice for the same view — and the two views they answered
turned out to have no GET route at all, so the fallback was inventing URLs and
sending `page_simulation` at them. A file over its ceiling is sometimes a file
doing something it should not do.

The reading that transfers: measure how often a fallback is taken before
extracting the file that holds it. Three calls out of 204 is not a fallback,
it is a residue.

**The remaining three carry nothing dead, measured 2026-09-06.** A Prism census
over every method finds zero with no caller.

Two instrument errors while measuring that, both the same family and both worth
not repeating. A dead-method census reported eleven methods with no caller; the
first eight were predicates, where the `\b` after `Regexp.escape("fractional?")`
demands a word character after the `?` — the fourth time `\b` next to
punctuation has cost something here. The other three were reported dead because
the lookbehind excluded `.`, so a method reached only as `receiver.name` read
as unreachable. Eleven findings, zero real.

### One model nothing writes

Found 2026-09-05 while giving the nine promiseless models their reason, and
worth its own record because the marker on each said "nothing writes it", which
is a finding rather than an exemption.

- **`Stream` — dropped 2026-09-06.** It was the pre-Active-Storage way to hang
  a media file off a post: `url`, `content_type`, `duration`, created in the
  first schema batch ten minutes before `posts` existed, never written. Three
  models had taken the job — `Post has_one_attached :image/:video/:audio` with
  `Shared::MediaProcessable` for uploads, `Playlist::Track` (`SOURCE_TYPES`
  upload/youtube/spotify/soundcloud/whyp/direct/dilla) for audio hosted
  elsewhere, and `LinkPreview` for a pasted URL — with `Tv::LiveStream` and
  `Tv::StreamChat` owning live video. Wiring it meant a second media path
  beside Active Storage, which is what `ONE_SOURCE` forbids.

**`Mention` was the second and closed the same day** (`a05def16c`).
`Shared::Mentionable` writes the rows from `@username` in title and content and
notifies each named user, which is what `Notification::KINDS` and the
notifications controller's group order had been promising while `Post has_many
:mentions` stayed empty. It carries a real validation now rather than the
marker: one row per named user per post, which is the promise `mention_test`
makes twice and which no unique index enforces.

`Tagging` was the third candidate and is not one — verify the instrument before
the finding. A grep for `Tagging.` and `taggings.create` finds only readers,
because the writer is `self.hashtags = tags` inside
`Shared::Taggable#sync_hashtags`, an `after_save` on every post. An association
assignment writes the join row without ever naming its class.

### Deploy blockers

What stops a RAILS deploy from being a one-command operation, each with what
happens today, what has to change, and what already checks it. The former
`RAILS/BLOCKERS.md`. A blocker leaves this list when its unblock
criteria are met, not when it stops being mentioned.

This is the single home for them. `README.md` used to carry the list as five
unowned sentences under "Media integration"; two of them had gone stale without
anyone noticing, which is the argument for giving them a place with enough
structure that staleness shows. Operator-side debt is **not** duplicated here —
it is the OPENBSD section of this file and stays there.

---

### 1. City vanity TLS

**Status:** blocks first install of a new city apex; does not block day-to-day
deploys of the three live apps.

`OPERATOR.sh` stage 1 issues an acme certificate for every apex in
`ALL_DOMAINS`. relayd can only load a keypair for a certificate that exists on
disk, so an apex without a cert is an apex relayd will not serve — and
`OPENBSD/etc/relayd.conf` has held a keypair line for a certificate that did not
exist, which is worse than missing: installing that file downs every site on the
box.

**Owner:** operator. Requires registrar action (DNS delegation), which an agent
must not perform.

**Unblock criteria**

- Every apex in `OPERATOR.sh#ALL_DOMAINS` resolves and serves its own cert.
- `relayd -n` passes against the repo copy of `relayd.conf` on the box before
  install, not after.

**Checked by:** `domain_alignment` compares `ALL_DOMAINS` against
`Brgen::DomainRegistry` and asserts a keypair exists for the four live apexes.
Nothing checks the city apexes are actually reachable — that is deliberate: the
seven live cities sit behind `domain_alignment`, and the half that is registrar
money belongs to the domain expiry watch rather than to a gate.

---

### 2. relayd restart after route changes

**Status:** the missing half is built; the entry stays open until a real deploy
has exercised it on vm23.

A route change in `relayd.conf` needs `rcctl restart relayd`, and that restart
is not free. On 2026-08-10 relayd's `ca` process died during a restart
(`ca_dispatch_relay: invalid relay hash` → `lost child` → `parent terminating`)
and took every site on the box down for nine minutes. The deploy that triggered
it had logged `relayd(ok)` seconds earlier, because the check ran before the
restart.

**Owner:** operator.

**Unblock criteria**

- Post-restart verification is a separate step from pre-restart validation, and
  a deploy cannot report success on the earlier one.
- The failure signature is distinguishable from an app shed: relayd death
  refuses on **443** in ~30ms with sshd still up and the app answering on its own
  port from the box; a shed app leaves TLS answering and only the app port
  closed. Not port 80 — relayd declares one relay, `listen on 0.0.0.0 port 443
  tls`, so 80 refuses on a healthy box and tests nothing.

**Checked by:** `deploy_smoke_gate` validates relayd config content, and
`relayd_confirm_live` in `RAILS/_service.sh` re-checks 443 for 20s after the
restart, before the deploy is allowed to report success. It names which of the
two failure shapes happened: 443 refused while the app port still answers is
relayd down; both refused is the app, not relayd.

---

### 4. openrsync on vm23

**Status:** the README entry was wrong. Corrected here.

The README said "openrsync broken on vm23 — deploy uses git pull". Those are two
different operations and only one of them is a workaround:

- **Repo update** on the box is `git pull`, and always was. That is the design,
  not a fallback.
- **Tree sync** into `/home/<app>/app` is `sync_tree` in `RAILS/_sync.sh`, which
  calls `openrsync -a --delete` first, retries without `--delete`, and only then
  falls back to a `tar cf - | tar xf -` copy, logging `openrsync failed; falling
  back to tar copy`.

So openrsync is used on every deploy, with a working fallback. The bundle-cache
bootstrap in `_deploy.sh` called it too, with no fallback at all; it goes through
`sync_tree` now, so all four calls have one.

**Owner:** operations, low priority.

**Unblock criteria**

- If openrsync is genuinely unreliable on this release, the bundle-cache calls
  need the same fallback the tree sync has.
- If it is reliable, the fallback stays as insurance and this entry closes.

**Checked by:** the bundle-cache bootstrap now goes through `sync_tree` like
the tree sync does, so all four calls have the openrsync -> tar fallback. The
remaining half of this entry stands: the fallback is still silent apart from a
log line, so a box where openrsync never works deploys correctly and slowly
forever without anyone learning.

### Horizon — aspirational features (agent: ignore)

Migrated from `RAILS/apps.horizon.yml`, which is **kept** because
`MASTER/lib/pub4/status_report.rb` counts it and a deploy contract test
asserts it exists. These items are **`agent: ignore`** — out of scope for
agents unless explicitly requested. Canonical active inventory is
`apps.yml`; do not implement horizon items by default.

- **brgen**
  - _core_
    - AI feed ranking — status: planned
    - creator monetization — status: planned
  - _subapp_tv_
    - live stream infrastructure — status: planned
  - _subapp_dating_
    - premium memberships / boost purchases — status: planned
  - _subapp_marketplace_
    - AI recommendations — status: planned
  - _subapp_playlist_
    - creator donations / ad-free tier — status: planned
- **amber**
  - _wardrobe_
    - fashion embeddings (pgvector) — status: planned
    - visual similarity search — status: planned
    - virtual fitting room — status: planned
    - mood matcher — status: planned
    - event outfit planner — status: planned
    - sustainable styles / resale — status: planned
    - weather-based suggestions — status: planned
    - global trends / local designer highlights — status: planned
    - style agents (MASTER integration) — status: planned
- **bsdports**
  - _core_
    - FreeBSD/NetBSD ports parsers — status: planned (OpenBSD-only production scope)
    - semantic package search (pgvector) — status: planned
    - infrastructure knowledge graph — status: planned
    - OpenBSD package intelligence — status: planned

### Survey of `RAILS/` — 2026-09-08, structure, order and the shared engine

A read-only pass over the three apps, the shared engine and the gates. No code
under `RAILS/` was changed. Ranked by value, with what was run to verify each.
Everything measured live: the standalone suite is green but for the length
ratchet, every source gate passes, and every RAILS lint sits exactly on its
ceiling.

**Instrument note first, because it cost two findings.** BSD `grep` has no `\|`
alternation in a basic regular expression, and a pattern built through a Ruby
double-quoted string arrives as one. Two searches for `A\|B` therefore reported
zero hits over subjects that were there — `Shared::ConsentHelper` read as absent
while `shared/lib/shared/engine.rb:91` registers it, and two lints read as
unreferenced while `MASTER/tools/ratchets.rb:325` measures both. Use `grep -E`.
This is the "BSD variants break GNU idioms" rule catching a survey of its own
tree.

#### 1. `Shared::Authentication` is two things, and the model is the one that lost

`shared/app/models/authentication.rb` declares `Shared::Authentication <
ApplicationRecord`. `shared/app/controllers/concerns/shared/authentication.rb`
declares `module Shared::Authentication`. One constant, two definitions, and the
concern wins: booting bsdports and asking gives `Shared::Authentication ->
Module`, `respond_to?(:table_exists?) -> false`, and Zeitwerk's shadowed-file set
contains `RAILS/shared/app/models/authentication.rb` — so that file is never
loaded, in any environment.

The consequence is a 500 rather than dead weight.
`shared/app/controllers/omniauth_callbacks_controller.rb:66` and `:90` read
`defined?(Shared::Authentication) && Shared::Authentication.table_exists?`. The
`defined?` guard is satisfied by the module, so evaluation proceeds and raises —
verified in a booted app: `NoMethodError: undefined method 'table_exists?' for
module Shared::Authentication`. Line 66 is reached from
`find_or_create_user:43`, which `create:29` calls on every callback, and neither
rescues. Locally no provider registers (`shared/config/initializers/omniauth.rb`
returns early without a client id and secret), so it is latent here and live the
moment a key lands in `/etc/<app>.env`. The comment at lines 31–34 records this
endpoint raising `NoMethodError` once before, for a different missing method.

No app has the table: no migration creates `authentications` and none of the
three `db/schema.rb` carries it. So the fix is deletion, not renaming — drop the
shadowed model, `legacy_authentication_for` and `persist_legacy_authentication`,
and let `ExternalIdentity`/`IdentityProvider` be the one path, which is the
`ONE_SOURCE` answer the `Stream` record above reached for the same shape. Pays
one file.

`apps.yml:41` is wrong about this in a second way: it names
`Shared::OmniauthCallbacksController`, and the class is bare
`OmniauthCallbacksController`. The row says `status: done`.

The guard that would have caught it is one test. Boot one app and assert
Zeitwerk's shadowed set holds only the eight helpers `engine.rb` loads with
`require_dependency` — those are shadowed by design, the ninth was not.

#### 2. Eight gate classes each wrote their own HTTP client

`RAILS/tools/crawl_support.rb:67` is `CrawlSupport.fetch(url, timeout:)`, and
every gate already requires the module for `CrawlSupport.port_open?`. It cannot
set a `Host` header, so eight gates carry a private near-copy of it:

    gates/lib/live/user_flow.rb:389        fetch_with_host   open 8  read 15
    gates/lib/live/page_simulation.rb:345  fetch_with_host   open 6  read 12  + Accept
    gates/lib/live/first_screen.rb:216     fetch             open 8  read 15
    gates/lib/live/surface_schema.rb:90    fetch             open 8  read 15
    gates/lib/source/content_honesty.rb:111 fetch            open 8  read 20
    gates/lib/source/payment_honesty.rb:78 fetch             open 8  read 12
    gates/lib/research/visual_quality.rb:201 fetch           open 8  read 15
    gates/lib/rendered/journey_invariant.rb:158 fetch_raw    open 8  read 15

Verified by reading all eight: the bodies differ in the timeout numbers, one
`Accept` header and the method name. Giving `CrawlSupport.fetch` a `host:` and an
`accept:` keyword deletes about 64 lines across eight files and adds none. It
also fixes a latent gap — `CrawlSupport.fetch` sets `use_ssl:` from the scheme
and not one of the eight copies does, so none of them can probe an `https` URL.
This pays `user_flow.rb`'s +5 ratchet overage exactly, without a new file.

`gates/lib/live/flow_journey.rb:347` and `gates/support/guest_flow_persona.rb:129`
build POST and PATCH requests and are a separate subject; leave them.

#### 3. `_zen_shell.scss` does have a subject-named split, and the button family is it

The standing note above says the only order-preserving split is head/forms/tail.
That was reasoned from "source order is cascade order", which is true only
between two rules that can match the same element *and* set the same property.
Measured rather than assumed: a script walked the 104 top-level blocks, recorded
each block's selector tokens and declared properties, and reported every ordered
pair sharing both. **37 pairs out of 5,356 possible pin the order.** Everything
else in the file is free to move.

The `.btn` family at lines **94–160** — `.btn`, `:hover`, `:disabled` and
`[aria-disabled]`, the four compound variants and `.btn-sm`, with the comment at
126–132 that explains the compound-specificity contract — is pinned to itself and
to nothing outside itself. Fourteen of the 37 pairs are internal to it; none
crosses its boundary. Lift it verbatim into `_zen_buttons.scss` and it pays 67
source lines against a +25 overage, named for its subject.

Specificity closes the gap the pair list cannot. The only other rules in the file
that a `<button class="btn">` matches are `*, *::before, *::after` at 4–8,
`input, button, textarea, select { font: inherit }` at 28–30 and `:focus-visible`
at 45 — 0-0-0 and 0-0-1 against `.btn`'s 0-1-0, so they lose whatever the order.
Every `.btn` mention in the file is inside 94–160 or inside the two media blocks
below.

One position constraint, and it is the whole of the surgery. `_zen_shell.scss`
also names `.btn` inside `@media (forced-colors: active)` at 598–605 and
`@media print` at 607–624. Print uses `!important` and does not care; the
forced-colors block is 0-1-0 against the base's 0-1-0 and must stay later. So the
new partial is `@forward`ed **immediately before** `zen_shell` in both
`_stack.scss` and `_stack_brgen.scss` — after `animations`, which keeps it later
than `_layout_chrome.scss:107` and `_minimal.scss` (whose line 291 records that
zen_shell's position is the one that wins) and earlier than zen_shell's own media
overrides. Nothing moves, nothing is renamed, no value changes.

Two further blocks report zero pairs — the feedback family `.empty-state*`,
`.skeleton`, `.toast*` at 174–222 and `.tooltip*` at 257–279 — and **do not take
that verdict**, because the instrument compares property names and does not know
shorthand from longhand. `.toast:215` sets `border` and `.toast--success:221`
sets `border-inline-start`; different names, one cascade. `.empty-state*` also
appears in `_empty_state.scss`, forwarded after `zen_shell`. Either would need a
shorthand-aware pass first.

Confidence: the pair list is a lower bound. It matches selector tokens exactly,
so a compound or prefix relation between two classes that never share a selector
is invisible to it, and it does not see shorthand/longhand or inherited
properties. The button family survives all three gaps for a checkable reason —
every variant selector literally contains `.btn`, and the specificity argument
above covers what the pairs do not. The extraction is still a structural move and
wants the owner's yes, because the house rule is restore or ask.

#### 4. brgen re-implements the concern that exists to hold it

`shared/app/controllers/concerns/shared/application_setup.rb` is the one place
the three apps set up a controller. amber and bsdports use it —
`amber/app/controllers/application_controller.rb:4`,
`bsdports/...:4`. brgen does not:
`brgen/app/controllers/application_controller.rb:4-23` inlines the same five
includes, the same three `helper` calls and the same three settings, and carries
a longer version of the same comment that `application_setup.rb:13-16` carries,
each pointing at the other. `helper Shared::ConsentHelper` at line 20 is now
redundant besides: `shared/lib/shared/engine.rb:91` registers it for every app.

Underneath it is a smaller thing worth fixing first. `application_setup.rb:9`
reads `include Authentication` — a bare constant, resolved in each host app by
`{amber,brgen,bsdports}/app/controllers/concerns/authentication.rb`, three
byte-identical seven-line files whose whole body is
`base.include(Shared::Authentication)`. Verified identical by SHA. Nothing
overrides them. Writing `include Shared::Authentication` in the concern deletes
three files and 21 lines, and removes the engine's one reach into a host-app
constant name — the same reach that produced finding 1.

#### 5. The `Pub4::*Lint` family puts its entry point last

A Prism pass over 1,267 Ruby files under `RAILS/` (visibility tracked through
bare `private`/`public` call nodes, entry point taken as the method callers name)
finds six inversions, and five are one family:

    shared/lib/pub4/css_coverage_lint.rb:407     #scan, 22 helpers and 130 lines above it
    shared/lib/pub4/layout_stability_lint.rb:225 #counts, 12 helpers, 114 lines
    shared/lib/pub4/asset_url_lint.rb:186        #scan, 11 helpers, 84 lines
    shared/lib/pub4/scale_lint.rb:214            #check, 22 helpers, 83 lines
    shared/lib/pub4/breakpoint_lint.rb:162       #scan, 6 helpers, 39 lines
    test/method_length_ratchet_test.rb:111       #measure, 3 helpers, 30 lines

In each the reader meets `engine_dirs`, `strip_erb`, `to_px` and twenty siblings
before meeting `scan`, and `run` — the ratchet-printing main — is last of all.
They are `module_function` modules, so nothing is private and the fix is ordering
alone: entry, then what it calls, then the rest. `ScaleLint::Finding` and a few
helpers are named directly by tests, so nothing can be made private.

Four smaller cases in the gates, from the same pass at a lower threshold:
`gates/support/geometry_type.rb:60` (`check` behind five helpers it calls),
`gates/support/layout_search.rb:63` (`report` behind six),
`gates/support/gate_calibration.rb:36`, `gates/support/dom_surface_schema.rb:21`.
`geometry_type`'s `check_measure` and `check_tabular` are called from
`test/gates/rendered_gates_test.rb:307,314`, so again ordering only.

The counterpart defect is absent. A public method declared below a scope's first
`private` appears **nowhere** in `RAILS/` — 0 findings over 1,461 files, with the
instrument proved on a planted positive that was then deleted.

#### 6. The sign-in screen is written three times, and two of the copies lack something

`{amber,brgen,bsdports}/app/views/sessions/new.html.erb`, 27–38 lines each, 74%
of their non-comment lines shared, with no shared counterpart —
`shared/app/views/sessions/` does not exist, though `Shared::SessionsActions` is
the controller and all three `sessions_controller.rb` are five-line shims onto
it. Three of the differences are real and two are not cosmetic:

- amber renders no `shared/oauth_links`. brgen renders it in `sessions/new:4`
  and `users/new:7`, bsdports in `sessions/new:4`. The route
  (`shared/config/routes/auth.rb:15`) and the provider registration are
  engine-wide, so amber is the only app where a configured provider would have
  no button.
- bsdports offers no create-account link at all; amber links
  `new_registration_path`, brgen `new_user_path`.
- brgen uses `.field--float`, the other two plain `.field`. That is the
  deliberate visual difference and is not for an agent to unify.

Record the first two as behaviour; the consolidation into
`shared/app/views/sessions/new.html.erb` with the field wrapper as a local is a
second step and needs the owner, because it moves markup.

#### 7. The remaining two length-ratchet rows

`gates/lib/live/user_flow.rb` is +5 and finding 2 pays it exactly, by deletion
rather than extraction.

`gates/lib/rendered/rendered_geometry.rb` is +1 across 20 `check_*` methods, and
a one-line overage does not want a file. If deletion cannot be found — a Prism
census on 2026-09-06 found nothing dead, and a fresh grep finds no twin of
`fractional?`, `on_rhythm?`, `expand_hex`, `collect_hexes`, `rect_gap`,
`undersized?`, `inline_target?`, `critical?` or `token_palette` anywhere in the
repo — the shelf with the clearest edge is the colour group:
`check_token_conformance:618`, `token_palette:671`, `collect_hexes:677`,
`expand_hex:687`, about 40 lines answering one question, extractable as
`rendered/rendered_geometry/token_checks.rb` and included back in exactly as
`design_metrics/type_checks.rb` and `contrast_checks.rb` already are.

Sequencing, since `growth.rails` is at 2374/2374 and `.md` counts toward it: a
split costs one file, and `RAILS/INSTANT.md` is one to spend. It is 304 lines of
forward proposals at a tree root, referenced by nothing in the repo, while the
repo rule is that every per-tree backlog folded into this file. Fold it into the
forward-work section and delete it, and the button partial and the token shelf
are both paid for.

#### 8. `shared/lib/pub4/` wants a `lint/` shelf, and it costs no files

13 of the 20 files in that directory end `_lint.rb` — 2,819 lines — and the other
seven are `deploy_paths`, `ci_guard`, `load_average`, `master_design`,
`baseline_ratchet`, `dialect_token_drift_check` and `importmap_preload_audit`,
which are not lints. `MASTER/tools/cohesion.rb --census --tree=RAILS --list`
proposes the regroup and it is the largest of the sixteen it finds. Moving files
into `pub4/lint/` leaves the count unchanged, so the ratchet is neutral; the cost
is renaming `Pub4::ScaleLint` to `Pub4::Lint::Scale` and following it through
`MASTER/tools/ratchets.rb:318-327` (which derives the constant from the basename
at line 360, so that mapping changes too), `shared/config/ci.rb:53-60`,
`gates/lib/source/scale_ratchet.rb` and nine test files. Worth doing, but it is
an afternoon and it touches a MASTER ratchet, so it is not a first move.

#### 9. Smaller, verified

- `shared/lib/pub4/asset_url_lint.rb:48-60` says "The 5 that remain" and "2 are
  lg.svg, once per vendored copy". `BASELINES` on line 61 is 4 and the lint
  prints 4, because `Dir.glob("**/lightgallery.css")` now returns one path. The
  duplicate the comment describes, and the `rails_duplicate_vendor_css` register
  entry it cites, are both gone. A comment states the present-tense reason.
- `shared/app/services/scrape.rb` defines bare top-level `Scrape` from an engine
  autoload root, called from six places in two apps. It works, but it is finding
  1's hazard class: the engine puts 19 files at unnamespaced roots, and one of
  them has already lost a collision silently. The `Application*` five must stay
  bare by Rails convention; `scrape.rb`, `site_verification.rb`,
  `schema_helper.rb` and `passwords_mailer.rb` need not.
- `RAILS/test/` holds 80 files in one drawer and `test/gates/` holds 13.
  `run_all.rb` globs recursively (`test/**/*_test.rb`), so subject shelves —
  `test/lints/`, `test/layout/` — need no runner change. Navigational only.
- `dns_zones` is the one red gate: `bsdports.org` resolves to
  185.134.245.114, not to us. Already the OPENBSD section's
  `bsdports_org_delegated_to_parking`; not a RAILS defect.
- `Shared::Engine.config.eager_load_paths` is empty while
  `Shared::Engine.paths.eager_load` lists eleven directories. Whether that means
  the engine is not eager-loaded in production, or is only a Rails 8.1 internal,
  is **not settled** — `bin/rails zeitwerk:check` could not finish in this
  worktree because the development database has no `users` table. Least sure item
  here; worth ten minutes on a migrated checkout, because it is the difference
  between a boot failure and a first-request 500.
- Eager loading needs a migrated database either way: `zeitwerk:check` aborted at
  `bsdports/app/controllers/categories_controller.rb:6` with `Could not find
  table 'users'`, because `Shared::Authentication.allow_unauthenticated_access`
  reads `::User.column_names` in a class body.

#### Not worth chasing — measured and rejected

- **The three per-app `Current` models.** `amber` and `bsdports` are
  byte-identical six-liners and brgen's 36-line version is a strict superset with
  eleven extra attributes it genuinely needs. `Current` has to be a bare constant
  for `Current.user`; there is nothing to share.
- **`brgen/app/models/user/*_associations.rb`.** Seven files of 12–48 lines, one
  per vertical, and the cohesion census proposes a `user/associations/` shelf.
  `brgen/ENGINES.md` says under "What stays in the host": shared models, `User`
  first. Moving them into the engines contradicts the contract; renaming them
  gains a path segment.
- **The `honesty` shelf in `gates/lib/source/`.** Three files, 275 lines,
  united by a word rather than a subject — affiliate disclosure, Faker filler and
  payment claims. `gates.yml` addresses each by `require` and `class`, so a shelf
  renames three classes and edits three rows for one path segment in a directory
  of 17. The census's constant renames are wrong here anyway: gates use explicit
  `require_relative` with hand-chosen namespaces.
- **The four ActiveRecord regroups the census proposes** — `item` and
  `declutter` in `amber/app/models`, `community`, `fedi` and `story` in
  `brgen/app/models`. `OutfitItem -> Item::Outfit` collides with `Outfit`, and
  every one of them costs `class_name:`/`table_name:` churn through
  strict-loading associations for a navigational gain. `fedi_*` is the only one
  that reads cleanly as `Fedi::*`, and it is four files of 119 lines.
- **The four missing assets `asset_url_lint` reports.** Both exemptions are
  documented at `shared/lib/pub4/asset_url_lint.rb:48-60` and verified still
  true: the three `pp-neue-montreal` woff2 are a licensed face that cannot be
  committed, behind two `local()` entries and an Arial fallback; `lg.svg` is
  lightGallery's IE9 tail entry that no browser asks for.
- **`RAILS/*.sh`.** All ten root scripts are reached — `_scaffold.sh` and
  `_service.sh` from `_deploy.sh`, the rest from `OPENBSD/bin/vps-deploy`,
  `vps_ci.sh` and the contract tests. Not sprawl.
- **`MASTER/tools/cohesion.rb <dir>` on a tree root.** It globs
  `File.join(dir, "*.rb")` and does not recurse, so `cohesion.rb RAILS/shared`
  reports "nothing to merge" having read zero files. Use
  `--census --tree=RAILS --list`.

#### What could not be measured

The `rendered_*` and `live_*` families need a booted fleet and the fleet was not
booted, so `rendered_suite` and its eleven leaves, `user_flow`, `first_screen`,
`surface_schema`, `flow_journey`, `page_simulation`, `deploy_drift`,
`human_walkthrough`, `visual_contract` and `gate_mutation` are unmeasured here.
So is per-app `bin/ci`: RuboCop, Brakeman and the app test suites want each app's
bundle and a migrated database, and this worktree has neither. The
`_zen_shell.scss` split and the `CrawlSupport.fetch` consolidation both want
`RAILS/bin/triangle up` and a full `rendered_suite` before they are called done.

---

## OPENBSD

### Operator debt — still open

The former `OPENBSD/data/debt.yml` `open:` register. Each item below
carries a hidden HTML-comment marker on its own line just under its
heading; `MASTER/lib/pub4/operator_docs.rb` counts those marker lines for
the `MASTER/bin/pub4 status` debt line, so keep exactly one per open item.

#### `libvips_local_build`  — tag: operator-priority

<!-- open-debt -->

vm23 runs a locally built libvips, and `pkg_add -u` will replace it with the stock package. The port graphics/libvips carries `-Drsvg=disabled` among the loaders OpenBSD turns off, so the packaged build has no svgload at all — librsvg-2.61.1 is installed beside it and is never reached. amber's garment cut-outs need it: Amber::GarmentSilhouette rasterises SVG it generates itself.
 Rebuilt 2026-08-23 from a signify-verified 7.8 ports tree with `-Drsvg=enabled` and `x11/gnome/librsvg` added to LIB_DEPENDS (the port path is x11/gnome, not graphics — `graphics/librsvg` fails as a broken dependency). Package kept at /usr/ports/packages/amd64/all/libvips-8.14.5.tgz, so a re-install after an update is `make reinstall` in /usr/ports/graphics/libvips rather than a fresh build.
 What makes this quiet: GarmentSilhouette#png returns nil and logs one line when vips cannot read SVG, and the seeder then keeps whatever photos the items already had. A stock-package upgrade therefore does not break the site, it just stops the cut-outs regenerating — nothing announces it. Re-check with `vips -l | grep svgload` after any pkg_add -u touching graphics.
The detection this entry asks for exists. `OPENBSD/etc/daily.local` checks `vips
-l` for svgload and logs loudly when it is gone, naming the recovery. Verified in
both directions — it passes against the live loader list and fails against a
string without svgload.
RE-MEASURED 2026-09-08 on the box: still healthy. `vips --version` reports
8.14.5, `vips -l` lists 4 svgload operators, and the rebuilt package is still at
/usr/ports/packages/amd64/all/libvips-8.14.5.tgz. The live /etc/daily.local
carries the same check as the repo copy; the two differ in one comment, which
names the retired `debt.yml` instead of this file, so an operator run of
`install_root_configs` is pending but nothing functional has drifted.
What remains is conditional operator work, not a defect: after any `pkg_add -u`
touching graphics, run `make reinstall` in /usr/ports/graphics/libvips, then
confirm with `ruby34 -e 'puts \`vips -l\`.scan("svgload").size'`, which must
print 4. daily.local runs the same read every morning and logs when it drops.

#### `off_host_dr`  — tag: operator-priority

<!-- open-debt -->

Litestream has never replicated anything, and not for the reason this entry gave. Measured on the box 2026-08-12: the binary is not installed. `which litestream` finds nothing, pkg_info has no entry, and /etc/rc.d/litestream points at /usr/local/bin/litestream, which does not exist. rcctl has been reporting litestream(failed) in daily.out under "Services that should be running but aren't", next to httpd, for months. /etc/litestream.yml was also the pre-2026-07 version, with `path: <dir>` plus `pattern:` — a form litestream rejects — so even installed it would not have started. The repo's corrected copy (one entry per database file, three apps, hjerterom's stanza gone) is deployed, so the config is right whenever the package lands. Two things, in order: `doas pkg_add litestream`, then an off-host replica. The file:// replicas are on the same disk as the source, which covers an accidental delete and nothing else. Until then Shared::DatabaseSnapshotJob is the only thing backing up production.sqlite3, and it writes to that same disk.
 STOPGAP LANDED 2026-08-22: OPENBSD/bin/dr-pull pulls VACUUM INTO snapshots of every primary nightly to the operator Mac via launchd, integrity-checked and restore-drilled (brgen opens with 81,911 readable users). Litestream-with-a-bucket remains the endgame and needs an account.
RE-SCOPED 2026-08-25. This row reads as "there are no off-host backups", which
is false and has been for a while. dr-pull runs nightly from the operator Mac
under launchd, snapshots every production*.sqlite3 with VACUUM INTO, verifies
PRAGMA integrity_check on arrival and keeps 14 — verified by an actual restore
drill on 2026-08-25, posts and listings matching live exactly. The row is about
LITESTREAM, which is not in OpenBSD ports and so cannot be pkg_add'ed at all.
It is now rcctl-disabled and out of pkg_scripts, because a service that can
never start kept `rcctl ls failed` permanently non-empty and taught everyone to
skim the one list that announces a real outage. See OPENBSD/DECISIONS.md.
RE-MEASURED 2026-09-08. dr-pull is healthy — `ruby OPENBSD/bin/dr-pull --check`
reports the newest pull 0 days old, 7 kept. litestream is still absent
(`pkg_info` has no entry, /usr/local/bin/litestream does not exist) and now has
no rc.d script at all, so `rcctl get litestream status` answers "service does
not exist"; `pkg_scripts` reads master brgen amber bsdports brgen_jobs.
/var/backups/litestream/ is empty and has been since it was created on
2026-07-27, which is the measurement the rest of this entry rested on.
FOUR PLACES STILL BELIEVED IN IT, fixed 2026-09-08 and worth naming because
each was a separate fact. `RUNBOOK.md` told the operator that `etc/litestream.yml`
replicates each database to `file:///var/backups/litestream/` — the one document
an operator reads about backups, describing a replica that has never held a
byte; it now describes dr-pull and says plainly that litestream replicates
nothing. `restore_backups.sh` skipped every app whose replica was missing and
exited 0, so the disaster-recovery script walked all three apps, restored none
and printed "done"; every precondition is now a hard failure naming dr-pull, and
`test/test_restore_scripts.rb` holds it (verified by mutation — restoring the
skip turns it red). `resource_guard.sh` still said in comments that litestream
leads the shed list and that "a mild breach costs litestream and nothing else",
while `OPTIONAL` had read `bsdports amber` for some time: the guard's cheapest
step was described as free when it actually takes a site down. And
`test/resource_guard_test.sh` — the only thing that proves which site goes down
under memory pressure — asserted litestream went first, failed five of its eight
cases, and read green because no script in this repository named it. It is
corrected against the two-service ladder, verified in both directions by
reversing `OPTIONAL`, and `OPENBSD/bin/check-openbsd` runs it now. litestream is
also out of `vm_resource.yml`'s optional_services, OPERATOR.sh's optional_apps
and emergency_cpu.sh's stop loop. `OPENBSD/etc/litestream.yml` stays, because
the config is correct for the day someone builds the binary.
WHAT IS LEFT is one purchase: an off-host object store. dr-pull's copies live on
the operator Mac, which is one other disk, not a bucket.

#### `multi_app_ram`  — tag: operator-priority

<!-- open-debt -->

vm23 ~1GB cannot keep master + brgen + amber resident, and bsdports is a fourth app that does not fit at all. UVM out-of-swap kills ruby34 when they all boot. Raise RAM (≥2GB) or run amber on-demand. Restart order: master → brgen → amber → relayd. Smoke: sh OPENBSD/bin/deploy-smoke.sh (ALLOW_AMBER_DOWN=1 if amber policy is optional). It also shows up as a STARTUP RACE rather than an OOM kill, and that form looks like a broken app. amber needs ~20s to signal ready; Falcon SIGKILLs the worker if that misses its health-check window, so while another app's CI has the box at load 5+, amber restarts, gets killed, and rcctl reports amber(failed) with port 61352 closed. It is not broken — `bin/rails runner` boots it (BOOT_OK) and on a quiet box it logs "Finished startup" then ready:true within ~20s and stays. Wait for the deploy to finish and restart. Do NOT reproduce this by hand without --health-check-timeout 300: the rc.d passes it, a bare `falcon serve` defaults to 30s, and the worker then dies at exactly +30s, which reads as confirmation of a timeout theory that is wrong.
 DECIDED 2026-08-22 (operator delegation): stay at 1GB with exactly one resident worker (brgen_jobs, ~380M measured, 131M free after). The resize question reopens only if amber earns its own worker.
vps-deploy already stands the app's job worker down for the CI run (line 156,
since the 2026-08-23 OOM); doing it by hand first is unnecessary and makes that
stand-down silently skip.
THE UPGRADE DID NOT HAPPEN. An entry here said on 2026-08-25 that the operator
had scheduled 2 GB "for Friday". Two Fridays later, measured 2026-09-08:
`sysctl hw.physmem` reads 1056952320, still one gigabyte, and `swapctl -s`
reports 2549544 of 2588672 blocks used — 98.5% of swap, with 43 MB free and no
deploy running, worse than the 96% that entry recorded. A scheduled date is not
a measurement; re-read the box before believing one.
The operator command is a provider resize of vm23 and nothing in this repository
can do it. After it lands, `sysctl hw.physmem` must read at least 2147483648.

#### `internet_app_runs_as_passwordless_root_user`  — tag: operator-priority

<!-- open-debt -->

etc/rc.d/master:22 sets daemon_user="dev", and dev's doas rule is nopass with no command scoping, so ANY code execution as dev on the internet-facing app (ai.brgen.no) is root without a password. brgen/amber/bsdports correctly run as their own users; only master does not. The fix is a dedicated master user + chown. It is NOT doas command scoping — see DECISIONS.md, "/etc/doas.conf installs only on a deliberate root run", for why cmd rules cannot work here. REDUCED 2026-08-03: the `keepenv` half is gone (dev now has a five-variable setenv allowlist), so the environment-injection route to root no longer exists. The chat entry point into exec was closed 2026-07-27. The escalation primitive itself is unchanged.
 DECIDED 2026-08-22 (operator delegation): the dedicated master user migration is approved and scheduled as its own sitting — NOT improvised on a live box: create _master, chown MASTER runtime state (.master/, knowledge/, web/tmp, web/public/assets), rc.d daemon_user=_master, drop dev from doas or scope it, then a full restart drill. Until then dev's unscoped nopass doas stands measured (permit nopass ... dev as root, read from /etc/doas.conf on 2026-08-22).
NARROWED 2026-08-25. rc.d/master ran the internet-facing daemon as dev; it
now runs as master:1005, built to the same shape as brgen/amber/bsdports —
own group, _pub4ci for traverse, /bin/ksh because rc.subr needs a login shell.
It reads code and gems from /home/dev/pub4 (0755, read-only to it) and writes
only .master, web/tmp and web/log (dev:master 2775, setgid). Verified as master
before the switch: writing repo code refused, doas refused. /home/dev went
drwx--x--- to drwxr-x--- because getcwd needs read on every ancestor and
bundler calls Dir.pwd first; .ssh and priv keep drwx------.
STILL OPEN: `MASTER/bin/master` from a terminal is dev, and dev is still nopass root.
The remote path is closed; the local one is the remaining half. Both halves
re-measured on the box 2026-09-08: `/etc/rc.d/master` carries daemon_user="master"
and BUNDLE_FROZEN=true, and `/etc/doas.conf` line 39 still reads
`permit nopass setenv { … } dev as root`. The operator work is to drop or scope
that line, after which `doas -C /etc/doas.conf -u dev id` must stop naming root.
COST, recorded 2026-08-25 because the next app to be moved will pay it too:
the first deploy that carried daemon_user="master" to the box did not bring
ai.brgen.no back, and vps-deploy halted the whole pass at master. Bundler.setup
ends in Definition#write_lock, which touches Gemfile.lock on every boot even
when the resolution is unchanged; the lock is dev's, so as dev that write had
always succeeded silently and as master it is EACCES and falcon never binds.
The trace names File.utime and says nothing about users or permissions.
BUNDLE_FROZEN=true in the daemon's env is the fix and is now load-bearing —
it also makes the structural Mac-vs-BSD lock drift a startup error naming the
gem rather than a silent rewrite. Before moving brgen/amber/bsdports off any
daemon_user, check the same assumption: the daemon had write access to its own
source tree and something was quietly using it.

#### `home_partition_full_from_git_history`  — tag: operator-priority

<!-- open-debt -->

Re-measured on the box 2026-08-12, as this entry asked. /home is at 89% (1.9G free of 17G), up from 99% that morning — the three retired apps (baibl, blognet, hjerterom) still had home directories worth 1.6G between them, for products removed from the repo in July. The git figure moved too: /home/dev/pub4 is 8.0G and .git is 3.3G of it, not the 7.7G recorded on 2026-08-02, so someone has run a gc. The claim underneath stands. The ten largest objects in history are 80–87 MB WAV renders under DEPLOY/dilla/renders/beats/, a path that no longer exists and never will again; every `git pull` deploy carries them, so this does not improve by itself and more RAM does not touch it. Operator-owned: the fix is a history rewrite, i.e. a force-push to a public repo. Strip these blobs in the same pass as the key purge above.
 RE-MEASURED 2026-08-22: /home is 67% (5.4G free) and the three retired app homes are gone. What remains is exactly the history rewrite, and it is SCHEDULED, not casual: it needs every session quiescent (STUDIO carries live uncommitted work), a coordinated force-push, and a vm23 re-clone in the same hour. Strip the WAV blobs and the key purge in one pass.
RE-MEASURED 2026-09-08: /home is 67% (5.3G free of 17G), not the 89% above.
The three retired app homes this entry names — baibl, blognet, hjerterom — are
gone, and /home/dev/pub4 is 4.4G against the 8.0G recorded, so the weekly
`git gc` in weekly.local is doing its job. .git is 3.6G of the 4.4G, unmoved
across three weeks, which is the remaining shape of the problem — but it is not
pressure: /var is 16% and / is 18%. Nothing here is urgent; the entry stays only
so the .git figure has somewhere to be re-read, and the fix is still the
scheduled history rewrite, which needs every session quiescent, a coordinated
force-push and a vm23 re-clone in the same hour. Read it with
`ssh brgen 'df -h /home; du -sh /home/dev/pub4/.git'`.

#### `bsdports_org_delegated_to_parking`  — tag: operator-priority

<!-- open-debt -->

open 2026-08-25, registrar-side. bsdports.org does not resolve: the .org registry delegates it to ns1/2/3.expireddomain.hyp.net — Domeneshop's parking servers — which publish no A record. Confirmed against b0.org.afilias-nst.org, not a cached resolver. The registration is ours and paid to 2027-08-08, and whois shows autoRenewPeriod, so the shape is: it lapsed on 2026-08-08, Domeneshop moved the nameservers to parking, the registration auto-renewed, and the nameservers were never put back. Everything downstream still believes in it — relayd holds a keypair and a Host match, a valid certificate sits at /etc/ssl/bsdports.org.fullchain.pem to Nov 10 2026, RUNBOOK.md names https://bsdports.org as the URL, OPERATOR.sh probes it, rcctl says ok and the app answers 200 on 47312. It has simply been dark. Fix is one registrar change: set the nameservers at Domeneshop to ns.hyp.net and ns.brgen.no, which is what brgen.no uses. Do it before Nov 10 or the certificate renewal fails too — acme-client needs the name to resolve here for HTTP-01. Nothing we had could have caught this: domain_watch takes its population from nsd.conf and bsdports.org is not a zone we serve, and the expiry watch reads expiry, which is paid. dns_zones now asks a public resolver whether each app domain points at 46.23.89.226, and fails on this one.
STILL OPEN 2026-09-08, and this row owns it — `WISHLIST.md` 104 names the same
registrar change and points here rather than restating it. `dns_zones` also
fails on nine domains that are past expiry, which is `WISHLIST.md` 103: money at
a registrar, not code, and not a finding to re-open under a second name here.
ONE DETAIL ABOVE IS NOW WRONG, and the correction makes this worse rather than
better. bsdports.org resolves: the parking servers publish 185.134.245.114 and
2a01:5b40:0:bc04::1, and http://bsdports.org/ answers 200 with Domeneshop's
parking page. A check that reads a status code therefore calls the domain
healthy while it serves someone else's page. Only `dns_zones` catches it,
because it compares the answer against 46.23.89.226 rather than against 200.
The nameservers at the .org registry are still ns1/ns2/ns3.expireddomain.hyp.net
and whois still shows autoRenewPeriod against an expiry of 2027-08-08.
Operator command, at Domeneshop and nowhere else: set bsdports.org's nameservers
to ns.hyp.net and ns.brgen.no. It is done when
`ruby RAILS/gates/runner.rb dns_zones` passes. Do it before Nov 10 2026 or
acme-client's HTTP-01 renewal fails too.

### Debt — resolved records

Closed records are deleted when they close, and `git log` holds them. A finding
that is fixed is not a backlog item, and a file that keeps every one it ever had
teaches the reader to skim. What stays here is forward work and the false
positives worth not re-discovering — those are guards, not history.

**amberapp.com is not ours and never has been.** A row here called
`amber_moving_to_its_own_apex` planned amber's move onto that apex and, on
2026-08-22, recorded it as "bought and certified" after reading a 114-byte
JS-redirect page. That page is Afternic's for-sale lander: it redirects to
`/lander`, and the domain has been registered at GoDaddy since 2019 with
nameservers `ns1/ns2.afternic.com` and a `VERIFY.HN` fast-transfer record. The
listing asks USD 5,999. Nothing in this repository names amberapp.com, so the
belief cost nothing, but it was wrong the day it was written, and a redirect
page is not evidence of ownership — read whois before calling a domain ours.
amber is canonical at amber.brgen.no. Buying the apex is a spend decision for
Johann and Ragnhild, not a scheduled step, and the coupling it would trigger is
worth keeping: the session cookie is `domain: :all`, scoped to the registrable
domain, so a move off brgen.no silently ends cross-app sign-in, and
`Shared::SsoToken` is consume-only in this tree.

### Survey — the shell tree read end to end, 2026-09-08

A survey, not a cleanup. Nothing under `OPENBSD/` was changed. Every item names a
file and a line, or a command and its output, and says how it was checked. Box
measurements are read-only over ssh, taken while another session was deploying,
and are stated as divergences rather than as live effects.

One instrument was wrong before it was right, and it is the first thing to read.
`bin/vps-deploy:153` guards its config-drift warning on
`[[ -x /usr/local/bin/config_drift_gate.rb ]]`, which is the exact shape
`installed_targets_gate.rb`'s own header records as a dead guard for
`daily.local`. It is not dead. `OPERATOR.sh:293` installs that file explicitly,
`ls` on the box finds it dated Aug 25, and `/tmp/vps-deploy-drift.out` is dated
Sep 5 12:34 — the last brgen deploy. The finding died on verification and a
better one came out of the same measurement, item 3 below.

The tree holds 169 files outside `var/`: 43 `.sh`, 35 with no extension, 34
`.rb`, 11 `.exp`, the rest config and prose. Those are this survey's own counts;
`MASTER/tools/ratchets.rb` and `sprawl_census.rb` printed nothing when run
directly, so the `growth.openbsd` ceiling of 107 counts a narrower set and no
number here is quoted from it.

The operator-debt rows above were worked on the same day and are not
re-surveyed. None of them turned out to be wrong.

#### 1. `bin/pub4 gate` measures twelve of this tree's 292 assertions

`MASTER/lib/pub4/gate_chain.rb:142` runs the OPENBSD suite as
`Dir["test/test_*.rb"].sort.each { |f| system(RbConfig.ruby, f) || abort(f) }`.
`abort` stops the loop. `test/test_domain_expiry.rb` sorts first and is red on
nine domains past their expiry date, so the stage ends there. Run verbatim from
`OPENBSD/`: 4 runs, 12 assertions, exit 1, last line `test/test_domain_expiry.rb`.
`OPENBSD/bin/check:36` loads the same glob into one process and gets 76 runs and
292 assertions. Nine files — the gate library, the githooks, guard state, the
health check, reach, the restore scripts, solid queue, the tracked crontab and
the safety gate — have therefore not executed under the repo-wide ladder since
the ninth domain lapsed, while `bin/check` runs them all and reports the same one
failure. The failure is a registrar bill, not code, and it is hiding 280
assertions behind itself. Fix: collect failures rather than `abort`, and give the
expiry assertion its own step so a spend decision cannot silence a contract
suite.

#### 2. Live `/etc/rc.d/amber` and `/etc/rc.d/bsdports` wait 30 seconds where the repo waits 300

`ruby OPENBSD/config_drift_gate.rb --remote` exits 1 and names three drifted
files; `doas cat` and `diff` give the content. Both rc.d scripts differ from the
repo in one number: `while [ "$_i" -lt 300 ]` in the repo, `-lt 30` on the box,
at `rc.d/amber:58` and `rc.d/bsdports:60`. That loop sets `_up_ok`, and `_up_ok`
is what decides whether `rcctl restart relayd` runs — an app that answers `/up`
late leaves relayd pointing at a dead backend and logs `relayd skipped`. Commit
`d76fa573c` (2026-08-28, "the box is slower than every timeout allowed for")
raised both to 300 for exactly that reason. The live files are dated Aug 27
17:35 and predate it; `/etc/rc.d/brgen` and `/etc/rc.d/master` were installed
Sep 5. So the documented fix for the recurring amber/bsdports shed-and-stay-down
has never reached the two services it was written for. Fix: one
`install_root_configs` run. `grep "relayd skipped" /var/log/daemon` finds none,
but `daemon` rotates roughly hourly and the current file covers about two and a
half hours, so nothing here dates the last occurrence.

The third divergence is a comment: the repo's `doas.conf` cites `TODO.md` where
live cites the retired `OPENBSD/data/debt.yml`. Functionally identical, and it
is why the drift gate is red — which is the shape that teaches an operator to
skim a red gate.

#### 3. Nothing compares `/usr/local/bin`, and seven of twelve root-cron executables differ

`config_drift_gate.rb`'s `VERBATIM` is eleven files under `/etc` and its
`EXCLUDED` is four more. It never reads `/usr/local`, where every cron job on
this box lives. Checked by `cksum` over ssh against the repo copies: divergent
are `config_drift_gate.rb`, `resource_guard.sh`, `config-drift-check`,
`core-reclaim.sh`, `drain-jobs.sh`, `prune-guests.sh` and `relayd-watchdog`;
matching are `keep-warm.sh`, `prune_guests.rb`, `renew-certs.sh`,
`uptime-check.sh` and `nsd-resign`. Two consequences. The drift detector cannot
see that its own installed copy has drifted, and the warning at
`bin/vps-deploy:154` is produced by that stale copy rather than by the gate in
the commit being deployed. And `test/resource_guard_test.sh` proves which site
goes down under memory pressure about `OPENBSD/resource_guard.sh`, 14,196 bytes,
while the file root runs every five minutes is 14,099.

The one difference that could be named is benign, and saying so is the point. Live
`OPTIONAL` reads `litestream bsdports amber` against the repo's `bsdports amber`,
and the shed loop at `resource_guard.sh:230` only sheds a service `rcctl check`
calls `(ok)`, which a service with no rc.d script never is. The category is
unwatched, not that today's instance bites. Fix: extend the gate to the installed
script tree, which is where the box's scheduled behaviour actually lives.

#### 4. `resource_guard.sh` guards its crisis tier on a file nothing installs

`resource_guard.sh:284` reads `[ -x /usr/local/bin/emergency_cpu.sh ]`, line 285
runs it, line 287 logs that it is not installed. `ls` on the box: no such file.
The target is tracked at `OPENBSD/emergency_cpu.sh`, the tree root, and
`OPERATOR.sh` carries explicit `install` lines for `resource_guard.sh` (276) and
`config_drift_gate.rb` (293) and none for this one. So `LOAD_CRIT` has only ever
logged, and it fails loudly, which is the one mercy here.

Two instruments exist for this shape and both report clean.
`installed_targets_gate.rb`'s `CONFIG_GLOBS` are `etc/crontab*`, `etc/*.local`
and `etc/rc.d/*`; `tools/reach.rb` reads the same three plus the nsd zones. A
guard living inside an installed script is invisible to both. Widening the scan
to every file in the tree finds exactly one genuine orphan — this one; the other
seven hits are test fixtures in `test_reach.rb` and one line of `RUNBOOK.md`. Fix:
add the install line, and widen both censuses, which will stay quiet.

#### 5. `uptime-check.sh` has mailed root 7,924 DOWN lines

`/var/log/uptime-check.log` is 660 KB and holds 7,924 `DOWN` lines: 4,811 for
`https://bsdports.org/up`, 2,693 for amber, 265 for ai and 155 for brgen. The
crontab comment says "cron mails root on a DOWN line". The largest share is a
registrar setting: `curl https://bsdports.org/up` returns 000, connection refused
on 443, because the parking nameservers terminate no TLS, while
`curl http://bsdports.org/up` returns 200 from Domeneshop's parking page. A
checker reading HTTPS calls the domain down forever; a checker reading HTTP calls
it healthy. Both repo checkers use HTTPS, and `bin/deploy-smoke.sh:201` makes it a
required check. The registrar fix is already the `bsdports_org_delegated_to_parking`
row above. What belongs here is the alarm: thousands of mails whose cause is
known make root's mailbox unreadable, which is the same lesson the litestream
`rcctl ls failed` decision records. Waive the domain by name in both checkers
until the nameservers move.

#### 6. The two `uptime-check.sh` disagree, and cron runs the one the other argues against

`bin/uptime-check.sh` is a wrapper onto `health_check.rb --public-only
--all-ready-apps`, and its header argues that a hardcoded URL list "can only go
stale — it would still name four domains after a fifth app ships, and nothing
would report that". `usr/local/bin/uptime-check.sh` is that hardcoded four-domain
list, and `doas crontab -l` shows it is the one running every five minutes. The
wrapper works — `health_check.rb` does accept `--public-only`, checked at line 34
— it simply runs nowhere. Fix: install the wrapper, or drop the argument from the
header and keep the list.

#### 7. Eight cron logs grow without rotation

`etc/newsyslog.conf` carries stanzas for four pub4 logs; `etc/crontab.vm23` and
`etc/*.local` write nine. Unrotated: `config_drift.log`, `core-reclaim.log`,
`domain_watch.log`, `drain-jobs.log`, `git_gc.log`, `keep-warm.log`,
`prune-guests.log`, `uptime-check.log`. On the box `drain-jobs.detail.log` is
10.8 MB, `uptime-check.log` 660 KB and `config_drift.log` 417 KB of identical
`config-drift ok` lines, one every fifteen minutes. `/var` is at 16%, so this is
not pressure — but that file's own header records `/var` at 106% from exactly
this neglect, and the fix it applied covered only the logs that existed then.
Every job added since brought a log and no stanza. Fix: a stanza each, and a test
asserting every `>> /var/log/...` in the crontab has one.

#### 8. `vps_weekly_integrity.sh` says where to install it, and it is installed nowhere

Its header reads "Install in root crontab or daily.local". `doas crontab -l`,
`etc/weekly.local` and `etc/daily.local` were all read and none names it. So
`integrity_gate.rb` and `health_check.rb --public --all-ready-apps --json` run on
no schedule on vm23; the only integrity run is `OPENBSD/bin/check-full` on the
operator's Mac. Its own skip path is the same shape: line 16 exits 0 when the CI
lock is held, into a log nothing reads, so a skipped weekly run and a passing one
are the same event. Fix: schedule it, or delete it and say plainly that the
integrity gate is a laptop gate.

#### 9. `etc/rc.d/master:153` still does what the comment twenty lines above forbids

Lines 126-129 explain the bug: `|| true` on precompile plus an unconditional
stamp write made every later start skip precompile, because the skip test is
stamp-equals-digest. Lines 136-141 write the stamp only on success. The
gate-failure retry at 153-154 runs
`(... rails assets:precompile) 2>/dev/null || true` and then writes the stamp
regardless. The blast radius is bounded — line 158 still refuses the start when
the gate fails twice — so this is a stamp that lies rather than an outage, and it
is the item on this list I am least sure earns work. Fix is the same `if`/`else`
as above it. Line 112 in the same file has the quieter version: `_face_assets=$(
... face_asset_paths.rb 2>/dev/null)` yields an empty list when that script
fails, narrowing the digest to the seven hardcoded inputs and reproducing the
stale-fingerprint bug the comment above it describes.

#### 10. Seven scripts deploy this box, three write the same master sequence, two report success having done nothing

The seven: `bin/vps-deploy` (the one CLAUDE.md and RUNBOOK name), `deploy_all.sh`,
`vps_install_all.sh`, `vps_on_vm_install.sh`, `vps_production_push.sh`,
`vps_deploy_master.sh`, `manual_master_deploy.ksh`. Three of them build the three
face bundles, precompile and run the `master_web_assets` gate, with three
different failure semantics: `rc.d/master:100` swallows the face build,
`vps_deploy_master.sh:42` swallows it, `manual_master_deploy.ksh:37` records
`_fail=1` and exits 1. Two end green whatever happened —
`vps_on_vm_install.sh:22` turns a failed app deploy into `WARN: $app failed` and
finishes on `log "done"`, defeating its own `set -euo pipefail`, and
`vps_install_all.sh:61` finishes on `doas rcctl check master 2>/dev/null || true`.
`deploy_all.sh`, `vps_run_remote.sh` and `manual_master_deploy.ksh` are named by
`RUNBOOK.md` and by nothing that runs. `OPENBSD/bin/` is at its
`pub4_entrypoint_ceilings` of 17, five of them `check-*`. Fix: retire the scripts
whose only caller is the runbook, and make the survivors exit non-zero.

#### 11. Seven implementations of one load gate, and the awk ban has no detector

`vps_master_scan.sh:13-16` carries the note "awk twice, in a repo that bans it in
committed scripts" and does the comparison in one `ruby34 -e`. `vps_ci_all.sh:13`
and `:17` still shell out to awk for the identical `vm.loadavg` field, and
`check-openbsd:39` only runs `zsh -n` over that file, which is syntax. Seven
places read the load and compare a field against a ceiling: `vps_ci_all.sh`,
`vps_master_scan.sh`, `resource_guard.sh:101`, `core-reclaim.sh:65`,
`stale_ci_cleanup.ksh:16` in awk, and `drain-jobs.sh:52`, `prune-guests.sh:49` in
Ruby.

The ban itself is unenforced here. `zsh.banned_commands` at
`MASTER/data/rules.yml:560` has two readers, `MASTER/lib/io/shell.rb:27` and
`MASTER/lib/voice/personality_prompt_builder.rb:325`, so it governs what MASTER's
own shell effect runs and warns about, not what this tree commits. A scan over
`OPENBSD/` for those commands in command position finds 75 hits in 17 files, 30
of them in `dotfiles/mov.sh`. Fix: one `lib/load.sh` helper the seven callers
share, and then either a scanner rule over `OPENBSD/**/*.{sh,ksh,zsh}` or a note
saying the ban is advice outside MASTER.

#### 12. Usage after the work, in four files

`OPERATOR.sh` is 960 lines and its usage is at 906. `bin/deploy-smoke.sh` handles
`-h|--help` at 161, after the banner at 149: `sh OPENBSD/bin/deploy-smoke.sh
--help` prints `deploy-smoke: mode=--help timeout=20s` and then the usage, which
was confirmed by running it. `validate_doas.ksh` puts usage at 100 of 116 with
its first side effect at 31. `lib/ssh_vm23.sh` at 52 of 60. What an operator
needs first should come first; in all four it comes last.

#### 13. Nine two-line expect shims, and three dead in-tree paths

`vps_console_status.exp`, `_probe`, `_short`, `_install`, `_fix_key`,
`_poll_install`, `_start_install`, `_sync_and_install` and `vps_drop_install.exp`
are each one line: `exec [file join [file dirname $argv0] vps_console.exp]
<subcommand> {*}$argv`. The dispatcher already takes the subcommand as its first
argument. Their shared guard is wired — `vps_console.exp:8` sources
`vps_console_common.exp` and line 9 calls `require_console_risk_ack` — and its
refusal message names `OPENBSD/VPS_SAFETY.md` and `OPENBSD/OPERATOR_CONTRACT.md`,
neither of which exists. `deploy_all.sh:6` points at
`OPENBSD/archive/recovery/manifest.json`, which does not exist;
`DECISIONS.md:200` still names the retired `OPENBSD/data/debt.yml`. Six dangling
in-tree paths in total, and that is the whole list. The shims were not exercised
— they refuse without `I_UNDERSTAND_CONSOLE_RISK=1` and are recovery-only — so
whether Tcl's `exec` buffers their output is unverified.

#### 14. One dead local in `restore_backups.sh`

`ROOT_DIR` at line 21 is assigned and read nowhere in the file. The disaster-recovery
hardening the previous session landed does hold: every precondition exits 1,
`test_restore_scripts.rb` pins the replica check, and the bare `ruby` at line 34
is fine because `/usr/local/bin/ruby` on vm23 is a symlink to `ruby34`.

#### Not worth chasing

- **Ruby entry points come last, everywhere.** `config_drift_gate.rb`'s skip
  guard is at 125 of 162, `installed_targets_gate.rb`'s `run` at 83 of 111,
  `health_check.rb`'s first `def` at 51 of 414. The language wants the definition
  before the call and the tree is consistent about it. Reordering buys nothing.
- **Hardcoded ports in `bin/smoke-apps.sh` and `bin/deploy-smoke.sh`.**
  `ruby RAILS/gates/runner.rb port_inventory` compares them against `apps.yml`
  and passes; `RAILS/gates/lib/host/port_inventory.rb:57-58` names both files.
- **Most `|| true`.** About a hundred instances, and the majority are idempotence
  on `rcctl`, `pkill`, `chmod`, `install` and `rm -f`. `start_all_apps.sh:16-17`
  swallows enable and start and then fails correctly at line 24
  (`rcctl check "$svc" || exit 1`). Read the exit path before flagging one.
- **`test/resource_guard_test.sh`.** `ksh OPENBSD/test/resource_guard_test.sh
  OPENBSD/resource_guard.sh` prints ALL PASS across all eight cases and exits 0,
  and `check-openbsd:36` runs it. The precedent is closed. The only note is that
  `bin/pub4 gate`'s OPENBSD stage globs `test/test_*.rb` and so does not include
  it — the two entrypoints cover different halves of this directory.
- **`dotfiles/mov.sh`.** 2,343 lines, the largest shell file in the tree, thirty
  banned-tool hits, and a torrent-and-transcode tool with nothing to do with
  vm23. It is a dotfile and it is the owner's. Moving it is a `growth` argument.
- **`test_gate_lib.rb:23`** prints `Failures:` and `  - nope` into the suite's
  stdout. Cosmetic.
- **Four gates that pass and mean it.** `installed_targets_gate.rb`,
  `tools/reach.rb`, `deploy_smoke_gate.rb` and `port_inventory` all pass, and
  `config-drift-check` is green on the box (13 relayd hosts, 417 acme SANs, 57
  zones). Their coverage gaps are items 3 and 4; there is no finding inside them.
- **The `config_drift_gate.rb` / `config-drift-check` name pair.** Two different
  questions — repo-versus-live `/etc` bytes, and relayd/acme/nsd consistency —
  under two names one letter apart, and the confusion has already cost a check
  its life once. Renaming either breaks an install line and a crontab entry, so
  this is a note, not work.

#### What could not be measured

`brgen.no` and `ai.brgen.no` answered 000 during this survey while `amber.brgen.no`
answered 200; another session was deploying, so none of that is treated as a
finding and the live smoke was not run. `/var/log/daemon` rotates about hourly and
the current file holds no `relayd skipped`, which dates nothing. The expect shims
are recovery-gated and were not executed. And the ratchet tools printed nothing
when invoked directly, so every file count above is this survey's own census.

## STUDIO

No standing backlog file exists for STUDIO, and none is invented here. dilla,
postpro, repligen and lora carry their working decisions in their own
`README`/`AMBITION`/`ENV_AND_RENDER` docs and in operator memory, not a debt
register. Two standing constraints belong on the record because they bound any
agent work in this tree:

- **Renders are irreplaceable.** dilla and postpro write real output with
  rotating seeds; never render over a take that matters, and never change a
  rendered-sound or graded-look default on your own judgement.
- **dilla is production tooling**, aimed at being genre-agnostic (Detroit lean,
  but techno/soul/jazz must blend as parameters). That direction is a design
  goal, not a backlog item to close unprompted.

### The crate — what 2026-09-02 established about it

Measured while answering a question about disk, and the numbers are worse than
the question was.

- **160 of the crate's 161 sources no longer exist.** Every rack's sidecar
  names the file it was chopped from; exactly one, `samples/dug/arat_swost_wolet.mp3`,
  is still on disk. `samples/dug/` was gitignored, so the 2026-08-31 tree loss
  took it and the reclone could not bring it back. The 2-second loops in
  `samples/chopped/` are now the only surviving audio from those records.
- **The crate is in no backup.** `STUDIO/dilla/.gitignore:11` ignores
  `samples/` wholesale — zero racks are tracked — and `OPENBSD/bin/dr-pull`
  copies the three production databases and nothing else. So 12 minutes of
  irreplaceable audio lives on exactly one disk, which is the state
  `samples/dug/` was in the day before it went. **This is the open item**: pull
  `samples/` to the same rotated off-box location dr-pull already uses, or
  somewhere the operator names.
- **37 duplicate racks were deleted 2026-09-02, on the operator's instruction.**
  `radio_chop.rb:664` records the cause: one shared work directory keyed cuts on
  the window's offset alone, so record B was handed the cut record A made at the
  same decisecond. 161 racks carried 123 unique loops; Barney Kessel, Gorillaz
  and "Gimme the Flu" were one wav under four names. The fix (a directory per
  source) was already in; the damage was not, and none of it could be re-chopped
  because all 66 affected sources are gone.
  The rule was: keep every rack the liveset names, then the earliest
  `rendered_at` in each group — the rack whose own chop run made the audio,
  since the later ones only reused its cached cut. A dry run caught the rule
  deleting `andrzej_koszinski_eurocr_01`, a live bed, because a *second* rack in
  its group was also a bed and won on age; keeping every named rack is why one
  duplicate pair deliberately survives. 124 racks now, 123 unique, all 22
  liveset beds resolve.
- **`scratch/chop_work` was deleted with them** — 2,144 files, 5.4 GB, the
  Henryk Debich windows and their six-stem separations. It was never wired into
  the liveset (the rig globs `samples/chopped/*/`), and its one consumer, the
  chop cache, is unreachable because `RadioChop.chop` scans the source before it
  consults the cache and that source is gone. It was still 67 minutes of audio
  against the crate's 12, and it is not recoverable.

### The engine is one file

dilla.rb carries the 81 parts that were under `lib/engine/`, in the order they
were required, because that order was load-bearing. 129 ruby files to 48.
`DillaSources` still defines the corpus and it is now the entry plus the 41
support modules; `STUDIO/gate.rb` fails if `lib/engine/` reappears, and
`DILLA_SUPPORT_CEILING` caps the modules that could grow in its place.

Not done: the 41 `lib/*.rb` are still separate. Fourteen of them use `__dir__`
or `__FILE__`, which shift a directory level when a file moves — the bug that
broke three tests during the first fold, and the reason to do the second one
deliberately rather than as a tail-end.


### The crate — opened 2026-09-01

The chop cache was keyed on a window's offset and not on the record, fixed in
`003e0a9f9`. What follows is what that fix does not repair and what looking for
it turned up. The preset half of this subject is `WISHLIST.md` 100–101 and is
not restated here.

- **Forty-one of the crate's forty-two sources are gone.** `samples/dug/` holds
  one file. They were gitignored on the reasoning that dug audio is
  "re-fetchable from the network", and nothing recorded a URL — not
  `provenance.json`, not one of the 161 loop sidecars, which carry only the
  reproduce command and so name a path that no longer exists. Only the titles
  survive, in the slugs. Re-fetching by title returns *a* upload, not the one
  that was cut, so offsets and mastering will not match and no loop is
  reproducible from its sidecar. One record is the exception:
  `henrik_debich`, whose separated stems outlived its source in
  `scratch/chop_work/` and were moved under their slug rather than orphaned.
  New fetches record the HTTP URL: `CrateDig.archive_entry` / `ccmixter_entry`
  store `url`, `record!` refuses an entry without one, and the chop sidecar
  copies it from crate provenance. The 160 already-missing sources stay gone.
- **Thirty-eight of 161 racks are another record's audio under the wrong name.**
  123 unique wavs, 28 collision groups; Barney Kessel, Gorillaz and "Gimme the
  Flu" share one loop. The cache fix stops it recurring and repairs none of it:
  reattributing a rack needs the source that made it, and the sources are the
  entry above. The registry can be deduplicated to 123 by checksum — that is
  measurement — but which of the names in a group is the true one cannot be
  recovered, so the honest move is to drop the duplicates and keep whichever
  rack the worth table already scored.
- **153 of 161 racks were cut by the seam test that preferred mid-phrase.**
  `28225f2c9` fixed it and re-cut only the OSC eight, saying plainly that the
  rest is re-cut or left alone. Re-cutting is blocked by the missing sources, so
  the only source-free remedy is rotating each loop onto its strongest downbeat,
  which is content-preserving because a rack is one whole period. Measured over
  the crate: current downbeat mean +1.17 dB against +2.86 for the re-cut eight,
  108 of the 153 sitting under 1 dB. **The measure needs a floor before it is
  acted on** — several of the largest apparent gains are a quiet tail scoring as
  a downbeat, not a bar line, and one rack starts at -57 dB.
- **148 registry rows carry only what a wav can be asked for.** The rebuild that
  recovered the crate after the registry was clobbered reconstructed bpm from
  each file's own duration and voicing from its spectrum, and `key` was measured
  back on 2026-09-01. `source`, `source_start_sec`, `self_similarity` and
  `rejoin_db` are gone for those rows and cannot be recomputed without the
  source. `vocal_chop` skips a row that cannot name its record rather than
  guessing, which is why those 148 have no vocal chop available.
- **`DRUM_LOOP` falls back to `~/Downloads`.** `drum_loop_source`
  (`dilla.rb:7215`) resolves to `File.expand_path("~/Downloads/techno_drums.mp3")`
  when the samples copy is absent, and the samples copy is absent. A render
  therefore depends on a file outside the repo, and the one there is industrial
  techno, which the crate rules exclude. Naming the replacement is an operator's
  call because it changes rendered sound.
- **`test_dilla_audio_graph_parity.rb` follows the engine.** Bus routing is
  opt-in (`DILLA_MIX_BUSES=1`); the default path is still a flat amix, and the
  test asserts both.
- **Three engine tests exceed their 90 s timeout under suite load.**
  `test_smoke_two_bar_render`, `test_provenance_separates` and
  `test_dilla_frozen_reads` each pass in about 23 s run alone and time out
  inside `rake test`. Not a defect in what they measure; the budget does not
  survive a loaded machine, and a green subset here proves only that.

## The unified handoff, read against the tree — 2026-08-31

`CLAUDE_OPUS_UNIFIED_HANDOFF.md` arrived at the repo root in `8dfe41309` as an
implementation brief. It is 302 lines and it stops mid-list, at
"pagination/filtering;" under section 7 — the file is truncated, so anything the
author intended after the Rails test matrix is not in this repository at all.
It is also a fourth file at a root that `CLAUDE.md` says holds two, and most of
its asks restate this file or `WISHLIST.md` in different words, which is the
"two backlogs saying the same thing" defect the preamble here names. It is left
in place rather than folded or deleted, because that is an owner's call; what
follows is the audit, so the next reader does not do it again.

Its own first instruction — "reconcile every change against the current tree
before applying it, do not blindly paste historical snippets" — is what this
audit is. Two of its premises did not survive that reconciliation.

**3.2, the circuit-breaker hazard — done, and its premise was already stale.**
The brief asks after a `Stoplight::Light` NameError and says to check the tree
rather than assume. Checked: `Stoplight` appears nowhere — not in `lib/`, not in
the `Gemfile`, not in `Gemfile.lock`. There is no hazard to repair and no stale
reference to remove. The half that was real is the one it names second: test the
replacement's states. `Master::Io::CircuitBreaker` is hand-rolled and its two
existing tests covered the rate limiter and the per-model registry, so the
closed -> open -> half_open -> closed machine, the eight-failure threshold, the
thirty-second cooldown and the recovery had nothing holding them.
`MASTER/test/test_circuit_breaker_states.rb` holds all four now, plus the two
error classes that must *not* open it (a provider rate limit, an absent key) and
the state file that survives the process. Verified by mutation: four separate
breaks in the implementation each turn it red.

**4, multi-agent safety — done.** "Where hooks already exist, test them as
executable behaviour rather than documenting them only" was the sharpest line in
the brief, and it was exactly right. `OPENBSD/dev/githooks/` holds the three
guards that are the whole defence against trap one, and nothing tested any of
them. A hook that stopped firing looks identical to a week in which nobody made
the mistake. `OPENBSD/test/test_githooks.rb` runs all three through real git in
a throwaway repository — real commits, a real bare remote, a real push — because
a hook is installed behaviour and unit-testing its logic would not catch a lost
chmod, a bad shebang, or a `core.hooksPath` pointing somewhere else. It covers
every case the brief lists (cross-tree refusal and its override, multi-commit
push refusal and its override, the clean single-commit path, the diagnostic
output) and three the brief did not: the half-landed move, STUDIO session
ownership, and that an absent session ledger reads as "unknown" rather than
accusing every commit of being foreign.

**3.1, 3.3, 3.4, 3.5, 3.6, 5, 6, 7 — open, and each is a sitting.** These are
programs, not tasks: boundary validation for every data contract, the
require-order graph, snapshot rollback, autoloop fencing, dead-session startup,
routing resilience, and a full Rails audit with a test matrix. Where they touch
something this file already tracks, this file is the record and the brief is a
restatement — do not open a second row for the same work under the brief's
numbering.

## Cross-cutting programs

Larger efforts that span trees or do not belong to any single one. Each is a
program with its own sitting, listed so they are visible in one place rather
than implied across four.

- **Realtime wiring — instrumented and down to one recorded exception, 2026-09-05.**
  `turbo_broadcast_contract_test.rb` already asked whether a broadcast has a
  partial. It now reads every *named* stream from both ends, and two pairs had
  never matched: `brgen:notifications:*`, written on every notification create by
  a synchronous `broadcast_prepend_to` and read nowhere, and `items`, subscribed
  by amber's busiest page against a model that declines `broadcasts_refreshes` on
  purpose. Both removed, each with the reason at the site. The one tolerated
  entry is `NotificationDeliveryJob`, which is enqueued by nothing and kept only
  until vm23 confirms no queued row names it; `UNREAD_STREAMS` carries it and
  fails if it stops being true.

  Literal streams only, and that is the whole of the instrument's honesty:
  `broadcast_refresh_to self` names its stream at runtime, and guessing which
  view subscribes to `@conversation` is how a census reports the shape of the
  tree and calls it a defect. Three false positives died on the way and each is
  worth not re-deriving — the ERB comment recording a dropped subscription read
  as the subscription, `broadcast_refresh_to` was outside the DOM-verb pattern so
  three quarters of amber's streams read as orphans, and
  `Turbo::StreamsChannel.broadcast_append_to(` puts its stream literal on the
  next line, which made `LocationsController` silent and the layout's
  `nearby_alerts` subscription an orphan. Mutation-checked in all three
  directions: a new dead broadcast, a stale `UNREAD_STREAMS` entry, and a
  restored orphan subscription each turn it red.

  What is left is the dynamic half, deliberately: a stream named by an object
  rather than a string needs a runtime instrument, not a wider regex.
- **Seed realism.** Coordinates and timezones for every DomainRegistry city
  live in `CitySeed::COORDINATES` / `TIME_ZONES`. Population is still unset.
- **Bringhurst typography codification.** Turn the typographic rules the design
  system already half-follows into enforced tokens and a gate, rather than
  convention.
- **The layout pass.** Roughly 178 proposals from a study of joi.com, kimi.com
  and medium.com, worked one category at a time; about sixty are closed. Its own
  section below carries the state and the doctrine it produced.
- **Web-face redo.** The MASTER web face (WebGL + TTS) wants a rebuild; see the
  web-face notes in the MASTER debt records for the current failure map.
- **README consolidation.** The per-tree READMEs overlap and drift; one pass to
  make each the single maintained long-form reference for its tree.
- **`tree.rb` on entry.** Run the tree map on session entry so an agent orients
  from the real layout rather than a remembered one.
- **Onboarding.** A first-contact path that gets a new agent or contributor from
  clone to a green check without reading every contract.
- **Local-LLM fallback.** A path that keeps the runtime working when no API key
  and no `claude` CLI are present.
- **PWA banner.** Closed 2026-09-05. The banner waited for a post/play/chat
  after `beforeinstallprompt`, so a first visit that only read never saw it.
  It now shows when Chrome can install, and on iOS (where that event never
  fires) it tells Safari/Chrome how. The three apps already shipped the
  partial, the worker, and the manifest.
- **Aegis, seaborne.** A safety agent for the water, and the first body the
  embryo could plausibly take. It is a program rather than a feature because
  most of it is gated on hardware; the section below says what is buildable now
  and what is not.

## The layout pass — opened 2026-09-02

A study of joi.com, kimi.com and medium.com, read against this tree, produced
roughly 178 proposals. They are worked one category at a time, and about sixty
are closed. The list itself lived in a conversation and was never written down,
so perhaps forty of the closed items are recoverable only from `git log` and
another forty of the open ones are gone. That is the defect this file exists to
prevent, and it is recorded here rather than quietly repaired: what follows is
what survived, not a copy of the original.

What the pass has actually taught, which is worth more than the list:

- **Most proposals were not problems.** Of the three raised against motion, two
  were already satisfied — `transition: all` was two sites rather than a
  pattern, and `REDUCED_MOTION` was met. The real defect was thirty byte-
  identical copies of one reduced-motion reset, which no proposal named.
- **A finding against the design system is usually a finding against the
  instrument.** `--transition-fast` looked undeclared in every bundle until the
  resolver was found to follow `@use` and not `@forward`; `.42s` read as 42000ms
  until the regex was fixed. Compile the three apps before and after, and
  compare, rather than trusting a scan.
- **A value-preserving snap is a fix; a value-changing one is a decision.**
  160ms is `--transition-fast` written 20ms apart, and whether those are one
  step or two is a question about how a hover should feel. Off-scale values that
  cannot be moved without changing the render are recorded as baselines with the
  argument written down, never snapped to silence the lint.

### Closed

- **Motion**, 14. Thirty duplicate reduced-motion resets collapsed to the one in
  `_animations.scss`, with `scroll-behavior: auto` promoted into it because
  `animation: none` does not reach it (`4211c4ebb`).
- **Measure**, 10. `--measure-body` was a second name for `--measure`'s 66ch,
  declared three times and used seventeen; collapsed across sixteen files, and
  `rules.yml` corrected from 65ch to 66ch (`e2dc94299`, `a85160ee7`).
  It came back on 2026-09-05 and the route in is worth knowing:
  `layout_contract_test` still asserted the retired spelling in
  `_dialect_tokens.scss`, so the collapse left a red test behind and the obvious
  way to make it green was to re-declare the twin. `design_tokens.yml`'s
  `measure_body` key reads like a token the CSS forgot to emit and is not — it
  is YAML `design_metrics` reads. **A retirement is not finished while a test
  still names the retired thing.** The assertion asks the real question now: the
  measure is declared exactly once, in `_typography.scss`, under one name, and a
  second declaration anywhere in the four stylesheet trees fails (`cd09222b0`).
- **Weight discipline.** `--weight-heavy: 800` is now the top of
  `scale.font_weight` rather than an exception to it: the ramp in use is
  400/600/800, which is the only even ladder meeting `min_weight_delta: 200`,
  and system-ui carries a drawn Heavy. Retired the last 31-finding baseline
  (`1e32bd964`).
- **Grid and tiles**, 14. Nineteen tile grids gave nineteen answers to how
  narrow a column may get, four of them in rem against two different roots;
  six steps now, ten grids moved, none by more than 20px (`b7760ac8c`).
  Thirteen tokens the tree asked for were declared nowhere -- the fallback
  always won, and one had none, so `.tv-feed-title` shipped with no
  font-size. Two lints could not read their own opt-out (`b49b2c82d`).
- **Surface and colour**, 12. Three compat aliases -- --surface2, --text-dim
  and --radius -- were 104 call sites and seven declarations of a second
  name, and the mechanism had already caused a 1.23:1 contrast bug that the
  comment above them documented. The alpha ladder was the one scale nothing
  measured, and its two hand-kept copies had drifted by a step (`67ec62871`).
- **Mobile**, 12. Ten were not problems -- the tree already writes dvh, guards
  touch and reads safe-area everywhere. The two that were: `--tap-min` spent the
  law's 44px from five hand-written copies with nothing comparing them to the
  rule, and eighty-three var() fallbacks named the token they fell back from,
  three of which were hiding an alpha from the ratchet (`21ba3e7ca`).
- **Elevation and hairline**, and **bsdports**. Both finished rather than
  skipped: one `box-shadow` across 106 stylesheets, and zero auditor warnings.

### Open, by category

Counts are what remained when each category was last read; re-measure before
working from one.

- **Controls** — 10 left.
- **brgen** — 9 left.
- **Radius** — 6 left.
- **amber** — 5 left.
- **Instrument** — 4 left.

### Held open deliberately

- **Duration baselines.** 20 off-scale durations in the apps and 33 in the face,
  recorded rather than snapped. Twelve of the twenty are 160ms. The face keeps
  its own timings — `.09s` and `.15s` `steps(4,end)` belong to a terminal
  redrawing in character cells, not to the apps' four-step ladder.
- **Four face transitions exceed `NO_LONG_TRANSITION`.** `face.css:380` at
  1200ms, `:635` at 1800ms, `:867` at 400ms, `:1015` at 600ms, and
  `chat_upload.css:42,48` at 420ms each. Left alone: this is the operator's own
  face timing, and the rule caps UI transitions, not a deliberate slow reveal.


### Grid and tiles, what it left open — 2026-09-04

The tile ladder landed and the undeclared tokens are gone. Three findings from
the same pass are open, each measured and none of them a guess.

- **The generated-asset gate cannot see a stale committed build.** Closed
  2026-09-05. It now compares simple custom-property literals in the committed
  `application.css` against the SCSS (and mixin defaults, the same source
  `fallback_drift_lint.collect_from_scss` already reads). `--bg: #{$bg}` is not
  a literal, so it does not report every dialect as drift. `--radius-card:
  16px` in a build whose sources say 12px does. The checksum rebuild is still
  the exact check and is not this.

- **The remaining `layout_rules` keys are now read.** `design_metrics` already
  read `gap_over_margin`, `card_padding_px`, and `target_recommended_px` (must
  be ≥ `target_min_px`). It now also refuses a missing `grid.columns`,
  `paragraph_margin_em`, `section_padding_min_rem`/`_max_rem`,
  `split_sidebar_ratio` (must sum with `split_main_ratio` to 1), and
  `visible_grid_optional`. `prefer_monochrome_with_one_accent` is read next to
  `max_palette_roles`. The CSS scans for children-with-margin and card padding
  other than 24px landed 2026-09-05 as `css_constitution` tallies
  `child_margin` (floor 0, pens skipped) and `card_padding` (1:
  `_minimal.scss` `.card { padding: 1rem }`, a look decision).

- **`--border-strong` is declared only in `MASTER/web/public/face.css`.**
  brgen's composer asked for it twice and got its `var(--border)` fallback both
  times, which is now written directly. The intent — a border stronger than the
  default one — has no token in RAILS. Naming one is a design decision, not a
  lint fix.

Two more dead indirections sit in the face, outside this lint's reach:
`face.css:372` asks for `--x-font` (the `x_` prefix was retired from the design
system) and `:399` for `--c-mic-off`. Both resolve to their fallbacks. The face
is one-theme by design and its colour lines are the operator's, so they are
named here rather than edited.

### Surface and colour, what it left open — 2026-09-05

- **Sixty-four off-scale alphas, now measured.** apps 26, face 38, recorded as
  baselines rather than snapped. Eleven of the apps' twenty-six are chrome and
  card washes between 6% and 45% and could go on the ladder for a small visible
  change each; the rest are the three engines that paint glass — playlist at
  94%, maps at 92%, tv at 78% — where the number is that pane's own opacity and
  moving it is a decision about the surface.
- **Twenty-two color-mix blends are a separate axis and deliberately unmeasured.**
  `color-mix(in srgb, X 22%, var(--surface))` mixes two opaque colours; 22% is a
  ratio between them, not a transparency. Fourteen distinct ratios. A tint ladder
  would be a real design decision, not a lint.
- **`large_text_contrast` is read.** `visual_contract_lint` takes its text floor
  from that key (AA 4.5). `design_metrics` still enforces `normal_text_contrast`
  (AAA 7.0) on every token pair, large text included — a stricter bar than WCAG
  asks, and a choice, not an unread key.
- **`visual_contract_lint` hardcodes 3.0** for UI/accent pairs. Text now reads
  `large_text_contrast`. Raising the CI floor to AAA 7.0 would flood the
  compiled bundles; `design_metrics` is the gate that enforces
  AAA. Both currently pass, so nothing is broken — but the CI lint would not
  notice a pair falling from 7.0 to 4.6.
- **`prefer_monochrome_with_one_accent` is read** next to `max_palette_roles`
  in `design_metrics`. The numeric cap is the check.

### Mobile, what it found and what it did not — 2026-09-05

Ten of the twelve proposals were not problems, which is the pattern by now and
worth recording so nobody re-derives it. The tree writes `100dvh` twenty-six
times against one `100vh` (now none), guards touch with `touch-action` fifteen
times and `overscroll-behavior` twelve, reads `safe-area-inset` in eighty-nine
places, and has no `text-align: justify` anywhere. The mobile hygiene is done.

- **Sticky hover is not a defect here, and this is why.** 122 `:hover`
  declarations across 52 files, and only four `@media (hover: ...)` guards —
  which reads alarming until the hovers are classified. Eighty-two only repaint,
  thirty declare nothing that matters on touch, and the ten that move or reveal
  are all opacity or transform nudges. `.edge-grip` even carries a
  `@media (hover: none)` permanent affordance beside its hover. No menu, no
  reveal, nothing that strands a tap. Re-classify before re-opening this.
- **`justify_never_on_mobile` has no reader and nothing to catch.** The rule is
  satisfied by a tree that never writes justify; a check would measure zero
  forever. Left as doctrine.
- **`target_recommended_px` is read.** `design_metrics` requires it ≥
  `target_min_px`.
- **`width: min(360px, 100%)` in `_nearby_chat_widget.scss`.** Was 100vw, which
  includes the scrollbar gutter. 100% of the positioned containing block.
### Where the ratchet stands, 2026-09-04

Every kind sits exactly on its baseline, which is what a ratchet with no slack
looks like: `off_scale_opacity` 67 (apps 29, face 38), `off_scale_duration` 53
(apps 20, face 33), `off_scale_space` 48 (apps 16, face 32),
`off_scale_tracking` 14 (all face). Radius, line-height and font-weight are at
zero on both surfaces. `RAILS/shared/design_tokens.yml` holds
the baselines and the argument for each; the contract is that none is ever
raised to silence a new finding, and a staleness test forces a lowering when one
is beaten.

## The wish list, read against the tree — 2026-08-31

`uplift_summary.txt` sat untracked at the root: the owner's own words, six
numbered layers. It is folded here and the file removed, because a wish list at
a root that holds two files is the same "second backlog" this file's preamble
names. Each layer below is what the tree actually holds against it, so the next
reader does not re-audit.

One word about the word. That file called the whole thing an "uplift", and the
six layers are not one job: making the tree legible (1 and 6), making a stated
rule enforceable (2 and 5), and collapsing duplication (3). An umbrella that
vague is how three of the six came to be already built without anyone checking —
so the umbrella is dropped here rather than renamed, and the layers are read one
at a time. Where this tree needs a word for the third of those it already has
two. `collapse` is a rule id — `COLLAPSE_BEFORE_ADDING`, declared and with no
detector, which is its own entry below. `fold` is what `lib/core/` and
`rake lint:spine` mean, and it is enforced.

**1 · Orientation — a map and a glossary. Done.** The map already existed and
is reached from `AGENTS.md`: `data/agent_map.yml` routes by topic,
`START_HERE.md` is the contract, `OPENBSD/tools/tree.rb` draws the layout. The
glossary did not. One arrived during the Codex cluster and was removed with it —
five entries, three of them terms this repo does not use ("Gravity Debt", "The
Bridge"), which is what a glossary written from outside a tree looks like.

The replacement is a section of `AGENTS.md` rather than a file, because
`COLLAPSE_BEFORE_ADDING` applies to documents too and its reader is the agent
already reading that file. It defines the words that mean one thing here and
something else everywhere else — law versus rule, conduct, twin, intentional
marker, fold and spine, ratchet and census, inconclusive, verdict, tier, the
triangle, vertical, the face — and every entry names the file behind it, so a
claim about one can be checked. Three of them were wrong on the first pass and
the tree said so: `face.part4.txt` does not exist, brgen has six engines and not
five, and the intentional marker is honoured by `Rule#scan_lines` as well as by
the law engine. Related: **`tree.rb` on entry** and **Onboarding** above.

**2 · Guardrail — traps out of documentation and into hooks.** Done, and before
the wish list was written. `OPENBSD/dev/githooks/` holds all three guards, they
are installed through `core.hooksPath` by `bin/pub4 hooks`, and
`OPENBSD/test/test_githooks.rb` runs them through real git in a throwaway
repository. The cluster's `bin/pre-commit-hook.sh` and `bin/trap_check` were a
second copy of the first two thirds of that, using `wc` and `grep`, which the
house rules ban in committed scripts.

**3 · Technical debt — decompose the God Classes in Scanner and Dispatcher.**
Scanner is done: 466 lines to 139, with `PathFilter`, `ProgressReporter` and
`Transport` beside it in `engines/`. The record of how that went is above and it
is the cautionary half of this layer — an extraction that carries a method out
and puts a stub back is worse than the class it replaced. Dispatcher was already
done: `llm_dispatcher.rb` is 410 lines over `react_loop`, `ruby_llm_sender` and
`tool_registry`. What is actually large now is `structural_rules.rb` at 814 and
`surface_rules.rb` at 635, and both are registries of independent rules rather
than classes with gravity, so neither is the same problem.

**4 · Face and body — normalise the deploy pipeline between Rails and
OpenBSD.** Open, and the sharpest piece of it is already recorded: every deploy
sheds amber and bsdports while relayd keeps answering TLS on their closed ports,
so the outage reads as a hang. `OPENBSD/deploy_smoke_gate.rb` now checks the
named-table-plus-forward shape `relayd.conf` actually uses rather than a backend
block that never existed, which is a start on the same surface.

**5 · Studio — asset versioning to protect irreplaceable renders.** The write
site refuses an existing named take unless `DILLA_OVERWRITE=1`; scratch and
stream demo.wav still overwrite. `render_seed` now honors `RENDER_SEED` when
GEN_SEED and SEED_TEXT are unset. About 0.012 dB of run-to-run spread remains,
so a bit-identical re-render is still not available.

**6 · Future agent — optimise the repo for LLM-native navigation.** This is
layer 1 plus the standing complaint that the gap here is discoverability rather
than features. The concrete moves already named: the glossary, `tree.rb` on
entry, the profile matrix published in one place, and one name for one job — the
entry-point ratchet in `spine.yml` is what keeps the last of those honest.

## From the 2026-08-31 session

Raised while building the audio-driven README loop and the file-discipline
rules. Each was found by measurement, and each is left with what it would take
to finish rather than a bare title.

- **`rules.yml` refactor.** Aggressively DRYing the law wants a measured pass.
  It was held while the gate was down and the scanner mis-scanned; both of
  those closed on 2026-09-01, so the block is gone and only the work remains.
- **Three outboard units are in no rack.** `freq_shift`, `phase_rotate` and
  `hedd_triode` are built and dispatchable in `Outboard.chain` — the `when`
  arms exist — but no rack names them, so those arms are dead. They are also
  the most advanced processing in the tree, which is what makes it worth
  either wiring them into a rack or deleting the arms.
- **Six Sonitex knobs have no reader.** Docs now say so: `ENV_AND_RENDER.md`,
  the README, and `dilla.rb`'s ENV help. Wiring them still changes rendered
  sound. Use `SONITEX` / `SONITEX_PRESET`.
- **`Policy.default_volume` has no reader.** `+40%` in `data/voice.yml`,
  hardcoded again at `lib/voice/policy.rb:20`, exposed at `:65`, consumed
  nowhere — not by `browser_payload`, not by the worker. Left inert
  deliberately: wiring it changes how MASTER sounds, which is an operator's
  call. That file's own header is a long account of a voice value living in
  more places than the one that changed; this would be the third entry.
- **Merge the three techno renderers.** `render_industrial`,
  `render_hate_techno` and `render_techno` share `techno_harmony_roots` and the
  schedule builders but hold genuinely different arrangements, and
  `dilla.rb:815` records that giving industrial its own target was "a sound
  decision, not a gap." Read all three before cutting; merging on surface
  similarity flattens the arrangements into one sound.
- **`dilla.rb` is 34,545 lines.** `GLOSSARY.md` defines gravity debt as a file
  over 300 lines; this exceeds it by 115x and holds 71% of the engine against
  `lib/`'s 41 files and 14,263 lines. Split along the seams it already has —
  the renderers, the ENV default tables, the SMF writers, the patch registries.
  The direction is out of the monolith, not into it.
- **RAILS token discipline, from the joi.com study.** Three patterns worth
  taking, none of them ornament: colours composed from a named opacity scale
  rather than hardcoded alpha, line-height bound to a semantic role rather than
  a size, and one spacing primitive with `calc` multiples instead of ten
  hardcoded steps. Do not take the 8-step radius scale, the rounded cards or a
  webfont — `--font-brand` is a deliberate zero-byte stack. Line-height landed:
  both surfaces read zero off-scale. The other two are open, and belong to the
  layout pass rather than to this entry — check there before starting either.
- **Flatten `STUDIO/dilla/renders/` into the dilla root.** Operator's
  instruction. It needs `.gitignore` rules to follow the files, since
  `renders/` is currently ignored wholesale, and `dilla.rb`'s hardcoded
  `File.join(ROOT, "renders", ...)` defaults move with them.

## From the 2026-09-01 audit

- **Live RAILS gates still measure too little.** `user_flow`, `first_screen`,
  `payment_honesty`, `content_honesty` and several rendered gates skip when the
  app ports are closed. Run the suite once with `GATE_REQUIRE_LIVE=1`,
  `GATE_STRICT_INCONCLUSIVE=1` and `GATE_STRICT_ERRORS=1` on a host where brgen,
  amber and bsdports are listening, then record any findings that only appear live.
- **Nine domains are expired.** Renew `brmingham.uk`, `cardff.uk`, `denvr.us`,
  `dnver.us`, `edinbrgh.uk`, `glasgw.uk`, `lverpool.uk`, `mnchester.uk` and
  `wshingtondc.com`, then refresh the expiry snapshot with
  `OPENBSD/bin/domain_watch.rb --update`.
- **The yep search pen still owns a magic hex.** `#ccc` is currently banked at
  139 because it is the pen's own divider. If/when the pen is re-tokenised, use
  an existing border token or a named pen token and ratchet `magic_hex` down
  with `GATE_CSS_RATCHET=1`.

### From the 2026-09-01 session sweep

Fifty-seven session transcripts read back against the tree, asking of each
whether its work is present here. Almost all of it is: the 2026-08-31 tree loss
was made good by the `pub4-rescue` snapshot, and a file-level diff of that
snapshot against this checkout leaves nothing of substance behind. These are
what the sweep found still open, each verified against the tree rather than
taken from the transcript that raised it.

- **The three journey-gate follow-ons are done and the journeys have run.**
  `brgen` and `bsdports` carry `test/integration/authorization_matrix_test.rb`
  beside amber's, mutation-checked. `requires_data` is `inconclusive!` rather
  than `warn`. And `flows.yml` has three signed-in writing journeys where it
  had none — 55 steps, all GET, no flow declaring an actor. Driven live on
  2026-09-02 against a booted triangle with an account seeded per app:
  **`flow_journey PASSED`, 25 checks ran, 1 skipped**, and a deliberately wrong
  password fails it with `landed back on /session/new — refused, not signed in`.
- **`flow_journey` could never have reported PASSED.** Found by running it: the
  gate never called `GateResult#checked!`, so `measured_nothing?` saw
  `checks_ran == 0` and one skipped precondition spoke for the whole run — 25
  journeys green under a verdict line reading "checked nothing". Fixed, and it
  is the same defect `checked!` was written for in `human_walkthrough`, which
  suggests looking at the other gates that never call it.
- **A skipped writing journey does not block, and the earlier note here said it
  did.** `GATE_STRICT_INCONCLUSIVE` promotes only `measured_nothing?`, so a run
  that exercises 25 journeys and skips one passes in strict mode too —
  `gate_result.rb` explains that this is deliberate, because promoting at
  record time once made a gate that ran fifty checks and skipped one hard-fail
  on the deploy host. What unchecked buys is that the journey is named in
  "Not checked" every run and never counted among the passes; noticing it is
  still a person's job. If that is not enough, the missing piece is a
  per-journey severity, not a stricter reading of the existing flag.
- **`bin/sine_stream.rb:967` is the last un-oversampled `asoftclip`.** Every
  other saturation site in dilla runs `oversample=4` or `8`; this one runs the
  ffmpeg default and aliases above Nyquist. It is left alone deliberately —
  changing it changes how the stream sounds, which is the operator's ear and not
  a gate's. Worth an A/B before it moves.
- **brgen's `Gemfile.lock` was written by a different bundler major than the
  box resolves with.** vm23 runs ruby 3.4.9 with bundler **4.0.17**; amber and
  bsdports record `BUNDLED WITH 4.0.7`, brgen records `2.7.2`. brgen also
  writes its `RUBY VERSION` as `3.4.9p82` where the others write `3.4.9`,
  which is the older bundler's format — so the whole lockfile, not just the
  footer, came from 2.x. Not fixed here on purpose: the body was resolved by
  the bundler that wrote it, `vps-deploy` installs from it on a 1 GB box, and
  `vps_gemfile_lock_drift` already records that a Mac-written lock against
  BSD-only gems is how this breaks. Re-resolving is a deploy-day change with
  a rollback plan, not a footer edit.
- **The 61-track crate fetch was abandoned at 2.** `~/dilla-crate-incoming`
  holds two FLACs and three fetch scripts from the 2026-08-31 rebuild, which
  finished by another route — `samples/chopped/` has 162 entries. Either resume
  that fetch deliberately or delete the staging directory; a half-finished
  download beside a finished crate reads as the crate.

---

---

## Session record — 2026-09-02, Big Pickle

The dead-route cleanup on RAILS (`e33df9923`) and the three OPENBSD fixes
(`118f38835`) were signed by me. The five OPENBSD findings were verified against
the file source and the live box before any of them was touched, and that
verification changed the plan twice, which is the record to keep:

**Verified, then fixed.** `setup_litestream` installed a `etc/rc.d/litestream`
template that e511ccba1 had retired and neither the tree nor vm23 carries;
`install_template` exits 1 on a missing source, so every `--stage-2` and
`--first-install` aborted there. The fix keeps the config install for the day a
replica exists and drops the rc.d install, matching the comment that was already
there. `--first-install` reached `stage_1` (the DNS-material wipe) without the
`I_UNDERSTAND_DNS_WIPE=1` guard `--stage-1` requires; the guard now gates both
entry points. `brgen_jobs` has been in `pkg_scripts` since e511ccba1 and
confirmed live; the rc.d footer and `operator.yml` still said no `_jobs` service
was enabled, and both now say brgen_jobs is and the others are not.

**Verified, then left alone.** The `chmod 555 /etc/rc.d/master` in OPERATOR.sh
is immediately overwritten by the `chmod 755` loop over every `/etc/rc.d/*`, yet
the box runs every app rc.d at 555. Both lines came from the same original
split, so the intended mode is ambiguous, and neither reading is contradicted by
a comment or a RUNBOOK line — changing the mode of a live service file on my own
judgement is exactly the render-default trap in different clothing. Left for the
operator, reported, not touched. The duplicate `ruby "$REPO_ROOT/RAILS/...` and
`$m3dir/../RAILS/...` fallback in the last-clock check resolves to the same path
under `/home/dev/pub4`; redundant but harmless, same call as the chmod.

**Re-confirmed, already owned.** `dns_zones` still fails on bsdports.org
(resolves to `185.134.245.114, 2a01:5b40:0:bc04::1`, not `46.23.89.226`). That
is `bsdports_org_delegated_to_parking` above, open since 2026-08-25 with a "do
it before Nov 10" deadline; no second entry was opened because the first one
still owns it.

---

# Forward work

Merged from `WISHLIST.md` on 2026-09-06, which is now deleted. That file held
wishes, hypotheses and the shape a tree would take if somebody rebuilt it,
while this one held records with a measurement behind each. Two files meant two
places to look and two places to go stale, and the split cost more than it
bought: a reader chasing one subject had to know which half owned it, and three
entries above already point across the seam.

What was true of the old file stays true of this section. **Every section is
dated and says who wrote it**, because several are not by the same hand and
disagree in places. An item leaves this section when the tree ships it, not
when it stops being mentioned. Where a wish has been measured against the tree
it belongs above, as a record, not here.

## 112 things one day taught this repo — 2026-08-29

Every item traces to something that actually happened rather than to general
advice — where a claim has a file and a line, they are named, so a reader can
check the reasoning instead of trusting it.

The session's own record is not flattering, and that is the point. Roughly a
third of these exist because a measurement was wrong, and about half of those
measurements were mine. This tree already says the instrument is wrong more
often than the code; a day of evidence agreed.

**[cheap]** is an afternoon. **[deep]** is a project. **[yours]** is a decision
rather than work. **[done]** landed that day and is listed so the pattern is
visible.

### A · The surfaces have multiplied (1–14)

`MASTER/bin` holds 28 entry points. `CLAUDE.md:50` says "Two surfaces, no third."
Nothing measures the gap, which is how 2 became 28 without a single failure.

1. A ratchet on entry-point count, per tree, in `spine.yml` beside the source-file ceilings. **[done]** `pub4_entrypoint_ceilings` in `spine.yml`, read by `entrypoint_rows` in `tools/ratchets.rb`, which counts *tracked* executables directly under each tree's own `bin/` — so another session's untracked scratch is not mistaken for a surface, and a Rails app's generated `bin/rails` is not either. MASTER 27, OPENBSD 17, RAILS 2, STUDIO 0.
2. Break the `check` ↔ `ci` cycle. **[done]** `bin/ci` is now nineteen lines that `exec` `bin/check --profile=ci`; one registry, and the double payment for selftest and core_smoke is gone. Kept as a script because its callers — a workflow file, `bin/preflight`, an operator's muscle memory — are outside this repo's reach.
3. Fold the twelve verification commands — check, gate, ci, audit, dogfood, preflight, probe, smoke, smoke-web, test-safety, doctor, nsaudit — into the two sanctioned surfaces. **[deep]**
4. Delete `bin/master`. It is 75 lines, 34 of them comment, and six of behaviour: a `chdir`, one env var, one argument rewrite, `exec bin/cli`.
5. Move that `chdir` into `bin/cli` by resolving its root from `__dir__` rather than `Dir.pwd`, which is the thing the wrapper exists to paper over. **[done]** `bin/cli` chdirs to its parent before boot. `bin/master` still does the same chdir for callers that go through it.
6. Grep every caller before deleting any entry point — `OPENBSD/`, `RAILS/gates/gates.yml`, rc.d scripts on the box. A command with no callers in this repo may still be in a cron line on vm23.
7. One name for one job: `bin/gate` *is* the scan→fix→critique→review chain and does not say so in its name.
8. A test that fails when a doc's stated invariant stops being true. "Two surfaces, no third" was prose, so it rotted silently. **[deep]**
9. `bin/pub4 test` with no arguments runs **nothing** when STUDIO is dirty. **[done]** It partitions STUDIO paths out and warns, rather than aborting on sight of one; the other three trees now run. The abort survives only for the case where STUDIO is the *only* dirty tree, which is a correct report of nothing to do rather than the bug.
10. Make that refusal a skip with a warning, so the other three trees still run. **[done]** With #9.
11. `bin/check --profile=agent` "may fail on known debt" — a profile whose failure carries no information teaches people to ignore it.
12. Publish the profile matrix somewhere a reader can see which profile runs which suite without reading three scripts. **[done]** The matrix is the comment block at the top of `MASTER/bin/check`.
13. Retire `master-core` or say in one line how it differs from `master`. **[done]** The file's first line: fold spine only; `bin/master` boots the full runtime.
14. An `--explain` flag on the chain that prints what it will run before running it. `bin/gate` knows it, and refuses a flag it does not know rather than falling through to full-fix. **[done]**

### B · Gates that measure nothing (15–30)

The worst failure here is not a red gate. It is a green one.

15. `GATE_STRICT_INCONCLUSIVE=1` should be the default, not an opt-in. Four gates reported "checked nothing" in today's sweep and the summary line still read as a pass. **[yours]**
16. `rails_runtime` required `lib/production` after that file moved to `lib/host/production`. It failed at *require* time for months, so the composite went red naming no finding. **[done]**
17. `RAILS/test/gate_requires_resolve_test.rb` pins it: every `require_relative` under `gates/` resolves, and every `gates.yml` row names a file on disk. **[done]**
18. Extend that to every tree, not just RAILS. **[done]** `gate_requires_resolve_test` now walks MASTER/lib and OPENBSD too, skipping heredoc requires.
19. A gate that skips its live half should report the count it skipped in the summary line, not only in its own output.
20. `runner.rb` takes whatever `ruby` is on PATH and prints one warning. Make the version mismatch fatal — app-bundle gates then fail for the interpreter and read as findings. **[done]** `abort`, not `warn`.
21. Boot the triangle automatically for gates that need it, or fail rather than skip.
22. `flow_journey` skipped 23 live checks and `rendered_suite` 32; both reported inconclusive and neither failed.
23. `deploy_drift` "checked nothing — 1 precondition missing" and never says which precondition. **[done]** It names the missing git checkout or the missing stamp dir.
24. Name the missing precondition in every inconclusive line. **[done]** The live and rendered gates already name Chrome, closed ports, missing sass, empty sitemaps. No remaining `inconclusive!` without a reason.
25. A red gate naming no finding should say "this gate could not load" rather than printing an empty failure list.
26. `visual_contract` baselines are gitignored and overwritten on read, so a regression reports once and becomes the baseline.
27. `layout_snapshot` commits reviewable JSON instead — make that the default and retire the self-overwriting one. **[yours]**
28. A gate that can pass on a dirty tree and one that needs a clean one should say which they are, in `gates.yml`.
29. Record per-gate wall time; `rendered_suite` monopolises a Mac for an hour and nothing warns first.
30. A summary line that distinguishes passed / failed / measured-nothing, rather than folding the third into the first.

### C · Built, documented, and switched off (31–47)

The tree's own README names this: "A feature can be fully built, correct, documented — and switched off."

31. dilla had **156 of 405** ENV switches defaulting off. `DILLA_FULL` now turns on the 18 additive ones. **[done]**
32. `MELODIC_LEAD=1` and `SCALE_LEAD=1` both resolve and all four lead lanes still return empty — "lead: none". The switch is on and the feature generates nothing. **[deep]**
33. Audit the other 138 the same way: which are additive, which are exclusive forks, which are operational.
34. A rule that flags an ENV switch read in exactly one place and defaulting off — that shape is either dead or inert.
35. amber shipped **no `config/demo_media/` at all**, so all 17 garments fell through to random picsum stock. **[done]**
36. `DemoMedia::Catalog`'s last fallback was a file named `bergen.yml` under any app's root — amber has no `city_record`, so every lookup there hunted for a city it is not in. **[done]**
37. `FLYLO_DRUM_OVERLAY`, `FLYLO_TOP_DIRT`, `FLYLO_HAT_DUCK` were documented in dilla's README after `lib/` had renamed them to `WONKY_*`. Operators were setting switches nothing read. **[done]**
38. A check that every ENV name in a README is read somewhere in that tree's source. `MASTER/test/test_readme_env_names.rb`, over MASTER, OPENBSD and dilla. **[done]**
39. `FLYLO_QUINT_HATS` is read by nothing under either prefix — a genuinely dead switch, annotated rather than renamed.
40. The assertion under it passes because quint is never scheduled at all. A test that passes for the wrong reason is worse than one that fails.
41. `repligen` is a Replicate client and there is no Replicate access. The whole tool is unreachable. **[yours]**
42. `postpro.rb` takes `--input`/`--output`; called positionally it drops into an interactive picker and, in a script, hangs or silently does nothing. **[done]**
43. Document the headless invocation next to the interactive one.
44. `Shared::PostproProcessor` already had the working call — a second caller reinvented it wrongly. Extract one helper.
45. `system()` returning true is not evidence a file was written. Check the output exists and is non-empty.
46. The seeds' postpro path grades whatever it gets and reports nothing when the grade fails.
47. A failed grade should keep the ungraded frame and say so, because a missing file falls back to stock and looks seeded. **[done]**

### D · The instrument is wrong (48–66)

Half of these were mine, in one day.

48. I read `render_config.rb:104` and quoted it back while calling FLUX's limit a *VRAM* ceiling. It says host RAM at load: 23.8 GB of fp16 materialised before quantisation, against 12.7 GB. Recorded in two files; I had read one of them.
49. My seed-media notebook would have been killed at "Loading checkpoint shards" for 49 of 61 frames.
50. Quantisation cannot help a load-time limit — the model must exist before it can be made smaller. Write that where the next reader will look.
51. My luminance check read "mean grey 0/255" on a face that was plainly visible: a 1×1 downscale rounds a sparse bright field to zero. Max and percent-above-threshold are the right measures.
52. My corpus extractor paired every seed key with the *following* record's title, because I searched a window either side and took the last match. It would have produced 61 confidently wrong prompts.
53. Assert two known pairings before trusting an extractor over 61 unknown ones. **[done]**
54. I confirmed a dilla mix change on an 8-bar render. The arrangement cycle floors at 16 bars, so a short render is intro-main-outro and **the kit never enters** — I was comparing two drumless takes.
55. Record minimum useful render lengths per claim: mix balance needs 48 bars; a switch bisect can use 8.
56. I called a 6 dB sub rise "mud" before the sidecar showed the original was rendered with `DRUMS` unset. There were never any drums.
57. Read the provenance sidecar before comparing two renders. It is there for this.
58. `RENDER_SEED` does not fully pin — ~0.012 dB of run-to-run spread. Fine for an 11 dB bisect, useless for a 0.1 dB claim.
59. A helper that states which comparisons a given spread can and cannot support. **[cheap]**
60. I asserted CDP needed a trusted event for the face's primer. The gate is a plain JS flag and the page exposes `__MASTER_PRIMER_TAP__()`.
61. My first capture probe read `window.face` instead of `window.MASTER_FACE`, got undefined for both fields, and could not tell that apart from the legitimate 2D path. It reported success on a page that had drawn nothing. **[done]**
62. Any probe reading a global should fail loudly when the global is absent, never treat absence as a valid state.
63. Four separate patches failed on heredoc indentation because `<<~` strips the common margin. Line-index edits, or explicit indentation, for anything touching an indented block.
64. `dup_census` records only an integer, so there is no way to diff *which* duplicates are new. The same is true of `data_reach`. All three censuses record members now — `data_reach`, `self_findings` and `dup_census`. **[done]**
65. Record the member list beside the count in every census ratchet. Without it, "over by two" cannot be attributed. **[done]**
66. That gap cost real time today: I could not tell whether two new unread keys were mine. They were `business_plan` and `markdown_style`; both have readers now.

### E · A shared checkout is a hazard (67–79)

67. I read `rules.yml`, another session committed to it, and my write reverted their `business_plan` and `markdown_style` sections. Read-modify-write across three moments.
68. Publish through a worktree off `origin/main`, never by writing the shared tree. Now in `AGENTS.md`. **[done]**
69. A pre-commit check that refuses a write whose base is older than the file on disk. **[deep]**
70. `git checkout -- <path>` restores from HEAD; their commits were safe on origin. Say what you did rather than hope.
71. The pre-commit hook lists what it leaves behind — good — but a 160-path list trains people to skip it.
72. Summarise the leave-behind by tree with a count, and name only paths matching the commit's own tree.
73. `PUB4_UNTRACKED=1` is discoverable only by triggering the refusal. Document it. **[done]**
74. A push publishes every commit beneath yours. `git log --oneline origin/main..HEAD` before every push, and name what went with you.
75. Cherry-picking onto a moving `origin/main` rewrites SHAs, so "is my work pushed?" must be answered by content hash, not by SHA.
76. A helper that answers that: `pub4 pushed? <paths>`. **[done]** `bin/pub4 pushed?` compares content to `origin/main` and names dirty, unpushed, or pushed. Exit 1 unless every path is on origin.
77. `self_findings` crashed because a file vanished between listing and reading. In a shared tree that is normal, not a fluke. **[done]**
78. Every census that walks a file list needs the same tolerance.
79. Worktrees left behind are their own hazard — remove and prune in the session that made them.

### F · Documentation that outlived its code (80–92)

80. dilla's README advertised three switches `lib/` had renamed. The operator-facing file was the last to know.
81. The radio tunnel's comment said the visualiser "fills the frame identically at every size". It filled *proportionally*; the sides were never reachable. **[done]**
82. A comment stating a property is a claim. Where the property is measurable, a test should hold it.
83. `MASTER/AGENTS.md` called itself the entry for coding agents and never mentioned the root `CLAUDE.md`, which is the authority above it. **[done]**
84. It also omitted every operational trap: the Ruby pin, `git add -A`, the worktree recipe, Norwegian defaults, irreplaceable renders. **[done]**
85. `TODO.md` said three things twice after `RAILS/TODO.md` was folded in. **[done]**
86. A document that says a thing twice teaches the reader to skim.
87. `web/CLAUDE.md` documents a 2D fallback; it exists (`face.part1.txt:6`), which is worth knowing because I claimed otherwise before checking.
88. `check_hf_flux_access.rb` documents its own bug: it blocked SDXL renders on the licence terms of a model they do not use. My notebook reproduced that bug independently. **[done]**
89. When a tool documents a mistake, check whether the sibling tool makes it too.
90. `domain_watch.rb --update` cannot run on macOS — it shells to `/usr/bin/timeout`. So the snapshot can only be refreshed on the box, and nothing says so.
91. State a tool's host requirements in its usage line, not in a stack trace. **[done]** `domain_watch.rb --update` says it needs `/usr/bin/timeout` and to run on vm23.
92. `spine.yml` warns that a raise absorbing another change's growth kills the ratchet. Every raise today names its file. Make naming mandatory. **[cheap]**

### G · Sound, and the things that only measure (93–102)

93. dilla's mix balance is a sub-to-body relationship, and five switches inverted it by 20 dB while every loudness number stayed correct.
94. Integrated LUFS, LRA and true peak were all healthy on a render that was hollow in the mids. Loudness metrics cannot see balance.
95. Add a sub/body/presence/air report to `dilla quality` so the four bands are one command. **[cheap]**
96. `MASTER_WIDTH` widens above 300 Hz, taking energy out of the correlated mids while leaving the sub — 7.2 dB of an 11.1 dB swing on its own.
97. Width is not free and should not be a default.
98. The README already says it: a loop with crowded mids cannot be beaten by pushing drums into them.
99. An A/B helper that renders two variants at the same seed and prints the four bands side by side. **[cheap]**
100. `chop` registers loops that `TRACK_PRESETS` has no row for, so using a documented command turns the suite red.
101. Either `chop` writes a preset row, or the reachability test learns about registry-driven loops. **[yours]**
102. Renders are gitignored and seeds rotate; never render over a take that matters, and back up before any destructive probe.

### H · Things only money or a person can fix (103–112)

103. **Nine domains are past expiry.** `cardff.uk` and `edinbrgh.uk` still answer on our nameservers and are recoverable; five have no NS at all. **[yours]**
104. **`bsdports.org` is parked** on `ns1.expireddomain.hyp.net` while `domain_inventory.yml` claims it is registered until 2027. A live product domain, down, invisible to the inventory. **[yours]**
105. Only `dns_zones` caught it, by resolving for real. Trust the live check over the snapshot.
106. **OpenRouter credits are exhausted** — the council personas fail and the entire semantic rule tier cannot run. **[yours]**
107. A chain that skips a whole tier must say so rather than report clean. **[done]** Scan completion already carries `QuotaGate.report`. `/through`'s footer does now too.
108. Replicate and RunPod are unavailable; Colab plus a HuggingFace token is the render path.
109. Ragnhild's adapter is SDXL (`ss_base_model_version: sdxl_1.0`), so it cannot load into FLUX — the same hardware limit, one step earlier.
110. LoRA weights are gitignored, correctly: 218 MB of a real person's likeness does not belong in a public repo. The notebook searches Drive instead. **[done]**
111. Never hardcode a Drive share ID in a public repo; it discloses exactly what the gitignore prevents. **[done]**
112. The face renders at 0.4% of pixels lit. Whether that is right is a look decision, and not one an agent should make alone. **[yours]**

---

## Hypotheses and proposals — 2026-09-01

Three lists from external sessions, kept as written. None is measured
against the tree; that is what makes them wishes rather than records.

### Architectural Hypotheses
These are structural improvements considered from an external engineering perspective, not yet measured as debts.

- **Standardize CLI Tooling:** Replace `ruby -e` patterns used to avoid GNU tools with a shared internal CLI library to reduce cognitive load.
- **Staging Environment:** Introduce a mirror of `vm23` to validate constitutional gates in a live-like environment before production deploy.
- **Engine Boundaries:** Extend the "Fold Spine" budget concept to `RAILS` engines to enforce strict decoupling between the core and verticals.
- **Worktree Enforcement:** Implement a locking mechanism or `git` wrapper that mandates worktree creation for non-trivial changes.

### Brainstormed Enhancements
Conceptual gaps identified during system analysis.

- **Judge's Dashboard:** A dedicated UI for reviewing and resolving `Request` verdicts, replacing the current CLI-heavy process.
- **Decision Graph:** Transition `DECISIONS.md` from flat text to a structured graph linking `soul.yml` rules $\rightarrow$ Rationale $\rightarrow$ Git Commit.
- **Constitutional Telemetry:** Track "Verdict Frequency" (e.g., how often `Revise` is triggered) to detect prompt drift or overly strict laws.
- **Local Box Simulation:** a Vagrant/Docker OpenBSD-lite environment for safe local testing of `rc.d` and deploy scripts.
- **Soul Amendment Workflow:** A formal "Constitutional Audit" process to test new `soul.yml` rules against historical commits before adoption.

### Global Federation Proposal (The "City-State" Model)
Proposed by Nemotron 3.5 Lightning to evolve pub4 from a single-box fortress to a global network.

- **Constitution-as-a-Service:** Elevate `MASTER` to a Central Control Plane. City-boxes pull `soul.yml` and `rules.yml` via API to ensure global legal synchronization.
- **Sovereign-Cell Architecture:** Deploy the `RAILS` stack as isolated "Cells" (one box per city). Scale by replicating cells rather than expanding a single monolith.
- **Global Passport Identity:** Implement a federated identity layer signed by the Central `MASTER`, allowing users to move between city-networks (e.g., brgen.no $\rightarrow$ lsangeles.com) seamlessly.

---

## Reflections — after walking all four trees

Every tree is a constitution in progress: a place where the rules
govern the authors as much as the code. After reading through all of
them, the same pattern repeats — the trees argue well for *what* should
exist and lazily for *how* to make it findable, runnable, and
changeable by someone who has never read the file before. Below are the
wish lists and the 10/10 vision. They are opinions, not debt; a wish
list item is closed when the tree ships it, not when it stops being
mentioned.

### MASTER — what would make the constitutional runtime a joy to read

1. `bin/master` should print a one-line prompt so the user knows it
   is alive. A runtime that answers nothing looks broken.
2. Every `Law` class should declare its `source:` as a machine-readable
   URI, not a citation string, so `MASTER/bin/pub4 measure --origin` can
   trace any rule back to its origin paper or issue.
3. `data/rules.yml` should carry a `last_measured:` date per rule id so
   a reader knows when a finding count was last verified.
4. The fold spine (`lib/core/`) should own a `spine.yml` reader that
   prints the current line count against the ceiling on every boot,
   instead of only when `rake lint:spine` is run.
5. `rules.yml` `self_test` should be executable as a standalone gate
   (`bin/pub4 selftest`) rather than buried inside a YAML file a human
   has to parse.
6. Every `detect_semantic:` string should be paired with a `detect_lexical:`
   fallback in the registry, so no rule is purely semantic-only by accident.
7. `soul.yml` `version:` should drive a `CHANGELOG.md` at `MASTER/` so
   evolution is a log, not a git diff.
8. The `anti_simulation` forbidden words should be enforced by a
   pre-commit hook on `data/` files, not only at runtime.
9. `lib/review/scan/` should publish a public DSL reference (`scan.md`)
   so a new law writer knows the shape of a rule before opening the
   code.
10. `bin/pub4 gate` should accept `--tree MASTER` and only run MASTER's
    own laws against MASTER's code, not the union of all trees.
11. The `evidence_scoring` weights should be tunable per-tree without
    editing `rules.yml` — a `data/weights.yml` override.
12. `constitution.rb` should expose `Constitution.rules_for_law(name)`
    so a caller can ask "what does ROBUSTNESS require?" without
    re-parsing YAML.
13. `data/soul.yml` `persona:` and `voice:` should be validated at boot
    against a known-voices registry, not silently accepted.
14. The `hooks:` block in `soul.yml` should be wired to a test that
    verifies every listed event has at least one handler.
15. `lib/core/world.rb` `Effect` verbs should be enumerated in a
    `VERBS` constant and any unknown verb should raise at boot, not at
    runtime.
16. The scanner should warn when a rule's `detect_semantic:` contains a
    string longer than 200 characters — a readability guard for the law
    writers themselves.
17. `MASTER/data/project_context.yml` should be read at boot and its
    schema validated, since it is listed in `soul.yml` sacred paths.
18. A `bin/pub4 law --audit` that lists every rule id not carried by
    any principle in `principle_priorities`, exposing the inverse of the
    already-fixed principle-map gap.
19. `lib/review/scan/rules/` should carry a `README.md` that auto-generates
    from the registry so the rule inventory never drifts from the code.
20. `bin/master "<instruction>"` should support a `--dry-run` flag that
    simulates the fold's verdict without touching the world.
21. `data/rules.yml` `beauty:` should be split into its own file
    (`data/beauty.yml`) — aesthetics are not laws and should not live
    next to veto patterns.
22. Every `research:` URL in `rules.yml` should be verified at `bin/pub4
    gate --links` to catch 404s before the next audit cycle.
23. `MASTER` should ship a `CONTRIBUTING.md` that tells a new agent:
    "run `bin/check --profile=agent`, then `bin/check --profile=web`".
24. The `test/` directory should mirror `lib/` one directory deep, so
    every `lib/foo/bar.rb` has a known `test/foo/bar_test.rb` location.
25. `rules.yml` `failure_taxonomy` should be backed by a test that
    asserts every strategy has a `max_retries` and a `checksum`.
26. `lib/core/fold.rb` should log its own verdicts to a structured
    JSONL so the runtime can be reviewed after the fact.
27. The `learned_smells` list should carry a `measure_every:` date so
    a reader knows whether the findings are current or stale.
28. `data/limits.yml` should be enforced by a gate, not just read —
    every key without a reader should be flagged by `bin/pub4 limits`.
29. `MASTER` should declare its own `MASTER_VERSION` constant that
    matches `soul.yml version:` and `lib/core/world.rb` should refuse
    to boot if they disagree.
30. The `veto_patterns:` block should be compiled into a single
    optimized regex at load time and benchmarked — a veto pattern
    that slows the scanner is a veto pattern that gets disabled.
31. `lib/core/proof.rb` should carry a `PRODUCERS` constant that is
    tested against `evidence_scoring.producers:` to guarantee the
    regexes and the producers agree.
32. `rules.yml` `paths:skip_dirs:` should be enforced by `Dir.glob` at
    boot — a skip_dir that names no existing directory should warn.
33. The `self_test:` block should be executable via `bin/pub4 selftest`
    and its pass/fail should gate the `bin/master` boot.
34. `data/rules.yml` should carry a `schema_version:` that `RuleDSL`
    checks before parsing, so a future schema change is caught early.
35. Every `fix:` string in `rules.yml` should be tested against a
    synthetic violation to prove the fix actually resolves it.
36. `lib/core/memory.rb` should serialize its transcript to a file
    so a session can be replayed — a memory that lives only in RAM
    cannot be audited.
37. The `guard_expensive_ops` findings should be triaged by `bin/pub4
    triage --age 30` so stale findings do not accumulate silently.
38. `MASTER` should publish a `status.json` at boot containing the
    spine count, rule count, and verdict histogram for the session.
39. `data/principle_map.yml` should be validated to guarantee every
    `rule_id` exists in `rules.yml` and every `principle` exists in
    `principle_priorities` — a cross-reference that currently has no
    gate.
40. The `recovery:` block in `phantom_recovery` should be wired to
    `lib/core/world.rb` so the recovery steps are executable, not
    descriptive.
41. `MASTER` should ship a `bin/pub4 diagram` that emits a DOT graph
    of the fold spine — `Effect -> Constitution -> World -> Memory`.
42. Every `mode: opportunity` rule should be listed separately in the
    scan output so they do not inflate the error count.
43. `rules.yml` `engineering_fit:` should be tested by a gate that
    asserts every rule carries a `why_required:` answer.
44. `lib/core/constitution.rb` should be covered by a test that mutates
    each public method and verifies the fold still reaches the right
    verdict — a constitutional contract test.
45. `data/soul.yml` `absolute:sacred_paths:` should be verified at boot
    that every path exists and is not writable by the current user.
46. `rules.yml` `discovery` should be renamed — it is not a discovery
    mechanism, it is a `detect_semantic:` alias, and the name misleads
    every reader.
47. `MASTER` should declare a `CLI_PROTOCOL_VERSION` so the operator
    surface and the runtime can negotiate without drift.
48. `lib/review/scan/` should export a `scan_profile` JSON so the web
    face can display live scan metrics without reaching back into Ruby.
49. The `hooks:on_fix_applied` event should publish to a file that
    `bin/pub4 status` reads, so the operator sees how many fixes the
    system applied since last boot.
50. `rules.yml` should carry a `last_edited_by:` and `last_edited:`
    on every top-level section, and `git log` should be the source of
    truth for those stamps — a law without an author is a law without
    accountability.
51. `lib/core/fold.rb` `run` should accept a `timeout:` keyword that
    kills the scan after a configurable duration instead of hanging
    indefinitely on a stuck provider.
52. The `DECISIONS.md` or `NOTES.md` in `MASTER/` should carry a
    `search:` index so `bin/master` can answer "why was this rule
    created?" without reading the whole file.
53. `rules.yml` `auto_fix:` should be restricted to rules that have
    been verified against a snapshot — an unverified autofix is a
    silent corruption waiting for a tree-wide run.
54. `MASTER` should declare a `SUPPORTED_RUBY_VERSIONS` array and
    `bin/check` should verify the running Ruby is inside it before
    anything else loads.
55. Every `violation_priors:` row in `data/rules.yml` should be
    validated to name a rule id that actually exists — the empty-prior
    problem that `DATA_CLUMPS` lived inside for months.

### RAILS — what would make the city-network apps a joy to scale

1. Every engine should ship a `CONTRIBUTING.md` so a new developer
   knows the engine's test command without reading `AGENTS.md`.
2. The Norwegian locale files should carry a `lint:` that asserts
   every `t()` key in `app/` has a matching `nb.yml` entry, not just
   the reverse.
3. `brgen/test/` should mirror `engines/` one directory deep so every
   model test has a known home.
4. The `FrontPageWeightTest` and similar weight tests should be
   executable in isolation (`bin/rails test test/models/front_page_weight_test.rb`)
   without booting the full stack.
5. Every controller should declare `before_action :authenticate_user!`
   explicitly so a security scan can find the gap without guessing.
6. `RAILS/shared/lib/pub4/` should publish a `pub4.md` reference so
   shared helpers are discoverable by name.
7. `brgen/config/routes.rb` should carry a `RAILS_ROUTES_TEST` that
   asserts every named route resolves and no route is unreachable.
8. The `Shared::Sluggable` concern should be tested in isolation — a
   concern that is only tested through its host model hides integration
   bugs.
9. Every `has_many :through` should declare `inverse_of` explicitly —
   the 104 missing inverse_of count proves the default is not enough.
10. `RAILS/gates/` should ship a `README.md` that lists every gate and
    what it checks, so an operator knows which gate to reach for.
11. `RAILS/gates/data/css_budget.yml` should carry a `measured_on:`
    date so the budget is not blindly enforced against yesterday's
    render.
12. Every `accepts_nested_attributes_for` should be audited for the
    `reject_if` and `limit` options — nested attributes without them
    are a mass-assignment hole.
13. `brgen/app/javascript/` should carry a `package.json` audit that
    lists every dependency with its license and last-published date.
14. The `SolidQueue`, `SolidCache`, `SolidCable` stacks should each
    have a `test:_solid_*` job that verifies the connection survives a
    fork.
15. `RAILS/shared/design_tokens.yml` should be validated by a gate that
    asserts every token referenced in CSS/SCSS is declared and every
    declared token is used somewhere.
16. Every `scope` in a model should be tested with `unscope` to prove
    the inverse exists — a scope without an unscope is a chain that
    cannot be reset.
17. `RAILS/test/guest_write_rate_limit_test.rb` should be expanded to
    cover every guest-reachable write path, not just the six that were
    found on the first audit.
18. `brgen/engines/` each should declare their own `Gemfile` and
    `Rakefile` so they can be tested and bundled independently.
19. Every `validates :` should carry a message key in `locale/` —
    hardcoded validation messages are I18n defects by policy.
20. `RAILS` should declare a `RAILS_VERSIONS` matrix and `bin/check`
    should verify the running Rails version is inside it.
21. Every `after_commit` callback should be audited for idempotency — a
    callback that assumes it runs exactly once will misbehave on retry.
22. `app/channels/` broadcasts with no subscriber should be flagged by
    a gate so dead streams are caught before they hit production.
23. Every `default_scope` should be reviewed by a human and either
    justified or removed — default scopes are the silent killers of
    query performance.
24. `RAILS` should ship a `docker-compose.yml` for local development so
    the triangle can be booted without `vps-deploy`.
25. Every `find_by` that returns a single record should be tested for
    the not-found case (`rescue_from` or `handle_exception`) to
    guarantee a 404 and not a 500.
26. `app/mailers/` should be audited for missing `headers` — a mailer
    without explicit `from` and `reply_to` is a phishing vector.
27. Every `before_action` that modifies `Current` should be audited to
    ensure it resets `Current` in an `after_action` — a leaked Current
    is a cross-request data leak.
28. The `SolidQueue` or `SolidCache` queues should declare a
    `max_retry_count` and `dead_queue` so failed jobs are not silently
    dropped.
29. Every `ransack` or `searchkick` query should be audited for SQL
    injection — the user-supplied filter string is the attack surface.
30. `RAILS` should declare a `SESSION_EXPIRY` constant and test that
    sessions expire at that time — a session that never expires is an
    account takeover window.
31. Every `CarrierWave` or `ActiveStorage` upload should be audited for
    file type and size — an unbounded upload is a denial-of-service.
32. The `redis` or `solid_cache` connection should be tested for
    latency — a cache that adds 50ms to every read is worse than no
    cache.
33. Every `counter_cache` should be tested for correctness under
    concurrent creates — a counter that drifts under load is a lie.
34. `RAILS` should ship a `bin/rails audit:sql` that lists every N+1
    query detected by `Bullet` across the full suite.
35. Every `render json:` should declare `only:` or `except:` — a
    serialized model that exposes every attribute is a data leak.
36. The `CORS` configuration should be audited to guarantee every
    origin is explicit — a wildcard `Access-Control-Allow-Origin` is a
    CSRF enabler.
37. Every `sidekiq_options` should declare `retry:` and `dead:` so
    failed jobs are visible and not silently swallowed.
38. `RAILS` should declare a `PAYMENT_GATEWAY_FALLBACK` so the app
    degrades gracefully when Stripe is down — a payment app that
    crashes on a gateway timeout is a revenue killer.
39. Every `link_to` with a `method:` should be tested for the JS
    fallback — a progressive-enhancement link that fails without JS is
    a broken link.
40. `RAILS` should ship a `bin/rails health` that returns a JSON
    status of every engine, queue, and cache connection.
41. Every `strong_parameters` whitelist should be audited against every
    `form_with` to guarantee no field is accepted without explicit
    permission.
42. The `favicon.ico` and `robots.txt` should be declared as routes
    so they are not served by Rails at all — static files through the
    app are a performance tax.
43. Every `counter_cache` or `cache_column` should have a `REBUILD` task
    that can be run to fix drift without a full migration.
44. `RAILS` should declare a `DEPLOYMENT_SCORE` constant — a number
    from 0 to 100 that represents how safe a deploy is — and
    `vps-deploy` should refuse to proceed below 80.
45. Every `enum` should be tested for the invalid-value case — an enum
    that accepts a string it does not declare raises a silent
    `ActiveRecord::EnumNotFound`.
46. `RAILS/shared/` should declare a `SHARED_VERSION` constant so the
    shared code between engines can be versioned and its API
    backwards-compatibility tested.
47. Every `scope` that filters by `current_user` should be audited for
    the tenant isolation — a scope that does not scope is a data leak
    between cities.
48. `RAILS` should ship a `bin/rails security` that runs
    `brakeman`, `bundler-audit`, and the custom rule scanner in one
    command.
49. Every `after_initialize` or `to_prepare` block should be audited for
    thread-safety — a block that mutates global state is a race
    condition waiting to happen.
50. `RAILS` should declare a `PERFORMANCE_BUDGET` file that lists the
    maximum allowed response time, page weight, and query count for
    every page — and `bin/rails benchmark` should fail the deploy if
    any page exceeds it.
51. Every `ActionMailer::Base` subclass should declare `default from:`
    and `default reply_to:` so the framework enforces it, not the
    operator.
52. `RAILS` should ship a `bin/rails i18n:audit` that finds every
    hardcoded English string in a view helper and reports the missing
    locale key.
53. Every `has_and_belongs_to_many` should be reviewed for whether a
    `has_many :through` is more appropriate — HABTM cannot carry
    metadata on the join.
54. The `propshaft` manifest should be audited to guarantee
    every asset is referenced — an orphaned bundle is a waste of bytes.
55. `RAILS` should declare a `CITY_TIMEOUT` constant so every city
    engine can configure its own request timeout — a global timeout
    that fits Bergen does not fit Reykjavik.

### OPENBSD — what would make the deploy pipeline and VPS runbook a joy to operate

1. `OPENBSD/etc/rc.d/master` should print a startup banner that names
   the version, the PID, and the boot time so an operator knows the
   daemon is alive without checking `rcctl`.
2. Every script in `OPENBSD/bin/` should declare its own `VERSION`
   constant that `vps-deploy` reads before running.
3. `OPENBSD/bin/vps-deploy` should accept `--dry-run` that prints the
   full sequence of commands without executing any of them.
4. `OPENBSD/etc/relayd.conf` should be validated at boot by
   `relayd -n` and the result logged — a broken relayd.conf that loads
   is worse than one that refuses to load.
5. Every `rc.d` script should declare its `depends_on:` as a
   machine-readable list so `rcctl` can order them correctly without
   guessing.
6. `OPENBSD` should ship a `RELEASE_NOTES.md` that is updated on every
   deploy — an undeployed box is an undeployed change.
7. The `doas.conf` should be audited by a gate that asserts every
   rule is scoped to a command and a user — an unscoped doas rule is
   root access for everyone.
8. Every `pkg_add` in the install scripts should declare a
   `VERIFY_SIGNATURE` step — a package installed without a signify
   signature is a supply-chain attack.
9. `OPENBSD/bin/deploy-smoke.sh` should test every apex on the box,
   not just the three live apps — amber and bsdports need to hear
   their own smoke test.
10. `OPENBSD/etc/ssh/sshd_config` should be audited against
    `ssh-audit` on every deploy — a silent SSH downgrade is a root
    cause.
11. Every `cron` job should declare a `MAILTO=` so failures are
    emailed to the operator — a cron that fails silently fails forever.
12. `OPENBSD` should ship a `NETWORK_DIAGRAM.md` that maps every
    domain to its port, its relayd section, and its backend IP.
13. The `nsd.conf` zones should be validated by `nsd-check` at boot and
    the result logged — a broken zone file that loads serves stale DNS.
14. Every `acme-client` certificate should be audited for expiry by
    `OPENBSD/bin/domain_watch.rb` at boot, not just once a day.
15. `OPENBSD` should declare a `VPS_HEALTH_CHECK` that runs every
    five minutes and logs CPU, RAM, disk, and swap — a box that runs
    out of memory does not recover silently.
16. The `pf` firewall rules should be validated by `pfctl -nf` before
    loading — a bad rule set that loads blocks the operator's own SSH.
17. `OPENBSD/bin/sync_tree` should log the before-and-after SHA so a
    deploy can be verified without reading the git log.
18. Every `rc.d` script should have a `stop` that guarantees the
    process is dead — a daemon that refuses to stop cannot be upgraded.
19. `OPENBSD` should ship a `BACKUP_VERIFICATION` task that restores
    a random backup to a throwaway directory and runs `PRAGMA
    integrity_check` — a backup that has never been restored is not a
    backup.
20. `OPENBSD/etc/` should be tracked in git with a `git commit` on
    every change so the config has a history — config that lives only
    on the box is config that cannot be audited.
21. The `relayd` backend blocks should be audited to guarantee every
    backend has a health check — a backend with no health check is a
    backend that serves broken traffic.
22. `OPENBSD` should declare a `DEPLOY_ORDER` constant that lists the
    exact sequence of services to start and stop — a deploy that
    starts the app before the database is a failed deploy.
23. Every `pkg_add` should declare a `pkg_delete` fallback so an
    upgrade can be rolled back — a package manager without a rollback
    is a one-way door.
24. `OPENBSD` should ship a `LOG_ROTATION` config that guarantees
    every log file is rotated and compressed — an unrotated log fills
    the disk and takes the box down.
25. The `ntpd` or `openntpd` configuration should be verified to point
    at a reliable time source — a box with wrong time breaks TLS
    certificates and session tokens.
26. Every `rc.d` script should be tested by `OPENBSD/test/test_rc_scripts.rb`
    that starts, stops, and checks the process state in a throwaway
    jail — a script that works on the operator's box but not in a clean
    jail is a script that will fail on deploy.
27. `OPENBSD` should declare a `SECURITY_HARDENING` checklist that is
    verified on boot: SSH key-only, root login disabled, unused
    services stopped, firewall enabled.
28. The `daily.local` script should be audited to guarantee it does not
    run commands as root that could be replaced by a compromised
    binary — a daily script that runs everything as root is a privilege
    escalation script.
29. `OPENBSD/bin/dr-pull` should verify the restore by running a
    `sqlite3 .dump` diff against the source — a backup that restores
    to a different shape is a backup that lies.
30. `OPENBSD` should ship a `CAPACITY_PLAN` that documents the current
    RAM, disk, and connection limits, and the thresholds at which each
    would require an upgrade — a box that runs out of resources without
    warning is a box that runs out of service.
31. Every `ifstated` or `hostname.*` file should be tested to guarantee
    the hostname resolves to the correct IP — a box that answers the
    wrong name serves the wrong city.
32. `OPENBSD` should declare a `RUNBOOK_VERSION` that matches the
    deployed configuration — a runbook that does not match the box is
    a runbook that lies.
33. The `pf` table entries should be audited to guarantee no stale
    entries exist — a table that grows without bound is a table that
    slows the firewall.
34. `OPENBSD/bin/` should declare a `bin/usage` that lists every
    command and its arguments so an operator does not have to read the
    source to know what to run.
35. Every `ssh` key should be audited for its expiration and its
    `command=` restriction — an unrestricted key is a standing root.
36. `OPENBSD` should ship a `FAILURE_MODE.md` that lists the ten most
    likely failure scenarios and the exact command to diagnose each one.
37. The `rc.d` scripts should be tested for the `reload` case — a
    daemon that cannot be reloaded without a full stop/start is a
    downtime-inducing deploy.
38. `OPENBSD` should declare a `MONITORING_CONFIG` that exports
    `rrd` or `snmp` config so the box is watched by an external
    system — a box that monitors itself is a box that lies about itself.
39. Every `acme-client` domain should be audited to guarantee the
    certificate matches the hostname — a certificate for the wrong
    domain is a TLS failure waiting to happen.
40. `OPENBSD` should ship a `DISASTER_RECOVERY` script that can
    rebuild the entire box from a bare `pkg_add` — a recovery that
    requires the operator's manual is a recovery that will not happen
    at 3am.
41. The `smtpd` configuration should be audited to guarantee no
    open relay — an open relay is a spam bot's best friend and the
    operator's worst nightmare.
42. `OPENBSD` should declare a `NETWORK_POLICY` that documents every
    allowed inbound and outbound connection — a network without a
    policy is a network that accepts anything.
43. Every `rc.conf.local` variable should be audited for its default
    value — a variable set to a wrong default is a bug that hides
    until a fresh install.
44. `OPENBSD` should ship a `CHANGES.md` that is appended to on every
    deploy — a deploy without a changelog is a deploy that cannot be
    audited.
45. The `rc.d` scripts should declare their `provides:` so `rcctl` can
    resolve dependencies by capability rather than by script name.
46. `OPENBSD` should declare a `VPS_IMAGE` that can be booted in
    QEMU for testing — a deploy that cannot be tested locally is a
    deploy that can only be tested on the box.
47. Every `rc.d` script should be verified to run as the declared
    `daemon_user` — a script that runs as root when it should run as
    `_pub4ci` is a privilege escalation waiting for its exploit.
48. `OPENBSD/bin/` scripts should declare their `set -euo pipefail`
    at the top and be tested for it — a script without strict mode
    silently continues past every error.
49. `OPENBSD` should ship a `PERF_TUNING` file that documents every
    `sysctl` and `mount` option and the reason for each — a tuned box
    without documentation is a box that cannot be retuned.
50. `OPENBSD` should declare a `SECURITY_AUDIT` schedule — monthly
    `ssh-audit`, `pfctl -s all`, `pkg_info -m`, `daily.check` — and
    `vps-deploy` should refuse to proceed if the last audit was more
    than 30 days ago.
51. Every `relayd` section should be audited to guarantee the `block`
    policy is set on every listen — a relayd section without a block
    policy is a relayd that forwards anything.
52. `OPENBSD` should ship a `TICKET_TEMPLATE` that the operator fills
    out on every deploy — a deploy without a ticket is a deploy that
    cannot be tracked.
53. The `ntp` symmetric keys should be rotated on every deploy — an
    ntp key that never changes is a time-source compromise that never
    gets noticed.
54. `OPENBSD` should declare a `SERVICE_LEVEL_AGREEMENT` that maps
    every apex to its acceptable downtime — a service without a
    guarantee is a service that cannot be measured.
55. Every `rc.d` script should declare its `START_ORDER` so `vps-deploy`
    can start the box in the right sequence — a box that starts its
    app before its database is a box that wastes its first minute
    crashing.

### STUDIO — what would make the media tools a joy to create with

1. `dilla.rb` should ship a `dilla.md` that explains the 81 parts in
   the order they are required, so a new contributor can trace a sound
   without reading the whole file.
2. Every renderer (`render_*.rb`) should declare its `SAMPLE_RATE` and
   `BIT_DEPTH` at the top so the operator knows what the output will be.
3. `STUDIO/dilla/renders/` should be migrated into the dilla root with
   `.gitignore` rules, so the render pipeline is inside the repo where
   it can be audited.
4. Every `lib/*.rb` support module should declare its `__dir__` once at
   the top and use a constant, so moving the file does not break the
   path.
5. `DillaSources` should declare a `SOURCES_VERSION` that matches the
   sample corpus, so a mismatch between code and samples is caught at
   boot.
6. `dilla.rb` should be split along its existing seams — the renderers,
   the ENV tables, the SMF writers, the patch registries — into `lib/`
   files that `require` each other in a declared order.
7. Every `test_dilla_*` should declare its own timeout so a slow test
   does not kill the whole suite — a suite that fails from timeout is a
   suite that lies about what passed.
8. `test_dilla_audio_graph_parity.rb` should be fixed to match the
   current bus-routed graph topology — a test that expects a flat
   `amix` when the engine emits a routed graph is a test that tests
   the wrong thing.
9. `STUDIO/gate.rb` should declare a `GATE_VERSION` and test that
   `lib/engine/` does not reappear — a gate that does not test its own
   condition is a gate that can be silently bypassed.
10. Every `Outboard.chain` arm that names a module should be tested to
    verify the module exists and is dispatchable — dead arms are dead
    code that looks alive.
11. The `samples/dug/` corpus should be documented with a `sources.yml`
    that maps every file to its download URL — a sample without a URL
    is a sample that cannot be re-fetched.
12. Every `rack` in the registry should be deduplicated by checksum so
    the 38 duplicate recordings are collapsed to 123 unique wavs.
13. `dilla.rb` should declare a `LINE_LIMIT` of 300 and `bin/check`
    should enforce it — a file that exceeds the limit is a file that
    cannot be read.
14. Every `key` in the registry should be measured and verified against
    a `KEY_LIBRARY` constant, so a key that is out of tune with the
    rest of the crate is caught before it renders.
15. `STUDIO` should ship a `RENDER_SEED` constant that pins every
    render to a deterministic seed, so a "re-render" actually produces
    the same file.
16. Every `vocal_chop` that skips a row should log the skip reason so
    the operator knows why the vocal is missing — a silent skip is a
    silent defect.
17. `dilla.rb` should declare `DRUM_LOOP_SOURCE` as a constant
    that is tested to exist before any render starts — a drum loop
    that resolves to `~/Downloads` is a render that depends on a file
    outside the repo.
18. Every `techno_harmony_root` should be tested against a
    `HARMONY_VALIDATOR` so the most advanced processing in the tree is
    the most tested.
19. `STUDIO` should declare a `RENDER_BUDGET` that lists the maximum
    render time, the maximum memory, and the maximum disk per render.
20. Every `__FILE__` reference should be replaced with `__dir__` — a
    file path that hardcodes the directory is a path that breaks when
    the file moves.
21. `postpro/` should declare its own `CONTRIBUTING.md` so a colorist
    knows the grading pipeline without reading the source.
22. Every `repligen/` and `lora/` model should declare its `MODEL_VERSION`
    and `CHECKSUM` so a corrupted model is caught at load time.
23. `STUDIO` should ship a `GENERATE.md` that explains how to reproduce
    a specific render — a render without a recipe is a render that
    cannot be repeated.
24. Every `dilla.rb` part that manipulates audio should be tested with
    a known-input known-output file so the transform is verifiable.
25. `STUDIO` should declare a `SEED_REALISM` constant that guarantees
    every city's demo audio sounds like that city — 39 of 43 cities
    seeding at `0,0` is a map that reads as empty.
26. Every `render` should write a `.dilla` provenance sidecar that is
    validated at write time — a provenance that is optional is a
    provenance that is skipped.
27. `STUDIO` should ship a `RENDER_DIFF` tool that compares two
    renders with their seeds and reports the dB difference — a render
    that changes without a seed change is a render that changed by
    accident.
28. Every `sound` in the tree should be tagged with its `GENRE` so a
    genre-agnostic tool is genre-discoverable.
29. `STUDIO` should declare a `RENDER_BACKUP` policy that copies every
    render to an off-tree location before it can be overwritten — a
    render that can be overwritten is a render that can be lost.
30. Every `patch` registry in `dilla.rb` should be tested to guarantee
    the patch applies cleanly to the target version — a patch that
    fails silently is a patch that lies.
31. `STUDIO` should ship a `BENCHMARK` script that measures every
    render's CPU and wall-clock time and fails if it exceeds the budget.
32. Every `effect` in the chain should be auditable — the operator
    should be able to ask "what effect was applied here?" and get the
    exact module and arguments.
33. `STUDIO` should declare a `FORMAT_VERSION` for every output format
    so a format change is a breaking change that is versioned.
34. Every `loops` file should be tested for its `beats_per_minute`
    against the registry — a loop that lies about its BPM is a loop
    that breaks the mix.
35. `STUDIO` should ship a `RENDER_MONITOR` that watches the render
    directory and alerts when a render exceeds the time budget or the
    disk budget.
36. Every `plugin` or `external` call should be wrapped in a
    `with_timeout` so a hung external process does not hang the whole
    render pipeline.
37. `STUDIO` should declare a `QUALITY_GATE` that asserts every render
    passes a spectral analysis before it is considered done — a render
    that passes without analysis is a render that might be silent.
38. Every `sample` should be tested for its `duration` against the
    expected length — a sample that is shorter than expected is a loop
    that drops beats.
39. `STUDIO` should ship a `RENDER_LOG` that records every render
    command, every parameter, and every seed — a render without a log
    is a render that cannot be reproduced.
40. Every `mix` should be tested for its `peak_level` and `rms_level`
    so a clip that exceeds 0dB is caught before it is rendered.
41. `STUDIO` should declare a `MASTER_RENDER` that is the canonical
    reference render for every crate — a crate without a reference is a
    crate that cannot be judged.
42. Every `dilla.rb` constant that appears in `data/voice.yml` should
    be read from `data/voice.yml` — a constant that is also hardcoded is
    a constant that drifts.
43. `STUDIO` should ship a `CORPUS_AUDIT` that verifies every sample
    in the registry exists on disk and is not corrupted — a registry
    that names a file that does not exist is a registry that lies.
44. Every `sfx` bank should be tested for its `sample_rate` and
    `bit_depth` against the project settings — an sfx bank at the wrong
    sample rate is a sound that is pitched wrong.
45. `STUDIO` should declare a `RENDER_PIPELINE_VERSION` that matches
    the `dilla.rb` version — a pipeline that does not match the code
    renders a sound that does not match the spec.
46. Every `filter` should be tested for its `frequency_response` against
    a known target — a filter that does nothing is a filter that lies.
47. `STUDIO` should ship a `GENRE_PROFILE` for each supported genre
    that defines the BPM range, the key range, and the mix rules — a
    genre without a profile is a genre without a standard.
48. Every `envelope` should be tested for its `attack`, `decay`,
    `sustain`, and `release` values against the DAW convention — an
    envelope that is out of phase is a sound that hits at the wrong time.
49. `STUDIO` should declare a `RENDER_QUALITY_TIER` (draft, studio,
    master) so the operator knows what level of processing is applied.
50. `STUDIO` should ship a `RENDER_VALIDATOR` that runs spectral,
    temporal, and loudness analysis on every output and fails if any
    metric is out of range.
51. Every `tempo` change should be tested for its `time_stretch`
    algorithm — a tempo change without time-stretch is a pitch change.
52. `STUDIO` should declare a `MASTER_BUS` standard that every render
    must pass through — a render that bypasses the master bus is a
    render that has no master.
53. Every `bus` should be tested for its `gain` and `pan` against the
    stereo field — a bus that is off-center is a mix that is unbalanced.
54. `STUDIO` should ship a `RENDER_ARCHIVE` that compresses every
    finished render and stores it with its seed — a render without an
    archive is a render that can be lost.
55. `STUDIO` should declare a `CREATE_QUALITY` policy that asserts
    every generated sound passes a human-in-the-loop review before it
    is considered finished — an AI that generates without review is an
    AI that generates garbage.

### The 10/10 MASTER — vision

The perfect MASTER is a runtime where the constitution is not a file
you read but a surface you interact with. A developer clones the repo,
runs `bin/check --profile=agent`, and the first thing they see is not
a sea of red failures but a clean scan and a single sentence: "The
constitution is green. Here is what the fold found."

It is a runtime where every rule carries its own evidence — the finding
count, the last measurement, the false-positive history — and every
measurement is verified against a known-clean snapshot before it is
trusted. A rule that cannot prove itself is a rule that should not exist.

It is a runtime where the fold spine is measured by its own law, where
the scanner is tested by the rules it scans, and where the constitution
is the first thing that gets reviewed in a code audit — not the last.

It is a runtime where `bin/master` answers a question in a sentence,
where `bin/pub4 gate` tells you exactly which law a change broke and
why, and where `bin/pub4 measure` gives you a number you can trust
because it was measured today, not last week.

It is a runtime where the four trees are four citizens of one
constitution, where `MASTER` governs `RAILS` the way `RAILS` governs
`STUDIO`, and where the OpenBSD box is not a deployment target but a
provable artifact — every config file signed, every service
verifiable, every deploy auditable.

The 10/10 MASTER is a constitutional runtime that applies its laws to
itself without exception, where the governor is governed, where every
effect is proved and every verdict is recorded, and where a new
contributor can go from clone to green check without reading a single
contract file — because the runtime itself teaches them what it needs
from them.

---

## Reflections — Muse Spark 1.2 Free (2026-09-01)

Walked all four trees in one session, fixed what was verifiable, left
what needs an owner. The same failure repeats: a file that contains its
own proof of correctness while not being correct — TODO.md with conflict
markers, rules.yml with priors that name no rule, a render at the repo
root that claims to belong under `STUDIO/dilla/renders/`, a design token
ladder that cannot name its most-used rung. Below are the wishes, one
per tree, and the 10/10 vision. Each is an opinion, not debt; it closes
when shipped. Signed: Muse Spark 1.2 Free.

### MASTER — what would make the constitutional runtime a joy for humans and LLMs

1. `TODO.md` should never contain `<<<<<<<` — add a pre-commit hook that fails on conflict markers, verified by a test that asserts the marker string itself is not found.
2. `MASTER/data/rules.yml` `violation_priors` and `rule_deps` should be validated at boot: every id must resolve to a law or a rule, otherwise the constitution is citing a law that does not exist.
3. `MASTER/bin/master` should print a one-line prompt on TTY so `bundle exec ruby bin/cli` does not look dead.
4. Every `Law` class should declare its `source:` as a URI, not a prose citation, so `bin/pub4 measure --origin` can trace any rule to its paper.
5. `data/rules.yml` should carry `last_measured:` per rule id, so a reader knows if a finding count is today's or last month's.
6. The fold spine (`lib/core/`) should publish its line count vs ceiling on every boot, not only when `rake lint:spine` is run.
7. `rules.yml` `self_test` should be a runnable gate (`bin/pub4 selftest`), not a YAML block a human parses.
8. Every `detect_semantic:` should have a `detect_lexical:` fallback, so no rule is purely semantic by accident.
9. `soul.yml` `version:` should drive `CHANGELOG.md`, so evolution is a log, not a diff.
10. `anti_simulation` forbidden words should be enforced by a pre-commit hook on `data/`, not only at runtime.
11. `lib/review/scan/` should publish a DSL reference (`scan.md`) so a new law writer knows the shape before opening code.
12. `bin/pub4 gate` should accept `--tree MASTER` to run only MASTER's laws on MASTER.
13. `evidence_scoring` weights should be tunable per-tree via `data/weights.yml` without editing `rules.yml`.
14. `constitution.rb` should expose `Constitution.rules_for_law(name)` without re-parsing YAML.
15. `data/soul.yml` `persona:` and `voice:` should be validated at boot against a known-voices registry.
16. `hooks:` in `soul.yml` should be wired to a test asserting every event has a handler.
17. `Effect` verbs in `lib/core/world.rb` should be enumerated in `VERBS` and unknown verbs should raise at boot.
18. The scanner should warn when `detect_semantic:` exceeds 200 chars — a readability guard for law writers.
19. `data/project_context.yml` should be validated at boot, since it is listed in `sacred_paths`.
20. Add `bin/pub4 law --audit` listing every rule id not carried by any principle — the inverse of the principle-map gap.
21. `lib/review/scan/rules/` should carry an auto-generated `README.md` from the registry so inventory never drifts.
22. `bin/master "<instruction>"` should support `--dry-run` that simulates the fold's verdict without touching the world.
23. `data/rules.yml` `beauty:` should be split to `data/beauty.yml` — aesthetics are not laws.
24. Every `research:` URL in `rules.yml` should be verified by `bin/pub4 gate --links` to catch 404s.
25. Ship a `CONTRIBUTING.md`: "run `bin/check --profile=agent`, then `bin/check --profile=web`".
26. `test/` should mirror `lib/` one-deep, so every `lib/foo/bar.rb` has a known test home.
27. `failure_taxonomy` should be backed by a test asserting every strategy has `max_retries`.
28. `lib/core/fold.rb` should log verdicts to JSONL so the runtime is auditable after the fact.
29. `learned_smells` should carry `measure_every:` so a reader knows if findings are stale.
30. `data/limits.yml` should be enforced by a gate, not just read — every key without a reader should be flagged.
31. Declare `MASTER_VERSION` matching `soul.yml version:`; `world.rb` should refuse to boot if they disagree.
32. Compile `veto_patterns:` into one optimized regex at load and benchmark it — slow vetoes get disabled.
33. `lib/core/proof.rb` `PRODUCERS` should be tested against `evidence_scoring.producers:` to guarantee they agree.
34. `paths:skip_dirs:` should be enforced by `Dir.glob` at boot — a skip_dir naming no existing dir should warn.
35. `data/rules.yml` should carry `schema_version:` checked by `RuleDSL` before parsing.
36. Every `fix:` string should be tested against a synthetic violation to prove it resolves.
37. `lib/core/memory.rb` should serialize its transcript so a session is replayable — RAM-only memory cannot be audited.
38. Add `bin/pub4 triage --age 30` to prevent stale `guard_expensive_ops` findings accumulating.
39. Publish `status.json` at boot with spine count, rule count, verdict histogram.
40. Validate `data/principle_map.yml` cross-reference: every `rule_id` must exist in `rules.yml`.
41. Wire `phantom_recovery` `recovery:` to `lib/core/world.rb` so steps are executable, not descriptive.
42. Ship `bin/pub4 diagram` emitting DOT graph of `Effect -> Constitution -> World -> Memory`.
43. List `mode: opportunity` rules separately in scan output so they do not inflate error count.
44. Test `engineering_fit:` to assert every rule carries `why_required:`.
45. Cover `constitution.rb` with mutation tests verifying the fold still reaches the right verdict.
46. Verify `absolute:sacred_paths:` at boot: every path exists and is not writable by current user.
47. Rename `discovery` — it is a `detect_semantic:` alias, name misleads every reader.
48. Declare `CLI_PROTOCOL_VERSION` so operator surface and runtime negotiate without drift.
49. Export `scan_profile` JSON so the web face shows live scan metrics without Ruby.
50. Make `hooks:on_fix_applied` publish to a file `bin/pub4 status` reads, so fixes since boot are visible.
51. Carry `last_edited_by:` and `last_edited:` on every top-level section, with `git log` as source — a law without author has no accountability.
52. Accept `timeout:` in `Fold#run` to kill a stuck provider instead of hanging a 1GB host.
53. Carry a `search:` index in `DECISIONS.md` so `bin/master` can answer "why was this rule created?" without reading the whole file.
54. Restrict `auto_fix:` to rules verified against a snapshot — unverified autofix is silent corruption.
55. Declare `SUPPORTED_RUBY_VERSIONS` and verify at `bin/check` before anything loads.

### RAILS — what would make the city-network apps a joy to scale

1. Every engine should ship `CONTRIBUTING.md` so a new dev knows the engine's test command without reading `AGENTS.md`.
2. Add a `lint:` that asserts every `t()` key in `app/` has a matching `nb.yml` entry, not just the reverse.
3. `brgen/test/` should mirror `engines/` one-deep so every model test has a known home.
4. Make `FrontPageWeightTest` runnable in isolation without booting the full stack.
5. Every controller should declare `before_action :authenticate_user!` explicitly so a security scan can find the gap.
6. Publish `RAILS/shared/lib/pub4/pub4.md` reference so shared helpers are discoverable.
7. Carry `RAILS_ROUTES_TEST` asserting every named route resolves and no route is unreachable.
8. Test `Shared::Sluggable` in isolation — a concern only tested through its host hides bugs.
9. Every `has_many :through` should declare `inverse_of` explicitly — 104 missing proves default is not enough.
10. Ship `RAILS/gates/README.md` listing every gate and what it checks.
11. `css_budget.yml` should carry `measured_on:` so the budget is not enforced against yesterday's render.
12. Audit every `accepts_nested_attributes_for` for `reject_if` and `limit` — without them it is mass-assignment.
13. Carry a `package.json` audit listing every dependency with its license and last-published date.
14. Add `test:_solid_*` jobs verifying the connection survives a fork for SolidQueue/Cache/Cable.
15. Gate `shared/design_tokens.yml`: every token referenced in CSS must be declared and every declared token used.
16. Test every `scope` with `unscope` to prove the inverse exists — a scope without unscope cannot be reset.
17. Expand `guest_write_rate_limit_test.rb` to cover every guest-reachable write path, not just six.
18. Each engine should declare its own `Gemfile`/`Rakefile` so it can be tested independently.
19. Every `validates :` should carry a message key in `locale/` — hardcoded messages are I18n defects.
20. Declare `RAILS_VERSIONS` matrix and verify at `bin/check`.
21. Audit every `after_commit` for idempotency — a callback assuming exactly-once misbehaves on retry.
22. Flag `app/channels/` broadcasts with no subscriber so dead streams are caught before production.
23. Review every `default_scope` — default scopes are silent query killers.
24. Ship `docker-compose.yml` so the triangle boots without `vps-deploy`.
25. Test every `find_by` for the not-found case to guarantee 404 not 500.
26. Audit `app/mailers/` for missing `headers` — a mailer without explicit `from`/`reply_to` is phishing.
27. Audit every `before_action` modifying `Current` to ensure it resets in `after_action` — leaked Current is cross-request leak.
28. Declare `max_retry_count` and `dead_queue` for every queue so failed jobs are not dropped.
29. Audit every `ransack`/`searchkick` query for SQL injection — user-supplied filter is the surface.
30. Declare `SESSION_EXPIRY` and test expiry — a session that never expires is account takeover.
31. Audit every `CarrierWave`/`ActiveStorage` upload for type and size — unbounded upload is DoS.
32. Test `redis`/`solid_cache` latency — a cache adding 50ms per read is worse than no cache.
33. Test every `counter_cache` under concurrent creates — a counter that drifts under load is a lie.
34. Ship `bin/rails audit:sql` listing every N+1 query Bullet finds across the suite.
35. Every `render json:` should declare `only:`/`except:` — a model exposing every attribute is a leak.
36. Audit `CORS` to guarantee every origin is explicit — wildcard Allow-Origin is CSRF.
37. Every `sidekiq_options` should declare `retry:` and `dead:`.
38. Declare `PAYMENT_GATEWAY_FALLBACK` so the app degrades when Stripe is down.
39. Test every `link_to` with `method:` for JS fallback — progressive-enhancement link failing without JS is broken.
40. Ship `bin/rails health` returning JSON status of every engine, queue, cache.
41. Audit every `strong_parameters` whitelist against every `form_with` to guarantee no field is accepted without permission.
42. Declare `favicon.ico`/`robots.txt` as routes so they are not served by Rails — static files through app are tax.
43. Every `cache_column`/`counter_cache` should have a `REBUILD` task to fix drift without migration.
44. Declare `DEPLOYMENT_SCORE` 0-100; `vps-deploy` should refuse below 80.
45. Test every `enum` for the invalid-value case — invalid strings raise silent `EnumNotFound`.
46. Declare `SHARED_VERSION` so shared code between engines can be versioned and tested for back-compat.
47. Audit every `scope` filtering by `current_user` for tenant isolation — a scope that does not scope is data leak between cities.
48. Ship `bin/rails security` running `brakeman`, `bundler-audit`, and custom scanner in one command.
49. Audit every `after_initialize`/`to_prepare` for thread-safety — mutating global state is race.
50. Declare `PERFORMANCE_BUDGET` listing max response time, page weight, query count per page — `bin/rails benchmark` should fail deploy if exceeded.
51. Every `ActionMailer` subclass should declare `default from:`/`reply_to:` so framework enforces, not operator.
52. Ship `bin/rails i18n:audit` finding every hardcoded English string in a view helper.
53. Review every `has_and_belongs_to_many` for whether `has_many :through` is more appropriate — HABTM cannot carry metadata.
54. Audit `propshaft` manifest to guarantee every asset is referenced — orphaned bundle is bytes wasted.
55. Declare `CITY_TIMEOUT` so every city engine configures its own request timeout — a global timeout fitting Bergen does not fit Reykjavik.

### OPENBSD — what would make the deploy pipeline and VPS runbook a joy to operate

1. `rc.d/master` should print a startup banner naming version, PID, boot time so operator knows daemon is alive without `rcctl`.
2. Every script in `OPENBSD/bin/` should declare its own `VERSION` read by `vps-deploy` before running.
3. `vps-deploy` should accept `--dry-run` printing the full sequence without executing.
4. `relayd.conf` should be validated at boot by `relayd -n` and result logged — a broken conf that loads is worse than one that refuses.
5. Every `rc.d` script should declare `depends_on:` as machine-readable list so `rcctl` orders correctly without guessing.
6. Ship `RELEASE_NOTES.md` updated on every deploy — an undeployed box is an undeployed change.
7. Audit `doas.conf` via a gate asserting every rule is scoped to a command and user — unscoped doas is root for everyone.
8. Every `pkg_add` should declare `VERIFY_SIGNATURE` — a package without signify is supply-chain attack.
9. `deploy-smoke.sh` should test every apex on the box, not just three live apps — amber and bsdports need their own smoke test.
10. `sshd_config` should be audited via `ssh-audit` on every deploy — silent SSH downgrade is root cause.
11. Every `cron` job should declare `MAILTO=` so failures are emailed — a cron failing silently fails forever.
12. Ship `NETWORK_DIAGRAM.md` mapping every domain to its port, relayd section, backend IP.
13. `nsd.conf` zones should be validated by `nsd-check` at boot and logged — a broken zone serving stale DNS is worse than no DNS.
14. Every `acme-client` cert should be audited for expiry by `domain_watch.rb` at boot, not just once a day.
15. Declare `VPS_HEALTH_CHECK` running every five minutes logging CPU, RAM, disk, swap — a box out of memory does not recover silently.
16. `pf` rules should be validated by `pfctl -nf` before loading — a bad rule loading blocks operator's own SSH.
17. `sync_tree` should log before-and-after SHA so a deploy is verifiable without `git log`.
18. Every `rc.d` script should have a `stop` guaranteeing the process is dead — a daemon refusing to stop cannot be upgraded.
19. Ship `BACKUP_VERIFICATION` restoring a random backup to throwaway dir and running `PRAGMA integrity_check` — a backup never restored is not a backup.
20. `etc/` should be tracked in git with a commit on every change so config has a history — config only on box cannot be audited.
21. `relayd` backends should be audited to guarantee every backend has a health check — a backend without health check serves broken traffic.
22. Declare `DEPLOY_ORDER` listing exact sequence to start/stop — a deploy starting app before database is failed deploy.
23. Every `pkg_add` should declare `pkg_delete` fallback so an upgrade can be rolled back — a manager without rollback is one-way door.
24. Ship `LOG_ROTATION` guaranteeing every log file is rotated and compressed — an unrotated log fills disk and downs box.
25. Verify `ntpd`/`openntpd` points at reliable time source — a box with wrong time breaks TLS and session tokens.
26. Test every `rc.d` script via `test_rc_scripts.rb` starting/stopping in a throwaway jail — a script working on operator's box but not clean jail will fail on deploy.
27. Declare `SECURITY_HARDENING` checklist verified on boot: SSH key-only, root login disabled, unused services stopped, firewall enabled.
28. Audit `daily.local` to guarantee it does not run commands as root that could be replaced by compromised binary — a daily script running everything as root is privilege escalation.
29. `dr-pull` should verify restore by running `sqlite3 .dump` diff against source — a backup restoring to different shape is lying.
30. Ship `CAPACITY_PLAN` documenting current RAM, disk, connection limits and thresholds requiring upgrade — a box running out of resources without warning runs out of service.
31. Test every `ifstated`/`hostname.*` to guarantee hostname resolves to correct IP — a box answering wrong name serves wrong city.
32. Declare `RUNBOOK_VERSION` matching deployed config — a runbook not matching box is lying.
33. Audit `pf` tables to guarantee no stale entries — a table growing without bound slows firewall.
34. Declare `bin/usage` listing every command and args so operator need not read source to know what to run.
35. Audit every `ssh` key for expiration and `command=` restriction — unrestricted key is standing root.
36. Ship `FAILURE_MODE.md` listing ten most likely failures and exact command to diagnose each.
37. Test `rc.d` scripts for `reload` — a daemon that cannot reload without full stop/start is downtime-inducing deploy.
38. Declare `MONITORING_CONFIG` exporting `rrd`/`snmp` config so box is watched externally — a box monitoring itself lies about itself.
39. Audit every `acme-client` domain to guarantee cert matches hostname — a cert for wrong domain is TLS failure waiting.
40. Ship `DISASTER_RECOVERY` rebuilding entire box from bare `pkg_add` — a recovery requiring manual at 3am will not happen.
41. Audit `smtpd` to guarantee no open relay — an open relay is spam bot's best friend.
42. Declare `NETWORK_POLICY` documenting every allowed inbound/outbound connection — a network without policy accepts anything.
43. Audit every `rc.conf.local` variable for its default — a variable set to wrong default is bug hiding until fresh install.
44. Ship `CHANGES.md` appended on every deploy — a deploy without changelog cannot be audited.
45. Declare `provides:` in every `rc.d` script so `rcctl` resolves dependencies by capability not script name.
46. Declare `VPS_IMAGE` bootable in QEMU for testing — a deploy that cannot be tested locally can only be tested on the box.
47. Verify every `rc.d` script runs as declared `daemon_user` — a script running as root when it should run as `_pub4ci` is privilege escalation waiting.
48. Declare `set -euo pipefail` at top of every `OPENBSD/bin/` script and test for it — a script without strict mode silently continues past errors.
49. Ship `PERF_TUNING` documenting every `sysctl`/`mount` option and reason — a tuned box without docs cannot be retuned.
50. Declare `SECURITY_AUDIT` schedule — monthly `ssh-audit`, `pfctl -s all`, `pkg_info -m`, `daily.check` — and `vps-deploy` should refuse if last audit >30 days.
51. Audit every `relayd` section to guarantee `block` policy is set on every listen — a relayd section without block policy forwards anything.
52. Ship `TICKET_TEMPLATE` filled on every deploy — a deploy without ticket cannot be tracked.
53. Rotate `ntp` symmetric keys on every deploy — an ntp key never changing is time-source compromise never noticed.
54. Declare `SERVICE_LEVEL_AGREEMENT` mapping every apex to acceptable downtime — a service without guarantee cannot be measured.
55. Every `rc.d` script should declare `START_ORDER` so `vps-deploy` starts box in right sequence — a box starting app before database wastes first minute crashing.

### STUDIO — what would make the media tools a joy to create with

1. `dilla.rb` should ship `dilla.md` explaining the 81 parts in order required, so a new contributor can trace a sound without reading whole file.
2. Every renderer should declare `SAMPLE_RATE` and `BIT_DEPTH` at top so operator knows output.
3. `STUDIO/dilla/renders/` should be migrated into dilla root with `.gitignore` rules, so render pipeline is inside repo where it can be audited.
4. Every `lib/*.rb` support module should declare `__dir__` once at top and use a constant, so moving file does not break path.
5. `DillaSources` should declare `SOURCES_VERSION` matching sample corpus, so mismatch is caught at boot.
6. `dilla.rb` should be split along existing seams — renderers, ENV tables, SMF writers, patch registries — into `lib/` files that require each other in declared order.
7. Every `test_dilla_*` should declare its own timeout so a slow test does not kill whole suite — a suite failing from timeout lies about what passed.
8. Fix `test_dilla_audio_graph_parity.rb` to match current bus-routed graph topology — a test expecting flat `amix` when engine emits routed graph tests wrong thing.
9. `STUDIO/gate.rb` should declare `GATE_VERSION` and test that `lib/engine/` does not reappear — a gate not testing its own condition can be silently bypassed.
10. Every `Outboard.chain` arm naming a module should be tested to verify module exists and is dispatchable — dead arms are dead code looking alive.
11. `samples/dug/` corpus should be documented with `sources.yml` mapping every file to its download URL — a sample without URL cannot be re-fetched.
12. Every `rack` in registry should be deduplicated by checksum so 38 duplicate recordings collapse to 123 unique wavs.
13. `dilla.rb` should declare `LINE_LIMIT` 300 and `bin/check` should enforce it — a file exceeding limit cannot be read.
14. Every `key` in registry should be measured and verified against `KEY_LIBRARY`, so a key out of tune is caught before it renders.
15. Ship `RENDER_SEED` pinning every render to deterministic seed, so "re-render" actually produces same file.
16. Every `vocal_chop` skipping a row should log skip reason so operator knows why vocal is missing — silent skip is silent defect.
17. Declare `DRUM_LOOP_SOURCE` as constant tested to exist before any render — a drum loop resolving to `~/Downloads` is a render depending on file outside repo.
18. Test every `techno_harmony_root` against `HARMONY_VALIDATOR` so most advanced processing is most tested.
19. Declare `RENDER_BUDGET` listing max render time, memory, disk per render.
20. Replace every `__FILE__` with `__dir__` — a file path hardcoding directory breaks when file moves.
21. `postpro/` should declare its own `CONTRIBUTING.md` so a colorist knows grading pipeline without reading source.
22. Every `repligen/` and `lora/` model should declare `MODEL_VERSION` and `CHECKSUM` so corrupted model is caught at load.
23. Ship `GENERATE.md` explaining how to reproduce a specific render — a render without recipe cannot be repeated.
24. Test every `dilla.rb` part manipulating audio with known-input known-output file so transform is verifiable.
25. Declare `SEED_REALISM` guaranteeing every city's demo audio sounds like that city — 39 of 43 cities seeding at 0,0 is map reading as empty.
26. Every `render` should write a `.dilla` provenance sidecar validated at write time — optional provenance is skipped.
27. Ship `RENDER_DIFF` comparing two renders with seeds and reporting dB difference — a render changing without seed change changed by accident.
28. Tag every `sound` with its `GENRE` so a genre-agnostic tool is genre-discoverable.
29. Declare `RENDER_BACKUP` copying every render to off-tree location before it can be overwritten — a render that can be overwritten can be lost.
30. Test every `patch` registry to guarantee patch applies cleanly to target version — a patch failing silently lies.
31. Ship `BENCHMARK` measuring every render's CPU and wall-clock time and failing if it exceeds budget.
32. Every `effect` in chain should be auditable — operator should be able to ask "what effect was applied here?" and get exact module and args.
33. Declare `FORMAT_VERSION` for every output format so a format change is a breaking change that is versioned.
34. Test every `loops` file for its `beats_per_minute` against registry — a loop lying about BPM breaks mix.
35. Ship `RENDER_MONITOR` watching render directory and alerting when render exceeds time or disk budget.
36. Wrap every `plugin`/`external` call in `with_timeout` so a hung external process does not hang whole pipeline.
37. Declare `QUALITY_GATE` asserting every render passes spectral analysis before it is considered done — a render passing without analysis might be silent.
38. Test every `sample` for its `duration` against expected length — a sample shorter than expected drops beats.
39. Ship `RENDER_LOG` recording every render command, param, seed — a render without log cannot be reproduced.
40. Test every `mix` for its `peak_level` and `rms_level` so a clip exceeding 0dB is caught before rendered.
41. Declare `MASTER_RENDER` as canonical reference render for every crate — a crate without reference cannot be judged.
42. Every `dilla.rb` constant appearing in `data/voice.yml` should be read from `data/voice.yml` — a constant also hardcoded is a constant drifting.
43. Ship `CORPUS_AUDIT` verifying every sample in registry exists on disk and is not corrupted — a registry naming a file that does not exist lies.
44. Test every `sfx` bank for its `sample_rate` and `bit_depth` against project settings — an sfx bank at wrong sample rate is pitched wrong.
45. Declare `RENDER_PIPELINE_VERSION` matching `dilla.rb` version — a pipeline not matching code renders sound not matching spec.
46. Test every `filter` for its `frequency_response` against known target — a filter doing nothing lies.
47. Ship `GENRE_PROFILE` for each supported genre defining BPM range, key range, mix rules — a genre without profile is without standard.
48. Test every `envelope` for `attack`, `decay`, `sustain`, `release` against DAW convention — an envelope out of phase hits at wrong time.
49. Declare `RENDER_QUALITY_TIER` (draft, studio, master) so operator knows what level of processing is applied.
50. Ship `RENDER_VALIDATOR` running spectral, temporal, loudness analysis on every output and failing if any metric out of range.
51. Test every `tempo` change for its `time_stretch` algorithm — a tempo change without time-stretch is pitch change.
52. Declare `MASTER_BUS` standard that every render must pass through — a render bypassing master bus has no master.
53. Test every `bus` for its `gain` and `pan` against stereo field — a bus off-center is unbalanced mix.
54. Ship `RENDER_ARCHIVE` compressing every finished render and storing with seed — a render without archive can be lost.
55. Declare `CREATE_QUALITY` asserting every generated sound passes human-in-loop review before finished — an AI generating without review generates garbage.

### The 10/10 MASTER — Muse Spark 1.2 Free vision

The perfect MASTER is a runtime where the constitution is not a file you read
but a surface you interact with. A developer clones the repo, runs
`bin/check --profile=agent`, and the first thing they see is not a sea of red
failures but a clean scan and a single sentence: "The constitution is green.
Here is what the fold found."

It is a runtime where every rule carries its own evidence — the finding count,
the last measurement, the false-positive history — and every measurement is
verified against a known-clean snapshot before it is trusted. A rule that
cannot prove itself is a rule that should not exist.

It is a runtime where the fold spine is measured by its own law, where the
scanner is tested by the rules it scans, and where the constitution is the
first thing reviewed in a code audit — not the last.

It is a runtime where `bin/master` answers a question in a sentence, where
`bin/pub4 gate` tells you exactly which law a change broke and why, and where
`bin/pub4 measure` gives you a number you can trust because it was measured
today, not last week.

It is a runtime where the four trees are four citizens of one constitution,
where `MASTER` governs `RAILS` the way `RAILS` governs `STUDIO`, and where the
OpenBSD box is not a deployment target but a provable artifact — every config
file signed, every service verifiable, every deploy auditable.

The 10/10 MASTER is a constitutional runtime that applies its laws to itself
without exception, where the governor is governed, where every effect is proved
and every verdict is recorded, and where a new contributor can go from clone to
green check without reading a single contract file — because the runtime itself
teaches them what it needs from them. This vision was refined after fixing the
root-invariant violation (SEVEN at repo root), the TODO.md merge-conflict
markers, and the design-system opacity ladder — three files that contained their
own proof of correctness while not being correct, which is the defect this
constitution exists to prevent.

---

## Aegis, seaborne

Aegis is the proactive-bodyguard concept: passive sensing, active analysis,
preemptive action. Written for a city it is a hard build and a poor business.
Written for the water it is a narrower build with paying customers, and it is
the case where this runtime's offline-first design stops being a preference and
becomes the product.

**The urban threat model does not port.** It assumes an adversary who is human,
intentional, and three seconds away, in a place with dense infrastructure. At
sea the threat is environmental and indifferent, the timescale is twenty minutes
to twelve hours, rescue latency is hours rather than minutes, and connectivity
is absent by default rather than merely degraded. Every intervention that
depends on deceiving a person — the synthetic phone call, the fake system
update, the lit-street route — has no one to deceive and nowhere to walk. Gait
analysis, proximity tailing and weapon identification go with them.

What survives is small and gets much stronger. Immersion and sudden-deceleration
detection replace the acoustic and gait tiers. The last-known-position heartbeat,
a footnote in the urban spec because the city has signal, becomes the entire
value proposition. The forensic packet already has a regulatory home, because
voyage data recording is mandated on commercial vessels and is currently dumb.

**Man overboard is the anchor, and the only one worth starting from.** It maps
onto the existing pipeline almost unchanged: immersion plus acceleration anomaly
triggers, biometrics confirm the wearer is alive, an AIS-MOB and satellite burst
carries position, and the packet is the record. It is far more tractable than
the urban case because there is no intent to model and no adversary adapting to
the detector, and it drops the whole privacy surface with them. Existing MOB
beacons are pull-cord or water-contact triggers with no discrimination and no
prediction. The gap a model actually fills is drift: cold-water displacement is
predictable from sea state and current, and a search wants the probable position
twenty minutes from now, not the position at the moment of the fall.

**The gate is hardware, not software.** A phone cannot host this — salt,
immersion, battery, and the fact that it rides in a pocket rather than against
skin. The sensing substrate has to become a wearable or a vessel-mounted box
before any of the sensing tiers are worth writing. So the order is: prove the
tier-one anomaly stack on phones on land, where iteration is cheap, then port
detection to marine hardware, where the regulation and the budgets are. The
urban build is the laboratory, not the product.

**Do not scaffold the sensing tiers yet.** Stub sensors, placeholder threat
classes and a maritime module wired to nothing would be this tree's dominant
defect committed deliberately, and `data/soul.yml` forbids it under
anti_simulation. Nothing in this program is written until it has a reader.

The one piece buildable today with no hardware and no speculation is the drift
model: a pure function from entry position, sea state, current and elapsed time
to a probable-position ellipse, testable against published search-and-rescue
drift data. It is useful on its own to anyone running a search, it is the part
with real intellectual content, and it is falsifiable — which the rest is not
until there is a device. Start there or start nowhere.

Norway is the place to do it: the fishing fleet, the aquaculture pens, the
offshore wind buildout, Sjøfartsdirektoratet, and an Innovasjon Norge case that
argues far more readily for maritime safety than for a constitutional runtime.
It is the same pitch as `MASTER/README.md` makes, with a body attached.

---

## A hundred, toward a catalogue of livesets — 2026-09-02

Written after the three sets in `STUDIO/dilla/live/` landed, and after the
operator said what the lost Ableton sets were made of: Goldbaby drums, a master
chain of many Sonitex instances and several Nasty VCS on *summing phasy*, one
sweet sample, and Dilla's rule — make old things sound new and new things sound
old. The sets exist to replace a life's work that a robbery took. Three is not a
catalogue, and this is the list of what would make it one.

One fact shapes most of what follows. `dilla.rb` already carries the sound
design: devices (`COPY_MACHINE`, `HOCKET`, `VOICE_STACK`, `LPG`, `BUS_PATCH`,
`WAV_MAP`, `MIDI_BAG`), section maps, four mix buses, a modulation matrix, 401
chord progressions, 74 track presets, and forty-two support modules under
`lib/`. The three sets reach for about six of its knobs and re-synthesise from
scratch what the engine would have handed them. So a large share of this list is
not *build* — it is *connect*, which is this repo's dominant defect written down
in `MEMORY` as inert config and dead wiring.

**[cheap]** is an afternoon. **[deep]** is a project. **[yours]** is a decision
rather than work. **[risk]** changes a rendered sound and so is not mine to
choose. Numbers are for citation, not for order.

### A · The catalogue: sets to build (1–20)

1. **`vocal_chop_beats.als.rb`** [cheap] — `lib/vocal_chop.rb` already separates
   a vocal stem and refuses any rack that cannot name its source. Thirteen racks
   can. A set built on the voice rather than the instrumental is one new file
   against work already done.
2. **`drum_break_beats.als.rb`** [deep] — `radio_chop` runs `htdemucs_6s` and
   throws the drum stem away. Keeping it gives every record in the crate its own
   break, which is the other half of the sampling tradition and currently
   discarded at the moment it is most expensive to compute.
3. **`two_deck.als.rb`** [deep] — two beds at once. `Rack.grid` already derives a
   tempo from a loop's own duration, so beat-matching two racks is arithmetic
   that exists. A DJ shape rather than a beat: one record under another, one
   leaving as the other arrives.
4. **`interlude.als.rb`** [cheap] — twenty to forty seconds, one idea, no
   arrangement. *Donuts* is thirty-one pieces in forty-three minutes. The sets
   are all ninety-six or a hundred and eighty seconds because that was the first
   number typed, not because anything measured it.
5. **`beat_tape.als.rb`** [deep] — one render containing six linked pieces with
   transitions between them: a side of a tape rather than a track. The unit the
   lost sets probably were.
6. **`remix.als.rb`** [cheap] — `samples/own/` holds nine finished recordings by
   the operator and named collaborators. Every set so far plays other people's
   records. One that plays ours is a different thing to own.
7. **`spoken_word.als.rb`** [deep] — `lib/acapella.rb` exists. A bed under speech
   is the oldest form in the tradition and the one the crate is best suited to.
8. **`jazz_trio.als.rb`** [deep] — `chord_based_beats` voices its chords as
   detuned sines because that was the cheapest honest thing. `lib/harmony_lead.rb`
   and `lib/analog_synth.rb` and the four cached soundfonts exist. The same
   progressions through a real instrument is a second set, not a change to the
   first.
9. **`tape_loop.als.rb`** [deep] — a physical loop degrading each pass:
   `lib/tape_hysteresis.rb` is already written and the set would be the first
   caller that makes its behaviour audible over time rather than statically.
10. **`long_form.als.rb`** [cheap] — twenty minutes rather than three. The pad
    set is already the shape; only `TOTAL` and the swell period stand in the way,
    and a set you can leave running is a different use than a set you audition.
11. **`radio.als.rb`** [deep] — never ends. `live/broadcast.sh` rotates four
    processes with hard cuts between them; a set that crossfades its own
    successor is the thing that was actually wanted.
12. **`field.als.rb`** [yours] — a bed that is a place rather than a record.
    Needs recordings that do not exist yet, and making them is a day out with a
    recorder, which is the cheapest new material this project could get.
13. **`minimal.als.rb`** [cheap] — one voice, no kit, no bed, no console stack.
    Useful mostly as a control: everything else in the room is additive and
    nothing measures what each addition is worth.
14. **`flip.als.rb`** [cheap] — `lib/sample_flip.rb` chops against chords and is
    one of the engine's better ideas. No set reaches it.
15. **`dfam.als.rb`** [cheap] — `lib/dfam_engine.rb` models a semi-modular drum
    voice and is likewise unreached from `live/`.
16. **`gospel.als.rb`** [cheap] — the eight-bar climb specialised: slower harmonic
    rhythm, the climb as the whole arrangement rather than a row sampled out of a
    table of four hundred.
17. **`techno.als.rb`** [yours] [risk] — the crate rules exclude industrial
    techno and the standing goal is a genre-agnostic engine where techno, soul
    and jazz are parameters rather than forks. Those two are in tension and only
    the operator can resolve it.
18. **B-side sets** [cheap] — the same seed through a deliberately different
    room. Costs one environment variable if the console parameters become data;
    see 31.
19. **Tempo families** [cheap] — the beat sets both sit at 82–104 because that
    is where the crate lands after drag. A set at 60 and a set at 140 would say
    whether the room survives outside its comfortable octave.
20. **A set per crate region** [deep] — `project/sample_worth.json` scores every
    rack on seven terms. The sets use only the aggregate. Sets keyed to *voicing
    density* or *chord-register presence* would each sound like a different
    record collection, which is what a shelf of Ableton sets actually was.

### B · The room is sitting on an engine it does not call (21–36)

21. **`COPY_MACHINE`** [cheap] — the bed played six times at once at different
    speeds, with `_FAMILY=harmonic|chromatic|spray`. This is precisely what
    `sampled_based_beats` hand-rolls with `asetrate` and three voices, done
    better, already tested, and reachable.
22. **`VOICE_STACK`** [cheap] — four voices each playing all of it, differing in
    register, tuning and timbre, with a macro that picks a model and a patch from
    212. The pad set's four-interval voicings are a poor cousin of this.
23. **`HOCKET`** [cheap] — one line split across voices with `round_robin`,
    `pendulum`, `shift_register` modes. Nothing in `live/` splits anything.
24. **`LPG`** [cheap] — a Buchla low-pass gate, measured at 17.5 dB more high-band
    fall than body over a decay. It is what makes a note read as *struck*, and the
    chord set's whole problem is that its notes read as *triggered*.
25. **`BUS_PATCH`** [cheap] — a whole modulation patch on a bus: one source per
    destination, depths biased low, at least one inverted, `BUS_PATCH_SEED` to
    pin it. Movement over ninety-six seconds is the sets' weakest dimension and
    this is the built answer.
26. **`WAV_MAP`** [cheap] — a picture read as an oscillator in the track's key.
    Not a gimmick if the picture is a photograph of the thing the piece is about.
27. **`SECTION_LAYERS=full`** [cheap] — the harmony bus leaves in the intro and in
    any breakdown over eight seconds. The sets each hand-roll one volume
    automation across a fixed bar range and call it an arrangement.
28. **`FORM_FIT`** [cheap] — stretch a form across the track rather than cycling
    it, on by default past 64 bars. The pad set at 180 seconds is four intros
    cycling and does not know it.
29. **`DILLA_MIX_BUSES` and `CONSOLE_STACK`** [cheap] — four buses and a summing
    stack measured at 23 dB less third harmonic at three stages than one. The
    sets do their own flat `amix` with hand-tuned weights that had to be
    re-measured by hand this session when the kit changed.
30. **`FROZEN_STATE` / `DILLA_FROZEN`** [cheap] — the engine's own A/B pin. The
    sets grew a parallel seed mechanism because nobody checked whether one
    existed.
31. **Make the console parameters data, not call sites** [cheap] — `Rack.sonitex`
    and `Rack.vcs` are invoked eleven times across three files with literal
    numbers. A named table (`warm`, `dry`, `blown`, `phasy`) turns "which room"
    into a knob, which is what 18 and most of section G need.
32. **`lib/outboard.rb`** [cheap] — eight emulations, four of which measuring
    proved dead. The live rack re-implements two of the four that work.
33. **`lib/producer_dna.rb` and `GROOVE_DNA=donuts`** [deep] — `drunk_kit`'s
    jitter figures are hand-chosen constants. A DNA table already describes this
    and would let a set be *in the manner of* rather than *approximately drunk*.
34. **`lib/knobs.rb`** [cheap] — nineteen documented knobs the sets do not read,
    so a set cannot be steered without editing it.
35. **`lib/taste.rb` and the scoring modules** [deep] — `mix_score`,
    `groove_score`, `harmony_score` and `spectral_audit` can each judge a render.
    Nothing judges a pass. A set that scored itself and refused to journal a bad
    take would make the catalogue self-curating.
36. **`RINGTONE_LAYER` and `PAD_LAYERS`** [cheap] [risk] — known-good layers with
    known switches, unreached from `live/`.

### C · Drums (37–46)

37. **Run `lib/kit_dig.rb`** [cheap] — it cuts a kit from `samples/own/` by
    running demucs and keeping only the drum stem. It has never been run: there is
    no `provenance.json`, and `samples/drums/custom/` is the downloaded
    `03-soulful-vintage`. Our own drums are one command away and beat re-buying
    anything.
38. **Re-acquire Goldbaby** [yours] — nothing on this machine is named it. The
    licences presumably survive the robbery even though the sets did not; the free
    packs would do to start. This is the single named ingredient of the lost
    chain that is simply absent.
39. **More than one sample per role** [cheap] — `LIVE_KIT` plays one `kick.wav`
    for every kick in the piece. Real machines and real drummers do not repeat a
    waveform, and round-robin over a folder is the difference between a kit and a
    trigger.
40. **Velocity, not just position** [cheap] — `drunk_kit` jitters *when* a hit
    lands and never *how hard*. Dilla time is both, and the level dimension is the
    one that reads as a human.
41. **Ghost notes from the snare recording** [cheap] — a ghost is a quiet short
    snare, not a separate file. Deriving it would remove a role from `KIT_ROLES`
    and make more kit directories qualify.
42. **The two-kick habit** [cheap] — the engine already alternates a second kick
    body (`kit[:ind_kick]`). The live rack does not.
43. **Kit-aware mix weights** [cheap] — the sampled bus gain was matched by
    rendering and measuring, by hand, once. A calibration step that measures each
    kit on install and stores its trim is the version that survives a new kit.
44. **Swing that is not jitter** [cheap] — the hat pattern adds a flat 34 ms to
    odd steps. That is a swing setting, the exact thing the comment above it says
    this is not.
45. **Name a `DRUM_LOOP` replacement** [yours] [risk] — it currently falls back to
    `~/Downloads/techno_drums.mp3`, outside the repo and against the crate rules.
46. **A kit from the crate itself** [deep] — every rack has a discarded drum stem
    (see 2). A kit cut from the same record as the bed would glue in a way no
    imported kit can.

### D · The crate, and not losing it twice (47–58)

47. **Record the source URL at fetch time** [cheap] — forty-one of forty-two
    sources are gone with no URL anywhere. This is the same failure that took the
    Ableton sets: irreplaceable material with no way back. It is a one-line change
    and it is the most important item on this page.
48. **Write provenance before the audio** [cheap] — a sidecar written first
    cannot be outlived by what it describes, which is how `henrik_debich` alone
    survived.
49. **Checksum the racks and deduplicate** [cheap] — 161 rows, 123 unique wavs, 38
    phantoms in 28 collision groups. Dropping duplicates is measurement, not
    judgement.
50. **A silence floor on the downbeat measure** [cheap] — the rotation fix for the
    153 mis-cut racks is blocked on this, because a quiet tail currently scores as
    a bar line and one rack starts at −57 dB.
51. **Then rotate the 153** [deep] — content-preserving, since a rack is one whole
    period.
52. **Back the crate up off this machine** [yours] — `samples/` is gitignored by
    path, the renders are gitignored, and the one copy of both is a laptop. The
    robbery is the argument.
53. **A crate manifest that is not the audio** [cheap] — titles, seams, keys,
    worth scores and URLs in one committed file, so a lost crate can be re-cut
    rather than merely mourned.
54. **Dig more** [cheap] — `samples/dug/` holds one file. `dig`, `dig-seams` and
    `dig-cc` exist and work.
55. **Attribution as a build artifact** [cheap] — `credits` exists. A set that
    plays CC-BY material should be able to print what it owes without being asked.
56. **Key-aware bed selection** [cheap] — all 161 racks now carry `key`; nothing
    reads it. Two decks (3) and any harmony over a bed need it.
57. **Retire `sample_worth`'s single number** [deep] — it is seven terms collapsed
    to one, and the collapse is where a set loses the ability to ask for a
    *kind* of record rather than a *good* one.
58. **A rack the operator marked** [cheap] — no way exists to say *this one*. A
    starred flag in the worth table would outrank every automatic score, which is
    the correct hierarchy.

### E · Playing them, not running them (59–70)

59. **A set should not exit** [cheap] — every set renders a fixed block and stops.
    A performance does not.
60. **Change something while it plays** [deep] — the engine already has
    `asendcmd` modulation and a `modulate` command; `MOD_RATE_HZ` names its
    resolution. The live rack builds one static graph.
61. **MIDI in** [deep] — the difference between a generator and an instrument.
62. **A pass you can nudge** [cheap] — drag, kit, weights and drop points are
    all decided before the first sample and cannot be touched after.
63. **Cue the next bed** [cheap] — `pick_bed` chooses once, silently. Being able
    to see and reject the next choice is most of what a DJ does.
64. **Mute groups** [cheap] — kit, bed, phrase, crackle. Four switches would make
    the sets performable with nothing else on this list done.
65. **Tap tempo** [cheap] — the grid is derived from the record. Sometimes the
    record is wrong.
66. **A set that listens** [deep] — `LISTEN_PASSES` exists in the engine.
67. **Two sets at once** [deep] — `broadcast.sh` runs one at a time by design; the
    interesting case is a pad set under a beat set.
68. **Stop cleanly** [cheap] — killing audio this session meant killing processes.
    A set should end on a bar.
69. **A visible transport** [cheap] — bar number, section, next change. The banner
    prints once and then ninety-six seconds pass in silence.
70. **The rig on the box** [yours] — `playlist.brgen.no` is the label. A set
    rendering nightly on vm23 into the catalogue is a different project than a set
    played on a laptop, and the capacity ceiling there is real.

### F · Keeping, naming, releasing (71–82)

71. **Every take, not the kept ones** [yours] — `--keep` is opt-in and a good pass
    is recognised after it has gone. Ring-buffering the last ten renders costs
    disk and no decisions.
72. **A take is not a wav** [cheap] — `renders/live_<seed>/` holds an ignored wav
    and a tracked json. That asymmetry is right and should be stated somewhere a
    reader finds it.
73. **Replay verification in the suite** [cheap] — three determinism defects were
    found this session by rendering one seed twice and comparing hashes. Nothing
    stops a fourth.
74. **Name the takes** [cheap] — a seed is not a title. `dilla` already generates
    track names.
75. **Stems** [cheap] — `VOICE_STACK_STEMS` exists for the engine. A kept take
    that cannot be remixed later is a photograph, not a session.
76. **Export the set, not the audio** [deep] — the thing that was lost was
    editable. A take that reopens as parameters is the only real answer to the
    robbery, and the `.als.rb` naming already claims it.
77. **A catalogue file** [cheap] — `project/liveset.jsonl` is a log. A catalogue
    is the subset worth keeping, in order, with titles.
78. **Mark the three that must not be shared** [cheap] — the existing label rules
    already distinguish them and the live rig knows nothing about it.
79. **Loudness for the destination** [cheap] — every set ends in `dynaudnorm` and
    a limiter at a hand-picked `volume=`. Integrated LUFS is a solved measurement
    and lies about speech over music, which matters for 7.
80. **A sleeve** [yours] — `STUDIO/postpro` grades images and `repligen` generates
    them. A catalogue with covers is a release.
81. **Publish the tracklist** [yours] — `playlist.brgen.no` exists and is empty of
    this.
82. **Delete nothing automatically** [cheap] — the scratchpad sweeps audio, and a
    long render that lands there is gone. Renders must be written outside it and
    be resumable.

### G · The master chain, against the one that was lost (83–92)

83. **Verify `vcs` against the plugin** [yours] — `Rack.vcs` is `aphaser` into
    `aecho` and was written toward *summing phasy* from description alone. Nobody
    has A/B'd it against the real thing, and the operator is the only person who
    can say whether it is close.
84. **Count the instances honestly** [cheap] — the sets run five or six Sonitex
    stages and five or six VCS stages. *Tons* was the word used about the lost
    chain. Whether more is more here is measurable and unmeasured.
85. **Order matters and is unrecorded** [yours] — where in the chain each instance
    sat is not something the sets can guess.
86. **Per-channel versus master** [cheap] — the current placement is at every
    summing point, which is defensible and is not what a plugin chain on a master
    bus does.
87. **Gain staging as a measurement, not a constant** [cheap] — `vcs` carries a
    `volume=1.9` makeup that exists because three instances were throwing away
    22 dB. That is the right fix and the wrong form: it should be derived.
88. **`sonitex` runs its crusher at half strength** [cheap] — `acrusher` defaults
    `mix=0.5` and `Rack.sonitex` never sets it, so all eleven stages are fifty per
    cent dry. Whether full strength is better is an ear question; that the knob
    was never turned is a fact.
89. **The 1260 is a sample rate as much as a bit depth** [deep] — `acrusher` also
    carries `samples` (1 to 250, currently 1, meaning off) and an `lfo`. Bit
    reduction alone is the cheapest third of what a 12-bit sampler does.
90. **Tape before the console** [cheap] — `lib/tape_hysteresis.rb` is written and
    unused in `live/`, and tape is where the lost chain's *old* came from.
91. **A dry control** [cheap] — no set can be heard without the room. Nothing
    proves the room is an improvement.
92. **Measure THD, not taste** [cheap] — `CONSOLE_STACK`'s documentation cites a
    measured 23 dB figure. The live rack cites nothing.

### H · Instruments before findings (93–100)

93. **Nothing in the suite covers `live/`** [cheap] — three sets, a shared rack and
    a recall tool, and `grep` over `STUDIO/test` finds no reference to any of it.
94. **A graph that builds is not a graph that sounds** [cheap] — two defects this
    session were empty filter strings from Ruby comments inside line continuations,
    which ffmpeg reported as `No such filter: ''`. A lint over the built graph
    would have caught both before the render.
95. **`aloop` is not reproducible at scale** [deep] — proven at 1.5 million
    samples, fine at 120 000, bisected to the filter. The workaround is in
    `ambient_pads`; the boundary is unknown and the other sets sit on the wrong
    side of not knowing.
96. **Every generator needs a seed** [cheap] — `anoisesrc` seeds from the clock.
    One audit over the tree for unseeded sources would close the class rather than
    the instance.
97. **PRNG draw order is an interface** [cheap] — adding a `rand` above an
    existing one silently invalidates every journalled seed. Nothing states this
    and nothing tests it.
98. **A/B by rendering, always** [cheap] — the kit change was verified by
    rendering seed 777 against `HEAD` and comparing SHA256. That is the standard
    and should be a script rather than a habit.
99. **Level-match before judging** [cheap] — the louder arm wins every informal
    comparison, and three of this session's comparisons needed a measured trim
    before they meant anything.
100. **Ask what the lost sets sounded like, in more detail** [yours] — tempos,
    lengths, whether any were performance sets rather than beat sketches, what a
    typical one had on its channels. Four sentences from the operator are worth
    more than any twenty items above them.

## 110 wishes from one long day inside pub4 — 2026-09-06, Claude Opus

Written after a session that opened a ratchet nobody had, closed
`rule_fixture_debt` from 91 to 0, found a gate that cost 48 minutes an app, and
learned twice that its own measurement was the defect. Every item traces to
something in that day rather than to general advice. Where a wish has a file, the
file is named, so the next reader can check the reasoning instead of trusting it.

The bias of this list, stated up front: **most of what looked like debt was the
instrument, and most of what the instrument found was already known by somebody
who had left.** Nine of the ten things that cost me the most time were a census,
a gate or a rule that was confidently wrong. That is where the wishes cluster.

### A · The instrument (1–18)

1. Every census prints the corpus it walked, in the same line as the number.
   `self_findings` said 151 for a year and meant "151 from the law over 2,890
   files"; the registry's 145 rules were in no number at all.
2. A ratchet row names its population in its own id. `self_findings.law` and
   `self_findings.registry` read correctly at a glance; bare `self_findings` did
   not, and the label was wrong for a year.
3. Every rule carries a worked example it must flag and one it must not — done,
   0 unfixtured — and the same becomes true of every *census*: a corpus it must
   count and one it must not.
4. A rule that finds nothing anywhere says so in `bin/pub4 measure`, beside its
   ceiling. Twenty-four laws currently fire on nothing; that is either a clean
   tree or a blind detector and the row cannot tell you which.
5. `rule_audit` grows a `--corpus all` so its "silent" list means the fleet
   rather than a sixth of MASTER.
6. Every regex in the rule corpus is linted for the `\b`-next-to-punctuation
   trap. `rake lint:word_boundary` exists; it should run in `bin/check`, because
   that trap has now been recorded four times and hit a fifth.
7. A detector that has never fired in the tree AND has no fixture failure is
   proposed for deletion once a quarter, with the measurement attached.
8. `data_reach` reads nested keys, not only top-level ones.
   `STIMULUS_CONTROLLER_SIZE` had its `max_lines: 200` declared and hardcoded at
   the same time, and no census could see it.
9. Every `data/*.yml` states, in its own head, which reader reads it — and a
   test asserts that reader still exists. `tts.yml` said "NOTHING RUNNING READS
   THIS" over the config that decides how MASTER speaks.
10. A config file that cannot be parsed by its own census fails the census
    loudly. `radio_bergen_track_dossiers.yml` passed as clean for months because
    `safe_load` refused its symbols and the rescue returned nil.
11. `bin/pub4 measure --why <row>` prints the members behind a number, not just
    the delta. Three censuses now record members; the other nine do not.
12. Every ceiling file carries the command that reproduces its number. Half do.
13. A ratchet that has been over for more than a week says so in its row —
    `OVER +826 for 9 days` reads differently from `OVER +826`.
14. `growth.*` counts tracked files, or excludes untracked build output by
    default. A stems render raised `growth.studio` by five until today.
15. A ratchet's ceiling file records who last moved it and why, in one line, so
    the archaeology is not `git log -S`.
16. The four `growth.*` rows carry a per-directory breakdown, so "+13" points at
    the thirteen files rather than at the tree.
17. `bin/pub4 measure` gains `--since <ref>`: every row's delta against a commit,
    which is what a session actually wants to know before pushing.
18. One census over all four trees answers "what did this session change, and
    which ceilings moved". Today that took eleven separate commands.

### B · Gates, and whether they measured anything (19–32)

19. Every gate declares its cost in `gates.yml` and the runner prints it before
    running: `constitutional_scan ~2m`, `rendered_suite ~needs Chrome`.
20. No gate may block on a model call without saying so in its name or its
    header. `constitutional_scan` spent 48 minutes an app in a TLS read.
21. Every subprocess a gate spawns has a timeout. `capture2e` has no bound, and
    one gate hung a whole run with no output and no verdict.
22. A gate that skipped its own subject fails, or is `INCONCLUSIVE` — never
    green. `surface_schema` gets this right; the browser gates get it right; the
    pattern belongs everywhere.
23. `runner.rb --all` prints, at the end, which gates were skipped and why, as a
    list rather than a line.
24. A per-tree constitutional budget for STUDIO and OPENBSD, like RAILS's, so
    "run all four trees through MASTER" is one command with four numbers.
25. `constitutional_scan` reads the *last* `scan: done` line, or says which
    profile its budget is for. Today it silently measures the aesthetic pass.
26. Every gate's ledger entry records its own wall time, so a gate that doubles
    is visible before it becomes unrunnable.
27. `bin/pub4 gate --tree STUDIO` — the ladder scoped to one tree, for the
    common case of working in one.
28. The council tier degrades to a named skip with a cost estimate rather than a
    provider error, and `bin/pub4 gate` exits 3 for it — already true, and worth
    keeping when the credits come back.
29. A gate that autofixes says so in its output *and* lists the files, before it
    writes.
30. `GATE_STRICT_INCONCLUSIVE=1` becomes the default in CI and stays optional
    locally.
31. Every gate has one test that runs without the thing it gates — no Chrome, no
    vm23, no bundle — proving the gate's own logic.
32. A gate nobody has run in thirty days is reported by the ledger. Two of ours
    had not run in longer than that.

### C · One command, one door (33–42)

33. One verb for the loop: `/through`, with `--only scan|fix|critique|council`.
    Five public verbs for one pipeline is why nobody remembers which to use.
34. `bin/pub4` and `bin/master` stay the only two surfaces, and `bin/` stops
    growing: 27 executables under `MASTER/bin` against a ceiling of 27 is not a
    surface, it is a directory.
35. `bin/pub4 help` prints the ladder as a tree with what each stage costs.
36. Every slash command has a one-line `--explain` that says what it will write
    before it writes it.
37. A dry-run flag that means the same thing everywhere. Today `--scan-only`,
    `--no-autofix`, `MASTER_SCAN_AUTOFIX=0` and `GATE_AUTOFIX` all mean a
    variation of it.
38. Environment variables that gate behaviour are declared in one file with
    their defaults, and a test asserts every `ENV[` read appears there.
39. `bin/pub4 doctor` answers "is this checkout in a state where the gates mean
    anything" — right Ruby, clean tree, hooks installed, Chrome present.
40. Every command that can take minutes prints progress to stderr as it goes.
    `constitutional_scan` learned this; the others have not.
41. Long-running commands write a resumable log, so a session that dies mid-gate
    does not start over.
42. `bin/pub4 measure` and `bin/pub4 gate` share one exit-code vocabulary: 0
    clean, 1 findings, 3 could not measure.

### D · What an LLM needs that a human does not (43–58)

43. One generated contract per agent harness, from one source — done today, and
    the shape to keep: `AGENTS.md`, `GEMINI.md`, `.cursorrules`,
    `.github/copilot-instructions.md`, all written by
    `rake docs:agent_contracts` and asserted by `rake lint:agent_contracts`.
44. Every harness file's first line says MASTER is the authority and the file is
    a pointer. A copy of the law is the copy that drifts.
45. A machine-readable summary of the law: `bin/pub4 law --json`, so an agent can
    hold 122 rules without 4,000 lines of YAML in context.
46. `bin/pub4 law <ID>` prints one rule, its fixtures, its exemption and the file
    that owns it — the smallest unit an agent should read before writing.
47. The five traps, in a machine-readable file, so a harness can inject them
    rather than hope the agent read the prose.
48. Every tool prints the exact command that reproduces its number, so an agent
    can verify rather than trust.
49. A `--json` flag on every census and gate. Half have one.
50. The scratchpad convention is written down: where a session puts working
    files, and that nothing there is ever committed.
51. `bin/pub4 worktree` is the documented default for agents, and the hook says
    so when it refuses a cross-tree commit.
52. A short, real worked example per subsystem — `tools/example_scan.rb` is the
    model, and it exists because an agent confabulated three APIs in a row.
53. Every public API an agent is likely to guess has a runnable example beside
    it. The guesses are predictable: `Scanner.new(root:)`, `scan_file`,
    `report.findings`.
54. A single `pub4.yml` manifest naming every tree, its entry point, its test
    command and its gate, so an agent orients in one read.
55. Test names that state the claim rather than the method, throughout. Half the
    suite does this and it is the half that is legible cold.
56. Every ratchet failure message names the file to edit to record a new number.
    Most do; the ones that do not cost ten minutes each.
57. The repo states, once, that measurement beats memory: any number in prose is
    stale, read it from the command. Three files say it; it belongs in the
    generated contract.
58. An agent-facing changelog of *contract* changes only — when a rule, a
    ceiling or a command changed — so a returning agent diffs the law rather
    than the tree.

### E · What a human needs (59–70)

59. `TODO.md` is one file again as of today. Keep it one, and delete a record
    when it closes: 273 lines of closed history came out this afternoon.
60. Every record carries an owner tag — `owner: operator`, `owner: design`,
    `owner: dilla`, `owner: anyone` — so a reader can filter to what is theirs.
61. A record states its measurement and the command that produced it, in the
    first two lines. The good ones do.
62. `bin/pub4 status --backlog` prints the open records touching the files you
    have changed.
63. One page that says what pub4 *is*, for a person who has never seen it, with
    no command in it.
64. `TREE.md` is generated, not written.
65. Every README passes `README_PROSE` — enforced — and says what the folder is
    for in its first sentence.
66. Decision records get an index with one line each; `DECISIONS.md` is long
    enough that its own reader skims.
67. A weekly digest: what moved, what broke, which ceilings fell, generated from
    git and the ratchets rather than written.
68. The Norwegian-first rule is stated once where a newcomer meets it, not only
    in the trap list.
69. Screenshots or a short recording of each surface in its README, since half
    of this repo is visual and none of it is visible from the code.
70. A `HOW_TO_HELP.md` naming five small, real, unblocked tasks at any time.

### F · RAILS (71–82)

71. `shared/` gets a runner that works. `shared/bin/ci` aborts on a missing
    Gemfile, and fourteen of its twenty tests ran nowhere until today.
72. Engine tests run from the app that mounts the engine, in one command, so
    "run the RAILS tests" means all of them.
73. `NO_GOD_CLASS` at 26 is the largest single piece of design debt in the fleet:
    `Conversation` 28 public methods, `User` 27, `Takeaway::Order` 26,
    `BergenDemoSeeder` 834 lines. One decomposition a week closes it in half a
    year.
74. `file_length` and `growth.rails` stop contradicting each other: splitting a
    long file should not fail a file-count ceiling.
75. Every app's `bin/ci` runs the same steps in the same order, and one command
    runs all three.
76. The three apps share one test helper, one factory convention and one
    fixture story. Today they share a `test_defaults` and diverge after it.
77. A per-app finding budget that a person can read on one line, next to the
    app's name in `apps.yml`.
78. `strict_loading` violations get a fixture in the shared suite, since the trap
    is documented and untested.
79. The verticals-as-engines boundary gets one test per engine asserting its
    routes mount and its host constraint resolves.
80. Seeds that a developer can run twice without a foreign-key error.
81. One command boots all four surfaces and tells you which ports they took.
    `bin/triangle up` does this; it belongs in the generated contract.
82. The design tokens are the only source of a colour, a spacing or a font size
    in the fleet, and a gate proves it. Three gates measure fragments of this.

### G · STUDIO (83–90)

83. The twenty-six remaining silent rescues in dilla get their owner's decision:
    each is either a logged failure or a narrowed rescue, and nineteen of them
    are load-bearing for a render.
84. dilla's renders carry their provenance in the file, not beside it, so a take
    survives being moved.
85. `DILLA_OUTPUT_DIR` is the default, not the exception, so no render ever lands
    at the repo root again.
86. A stems render writes under `renders/<seed>/stems/`, which is where the
    gitignore already expects output.
87. One command answers "what did this render use" — seed, engine, sample set,
    master chain — from the file alone.
88. postpro and dilla share one provenance format.
89. The sample crate has a manifest with checksums, so a missing sample is a
    named absence rather than a silent difference.
90. A render is reproducible or says why not, in its own metadata. Today the
    seed does not fully pin it and that fact lives in a memory file.

### H · OPENBSD and the box (91–98)

91. Every `rc.d` script and `/etc` file in the repo is diffed against vm23 by a
    gate, and the drift is a number.
92. A deploy that sheds amber and bsdports is a failure, not a footnote.
93. `vps-deploy` prints the five checks that prove a deploy landed, and runs
    them.
94. The DNS zones, the DS records and the domain expiry dates are one report.
95. Every cron entry on the box is tracked in the repo, and a gate asserts the
    two match — including the PATH, which cost five jobs.
96. A one-line health answer that distinguishes "degraded because unkeyed" from
    "degraded because broken".
97. Backups are proved by a restore, on a schedule, not by the presence of a
    file.
98. The runbook's commands are executable, not prose — a script per procedure,
    with the prose beside it.

### I · The distant shape (99–110)

99. MASTER judges every effect against its constitution — including its own
    edits to the constitution, with the diff attached.
100. The law becomes executable everywhere: every rule in `data/rules.yml` has a
     detector or an explicit "this is a practice, not a detector" flag. 78 of
     228 currently resolve through a fold.
101. One rule population instead of two. `law/` and the registry differ in file
     format and in nothing else that matters to a reader.
102. A rule can be proposed by MASTER itself from a repeated finding, with its
     fixtures generated from the instances it saw.
103. The fix loop learns which fixes were reverted by a human and stops
     proposing them.
104. MASTER reviews a pull request in the same shape it reviews a file, and says
     which rule each comment comes from.
105. The four trees run through MASTER on a schedule, and the report is a diff
     against yesterday rather than a wall of findings.
106. A person can ask "why is this rule here" and get the commit, the incident
     and the measurement that produced it, in one answer.
107. The constitution is small enough to read in one sitting and complete enough
     that nothing outside it governs. Today it is 1,610 lines against a budget
     of 852 and the budget is the honest number.
108. brgen's city network runs on a box that costs what a phone costs, and the
     ratchets are what keep it there.
109. Every number in this repo is either measured on demand or stamped with when
     it was measured. Prose numbers go stale in a day; this file has proved it
     three times.
110. And the one that would have saved this session the most time: **a finding is
     a hypothesis until the instrument has been checked.** It is written at the
     top of this file, it is written in `CLAUDE.md`, and I still spent an hour
     today proving that forty of forty findings were the rule and not the tree.
     Wish 110 is that the tooling makes that check cheaper than skipping it.
