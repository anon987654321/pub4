# Agents

Task-scoped entry for coding agents (Cursor, Codex, Grok, Claude Code). This file is the contract; `README.md` is the tour.

**Start at the repo-root `AGENTS.md` (or your harness pointer, which routes there).**
That is the shared entrypoint; this file is the detailed MASTER contract.
Read `MASTER/data/soul.yml` first. It owns global identity, preservation,
source precedence and `absolute.sacred_paths`. Then read
`MASTER/data/laws.yml`, the canonical catalogue of individual Law identities,
statements, parentage and the nine invariant nodes' internal order.
`MASTER/law/`, `MASTER/data/law_runtime.yml` and `MASTER/checks/` implement
and verify those requirements; `MASTER/lib/review/scan/` is scanner machinery,
not another Law source tree. `CLAUDE.md` is a short bootstrap pointer.

The block below generates the full root `AGENTS.md`. Gemini, GLM and Cursor
entry files are short generated pointers to that one contract. Copilot reads
the root `AGENTS.md` directly; Claude reads the root `CLAUDE.md` pointer. Edit
this block and run `cd MASTER && rake docs:agent_contracts`; `rake
lint:agent_contracts` checks the contract and all pointers. One source,
four generated files, one complete policy copy.

## Task entry and artifact preservation

For every substantive change, state intent, repository-relative scope, mandatory preservation
dimensions and the proof required before editing. The canonical schema is
`MASTER/data/task_contract.yml`; validate programmatic contracts with
`Master::Fix::TaskContract`. Choose the narrowest intent that fits:

| Intent | Allowed change | Preserve |
|---|---|---|
| `content_only` | Requested words or data | Visual identity, layout, structure, assets, behavior, accessibility, public contracts and operator-owned values |
| `content_and_structure` | Content and document/page structure | Visual identity, assets, behavior, accessibility, public contracts and operator-owned values |
| `functional_change` | Behavior inside the agreed scope | Visual identity, layout, accessibility, public contracts outside scope, operator-owned values and data meaning |
| `redesign` | Presentation and layout | Product identity, content meaning, data meaning, accessibility, public contracts and operator-owned values |

Intent is not inferred from a file extension. The validator adds mandatory
preservation dimensions even when the caller omits them. HTML source checks prove
only named source invariants; they do not prove responsive layout, accessibility,
correct interactions or a browser render. Changed DOCX, PDF, XLSX and PPTX files
remain INCONCLUSIVE until a format-aware source check and rendered-output
comparison exist. An unchanged binary may pass exact-byte comparison; a redesign
needs rendered visual and accessibility evidence.

The existing evidence spine is canonical. FixPlan records eligible source hashes,
task scope, Law identity, authority, toolchain and adapter digests. The validated
contract and its digest are carried by the existing RunJournal terminal evidence
alongside the Law × stream × surface assessment. Transactions reject paths outside
the captured scope, including later enlistments. Legacy callers without a contract
remain compatible but must not be described as contract-verified. Missing proof is
NOT_RUN or INCONCLUSIVE, never PASS; a local edit is not a delivered change.

`ruby MASTER/tools/agent_context.rb --json` is the shared machine-readable entrypoint. It
returns the live authority, task-contract schema, Law coverage and a process capability
snapshot. `not_probed` means not tested; permission observations are not successful writes.

## Research and editorial quality

Separate engineering verification from editorial review. A passing suite does not
prove factual accuracy, fairness, accessibility or clarity; polished prose does not
prove software works. Define terms, institutions, populations and time periods.
Source material factual claims and retain publication date, population, method and
limitations. Distinguish verified facts, attributed claims, proposals, inferences
and open questions. Use descriptive headings and links, plain language and
accessible structure. Consider relevant trade-offs, uncertainty, counter-evidence
and affected groups; do not present advocacy as neutral research or false balance
as fairness. Report an unreviewed editorial dimension as INCONCLUSIVE.

Typography follows the surface (operator, 2026-11-06). Output that reaches a
terminal (the CLI, the shell and REPL prompt, the terminal face, dmesg and
log lines) is ASCII: a hyphen, three dots, straight quotes. Web copy, locales,
views and documents use proper marks: the ellipsis …, an en dash in a range
(10–16), curly quotes, and a spaced en dash for an aside (word – aside –
word). Norwegian copy quotes «slik», with ‘enkle’ inside; English uses “double”
curly quotes. EN_DASH_RANGE, TYPOGRAPHIC_EXCELLENCE, PARENTHETICAL_DASH and
QUOTES_BY_LOCALE hold this.


## Local test execution and /fix cleanup

Tests are run by the local Ruby toolchain in the checked-out repository, not by Vercel or another hosted CI service. Use `MASTER/bin/operator test <paths...>` for the smallest complete proof, then `cd MASTER && MASTER_TEST_JOBS=1 bundle exec rake test` for the full MASTER suite. Resolve local runtime and dependency blockers where possible; if a command cannot actually run, record the exact blocker as NOT_RUN or INCONCLUSIVE rather than treating a hosted status, authored test, or static inspection as a pass.

Every `/fix` exit runs `Master::Fix::FinalCleanup`. It releases the current invocation's commit lease, stops its owned visual runtime, removes that invocation's temporary visual captures, prunes only exact-named assessment/architecture artifacts outside the retained journal window, and emits a cleanup receipt. Cleanup warnings must be observable and must not overwrite the repair result. Never treat cleanup as permission to delete source changes, user files, checkpoints, transaction/recovery evidence, the durable audit ledger, or test logs.

## The contract every agent gets

<!-- agent-contract:begin -->
pub4 is governed by MASTER, the primary configuration for every agent
working in this repository. This text is the shared contract. Codex and
Copilot read the root `AGENTS.md` directly; Gemini, GLM and Cursor use short
generated pointers. Claude Code uses the hand-written root `CLAUDE.md`
pointer. The contract is derived from the marked block in `MASTER/AGENTS.md`;
edit the block there, never a generated pointer.

Workflow: one shared checkout; commit straight to `main` with path-scoped
commits; never force-push.

Before planning or acting, load MASTER's canonical context:

1. `MASTER/data/soul.yml` is the highest source of global authority. It owns
   system identity, preservation principles, source precedence and
   `absolute.sacred_paths`. It cannot create individual Law identities or
   restate their requirement statements.
2. `MASTER/data/laws.yml` is the one catalogue of individual Law records and
   their execution policy. It owns Law identities and statements, parent and
   root relationships, the ordered nine invariant nodes, root and severity
   vocabularies, resolutions and declared enforcement contracts. Its reserved
   `law_catalogue` block owns severity, mode, lifecycle, autofix, language,
   surface and path-exclusion metadata for each executable Law. A Law's
   positive path scope is the `path` in its `Law.define`.
3. At the start of every task, run
   `ruby MASTER/tools/agent_context.rb --json` and consume its current
   `conduct`, `blocking_rules`, `coverage`, `task_contract_schema`, and
   `capabilities` fields. This is the live working brief, not a replacement
   for reading the relevant Law records. For unfamiliar, cross-tree or
   repository-wide work, add `--tree` to the same command so the scope is
   grounded in the current checkout.
4. Read the applicable Law row in `laws.yml`. When changing executable
   behaviour or reach, also read that Law's `laws.yml#law_catalogue` entry
   (severity, mode, lifecycle, autofix, languages, surfaces and path_exclude),
   its `Law.define` implementation and `path` and bad/good fixtures (or `proved_by` test),
   plus the focused tests. `law_runtime.yml` is not a source of per-Law policy.
   A declared adapter or fixture does not prove that the detector ran or that
   the product is excellent.
5. Follow this contract and the relevant owning tree/product contract. Task
   routing, preservation dimensions, minimum proof and editorial review are
   defined here so agents do not need a second navigation guide.

Read the relevant source, tests, and local documentation for the requested
work. Never substitute remembered instructions, summaries, or assumptions
for the live files.

Source authority:
`soul.yml > laws.yml > executable laws and gates > tree contracts > Git history`.
Soul is highest for global identity, preservation,
source order and protected paths. The Law catalogue is authoritative for
individual Law identities and statements; its nine invariant nodes order Laws
internally. Git history is provenance, never an override of a live source.

`MASTER/lib/soul.rb` reads the source hierarchy and protected-path list from
`soul.yml`, and derives the nine-node Law order from `laws.yml`; it does not
author a competing graph. The executable Law Ruby in `MASTER/law/*.rb` holds
the definitions and adapters. `MASTER/data/laws.yml#law_catalogue` owns per-Law execution
policy; `MASTER/data/law_runtime.yml` holds scanner, veto, plugin and `/fix`
runtime configuration. `MASTER/checks/` routes operational checks. These are
enforcement instruments, not alternate sources of Law identity. Automatic
resolutions require proof fixtures.

One Law system: every Law is one catalogue entry and one `Law.define`, and
its detector is a `detect` regex, a `check` block, or a detector class in
one flat `MASTER/law/`. No compatibility directory or alias covers retired
Law paths. Every Law carries one canonical catalogue entry, a traceable Ruby
detector or an explicit semantic or visual evaluator, and coverage across
lexical, semantic, and visual review.

A Law names the requirement; a detector or assessment names the instrument;
proof is evidence. A declaration, an implementation, a passing test, and an
excellent product are four different claims. A missing or unrun measurement
is INCONCLUSIVE, never PASS. No count of declared Laws, files, tests, or
detectors proves the code correct, the design usable, or the system can
support a stated scale.

For every Law-affecting task, inspect its normative row in `laws.yml` and its
`laws.yml#law_catalogue` metadata when execution policy or reach is involved,
then inspect the exact `Law.define`, bad/good fixtures or `proved_by` test.
Verify identity, parent/root, severity, lifecycle, autofix, language, surface
and path reach (`Law.define` `path`, catalogue `path_exclude`), plus actual
execution evidence. Read `law_runtime.yml` only
when the task changes scanner, veto, plugin or `/fix` runtime configuration.
Never claim a Law is enforced because its name or detector is merely declared.

`MASTER/docs/synonyms.yml` is glossary-only. `MASTER/checks/checks.yml`
routes operational checks. Neither creates Law identities or normative
policy, and neither overrides the constitution. The four owners are MASTER/
(runtime, `MASTER/bin/master`), RAILS/ (apps, `MASTER/bin/operator` triangle
up), OPENBSD/ (deployment and vm23), and STUDIO/ (Dilla, photograph,
Replicate). `MASTER/tools/` keeps compatibility entrypoints for STUDIO tools.

`laws.yml#law_catalogue` is the single source for per-Law severity, mode,
lifecycle, autofix, language, surface and path exclusion. The catalogue retired
positive path scopes (a40d93e579); each scoped Law declares the files it
judges with `path` in its `Law.define`, and preflight refuses a catalogue
`path` or `path_pattern` that nothing would read. `Law::Definition`,
`LawCataloguePreflight`, `LawRegistryAudit` and `BootReceipt` all read that
same block. `law_runtime.yml` no longer contains a Law catalogue; it retains
scanner, veto, plugin and `/fix` runtime configuration. Its guard rejects any
attempt to add a duplicate `law_catalogue` there. Do not move per-Law policy
back into runtime configuration or infer it from a detector's other Ruby.

Task entry: before a substantive edit, state intent, repository-relative
scope, mandatory preservation dimensions, and proof. Validate programmatic
contracts with `Master::Fix::TaskContract`; the schema lives in
`MASTER/data/task_contract.yml`. `not_probed` marks an operation that no
run has exercised; permission observations do not prove a successful write.


**Existing-first structure is the default.** Extend the nearest existing owner
and its existing tests before adding a tracked path. A new file is justified
only by a distinct responsibility, public boundary, framework/deployment
requirement or independently maintained artifact that cannot reasonably live
in an existing owner. Declare its exact repository-relative path and a concrete
reason in `TaskContract.new_paths`; it must also lie inside the task scope.
A new directory is justified only when that declared file needs a genuine
ownership boundary. Keep additions to the minimum required. Do not split a
method/class, add a helper, create a separate test/fixture, documentation or
configuration file, or make a utility directory merely for convenience. Use
existing README, test, config, asset, tool and namespace locations first.
Report added/removed files and directories in the delivery summary.



Task routing and minimum proof:

- **MASTER behavior or Laws:** read the owning Law, implementation and callers;
  run focused tests, changed-line Law assessment and the relevant suite.
- **Task intent or preservation:** read `MASTER/data/task_contract.yml` and
  `Master::Fix::TaskContract`; verify scope, required preservation and evidence.
- **HTML or interface work:** inspect the owning renderer, styles, interactions
  and contract; prove source changes plus desktop/mobile renders, keyboard and
  accessibility behavior as applicable.
- **Rails behavior:** trace the owning app/engine, shared dependencies, routes,
  models, controllers, views and tests; run relevant app and browser proof.
- **Deployment:** read the OpenBSD contract and runbook; require actual host
  output, health checks and backup/recovery evidence.
- **STUDIO media:** use the owning project README, manifest and renderer; verify
  reproducible output, seed/version and alignment while retaining the prior take.
- **DOCX, PDF, XLSX or PPTX:** compare source and rendered pages, sheets or slides;
  parsing alone is not visual preservation.
- **Research/editorial work:** establish provenance, separate facts from claims
  and inferences, source material claims, and report editorial review separately.
- **Generated documents:** edit the owning generator/source and prove generated
  output matches it.

**Do the work now.** A clearly authorised request is an instruction to execute,
not an invitation to produce another plan. Finish every independent, in-scope
step available with the current tools, including repairs, proof and delivery.
Do not add TODOs or promise later work for a task that can be completed now.
Leave only a precisely named remainder that genuinely needs an unavailable
credential, device, human decision, external consent, remote authority or
unmet dependency; complete the independent work while that remainder is blocked.
Break the dead thing. Do not break the user's trust.

Shell commands obey the shell Laws in `laws.yml`. The runtime compatibility
registry may still carry older command metadata; it does not override the
normative Law statements. The tree contracts for RAILS, MASTER/web, and
OPENBSD live in `TREE_CONTRACTS.md` at the repo root; for STUDIO work,
follow the project README and source-level contracts. Scoped documents
never replace MASTER. On conflict, follow MASTER and name the stale or
contradictory file instead of working around it in silence.

The HTML preservation guard proves source-level invariants only. It does
not replace rendered, browser, viewport, keyboard, or accessibility
evidence.
<!-- agent-contract:end -->

## Working alone in this repo

An agent arrives with none of the session context that makes the tree
navigable, so these are the facts that are not deducible from the code and
that a fresh agent gets wrong on its first attempt.

**Ruby is pinned by `MASTER/.ruby-version` for development.** It is currently 4.0.5. On OpenBSD, `MASTER/bin/ruby` accepts the packaged Ruby 3.3.x/3.4.x lane instead of requiring 4.0.5; bare `ruby` is not the project contract.

**The checkout is shared and usually dirty.** Never `git add -A` or
`git commit -a`, and take no worktree or branch: every session writes to
`main` in this one checkout. Commit path-scoped with `git commit -- <paths>`.

**Never read-modify-write a file another session may hold.** Read, edit and
write are three moments; a commit landing between the read and the write can be
silently reverted by your write. Keep that gap short. Use
`bin/operator land -m <msg> <paths...>` to check, commit path-scoped changes and
push; never force-push.

**Verify the instrument before the finding.** Measurement code here is wrong
about the code more often than the code is wrong about the world. Check a probe
against a case whose answer is already known before believing what it reports,
and never report a check as done without its output.

**A census has more than one end, and the tree has four.** A gem is used by the
gems that require it in `Gemfile.lock` as well as by code: `tty-prompt` needs
`tty-reader`, which needs `wisper`. Every bus topic has a consumer while the
face is open, because `MASTER/web/app/controllers/events_controller.rb` subscribes
`"**"`; published and never
subscribed is all noise, and only subscribed and never published is worth
reading. An env var set by nobody in `MASTER/` may be set in `RAILS/` or
`OPENBSD/`. And before recording an orphan, ask what it is a second copy of —
that question, not "who calls it", is what has actually paid for deletions.

**Read a ratchet once, after the tree stops moving.**
`bin/operator measure` in the shared checkout counts other sessions'
uncommitted edits, `test_no_ratchet_is_slack` skips whenever a measured tree is
dirty, and a low recorded mid-session locks in a state that was not clean. Read
the live figures from the command; a number quoted in prose is stale within a
day.

**Comments state the present-tense reason.** Dates and "used to be" belong in
git — `NO_CHANGELOG_COMMENT` in `law/universal.rb` enforces it.

**The RAILS apps default to Norwegian.** Assert through I18n keys, never
English literals; a hardcoded English string is a defect, not a placeholder.

**Renders are replaceable.** dilla and photograph write output that a new run
may delete and replace. Never change a rendered-sound or graded-look default on
your own judgement.

**Scanner findings are hashes with a path, not Finding objects.**
`Scanner#findings(paths)` is the flat API. `scan_dir` returns Result wrapping
`[path, Result]` pairs whose inner values are hashes: `h[:rule]` works,
`f.rule` raises. `tools/example_scan.rb` is the worked example.

**`bundler/setup` rewrites Gemfile.lock.** A mtime-keyed cache built around
the lock is poisoned on every boot, even when the resolution is unchanged.
`BUNDLE_FROZEN=true` is what the daemon uses.

**A class in a multi-class rule file is invisible to Zeitwerk until the
file loads.** `Rules::AstOmissionRule` raises NameError cold. `require
"review/scan/rule_dsl"` is the load that defines them.

**A council pass looks exactly like a hang.** On a dev Mac the provider is the
`claude` CLI, which buffers when stdout is not a TTY, so `/fix --dry-run --critique master` sits
at 0% CPU with an empty pipe for up to sixteen minutes while personas think.
Count the `claude --print` subprocesses in `ps` before killing it.

**A check that passes bare and fails under `bin/check` is an environment leak.**
`bin/check` runs rake under `bundle exec`, and a child that inherits MASTER's
bundle cannot load STUDIO's gems. Wrap the child in
`Bundler.with_unbundled_env`; a hand-kept list of bundler variables is wrong on
every release that adds one.

**`\b` beside punctuation matches less than it reads.** A trailing `\b` after
`?` needs a word character next to it, so `/\bis_a\?\b/` misses `is_a?(Foo)`. It has
disabled a rule clause and hidden callers from a dead-file census.

**A bare top-level `ROOT` is safe only in its own process.** Two files that
each define one, loaded together, warn once and let the second win, and the
loser reads the wrong tree without complaint. Name it for the script
(`SWEEP_ROOT`, `INVENTORY_ROOT`) the day a script becomes requirable.
`rake lint:constant_collisions` follows `require_relative` only.

**The three Law-id counts answer three questions.** The scanner's `@rules`
(147) is what weights anything; a `Rule.registry` walk drops bridge classes; a
regex over `law/` and the rules files (what `tools/audit/law_hygiene.rb` uses) counts
more. An unreached-file sweep must include the repo-root `bin/` and filter by no
extension — `test/test_entrypoint_requires.rb` holds the case that broke
`bin/operator` for six days.

## Judging your own work

The task as given is the deliverable, but it is not the whole job. Reason about
what the change is actually for, and say what you find.

A finding is a hypothesis. Several backlog entries were stale within a day
of being written — the price-drop alerts, the takeaway push and three map layers
were all built while the file still called them open. Re-measure before working
from one, and prefer a small measurement over a long argument.

If the task as specified is wrong, or rests on a premise the tree contradicts,
say so in a sentence or two and then deliver the rest under a stated assumption.
Do not silently narrow the scope, and do not stop with nothing delivered because
one part was doubtful. Scaling the work down is the operator's call.

Report what happened rather than what was hoped for. If a check was skipped, say
which. If a check reported a pass having measured nothing — several here do when
the triangle is down — that is not a pass, and calling it one is worse than
failing.

A check certifies what it did not measure in seven ways, and each turns the
absence of a property into evidence of it:

1. **A comment outlives its rule.** A check that greps source strips comments
   first, with the pattern chosen by extension; a `/*` stripper run over Ruby
   eats `"etc/rc.d/*"`, and an assertion that reads comments teaches the next
   author to delete the explanation.
2. **An exemption outlives its subject.** Check each allow-list entry against the
   tree, as `rake lint:autoload` does.
3. **A build artifact outlives its source.** When behaviour contradicts source,
   diff what is served against the file it claims to be; Rack::Static serves a
   stale `public/assets` ahead of propshaft.
4. **A staleness alarm is silenced by regenerating.** Before running
   `assets:precompile` to clear a drift message, ask what the drift is evidence
   of.
5. **A test punishes the improvement it watches for.** Assert the invariant
   (`refute_empty findings`), never the instance (`ratio < threshold`).
6. **A writer reports an edit it did not make.** Read back what was written; in
   YAML the indentation is the syntax, and a census that cannot parse a file
   reports it clean.
7. **A root constant resolves one level too high.** A fallback that ends in "use
   the last candidate anyway" is not a fallback; assert what the root holds.

So a new check's first run is against a known-bad input, since a green first run
is equally consistent with nothing measured. Registration is not execution: a
check listed in `checks.yml` with no class-level `.run` never ran. A check reads the
source of truth rather than restating it, and a test that turns green while
asserting only what every subclass inherits is worse than one that errors,
because it reads as coverage.

## When it goes wrong

Nothing in this repo is so urgent that it is worth destroying someone else's
work, and the failure modes below have all actually happened.

**Before anything destructive, keep the bytes.** Copy the file somewhere outside
the tree first. A hash proves a change occurred; only the bytes let you put it
back.

**If you overwrote another session's work**, their commits are safe on
`origin/main` — the damage is only in the working tree. `git checkout -- <path>`
restores from HEAD. Say what you did rather than hoping it is unnoticed.

**A script that rewrites files by splice must prove every splice.** The first
version of the campaign's rewriter computed offsets against a stale copy, and
every splice after the first landed at shifted positions — silently corrupting
files that had looked verified a line earlier. It was caught because the
rewriter re-read and compared, not because anything downstream did. The rule:
re-read the current bytes immediately before each write; after writing, confirm
the file parses (YAML/Ruby/JSON as its suffix demands) and that every line
outside the splice is byte-identical to what was there; one write per
verification round. A rewriter that cannot do all three edits one file at a
time by hand instead.

**Never a tree-wide `git checkout -- .` inside a batch.** It ran once between
two batches of a campaign and erased a validated, uncommitted batch whole —
no diff, no recovery, the work simply gone. Destructive restores are for a
single named path, run deliberately, after the bytes have been copied
somewhere outside the tree. If a batch has gone wrong past fixing, stop and
report what was lost; do not compound it with a second discard.

**Before any push**, `git log --oneline origin/main..HEAD`. A push publishes
every commit beneath yours, including other people's. Name in your report what
went with you.

**One verb that writes.** `/fix [path]` is the convergence lifecycle: it reads
the path, lets the council argue about what it found, weighs competing repairs,
applies the strongest, validates it and reads the path again, until the tree
converges, stops improving, or reaches a state MASTER may not settle alone. A
run ends as DONE, PLATEAU, BLOCKED or VALIDATION_FAILED, and only DONE claims
the work is finished. `/fix --dry-run --critique` reads and argues without writing.
`/scan` is the detector-only observation surface; `/fix` adds repair and verification.

**That means a fix mutates the tree** — it has broken dilla and MASTER's own
chat path. `--no-autofix` and `--dry-run` hold it back. Read the printed diff
before committing, and never commit rewrites of generated caches: the scanner
descends into them.

The deterministic autofix stage, which runs before any model is asked, answers
to `Fix::AutofixGuard`. It never opens a protected path: Soul declares
`data/laws.yml`, `data/soul.yml`, `data/project_context.yml`,
`lib/soul.rb`, `lib/ground/pledge.rb` and `bin/master`. Other
`lib/cli/face/`, voice/TTS, `STUDIO/dilla/`, `STUDIO/postpro/` and golden
fixture paths have their own tree or artifact contracts; they are not silently
added to the constitutional sacred-path list. It parses every
candidate (Ruby, YAML, JSON) and never applies an edit to a data file that only
moves whitespace. After a write it runs the file's own `test_<name>.rb` when one
exists and puts the original bytes back if that test goes red. RuboCop's
correction of a nested ternary is off, because it rewrote one into an unindented
`if` and broke the ASCII face's golden frame. A run changes at most fifteen
files (`MASTER_AUTOFIX_MAX_FILES`); the rest are named in the pass summary.
`--autofix=off|dry|on` sets the mode (`MASTER_AUTOFIX_MODE` is the default): off
writes nothing, dry writes the diff to `.master/autofix-<time>.patch` and leaves
every file as it was.

The model phase is bounded the same way. Before the first file it sends each
live lane one tiny request (`Fix::LaneProbe`, 20 s, `MASTER_FIX_PROBE_S`;
`MASTER_FIX_PROBE=0` skips it) and drops any lane that errors or answers late
for the rest of the run. Each file gets 240 s of model time
(`MASTER_FIX_FILE_BUDGET_S`); a file that spends it is skipped and named in the
summary, and a lane that fails twice is dropped for the run. A repair sends the
failing finding with forty lines around it and asks for a minimal unified diff;
a proposal that changes lines more than twenty-five from every finding is
refused before the verifier is asked, and a file stops after two rejected
proposals. The pass summary prints the rejects by reason. Without a file cap,
`/fix` scans the complete eligible corpus, then queues files by highest finding
severity, weighted finding impact, and stable path before any streamed repair
starts. `--max-files=N` (or `MASTER_FIX_MAX_FILES`) is an explicit bounded lane
that may stop during inventory and take the first N files; set
`MASTER_FIX_RANK=1` to scan the complete eligible corpus before selecting the
highest-impact N instead. `Fix::RunLedger` holds this state.

A run says where it is and stops when it is going nowhere. Every minute it prints
`fix0 phase=<name> fixed=a failed=b rejected=c lane=<id> elapsed=s`, a line a
script can split on spaces and equals signs; the longer human line prints every
half minute as before. A pass is reported stalled when no file finished (fixed,
failed or rejected) in five minutes, and a sustained non-advisory stall ends the
run rather than waiting on a silent provider. `MASTER_FIX_ABORT_ON_STALL=0` may
request report-only behavior from explicit callers, but does not disable hard
stall, disk-pressure or protected-path safety stops. Every five minutes it also
compares `git diff --name-only` with the start of the run and ends the run if a protected path
appeared. On exit, normal or not, it prints one summary: the exit reason, the
counts, the autofix and reject accounts, and a self-check naming any protected
path the run changed. `bin/fix-here` stops a run that prints the no-yield line.

**A red check that names no finding is usually a check that cannot load.**
`rails_runtime` failed at `require` time for months and read as a normal
failure. Check the check before chasing its verdict.

**When you cannot verify, stop and say so.** An unverified claim costs more than
an unfinished task, because the next reader builds on it.

## The words that mean something specific here

Not general vocabulary. Each of these means one thing in this tree and something
else everywhere else, and each has a file behind it, so a claim about one can be
checked rather than believed.

**Law** is the one vocabulary for a governing constraint in this tree. A Law may be
declarative, executable, semantic, structural, or advisory, but it is still one
concept and one identity. Do not introduce Rule, Principle, Axiom, Guideline,
Doctrine, Heuristic, Standard or Norm as alternate names for a Law.

**Conduct** is what `Law.conduct` does to a law file before laws judge `law/`.
A law necessarily contains the pattern it forbids — in its detector, its fix
line and its bad fixture — so those are blanked, newlines kept, and the file is
read as declaration rather than as the thing it declares.

**Twin.** One Law id implemented in two places. Every silent drift the
2026-08-21 campaign found was a twin: two implementations under one name, one of
them quietly wrong. Retiring a twin means deleting the copy and leaving a note
where it stood.

**Intentional marker.** A line carrying `scan: intentional` opts that line out
of every Law and every scanner adapter that scans through the Law scan surface,
and must carry the reason beside it. It is the sanctioned way to
say "this finding is correct and the code is right anyway". A marker that
suppresses nothing is worse than none: it is a standing exemption for whatever
real finding lands on that line next.

**The fold** and **the spine** are `lib/core/` — the small set of files the
runtime is built out of, where a new top-level concept is a design change rather
than a line-count question. `data/spine.yml` holds both invariants, and
`rake lint:spine` fails when either moves.

**Ratchet** and **census**. A *census* counts a property over the tree —
duplicate files, unread data keys, findings, readers per file. A *ratchet* is a
census with a recorded ceiling that only ever falls, so the next regression
cannot arrive silently. Every census here records its members beside the count,
because a ceiling that says "over by two" and cannot name the two leaves the
next reader deriving the pair by hand.

**Inconclusive** is the third check state, and the one that matters. A check that
could not measure — no Chrome, no booted app, no deploy stamps — is neither a
pass nor a failure, and reporting it as a pass is the worst failure this suite
has: it claims the code was reviewed when nothing was read. In-process checks say
it with `CheckResult#inconclusive!`, subprocesses with exit 3.

**Verdict.** What the constitution answers a proposed effect with, and there are
four: `Block` refuses with a reason, `Request` stops to ask a person, `Revise`
hands back an amended effect, `Allow` applies it against a checkpoint. Nothing
touches disk on any other path.

**Tier.** Two meanings, both live. `bin/check --ladder` runs a *lexical* tier (law and the
scan registry, deterministic, no model) and a *semantic* tier (the critique
stage, `/fix --dry-run --critique --only critique`, which reaches a provider); the semantic one is
currently unreachable
and reports as skipped rather than clean. On a `laws.yml` row, `tier:` is the
Law's category — `clean_code`, `style`, `safety` — and is what resolves a
conflict between two Laws firing on one line.

**The triangle** is `MASTER/bin/operator triangle`: brgen, amber, bsdports and the MASTER
face, booted locally on the ports every check probes. Without it the live half of
the suite passes having measured nothing.

**Vertical.** One of brgen's mounted Rails engines — `RAILS/brgen_* packages/`
holds tv, dating, takeaway, playlist, marketplace and maps. Each is a named app on its own subdomain, not a section
of brgen, and "brgen" alone means the main city app only.

**The face** is MASTER's WebGL front end at `ai.brgen.no`. Its runtime is
generated: `web/public/face.part*.txt` are the sources and
`MASTER/web/public/face.runtime.js` is the build, which says in its own first line not
to edit it by hand. Editing the build is a fix that survives until the next
`assets:build_face_runtime` and then vanishes.

## Pick your topic

| Task | Read |
|------|------|
| Face boot / WebGL / primer | `data/agent_map.yml` → `topics.face_boot` |
| TTS / speech / visemes | `topics.tts` |
| Deploy / VPS / rc.d | `topics.deploy` |
| Persona / voice policy | `topics.persona` |
| Law / scanners / loop | `data/laws.yml` is the canonical catalogue; `law/` and `lib/review/scan/` implement enforcement. Run `LawRegistryAudit`; do not infer full coverage from one file or registry count. |
| Extend runtime behavior | `data/spine.yml` header and `test/test_core_no_lib_backedges.rb`. New ability in the fold = one Effect verb in `lib/core/world.rb`; new constraint = one rule in `lib/core/constitution.rb`; anything else is ordinary `lib/` and must not grow it (`rake lint:spine`) |
| Worn type / layout checks | `data/laws.yml` `design_rules.worn_type` + `MASTER/checks/support/geometry_type.rb`. Feed is a short measure; legal/prose is 66ch. |
| brgen city network / verticals | `RAILS/brgen/AGENTS.md` — one process, city apex + subdomain engines |

Touch-map: `data/agent_map.yml`. Law sections live in `data/laws.yml`. Work is a sentence, or `/fix [path]`. Slash set: `/fix` `/status` `/undo` `/commit` `/model` `/android` `/ios` `/doctor` `/help` `/clear`.

## Checks

Run the smallest proof: `bin/check` for ordinary code, `bin/check --profile=agent` for law, scanners and the loop, `bin/check --profile=web` for the face, `OPENBSD/bin/check-rails --profile=contributor` for deploy and Rails, and `MASTER/bin/operator check` for the whole ladder. On failure: `bin/check --profile=agent --format=brief`.

`--profile=agent` may fail on known debt tagged `agent-ignore`.
Do not chase scan noise on unrelated patches.

## Do Not Touch

Every entry names the check that fails when its claim stops being true, or says
why no check can hold it. This is not decoration: item 2 of this list used to be
"rule data stays split, because each shard sits near its consumers", and that
reason had been false since the day the shards were created — the four of them
had one consumer between them. A conclusion does not rot loudly. A test does.
`rake lint:do_not_touch` checks that every entry below carries one and that the
checks it names exist.

1. `lib/core.rb` and `lib/core/` are the fold spine, and they must not require
   the rest of `lib/`. The two-spine *directory* split ended 2026-08-12
   (the record of it went with `docs/`); the dependency direction it was
   protecting did not, and is now a test rather than a folder boundary. `core_files: 7` in
   `data/spine.yml` makes a new concept a design decision — raised from 6 on
   2026-08-12 for `Proof`, the first raise since the spine was written. — check:
   `test/test_core_no_lib_backedges.rb`, `rake lint:spine`
2. `knowledge/` is local-only — do not commit without updating
   `SearchKnowledge`. — check: `rake security_sweep`
3. WebGL / face boot stays deferred until primer tap. — check: `rake
   test:web_ui`, `test/test_web_ui.rb`
4. `RAILS/apps.horizon.yml` is agent-ignore horizon — do not implement
   unprompted. — no check: a horizon file is a list of things deliberately not
   built, so there is no artefact to assert on; the failure mode is an agent
   building one, which only a reader of the diff can catch.
5. VPS: one app CI/deploy at a time on vm23. — no check: concurrency on a remote
   host, enforced by the deploy lock on vm23 rather than by anything in this
   repo; a local check would assert against state it cannot see.
6. Secrets in `/etc/*.env` on VPS — never commit keys or generated assets. —
   check: `rake security_sweep`, `RAILS/test/tracked_secrets_test.rb`
7. After `git pull` on vm23, run `vps-deploy` before expecting live health. — no
   check: an ordering rule for two commands run on the VPS; nothing in the repo
   observes whether the box was deployed after its last pull.
8. Feature truth: `RAILS/apps.yml`; operator-only work: `MASTER/data/operator_seams.yml`. —
   check: `MASTER/checks/lib/source/apps_yml.rb`
9. Never autonomously run `vmctl console/stop/start` or kill `cu` on server4 —
   see `OPENBSD/RUNBOOK.md`. — no check: a prohibition on an action, not a
   property of the tree; the guard is the human-only env var in item 11.
10. Production VM is vm23 only (`dev@brgen.no`). — no check: a deployment fact
    about the world; the repo cannot assert which host is production, only which
    one its scripts name.
11. `I_UNDERSTAND_CONSOLE_RISK=1` and `I_UNDERSTAND_DNS_WIPE=1` are human-only
    checks. — check: `OPENBSD/checks/vps_safety_check.rb`
12. Dmesg every file op — see `OPENBSD/RUNBOOK.md`. — no check: a habit for the
    operator's own audit trail, checkable only against a session transcript,
    which is not an artefact this repo keeps.

One checkout, written straight to `main`, as the refusal of parallel change
streams below says. Never use `git commit -a` in a shared checkout; keep commits
path-scoped. `bin/operator land -m <message> <paths...>` runs the repository
checks, commits the named paths and pushes.

## Patch closeout

Match the contract examples closing `README.md`: what changed, exact checks run, known debt called out explicitly.

## Refused, and why

Standing refusals with no line of code to sit beside. Each was argued against
the tree once; reopen one only with the measurement or the consumer it names. A
reason tied to code lives as a comment on that code, and OPENBSD's refusals are
in `OPENBSD/CLAUDE.md`.

- **No covert room listening, and no verdicts on people.** MASTER does not listen to a
  room in the background, keep a rolling recording, or analyse speech it was not handed.
  `Cognition::DiscourseObserver` reads a transcript the operator supplies, points at
  catalogued wording with its span, the evidence against it and other explanations, caps
  its confidence at what wording alone can show, and appends every call to an audit
  trail. It never says what anyone intends or is. Capture, when it exists, goes through
  the `microphone` and `speech_recognition` grants in the personal ledger, shows its
  state while open, and covers only conversations the operator takes part in: recording
  others who do not know is a crime in Norway and no grant from the operator cures it.
  Reopen only with an adapter that enforces all of that and a test that fails without it.
- **No serif typefaces.** The operator's no-serif directive stands for brgen, amber and
  master. Instrument Serif, IBM Plex Serif and Source Serif 4, with their
  `ibm_plex_editorial` and `source_editorial` pairings, stay out of the token set;
  reopen only for a named surface that cannot read in the one sans and mono.
- **No third surface.** MASTER is `bin/master` and the face. A product surface
  born in an agent session, a desktop or companion app, or an editor extension
  restates one of the two and drifts from it; a new public app waits on the
  refusal of the same kind in `OPENBSD/CLAUDE.md`.
- **No external agent protocol.** No ACP stdio mode, A2A, OpenAI-compatible
  `/v1`, another harness behind `Io::Exec`, models.dev scrape or npm SDK. Each
  makes MASTER a backend to someone else's policy, which the constitution
  forbids; channel models and target URIs serve surfaces MASTER does not have.
- **No TUI.** A full-screen interface is a second presenter for one event
  stream. The CLI stays a dmesg-style line printer, terse and Unix-like in
  OpenBSD dmesg's shape with Bringhurst's economy, and the face is the rich
  surface.
- **No browser verification by the agent.** Driving a browser to confirm its
  own clicks is a computer-use driver, and so are screenshot and VNC workers.
  Rendered pages are measured by the checks over CDP, on the deploy host.
- **No parallel change streams.** One checkout, written straight to main: no
  worktree, branch or PR, and the fix loop commits only the paths its own pass
  changed. Docker, Modal and Daytona
  backends, a worker fleet and an agent process table answer a question one
  OpenBSD host does not ask. A session writable set seeded from git-dirty paths
  inverts in a shared checkout, admitting the files other sessions hold; the
  fold's `new_path_ask` scopes writes to what the turn has read instead.
- **No unreviewed self-modification.** `data/soul.yml` and `data/laws.yml`
  are operator-owned, sacred to autonomous writers and repair loops. A human
  may edit them deliberately and commit the validated change. Do not route
  edits to these files through `/fix` or an automatic writer. Validate the
  Soul schema/source hierarchy and Law catalogue invariants, preserve existing
  protected paths, prove Law-catalogue reconciliation, and run the relevant
  checks before a human commits the result.
- **One Law catalogue, with separate runtime configuration.**
  `data/laws.yml` owns individual Law identities and statements; its reserved
  `law_catalogue` block also owns executable severity, mode, lifecycle, autofix,
  languages, surfaces and path exclusion. `Law::Definition`, preflight, registry
  audit and boot receipts consume this same source; a Law's positive path
  scope is its `Law.define` `path`. `data/law_runtime.yml` keeps
  scanner, veto, plugin and `/fix` runtime configuration, and its guard refuses
  a second `law_catalogue`. Read the Law row and its catalogue entry together;
  do not infer reach from runtime configuration. Missing evidence
  stays INCONCLUSIVE.
- **No second record beside memory.** A belief store of verified, inferred and
  contradicted facts, an execution-context object and a durable notification
  queue each copy what memory, fiber locals and `StandingOrders` already hold.
  MASTER's sixteen tools need no lazy schemas or tool search.
- **No search or debate wrapped around FixLoop.** MCTS or a debate of three
  models adds calls to a loop whose value agent is already the council.
- **No golden traces or golden renders.** A model call's output and timing, and
  a dilla render, are not deterministic to the byte, so a golden file fails on
  noise or overwrites a take. A/B is interleaved listening.
- **No telemetry, score or check without a reader.** The face's audio clock
  closes the gap a TTS state enum, a timestamped event stream or a sync budget
  measures, and frame-time, thermal and soak data have no consumer. dilla's
  `TIMBRAL_FIT`-style scores, research ledgers and NaN checks on delivered PCM
  fall the same way: `MixScore` takes targets from takes kept after listening,
  never from a threshold picked in advance. The face's look and dilla's sound
  are the operator's.
- **Nothing restored from `master.yml@30dad7ead` because the fossil declared it.** The
  2026-09-16 `codify-master-gaps` patch added `analysis_depth` (practical /
  analytical / extreme, with depth limits and time budgets) and
  `version_control` (`message_format: "v{version}: {change_summary}
  [violations={before}→{after}]"`) to `data/laws.yml` from
  `master.yml@30dad7ead`. Nothing in the tree names a depth of analysis, so the
  first block is a declaration with no reader in a file that is `paths.immutable`;
  the second contradicts the convention every commit here follows, which is a
  capitalised sentence after `Master:`. A fossil is evidence of what was once
  meant, not a reason to declare it again.
- **No native extension and no second language.** tree-sitter, Herb,
  `tiktoken_ruby` and a Python compressor each put a toolchain beside a
  pure-Ruby runtime that deploys to OpenBSD; Prism is in the stdlib. tree-sitter
  reopens only as an operator decision about what MASTER is, Herb when Rails
  ships it as its ERB implementation.
- **No detector, index or corpus without a subject.** `LAYER_CAKE` finds nothing
  at three links and aliases at two; `DEAD_ABSTRACTION`'s module half measures
  Zeitwerk's file mapping and its class half finds nothing. A cross-file symbol
  index, more visibility, metaprogramming or Liskov corpora, and a
  clone-to-extract-method autofix wait for a finding in hand.
- **No performance machinery ahead of a measured slowness.** No benchmark,
  profile or hotpath commands, scan cache, per-detector budget, verdict cache or
  concurrent checks. An optimisation lands with its instrument in the commit, the
  number before and after, and a check that the output did not change; a cache
  keys facts by what invalidates them, never verdicts.
- **No audit without a path.** An intake item names a file, a caller or a
  measurement; a repo-wide audit prompt closes as a class, because the
  instruments it asks for exist. Mutation campaigns over whole directories,
  skip-count dashboards, an architecture graph with expiring exceptions and
  rules about the shape of backlog entries are the same request.
- **No writer for a reader that does not exist.** SARIF output waits for a
  consumer outside pub4, and taint tracking waits for a planner that never reads
  untrusted text; `InjectionGuard` and the Governor are the defences that run.
  `/forget` has no tombstone to write, because no index keys a memory by
  session.
- **No anchors inside `laws:`.** Every Law in `data/laws.yml` reads whole where it sits,
because agents read the Law one identity at a time. Reopen with a duplicate body, not a line count.
- **No synonym beside an established concept.** Law is the word; alternate names such as
  rule, axiom, principle, guideline, doctrine, heuristic, standard and norm are not
  introduced for it. `Ground::Policy` is authorisation, a different concept.
  Whether `check`, `lint`, `probe`, `audit` and `verify` name one act is
  unmeasured.
- **No documentation outside its boundary.** Human documentation is one
  `README.md` per boundary; Aegis, cognition and the contract examples live in
  `README.md`, and the Do Not Touch list lives here. `MASTER/docs/` holds only
  the execution-contract references, the generated Law digest, the glossary and
  preserved handoffs that `test/test_doc_paths.rb` names one by one; a new file
  there needs its entry in that test.
- **Media generation lives behind STUDIO.** Dilla, photograph and replicate
  are tool boundaries under `STUDIO/` (postpro and lora are retired, trees and
  entrypoints alike); `MASTER/tools/` keeps entrypoints, and `lib/core/world.rb`
  routes to them instead of owning their provider or media logic.
- **No unmeasured gem.** The ruby_llm satellites stay out: `-schema` is
  deprecated in favour of a Hash, and `-resilience`, `-top_secret`, `-agents`,
  `-team` and `-template` are thinner than what MASTER owns. `-test`,
  `-evaluations` and `-tribunal` are lock entries, changed only on the box, one
  at a time, against a named test they replace.
- **No RAILS stack import.** No Kamal, Thruster, Dockerfile, Inertia, Vite,
  ViewComponent, Lookbook, Cucumber, Percy, Chromatic, Playwright or
  capybara-screenshot-diff: deploy is rc.d and relayd, the frontend is
  importmaps, ERB, Stimulus and Turbo, and `visual_contract` and
  `layout_snapshot` are the one paint and one layout baseline. No Chart.js,
  Google Places, Pickr, scroll-to, timeago, content-loader or glow, each a third
  renderer, a third party on a Norwegian city app, or an effect `FLAT_UI`
  forbids. No two-tower feed, neural outfit model or pgvector ranking on a 1 GB
  SQLite box; the portable result is a SQL union in `RAILS/apps.horizon.yml`.
- **No look taken from a book.** Books are read for detectors. Parametricism,
  an Itten palette, a second type scale, Pallasmaa as texture and a swing retune
  each change a rendered value, which is the operator's; Venturi argues against
  Rams and Ando, who are already law. A book imported as YAML needs a reader the
  same day.
- **No second memory-review surface until a caller needs it.** `bin/operator memory
  review` (`Operator::MemoryReview`) is the one evidence-backed review: artifact
  digest plus an explicit `--confirm`. The extra pieces in draft PR #735 and its
  branches (`feat/operator-memory-review-*`, `recover/memory-governance-*`) have
  no caller, and a learning or governance layer nothing reads is the inert config
  this tree keeps deleting. Reopen with the caller that needs one.
- **No capability adapter ships without `PersonalPermissions`.** Microphone,
  camera, location, contacts, personal memory, financial reads and purchases go
  through `Master::Ground::PersonalPermissions` or they do not exist. Financial
  actions stay read-only by default; a consequential one needs fresh,
  transaction-specific approval with a verified summary. Until a real device
  adapter and its proof exist, say the guard is tested, never that the device is
  protected. Reopen with the first adapter that wants the capability.
- **No "fluent coding agent" programme ahead of a measurable turn.** The eight
  priorities (a continuous edit-test turn, one policy-bound tool graph, isolated
  subagents, durable long sessions, less routine friction, cost-aware routing, an
  IDE adapter, an always-available operator) and the cross-lane benchmark all
  presuppose one deterministic, provider-independent acceptance scenario that does
  not exist. Build that scenario first; a plan written before it ranks by taste.
  The IDE adapter waits on the core loop being measurable, and no benchmark runs
  against lanes the operator has not authorised.
- **No distant-future kernel rewrite.** Effect, Constitution, World, Memory and
  Proof, with the separate FixLoop lifecycle, are the kernel. Reopen with a
  concrete defect the present shape cannot express. The 2026-10-26 ChatGPT
  architecture briefs (effect kernel and evidence ledger, event sourcing, actor
  supervisors, a capability microkernel, a worker market, eighteen alternatives)
  fall here and under the parallel-stream, external-protocol, skill, memory and
  third-surface refusals above; their concrete parts landed instead as
  `Fix::OutcomePolicy`, one terminal-state list, `Io::LaneState` and
  `Fix::LanePreflight`.
- **No RBS or Steep yet.** Signatures are a second declaration of every
  interface, and a type checker is a toolchain run on an 8 GB Mac with no check
  that reads its output. `Data.define` values and the contract tests hold the
  boundaries that have broken. Reopen with an interface mismatch that shipped
  and that a signature would have caught.
- **Model order is quality order, not least recently used.** OpenClaw rotates
  auth profiles least recently used first, and `Io::KeyRotator` already does
  that for keys. Applied to models it would put sonnet ahead of opus by turns.
  The starvation it guards against was an idle lane read as unhealthy, fixed in
  `ProviderHealth` (a 15-minute window) and `ModelRouter#recently_failed?`.
- **The Rails 8.2 alpha pin moves only by a deliberate change.** Never float it.
  An upgrade is its own commit with compatible Gemfiles and lockfiles and the
  app, contract and browser suites after it. Reopen on an upstream release or a
  security advisory.
- **The Pluribus logo PDF is not chased.** The only copy sat under `__DELETE/`
  with a text layer that did not match its page; a source that disagrees with its
  own label is not evidence for a visual identity. The identity rests on the
  tokens in `data/tokens.yml`.
