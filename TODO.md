# TODO — MASTER self-adherence backlog

173 rules in rules.yml. Every item here is a gap between what rules.yml declares and what MASTER
actually does. Organized by category. Work left to right, top to bottom. Mark done with [x].

---

## A. Missing lexical scan rules

Rules with detect_lexical in rules.yml but no RuleDSL block in lib/judge/scan/rules/.

- [ ] A01 SECRET_PROXIMITY — detect `password|secret|token|api_key = 'literal'` (8+ chars) in any file
- [ ] A02 MAGIC_COLOR — detect raw `#rrggbb`, `rgb(`, `rgba(`, `hsl(` in CSS/SCSS/JS/HTML
- [ ] A03 UNBOUNDED_RETRY — detect `\bretry\b` or `while\s+true` without nearby `max_attempts`
- [ ] A04 KEYWORD_ARGS — detect Ruby `def` with 3+ bare positional args (no colon, no default)
- [ ] A05 GUARD_CLAUSE — detect `def …\n  if …\n … else\n … end\n end` (nested if-else in method body)
- [ ] A06 USE_THEN — detect sequential `x = foo(…)\n bar(x)` chains that could be `.then`
- [ ] A07 RESCUE_ON_DEF — detect `def …\n  begin\n … rescue` (put rescue on def line instead)
- [ ] A08 DEAD_CODE — detect any statement following `return|raise|exit|throw` on a later line
- [ ] A09 TRAILING_COMMAS — detect multi-line array/hash literals missing trailing comma on last element
- [ ] A10 FULL_BY_DEFAULT — detect `shallow|standard|quick|lite|basic` tier parameters/flags
- [ ] A11 OPTIONAL_CHAINING_JS — detect `(\w+)\s*&&\s*\1\.\w+` in JavaScript files
- [ ] A12 NULL_BLINDNESS — add as scan Rule (not just AstFixer): `= NULL` / `== nil` in SQL contexts
- [ ] A13 STRICT_MODE_ZSH — detect `#!/.*zsh` scripts missing `set -euo pipefail` on next line
- [ ] A14 NO_MAGIC_NUMBERS — detect unexplained integer/float literals not in constants (exclude 0/1/-1)
- [ ] A15 NO_COLUMN_ALIGN — detect 2+ spaces before `=>`, `=`, or `:` used for column alignment
- [ ] A16 FORBIDDEN_PATTERNS — wire anti_patterns.forbidden list (eval, Marshal.load, open($, rm -rf /) as :error rules
- [ ] A17 SPECULATIVE_GENERALITY_LEXICAL — detect `# TODO: future`, `# for later`, `# hypothetical` comments
- [ ] A18 COMMENTS_AS_DEODORANT — detect comments beginning with "This method/class/function"

## B. Missing structural rules

Rules referencing `detect_structural: handler` where no Rule subclass implements the handler.

- [ ] B01 SmallFilesRule — Prism AST or line count >300 (detect_structural: file_silhouette)
- [ ] B02 SmallFunctionsRule — Prism DefNode with >20 lines (detect_structural: long_method)
- [ ] B03 GodClassRule — class with >10 public method defs or >300 lines (detect_structural: god_class)
- [ ] B04 CqsRule — Prism: method that both modifies ivar/attr and returns a non-self value (detect_structural: cqs)
- [ ] B05 FileLayoutRule — Ruby: frozen → require → module → class → public → private order check
- [ ] B06 ExplicitRule — detect implicit requires, implicit return types, magic coupling (detect_structural: explicit)
- [ ] B07 NestingDepthRule — Prism: nesting >4 levels (if/while/case/module/class/def)
- [ ] B08 CyclomaticComplexityRule — move CC calculation out of DetectionPipeline into a proper Rule subclass
- [ ] B09 PatternExtractionRule — structural: "80% of the way to Strategy/Decorator/Pipeline/…" (mode: opportunity)
- [ ] B10 DataClassRule — class that holds data with no behavior (all attr_accessor, no methods)

## C. Missing autofix transforms in AstFixer

Rules marked `autofix: true` whose transform isn't in lib/judge/scan/ast_fixer.rb.

- [ ] C01 Collapse 3+ consecutive blank lines to 2 (SQUINT_TEST/WHITESPACE_PUNCTUATION)
- [ ] C02 Strip trailing whitespace from every line (TRAILING_WHITESPACE)
- [ ] C03 Append .freeze to mutable constants: `FOO = [` → `FOO = [].freeze` (IMMUTABLE)
- [ ] C04 Add `set -euo pipefail` after shebang in .zsh/.sh scripts (STRICT_MODE_ZSH)
- [ ] C05 Add `lang="en"` to `<html>` tags missing it (HTML_LANG)
- [ ] C06 Add `loading="lazy"` to `<img>` tags missing loading= (LAZY_IMAGES)
- [ ] C07 Add `<meta charset=UTF-8>` as first element in `<head>` (META_CHARSET)
- [ ] C08 Replace `var ` with `const ` in JS (NO_VAR) — only when variable not reassigned
- [ ] C09 Convert `for (const x in arr)` to `for (const x of arr)` (FOR_OF)
- [ ] C10 Convert `"a" + b + "c"` to `` `a${b}c` `` template literals (TEMPLATE_LITERALS)
- [ ] C11 Convert `a && a.b` to `a?.b` in JavaScript (OPTIONAL_CHAINING)
- [ ] C12 Remove statement after `return`/`raise` on immediately following line (DEAD_CODE)
- [ ] C13 Add trailing comma to last element of multi-line array/hash (TRAILING_COMMAS)
- [ ] C14 Convert `margin-left:` / `margin-right:` to logical properties (LOGICAL_PROPERTIES)

## D. Self-scan infrastructure

rules.yml success_criteria: "system_applies_to_itself_without_exception"

- [ ] D01 Boot-time self-scan: on `master start`, scan lib/ with all registered rules; publish self_violation on any finding
- [ ] D02 Boot dmesg line: emit `judge: lib/ N rules, M violations` in 5-line boot banner
- [ ] D03 /self command: scan MASTER's lib/ on demand, print dmesg-style report to stdout
- [ ] D04 self_test section wiring: ROBUSTNESS (bare rescue check), SINGULARITY (duplicate rule IDs), LINEARITY (nesting depth), PROXIMITY (test files co-located), ABSTRACTION (no god class), DENSITY (no long method)
- [ ] D05 Self-violation event: `self_violation` event on bus stops the loop until fixed
- [ ] D06 Periodic self-scan via Loop::Heartbeat: schedule lib/ rescan every 60 minutes
- [ ] D07 Self-autofix: if self-scan finds violations with autofix: true, apply AstFixer transforms to MASTER's own source
- [ ] D08 Block shipping if self-scan shows violations (Pipeline gate before deploy)
- [ ] D09 Self-scan covers data/*.yml: run SINGULARITY check (no duplicate rule IDs) on every boot
- [ ] D10 ground_truth_check enforcement: before any `claim_task_complete` in Loop, re-read file and confirm

## E. Rules.yml → code alignment

Every section of rules.yml that isn't implemented in Ruby.

- [ ] E01 Finding#rule_id: findings should carry the exact rules.yml ID string (e.g. "SECRET_PROXIMITY"), not Ruby class name
- [ ] E02 SemanticRule findings: include the specific rules.yml ID that triggered, not "semantic"
- [ ] E03 Prediction engine: RuleLoop#should_autofix? already exists in scanner.rb — wire it into RuleLoop before applying any fix
- [ ] E04 evidence_scoring: Pipeline should accumulate scan_clean (25 pts) and require ≥80 to ship
- [ ] E05 failure_taxonomy: RuleLoop transient retry (already TRANSIENT_RE) — add permanent/ambiguous branches with fail_fast and human_intervention
- [ ] E06 principle_priorities tier1: halt pipeline on PRESERVE_FIRST/DECOUPLE/DEGRADE_GRACEFULLY violation
- [ ] E07 principle_priorities tier2: route DRY/KISS/SRP violations to RuleLoop automatically
- [ ] E08 veto_patterns section: wire as :error severity rules that block the pipeline
- [ ] E09 anti_patterns.forbidden: each pattern becomes a SecretProximity/ForbiddenPattern lexical rule
- [ ] E10 schema_metadata fields (reversibility, blast_radius): expose on Finding objects
- [ ] E11 phantom_recovery: implement gaslighting_preamble detector in Judge::Agent — discard and retry if match
- [ ] E12 phantom_recovery: text_repetition_loop detector — if same 60-char span ≥3 times, escalate model
- [ ] E13 preserve_user_intent: Pipeline check that refactors don't change public method signatures
- [ ] E14 library_verify: pre_flight checks (Gemfile.lock has gem, path exists, binary in PATH) before shelling out
- [ ] E15 SINGULARITY self-check: boot assertion that all rule IDs in rules.yml are unique

## F. Architecture violations in MASTER's own code

MASTER must pass its own rules. Violations found by reading lib/.

- [ ] F01 scanner.rb#scan: 35-line method — split into read_file, parse_ast, apply_rules, publish (SRP + SMALL_FUNCTIONS)
- [ ] F02 DetectionPipeline: shallow relay class adds no abstraction (DIFFERENT_LAYER_DIFFERENT_ABSTRACTION) — merge into Scanner or delete
- [ ] F03 RuleLoop: council_fix and request_fix duplicate prompt-building logic (DRY) — extract build_prompt_for(violation, src, path, style:)
- [ ] F04 pipeline.rb#maybe_rollback: git stash logic in Pipeline violates SRP — extract to Loop::Rollback class
- [ ] F05 memory.rb: 256 lines (SMALL_FILES) — split into Memory::Store, Memory::Search, Memory::Consolidate modules
- [ ] F06 repo_ecology.rb: analyze_file returns 12-key Hash (DATA_CLASS) — introduce FileRecord = Data.define(...)
- [ ] F07 ground/constitution.rb: load_yaml called on every invocation — memoize with @constitution_cache (IMMUTABLE)
- [ ] F08 master.rb#bootstrap_container: 50+ line method — split into init_ground, init_judge, init_loop, init_reach
- [ ] F09 scanner.rb parallel_each: raw Thread.new without error boundary — wrap in rescue and publish thread_error
- [ ] F10 rule_loop.rb#preamble: reads soul.yml on every call — memoize (pure function same input = same output)
- [ ] F11 pipeline.rb ParallelGroup#merge_results: uses filter_map + reduce on results — simplify (KISS)
- [ ] F12 repo_ecology.rb: co_change_graph built twice (once in snapshot, once in scan) — always use memoized accessor
- [ ] F13 judge/agent.rb: verify method count ≤10 public methods (NO_GOD_CLASS threshold)
- [ ] F14 now/context_window.rb: verify no god class
- [ ] F15 loop/rule_loop.rb: CANDIDATE_COUNT=3 magic number — name as semantic constant with comment (NO_MAGIC)
- [ ] F16 ground/memory.rb: MAX_INJECT_TOKENS = 2000 used as token limit — verify against actual model context size
- [ ] F17 reach/llm.rb: verify no hardcoded API keys (SECRET_PROXIMITY)
- [ ] F18 All lib/**/*.rb: verify zero Marshal.load (anti_patterns.forbidden)
- [ ] F19 All lib/**/*.rb: verify zero `open(.*#{` shell-through-open (anti_patterns.forbidden)
- [ ] F20 All lib/**/*.rb: verify zero `system(.*#{` command injection patterns (UNSAFE_CALLS)
- [ ] F21 All lib/**/*.rb: check for mutable constants missing .freeze (IMMUTABLE)
- [ ] F22 All lib/**/*.rb: check for long chains a.b.c.d.e not covered by existing rule exclusions (LAW_OF_DEMETER)
- [ ] F23 All lib/**/*.rb: check for 3+ positional args needing keyword conversion (FEW_ARGUMENTS)
- [ ] F24 loop/fix_helpers.rb: read and verify SRP — only fix-related helpers, no scanning logic
- [ ] F25 judge/scan/rule_dsl.rb: verify auto_build? pattern documented (SELF_EXPLAINING)

## G. Voice and personality alignment

rules.yml voice section must govern MASTER's own outputs.

- [ ] G01 Anti-simulation: add forbidden word filter (will, would, could, might) to prompts MASTER sends to LLM
- [ ] G02 Strunk preambles: strip "In summary,", "Consequently,", "Therefore," from MASTER's own output generation
- [ ] G03 Strunk hedges: strip "I think that", "I believe", "seems", "appears" from MASTER output
- [ ] G04 Strunk endings: strip "as a result.", "for this reason.", "thus." from MASTER output
- [ ] G05 Banned output: enforce no headlines/bullet_lists_without_content/filler_phrases in voice/personality.rb
- [ ] G06 Inverted pyramid: MASTER's scan reports lead with outcome, then evidence, then detail
- [ ] G07 Boot message: verify 5-line dmesg style; never collapse to 1 line, never expand beyond 5
- [ ] G08 Silence on success: verify routine completions emit one line max
- [ ] G09 Diagnostic output: multi-line structured output is intentional — verify personality.rb preserve: section enforced
- [ ] G10 require_evidence: modification claims must show diff, completion claims must show command output

## H. Testing coverage

RuleCoverageRule: every Rule subclass needs a test file.

- [ ] H01 Test for SmallFilesRule (B01)
- [ ] H02 Test for SmallFunctionsRule (B02)
- [ ] H03 Test for GodClassRule (B03)
- [ ] H04 Test for CqsRule (B04)
- [ ] H05 Test for SECRET_PROXIMITY rule (A01)
- [ ] H06 Test for MAGIC_COLOR rule (A02)
- [ ] H07 Test for UNBOUNDED_RETRY rule (A03)
- [ ] H08 Test for STRICT_MODE_ZSH rule (A13)
- [ ] H09 Test for KEYWORD_ARGS rule (A04)
- [ ] H10 Test for DEAD_CODE rule (A08)
- [ ] H11 Test for TRAILING_COMMAS rule (A09)
- [ ] H12 Test for AstFixer: collapse blank lines transform (C01)
- [ ] H13 Test for AstFixer: trailing whitespace strip (C02)
- [ ] H14 Test for AstFixer: .freeze append on mutable constant (C03)
- [ ] H15 Self-scan test: MASTER scans its own lib/, expects zero violations
- [ ] H16 Idempotency test: scan + fix + scan produces same result as scan + fix + fix + scan
- [ ] H17 Test for evidence_scoring gate (scan_clean:25 weight, pass_threshold: 80)
- [ ] H18 Test for failure_taxonomy: transient errors retry ≤3, permanent errors fail immediately
- [ ] H19 Test for SINGULARITY: rules.yml has no duplicate IDs
- [ ] H20 Test for phantom_recovery: gaslighting preamble discards response and retries

## I. Data quality and config

- [ ] I01 rules.yml SINGULARITY boot assertion: verify all 173 IDs unique on load (no duplicates)
- [ ] I02 rules.yml schema validator: every rule has required fields (id, name, tier, severity, autofix)
- [ ] I03 rules.yml: fix any NO_COLUMN_ALIGN violations (multi-space alignment in YAML values)
- [ ] I04 data/soul.yml ↔ rules.yml cross-reference: ensure golden_rule in soul.yml matches rules.yml kernel tier
- [ ] I05 data/patterns.yml: audit for rules referenced here that are not in rules.yml
- [ ] I06 data/standing_orders.yml: verify voice directives match rules.yml voice section
- [ ] I07 MASTER/Gemfile: add `reek` if not present (ReekRule depends on it)
- [ ] I08 MASTER/Gemfile: verify `prism` version matches rules.yml language support claims

## J. Pipeline and convergence integrity

- [ ] J01 FixLoop: add cycle detector — if same violation appears N≥3 times across passes, stop and escalate
- [ ] J02 Pipeline: wire evidence_scoring — scan_clean(25) + test_pass(35) ≥80 gates the :deploy stage
- [ ] J03 Pipeline: tier1_critical rules → halt with rollback on violation, not just :err status
- [ ] J04 RuleLoop: genetic_fix must reject candidates that increase violation count vs original (not just differ)
- [ ] J05 Loop::Governor: verify pressure detection accounts for OpenBSD vmm memory (no swap, 1GB RAM)
- [ ] J06 scan_since: extend to include MASTER lib/ alongside user code (self-scan on git diff)
- [ ] J07 Heartbeat: emit `heartbeat:scan_clean` or `heartbeat:violations N` with self-scan result
- [ ] J08 Convergence loop: add max_iterations cap (UNBOUNDED_RETRY applies to MASTER itself)

## K. Missing behaviors

- [ ] K01 COST_TRANSPARENCY: after each LLM call, MASTER emits `[$N.NNNN, NNN tokens]` on event bus
- [ ] K02 CACHE_LLM: hash prompt + model → cache response with 5-min TTL; serve from cache on repeat calls
- [ ] K03 ERROR_CONTEXT: every Result.err includes {file:, method:, attempted:} context hash
- [ ] K04 USER_CONTROL: add --dry-run flag to scan/sweep — show findings without applying fixes
- [ ] K05 SYSTEM_STATUS: scan progress stream shows `scan: path/file.rb N violations` per file (already in stream_progress — verify wired)
- [ ] K06 IDEMPOTENT: verify scan+fix is idempotent — apply twice, second pass produces no changes
- [ ] K07 CACHE_LLM: LLM response cache should survive process restart (persist to .master/llm_cache.yml)
- [ ] K08 PROGRESSIVE_DISCLOSURE: /help shows one-liner per command; detail on /help <command>
- [ ] K09 FEEDBACK_LOOPS: scan_dir streams per-file progress; verify FixLoop does same
- [ ] K10 DESIGN_BY_CONTRACT: document preconditions on Scanner#scan (path must exist, depth must be :deep)

## L. Web surface (MASTER/web/)

- [ ] L01 All .erb views: scan with HTML_LANG, META_CHARSET, IMG_ALT, BUTTON_OVER_ANCHOR — fix violations
- [ ] L02 All .css/.scss: scan with MOBILE_FIRST, NO_IMPORTANT, NO_IMPORT_SCSS — fix violations
- [ ] L03 All .css: scan with MAGIC_COLOR — extract raw hex values to CSS custom properties
- [ ] L04 All .js/.ts: scan with NO_VAR, FOR_OF, TEMPLATE_LITERALS, CONST_BY_DEFAULT — fix violations
- [ ] L05 All .js: scan with JS_MODULE_SIZE — split files >300 lines
- [ ] L06 web/app/controllers: scan with RATE_LIMITING_MISSING — verify all auth routes throttled
- [ ] L07 web/app/models: scan with STRICT_LOADING_MISSING — add strict_loading_by_default true
- [ ] L08 web/db/migrate/: scan with MIGRATION_ADD_REFERENCE_NO_FK — verify all references have foreign_key: true

## M. OpenBSD / deploy alignment

- [ ] M01 Deploy: copy DEPLOY/openbsd/etc/rc.d/master to /etc/rc.d/master on VPS and verify
- [ ] M02 Deploy: verify /etc/master.env on VPS has all keys from master.env.sample
- [ ] M03 Deploy: `doas rcctl enable master` — verify master service enabled at boot
- [ ] M04 openbsd.yml audit: check if MASTER's shell-out commands use doas where rules.yml says `privilege: doas`
- [ ] M05 Backup: verify DEPLOY/openbsd/backup_priv.sh uses openrsync (not rsync) per openbsd.amsterdam docs
- [ ] M06 PTR record: verify brgen.no PTR record set via ptr4.openbsd.amsterdam (run from VM, not locally)
- [ ] M07 sshd_config on VPS: verify PermitRootLogin no, PasswordAuthentication no, MaxAuthTries 3

## N. Documentation alignment

- [ ] N01 MASTER/QUICKSTART.md: verify every command in quickstart runs on OpenBSD 7.9 with ruby34
- [ ] N02 AGENTS.md: update to reflect current 7-module structure (now/loop/judge/voice/ground/reach/trace)
- [ ] N03 README.md: verify tagline matches project_master_mission.md ("Constitutional AI for any text artifact")
- [ ] N04 rules.yml comments: remove any remaining TODO/FIXME markers (self-adherence to TODO_FIXME rule)
- [ ] N05 All deferred comments in lib/: rewrite to S&W active voice per STRUNK rule
