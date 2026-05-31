# TODO — MASTER self-adherence backlog

173 rules in rules.yml. Every item here is a gap between what rules.yml declares and what MASTER
actually does. Organized by category. Work left to right, top to bottom. Mark done with [x].

---

## A. Missing lexical scan rules

Rules with detect_lexical in rules.yml but no RuleDSL block in lib/judge/scan/rules/.

- [x] A01 SECRET_PROXIMITY — detect `password|secret|token|api_key = 'literal'` (8+ chars) in any file
- [x] A02 MAGIC_COLOR — detect raw `#rrggbb`, `rgb(`, `rgba(`, `hsl(` in CSS/SCSS/JS/HTML
- [x] A03 UNBOUNDED_RETRY — detect `\bretry\b` or `while\s+true` without nearby `max_attempts`
- [x] A04 KEYWORD_ARGS — detect Ruby `def` with 3+ bare positional args (no colon, no default)
- [x] A05 GUARD_CLAUSE — detect `def …\n  if …\n … else\n … end\n end` (nested if-else in method body)
- [x] A06 USE_THEN — detect sequential `x = foo(…)\n bar(x)` chains that could be `.then`
- [x] A07 RESCUE_ON_DEF — detect `def …\n  begin\n … rescue` (put rescue on def line instead)
- [x] A08 DEAD_CODE — detect any statement following `return|raise|exit|throw` on a later line
- [x] A09 TRAILING_COMMAS — detect multi-line array/hash literals missing trailing comma on last element
- [x] A10 FULL_BY_DEFAULT — detect `shallow|standard|quick|lite|basic` tier parameters/flags
- [x] A11 OPTIONAL_CHAINING_JS — detect `(\w+)\s*&&\s*\1\.\w+` in JavaScript files
- [x] A12 NULL_BLINDNESS — add as scan Rule (not just AstFixer): `= NULL` / `== nil` in SQL contexts
- [x] A13 STRICT_MODE_ZSH — detect `#!/.*zsh` scripts missing `set -euo pipefail` on next line
- [x] A14 NO_MAGIC_NUMBERS — detect unexplained integer/float literals not in constants (exclude 0/1/-1)
- [x] A15 NO_COLUMN_ALIGN — detect 2+ spaces before `=>`, `=`, or `:` used for column alignment
- [x] A16 FORBIDDEN_PATTERNS — wire anti_patterns.forbidden list (eval, Marshal.load, open($, rm -rf /) as :error rules
- [x] A17 SPECULATIVE_GENERALITY_LEXICAL — detect `# TODO: future`, `# for later`, `# hypothetical` comments
- [x] A18 COMMENTS_AS_DEODORANT — detect comments beginning with "This method/class/function"

## B. Missing structural rules

Rules referencing `detect_structural: handler` where no Rule subclass implements the handler.

- [x] B01 SmallFilesRule — Prism AST or line count >300 (detect_structural: file_silhouette)
- [x] B02 SmallFunctionsRule — Prism DefNode with >20 lines (detect_structural: long_method)
- [x] B03 GodClassRule — class with >10 public method defs or >300 lines (detect_structural: god_class)
- [x] B04 CqsRule — Prism: method that both modifies ivar/attr and returns a non-self value (detect_structural: cqs)
- [x] B05 FileLayoutRule — Ruby: frozen → require → module → class → public → private order check
- [x] B06 ExplicitRule — detect implicit requires, implicit return types, magic coupling (detect_structural: explicit)
- [x] B07 NestingDepthRule — Prism: nesting >4 levels (if/while/case/module/class/def)
- [x] B08 CyclomaticComplexityRule — move CC calculation out of DetectionPipeline into a proper Rule subclass
- [ ] B09 PatternExtractionRule — structural: "80% of the way to Strategy/Decorator/Pipeline/…" (mode: opportunity)
- [x] B10 DataClassRule — class that holds data with no behavior (all attr_accessor, no methods)

## C. Missing autofix transforms in AstFixer

Rules marked `autofix: true` whose transform isn't in lib/judge/scan/ast_fixer.rb.

- [x] C01 Collapse 3+ consecutive blank lines to 2 (SQUINT_TEST/WHITESPACE_PUNCTUATION)
- [x] C02 Strip trailing whitespace from every line (TRAILING_WHITESPACE)
- [x] C03 Append .freeze to mutable constants: `FOO = [` → `FOO = [].freeze` (IMMUTABLE)
- [x] C04 Add `set -euo pipefail` after shebang in .zsh/.sh scripts (STRICT_MODE_ZSH)
- [x] C05 Add `lang="en"` to `<html>` tags missing it (HTML_LANG)
- [x] C06 Add `loading="lazy"` to `<img>` tags missing loading= (LAZY_IMAGES)
- [x] C07 Add `<meta charset=UTF-8>` as first element in `<head>` (META_CHARSET)
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

---

## O. DRY / KISS / SOLID / POLA / Rails doctrine / clean code / refactoring

Violations and opportunities found by reading the actual source. Each item is a concrete location.

### O1. Single Responsibility (SRP / SOLID)

- [ ] O101 cli.rb (538 lines) is a god class — split into CLI::Repl, CLI::Renderer, CLI::BackgroundScan, CLI::SignalHandler
- [ ] O102 Builder: 9 boot_* methods — each boot phase should be a dedicated Bootable class
- [ ] O103 FixLoop: manages convergence state, commits, scan, LLM routing, circuit breakers — extract FixLoop::Committer, FixLoop::Scanner, FixLoop::LlmRouter
- [ ] O104 CommandRegistry: dispatch logic AND output formatting in same module — extract CommandRegistry::Formatter
- [ ] O105 bin/cli: stable_web_secret, boot_banner, boot_web_ui defined as top-level def — move each to its own class in lib/now/
- [ ] O106 chat_controller.rb#message: 70+ lines, mixes LLM call, TTS dispatch, SSE streaming, persona routing — extract ChatService
- [ ] O107 chat_controller.rb#uploaded_image_payload: file I/O + image resize + Rails response — three responsibilities, extract ImagePresenter
- [ ] O108 repo_ecology.rb#analyze_file: returns 12-key Hash — introduce FileRecord = Data.define(...)
- [ ] O109 scanner.rb#scan: read file, parse AST, apply rules, publish events all inline — extract FileProcessor

### O2. DRY

- [ ] O201 dispatch_review + dispatch_critique both call deliberation.review_convergent — extract run_deliberation(target, context:)
- [ ] O202 format_tribunal and deliberation_feedback produce council feedback in different formats — one canonical formatter
- [ ] O203 recent_events and dispatch_tail both parse JSONL from activity.jsonl with near-identical code — extract EventLog class
- [ ] O204 RuleLoop#build_prompt and build_diff_prompt share 80% of structure — extract shared_prompt_header(violation, src, path)
- [ ] O205 council_fix and genetic_fix both call preamble, extract_code, handle transient retry — extract FixAttempt class
- [ ] O206 bundle_status calls Open3.capture2e twice with same pattern — extract bundle_ok?(dir)
- [ ] O207 dispatch_status and from_git both run git status separately — share GitOperations instance
- [ ] O208 RuleLoop#scan_files and FixLoop#scan_violations both filter by severity — share SEVERITY_RANK threshold check
- [ ] O209 fast_pass and llm_pass both commit_if_dirty — extract single commit_if_dirty(label) with dirty check inside
- [ ] O210 Multiple rescue blocks with `Ground::Swallow.log(e, context: "…")` — add `safe_call(context:) { }` helper to Swallow

### O3. KISS

- [ ] O301 dispatch_scan → collect_scan_pairs → resolve_scan_profile → load_workflow_profiles — 4-deep call chain, flatten to 2
- [ ] O302 from_last_assistant: 7 sequential text.match? checks — replace with a lookup table of {pattern => proposal}
- [ ] O303 FixLoop#run is 40 lines with 3 conditional branches — extract run_pass(files, pass, deadline) method
- [ ] O304 format_fix_preview: flattens, groups, sorts, formats in one method — too many steps for one method
- [ ] O305 repl_loop has inline focus_mode conditional — extract prompt_for_mode → focus_prompt or normal_prompt
- [ ] O306 stream_chunk_handler returns a lambda capturing mutable state — replace with a StreamAccumulator object
- [ ] O307 bin/cli boot_web_ui spawns processes, kills existing, handles OpenBSD separately — extract WebServer.start(config:)
- [ ] O308 assign_container_refs!: assigns 11 @ivars from hash — replace with Container value object (Data.define)
- [ ] O309 FixLoop#stagnant?: MD5 of raw violations array — sort before hashing so reordering is not a false change
- [ ] O310 `scan` command parses profile keyword by string prefix match — switch to explicit keyword table

### O4. POLA (Principle of Least Astonishment)

- [ ] O401 /fix loop starts background; /fix <path> runs synchronously — same command, opposite semantics — split /fix and /watch
- [ ] O402 /model without args returns current model; /mode without args returns current mode — but named differently (model vs mode)
- [ ] O403 /scan with no profile silently scans lib/ — user expects . (cwd), document or change default
- [ ] O404 TTY::Reader.new(track_history: true) — history exists in session but is not saved to disk across sessions (surprising)
- [ ] O405 from_violations weight 0.9 + @violations/50 — magic formula, document or name (high_violation_weight)
- [ ] O406 pipe() silently ignores empty lines — at minimum log or emit empty_input event
- [ ] O407 /save command saves session; INT trap also saves session but says "saved" without newline — inconsistent
- [ ] O408 /axioms scans lib/; /scan with no arg also scans lib/ — two commands with the same default target, different output format
- [ ] O409 chunk_accumulator method name doesn't reveal it returns a lambda — rename to build_stream_handler or make a class

### O5. Rails doctrine

- [ ] O501 chat_controller.rb#tts: no before_action authentication — raw bytes served without web token check
- [ ] O502 /chat/tts endpoint: no rate limiting (RATE_LIMITING_MISSING) — same endpoint synthesizes unlimited audio
- [ ] O503 /chat/tts: no ETag or Cache-Control header — same voice+text re-synthesized on every request
- [ ] O504 chat_controller.rb: uses Rails.logger; other controllers use event bus — pick one per layer
- [ ] O505 chat_controller.rb#message: no strong_params — params used directly without explicit permit
- [ ] O506 No ApplicationController before_action enforcing web_token on all sensitive actions
- [ ] O507 chat_controller.rb synthesizes TTS synchronously in request — move to background job with polling
- [ ] O508 dashboard_controller.rb: check for N+1 queries on any AR collections it loads
- [ ] O509 web/app/models/: check all models for strict_loading_by_default (STRICT_LOADING_MISSING rule)
- [ ] O510 web/db/migrate/: verify all add_reference migrations include foreign_key: true

### O6. Clean Code

- [ ] O601 dispatch_why embeds a 2-sentence LLM prompt as a string literal — extract to voice/personality template
- [ ] O602 format_payload in work_commands: pay.map { |k, v| "#{k}=#{v.to_s.tr('"', '')[0, 30]}" } — extract to a KeyValueFormatter
- [ ] O603 CLI @violations updated from background thread; read in main thread without synchronize — race condition, wrap in Mutex
- [ ] O604 repl_loop: @bg_thread&.kill on exit — Thread#kill is unsafe, send a poison-pill message instead
- [ ] O605 from_idle: `last.fetch(:ts) { last[:timestamp] }` — inconsistent key access, normalize message struct
- [ ] O606 REPLAY_TURNS = 5 in cli.rb — magic constant, add comment or move to config
- [ ] O607 DMESG_BUFFER = 80 in cli.rb — never changes; if it should be configurable, read from config
- [ ] O608 `Time.now.to_i - ts.to_i` in propose.rb — numeric subtraction of time values, use Time arithmetic
- [ ] O609 format_tribunal: rescue 0.5 at end of confidence calc — bare rescue on a single expression, extract safely
- [ ] O610 dispatch_resync builds lines array with side-effecting operations inline — separate build and execute phases

### O7. Refactoring (Fowler catalog)

- [ ] O701 Extract class: Proposal hash in propose.rb → Proposal = Data.define(:action, :reason, :weight)
- [ ] O702 Extract class: ScanReport from format_scan_results in work_commands.rb
- [ ] O703 Extract class: TribunaFeedback from format_tribunal in work_commands.rb
- [ ] O704 Replace magic number: CANDIDATE_COUNT = 3 in rule_loop.rb — read from workflow.yml convergence config
- [ ] O705 Replace magic number: MAX_PASSES = 15, IDLE_SLEEP = 300, STARTUP_DELAY = 90 in fix_loop.rb — read from convergence config
- [ ] O706 Inline class: DetectionPipeline adds no abstraction over scanner — inline its logic into Scanner or delete
- [ ] O707 Replace conditional with polymorphism: `if ruby?` / `if shell?` / `if sql_in_ruby?` in AstFixer — strategy pattern
- [ ] O708 Introduce value object: violation hash in rule_loop has file, line, rule, message, severity — formalize as Violation
- [ ] O709 Replace loop with pipeline: fix_loop fast_pass → llm_pass → commit sequence is a pipeline, model it as Pipeline stages
- [ ] O710 Move method: dispatch_resync in work_commands reaches into git, bundle, rcctl — move to a ResyncService

### O8. Pragmatic Programmer / Polished Ruby

- [ ] O801 Circuit breaker state not persisted — survives process restart but not MASTER restart; persist to .master/circuit_state.yml
- [ ] O802 `watch_loop.rb` uses sleep polling — replace with kqueue (OpenBSD) or inotify via rb-inotify for event-driven watching
- [ ] O803 RuleLoop#rescan_candidate: Tempfile has no extension — language detection fails; use Tempfile.new(["prefix", ".rb"])
- [ ] O804 Open3.capture3 called with string args in several places — use array form to prevent shell injection
- [ ] O805 `SemanticRule#load_semantic_rules` called in constructor — if rules.yml changes at runtime, cache is stale; memoize with file mtime check
- [ ] O806 Session#token_est recalculates on every REPL prompt render — cache and invalidate on message append
- [ ] O807 Multiple lambdas in command_registry capture deps via closure — convert to method objects or Command pattern for testability
- [ ] O808 `dispatch_scan` builds scan profile from string prefix match — use a Trie or hash for O(1) lookup
- [ ] O809 FixLoop#collect_files uses Dir.glob without .gitignore awareness — use git ls-files for tracked files only
- [ ] O810 FixLoop#run_forever: bare `loop do` — add UNBOUNDED_RETRY-equivalent: max_cycles safety counter

---

## P. Execution flow improvements

Request lifecycle: user input → Pipeline → stages → agent → scanner → response.

### P1. Parallelism and throughput

- [ ] P101 Scanner POOL_SIZE = min(nprocessors, 8): on OpenBSD VM with 1 vCPU this is 1 (serial) — profile and document; consider async I/O instead of threads
- [ ] P102 LLM pass processes rules sequentially even when rules are independent — run independent RuleLoops in parallel (respect rule_deps.yml edges)
- [ ] P103 fast_pass runs rubocop on all files as one batch — if one file errors, rubocop non-zero exit skips reporting on all others; use --format json to isolate
- [ ] P104 SemanticRule sends one batched LLM prompt per file — good, but the prompt is rebuilt from scratch each call; memoize the rule-list template portion
- [ ] P105 ParallelGroup spawns all threads at once with no backpressure — cap at POOL_SIZE concurrently running threads
- [ ] P106 scan_dir sorts paths before scanning — sorting is unnecessary overhead on large trees; remove or lazy-sort for display only

### P2. Caching and memoization

- [ ] P201 co_change_graph in repo_ecology: reads 200 git commits on every call — persist to .master/co_change_cache.yml with mtime check on .git/HEAD
- [ ] P202 Memory#context_summary: YAML parse + sort on every pipeline turn — memoize with @store version counter
- [ ] P203 validate_data!: reads all data/*.yml on every boot — check mtime, skip if unchanged since last boot
- [ ] P204 LLM prompt caching (CACHE_LLM): hash (prompt + model) → cache in .master/llm_cache.yml with 5-min TTL
- [ ] P205 build_preamble in fix_loop: reads soul.yml on every FixLoop.new — class-level memoize with mtime guard
- [ ] P206 Session#token_est: recomputes by iterating all messages on every REPL render — increment counter on message append
- [ ] P207 `load_workflow_profiles` called per scan command invocation — memoize with file mtime guard

### P3. Context window and payload management

- [ ] P301 PipelineContext `output` key holds full LLM responses (100K+ chars possible) — truncate to last 8K on merge
- [ ] P302 PipelineContext `_timings` hash accumulates every stage on every pass — cap at last 20 entries
- [ ] P303 Session messages carry full content — implement sliding window: keep last N full, summarize older (already has token_est, wire the pruner)
- [ ] P304 Snapshot.md written on every boot including 100+ files — write only if any source file newer than snapshot
- [ ] P305 snapshot_artifact in work_commands reads up to 24K bytes per file, 40 files = 960K in one context — cap per-file and total differently

### P4. Correctness and race conditions

- [ ] P401 CLI @violations written by bg_thread, read by main thread with no synchronize — add Mutex around @violations access
- [ ] P402 FixLoop#stagnant? hashes violations array without sorting — reorder produces false "not stagnant" — sort by [rule, file, line] before hashing
- [ ] P403 maybe_rollback: calls dirty? (git status) even when @root is nil or .git doesn't exist — add guard before the git call
- [ ] P404 pipeline.rb#call: wraps initial in PipelineContext.wrap but if initial is already wrapped, wraps again — add type check
- [ ] P405 RuleLoop#best_candidate: rescan_candidate writes to Tempfile without extension — language detection in scan() returns nil, no rule applies — add extension suffix

### P5. Observability

- [ ] P501 Heartbeat publishes alive/dead but no scan metrics — add violations count and last_fixed timestamp
- [ ] P502 fix_loop:pass_start event has no file_count — add so operators can track scope
- [ ] P503 LLM call cost not published to event bus — add llm:call_complete event with tokens_in, tokens_out, cost_usd
- [ ] P504 scan:complete event has path and count but no rule breakdown — add top 3 rules to payload
- [ ] P505 No event when AstFixer applies a transform — add ast_fixer:transform event with path and transforms list
- [ ] P506 Pipeline stage timings stored in _timings but never published — emit pipeline:complete with full stage timing map

### P6. Reliability and error handling

- [ ] P601 FixLoop#run_forever: bare rescue StandardError publishes to bus but then exits the thread silently — restart the inner loop after a cooldown
- [ ] P602 RuleLoop council_fix: retries MAX_FIX_RETRIES times with exponential sleep — but sleeps block the thread, preventing heartbeat — use non-blocking approach
- [ ] P603 watch_loop: sleep polling will miss rapid file changes (two changes in one sleep window = one event) — use file mtime map with sub-second resolution
- [ ] P604 fix_loop collect_files: Dir.glob includes non-text binaries if extension matches — add File.binary? guard
- [ ] P605 Circuit breaker state not shared across RuleLoop instances in same pass — each RuleLoop opens its own breaker; share via FixLoop
- [ ] P606 Convergence CLEAN_RUNS = 2 required for done — if file changes between scans (editor autosave), loop never converges — add filesystem quiesce check

### P7. Stage ordering and dependency

- [ ] P701 rule_deps.yml exists but fix_loop ordered_rules doesn't use it — sort rules by topological order of dep graph
- [ ] P702 AstFixer runs before rubocop in fast_pass — but rubocop may undo some AstFixer changes — run AstFixer after rubocop
- [ ] P703 SemanticRule runs on every file even when lexical rules already caught the violation — skip semantic if file has unresolved lexical errors first
- [ ] P704 Evidence scoring (scan_clean: 25 pts, pass_threshold: 80) from rules.yml — wire into Pipeline as a gate before :deploy stage
- [ ] P705 tier1_critical rules (PRESERVE_FIRST, DECOUPLE, etc.) should halt pipeline, not just emit :err — wire principle_priorities tier1 to Pipeline halt

---

## Q. CLI UI improvements

### Q1. Input experience

- [ ] Q101 Command history not saved across sessions — persist TTY::Reader history to .master/cli_history (like shell .zsh_history)
- [ ] Q102 No tab completion for /commands — add TTY::Reader completion proc listing SLASH_COMMANDS
- [ ] Q103 No tab completion for filenames after /scan, /fix, /critique
- [ ] Q104 No CTRL+R reverse history search — implement via TTY::Reader key binding
- [ ] Q105 ARGV passthrough: ARGV.join(" ") treats --flags as literal text — parse ARGV properly with OptionParser
- [ ] Q106 Multi-line input: read_multiline has no line count guard — large paste exhausts memory; cap at 500 lines
- [ ] Q107 Paste detection: rapid input that looks like a paste should not trigger thinking indicator mid-paste

### Q2. Output and display

- [ ] Q201 /help shows flat list with no descriptions — each command needs a one-line description and example
- [ ] Q202 /help <command> should show detailed usage with examples (progressive disclosure, PROGRESSIVE_DISCLOSURE)
- [ ] Q203 Violation count in prompt is plain number — colorize: green=0, yellow=1-9, red=10+
- [ ] Q204 Status row rendered on every prompt — only render when something changed (violations, model, cost)
- [ ] Q205 /scan output dumps all violations without paging — pipe to TTY::Pager or show top N with "N more..."
- [ ] Q206 /model list doesn't mark the current model — add "→" marker next to active model
- [ ] Q207 /dmesg hardcoded to 80 lines — accept /dmesg N argument
- [ ] Q208 suggested_next_prompt shows one inline suggestion — show top 3 in TTY::Prompt select menu (press TAB to cycle)
- [ ] Q209 Thinking indicator is a static spinner — show elapsed seconds ("thinking 4s")
- [ ] Q210 Long responses not pageable — pipe to TTY::Pager when output exceeds terminal height
- [ ] Q211 Cost display shows raw float ("$0.0042") — show as "$0.00" for sub-cent, "$0.01" for larger
- [ ] Q212 No per-turn diff display after edits — show "N files changed" summary after each pipeline run
- [ ] Q213 /history truncates content to 120 chars but rule violations in history are illegible — show structured
- [ ] Q214 CTRL+C "saved" message lacks newline before "saved" — appears inline with partial input

### Q3. Commands and discoverability

- [ ] Q301 /scan, /fix, /review are separate but often used in sequence — add /triad <path> that chains all three
- [ ] Q302 /watch command not accessible from CLI — add /watch [on|off] to toggle file watcher at runtime
- [ ] Q303 /grep <pattern> missing — search session history for a pattern
- [ ] Q304 /audit missing — shows every file MASTER touched this session with before/after line counts
- [ ] Q305 /cost missing as standalone — currently buried in status row; make /cost show a breakdown by turn
- [ ] Q306 /dry-run missing — run /fix without applying changes, show what would change
- [ ] Q307 /rollback missing from /help — it exists as pipeline rollback but not user-accessible
- [ ] Q308 /self missing — trigger self-scan of lib/ and report result (self_test wiring)
- [ ] Q309 /propose missing from /help — show proposal engine output on demand
- [ ] Q310 /rules list — show all registered Rule subclasses with their IDs and severity

### Q4. Web UI — face.js (particle 3D face)

- [ ] Q401 face.js is 1,286 lines — split into face/particles.js, face/audio.js, face/expressions.js, face/tts.js, face/main.js
- [ ] Q402 No requestAnimationFrame pause on document.hidden — wastes CPU/battery on background tabs; add visibilitychange listener
- [ ] Q403 Audio analyser samples every frame regardless of playback state — skip analysis when !tts.playing
- [ ] Q404 analyserBuf allocated once but analyserFreqBuf re-checked — unify allocation in initAudio()
- [ ] Q405 Canvas not responsive to container resize — add ResizeObserver to reset canvas dimensions
- [ ] Q406 No loading state: blank canvas while face.js initializes — add CSS skeleton or fade-in on first frame
- [ ] Q407 Particle count hardcoded — scale N_PARTICLES based on device pixel ratio and screen area
- [ ] Q408 THREE.js conditionally imported but never used — remove dead import or commit to 3D
- [ ] Q409 prefers-reduced-motion: JS checks matchMedia but CSS message animations don't check it — add @media (prefers-reduced-motion: reduce) to face.css
- [ ] Q410 Face expression transitions are hard cuts — add linear interpolation (lerp) between expression parameters
- [ ] Q411 Boot greeting Osman → Pernille plays serially with no overlap — cross-fade or chain via onended
- [ ] Q412 Speaker identity not visually distinct in particle color/motion between Osman and Pernille — wire persona color palette
- [ ] Q413 No visual "fetching TTS" indicator between sentence end and audio start — add a brief pulse animation
- [ ] Q414 Canvas aria-hidden=true but no aria-live region announces TTS text to screen readers

### Q5. Web UI — TTS / Osman / Pernille

- [ ] Q501 /chat/tts endpoint has no rate limiting — add Rack::Attack throttle: 30 req/min per IP
- [ ] Q502 /chat/tts returns no ETag/Cache-Control — add ETag based on SHA256(voice+text), Cache-Control: max-age=3600
- [ ] Q503 No client-side TTS cache — store synthesized blobs in IndexedDB keyed by SHA256(voice+text)
- [ ] Q504 TTS bytes fetched per-sentence causing latency gap — prefetch next sentence while current plays
- [ ] Q505 tts:anticipate event published from Rails but face.js has no SSE listener — wire anticipate to expression pre-load
- [ ] Q506 tts:style:active event published but expression not applied until audio starts — apply expression on anticipate
- [ ] Q507 Browser speechSynthesis fallback uses default voice — map fallback to closest available voice name
- [ ] Q508 No audio normalization: whisper and shout differ by 30dB — add gainNode with compressor before analyser
- [ ] Q509 ttsSkip() on pointer down — if user taps during loading, skip fires before audio starts — add guard for loading state
- [ ] Q510 No offline mode — when synthesis API down, fallback to cached audio or browser TTS silently

---

## R. MASTER proactive proposal engine

How MASTER can autonomously surface solutions, alternatives, and opportunities without being asked.

### R1. Code intelligence proposals

- [ ] R101 After each clean scan pass, surface all mode:opportunity findings — switch SemanticRule to opportunity-only mode and show top 3
- [ ] R102 Pattern extraction proposal: when PATTERN_EXTRACTION fires, auto-generate a before/after showing the target pattern
- [ ] R103 After fixing a violation, check if the same violation exists in sibling files — auto-propose extending fix to siblings
- [ ] R104 Co-change coupling proposal: when RepoEcology finds co-change pair count ≥5, auto-propose extracting shared concern to a module
- [ ] R105 Semantic duplicate detector: within a file, find two method bodies with TF-IDF similarity >0.8 — propose DRY refactor
- [ ] R106 Entropy radar: track violations per module per session; if module has >10 new violations across 3 sessions, propose "architectural attention needed"
- [ ] R107 Dead code radar: schedule weekly dead_file_candidates scan; if any file appears 3 weeks running, propose removal
- [ ] R108 Proactive fix order: before /fix, compute topological sort of rule_deps.yml and propose the optimal sequence
- [ ] R109 After each commit, run git diff --stat and propose "/review <changed_file>" for any file with >50 lines changed
- [ ] R110 Test gap proposal: for every lib/ file with no test/ counterpart, surface as an opportunity with estimated effort

### R2. Session intelligence proposals

- [ ] R201 "Stuck" detector: if 3 consecutive inputs are questions (end with ?) without any /command, ask "what are you trying to accomplish?"
- [ ] R202 Context pressure proposal: when token_est crosses 70% of model context limit, auto-propose /checkpoint + /clear
- [ ] R203 Proactive resync: if git behind > 3 commits at session start, propose /resync before starting work
- [ ] R204 Memory crystallization: after 20 turns, propose "shall I remember the key decisions from this session?"
- [ ] R205 Idle ideation: when idle >5 min after a significant edit, generate 2 alternative approaches to what was just built
- [ ] R206 Cost proposal: when session cost exceeds $1.00, propose switching to haiku for routine tasks with estimated savings
- [ ] R207 Session topic drift: if conversation has shifted to a new domain, propose "should I save context and start fresh?"
- [ ] R208 Proactive benchmark: after fixing a performance violation, propose running bin/smoke to verify improvement

### R3. Architecture proposals

- [ ] R301 After scan clean, generate a one-paragraph architecture critique of the current module structure using STRUCTURAL_HONESTY rule
- [ ] R302 Design it twice trigger: when proposing a complex solution (>3 files affected), auto-generate a simpler alternative
- [ ] R303 Council convocation: when the same violation appears 5+ times across files in one session, propose elevating to soul.yml kernel law
- [ ] R304 Soul evolution proposal: after each session, diff axioms applied vs axioms surfaced — if 3+ new patterns emerged, propose adding to soul.yml
- [ ] R305 God class trajectory: if a file has grown >20 lines per session for 3 sessions, warn before it hits the god_class threshold
- [ ] R306 Proactive decoupling: when LAW_OF_DEMETER fires between two specific modules in both directions, propose an interface/adapter
- [ ] R307 Missing abstraction proposal: when same literal appears in 3+ files, propose extracting to a named constant or value object
- [ ] R308 Layer purity check: after any change to lib/now/, check if it calls lib/judge/ directly (should be via Pipeline) — propose routing fix

### R4. Proposal output quality

- [ ] R401 Proposals should include estimated tokens/cost for implementing the suggestion
- [ ] R402 Each proposal should include a confidence score (0.0-1.0) based on evidence strength
- [ ] R403 Proposals should be ranked by (confidence × impact) not just weight
- [ ] R404 Proposals older than 24h without action should auto-expire and be replaced
- [ ] R405 Proposals should include a "reject" action that logs the rejection to learnings for future tuning
- [ ] R406 /propose command should show the proposal reasoning chain, not just the action string
- [ ] R407 SoulProposals.md entries should include a one-line diff of what changed since the proposal was generated
- [ ] R408 Proposal engine should self-evaluate: track which proposals were acted on vs ignored; tune weights accordingly
- [ ] R409 Proactive proposals should never interrupt a user turn — queue for display at next REPL prompt
- [ ] R410 Add proposal type: "opportunity" (additive) vs "violation" (corrective) — show separately in UI

## S — Git Archaeology: Lost Concepts from master.yml / master.json Predecessors

### S1: Persona System (v49.7–v49.75 — fully specified, never ported)

- [ ] S101 Port full persona system: ronin (stoic/decisive), lawyer (Norwegian law/barnevernet), hacker (OpenBSD/CVE), architect (BIM/parametric), sysadmin (pf/httpd/vmm), trader (DeFi/technicals), medic (PubMed/disclaimer) — each with voice pitch/rate, greeting phrase, focus domain, knowledge sources
- [ ] S102 Persona switching command: `/persona ronin` changes identity, voice pitch/rate, greeting style, knowledge sources for TTS and LLM prompts
- [ ] S103 Each persona carries its own knowledge_sources list (lovdata.no, cve.mitre.org, archdaily.com, man.openbsd.org, pubmed.ncbi.nlm.nih.gov) — inject into LLM context on switch
- [ ] S104 Medic persona requires disclaimer injection: "Not a substitute for professional medical advice" appended to every medical response
- [ ] S105 Persona voice config feeds directly into face.js TTS pitch/rate sliders — ronin speaks slow+low, medic speaks measured+mid

### S2: Meta-Analysis / Self-Evolution (v49.8 — specified, never wired)

- [ ] S201 After each session, run meta_analysis capture: "What new techniques were discovered?", "What patterns kept recurring?", "What manual steps could be automated?" — write answers to runtime/session_learnings.md
- [ ] S202 Self-evolution trigger: after every significant refactor, run MASTER on itself with full scan+sweep, capture delta, commit changes
- [ ] S203 Session capture question: "What questions yielded good results?" — add high-yield prompts to data/patterns.yml for reuse
- [ ] S204 Meta-analysis question: "What external tools/APIs were useful?" — append to data/openbsd.yml providers section if OpenBSD-related
- [ ] S205 Trigger: "After session with good outcomes — ask: what made this work? Codify it." — implement as /capture command that writes to data/soul.yml learned_behaviors
- [ ] S206 learned_smells[] array in data config was designed to accumulate session-discovered patterns — wire it to scan engine as dynamic extra rules

### S3: 7-Phase Workflow with Gates (v49.25 — fully specified, never enforced)

- [ ] S301 Implement /phase command: show current phase (discover/analyze/ideate/design/implement/validate/deliver), gates that must pass, what's blocking
- [ ] S302 discover phase gates: no_vague_words (detect "it", "things", "stuff" in problem statement), audience_identified, success_measurable
- [ ] S303 analyze phase gates: components_distinct (no overlapping responsibilities), dependencies_acyclic (detect circular deps)
- [ ] S304 ideate phase gate: count_gte_15 (at least 15 alternatives generated), trade_offs_documented
- [ ] S305 design phase gates: interfaces_explicit (all public methods documented), errors_documented
- [ ] S306 implement phase gates: tests_pass, zero_violations (council reports clean)
- [ ] S307 validate phase gates: zero_test_failures, edge_cases_covered (nil/empty/max/unicode checked)
- [ ] S308 deliver phase gates: deployed (rcctl status master = active), monitoring_configured (uptime check present)
- [ ] S309 Phase transitions are gated — /phase next refuses if any gate is red; lists exactly what must be fixed

### S4: Profiles / Principle Groups (v49.25 — specified, not implemented)

- [ ] S401 Implement scan profiles: quick (core axioms only), full (all rules), axioms_only, solid_focus (SOLID + axioms), critical (veto-severity only)
- [ ] S402 /scan --profile quick uses group:quick rule subset [clarity, KISS, SRP, names, small_functions] — fast feedback loop
- [ ] S403 principle_groups map: group:axioms, group:solid, group:coding, group:clean_code, group:ui, group:llm, group:operations, group:design, group:architecture
- [ ] S404 /scan --profile critical only surfaces :error + :veto severity findings — zero noise for urgent triage
- [ ] S405 Default profile in rules.yml / soul.yml selectable at boot time, overridable per scan invocation

### S5: Conflict Resolution Rules (v49.75 — specified, not wired to rule engine)

- [ ] S501 Implement conflict resolver: when DRY fix would conflict with WET/AHA principle, apply "fewer than 3 duplications → favor WET" resolution automatically
- [ ] S502 Conflict rule: "clarity conflicts with simplicity → favor clarity" — when both fire, suppress simplicity finding
- [ ] S503 Conflict rule: "fix introduces higher-priority violation → reject fix" — FixLoop must recheck severity after every patch application
- [ ] S504 Log all conflicts to runtime/conflict_log.jsonl: {rule_a, rule_b, resolution, file, line, timestamp}
- [ ] S505 Conflict resolution strategy in soul.yml: highest_priority_wins, prompt_user: false — make this configurable

### S6: Hooks System (v49.25 — specified, never wired)

- [ ] S601 on_violation_found hook: append to .constitutional_violations.jsonl per file, per session
- [ ] S602 on_cost_threshold hook: warn user when cumulative session cost exceeds 50% of max_per_session
- [ ] S603 Hook architecture: hooks[] array in soul.yml, each entry {event, action, params} — load at boot, fire via EventBus
- [ ] S604 Hook events needed: on_violation_found, on_fix_applied, on_cost_threshold, on_session_start, on_session_end, on_phase_transition, on_convergence
- [ ] S605 Git hook integration: pre-commit hook that runs /scan --profile critical and blocks commit if :error findings exist

### S7: Multi-Model Consensus (v49.25 — specified, disabled=false toggle never built)

- [ ] S701 Consensus mode: send same prompt to 3 models (claude-sonnet, glm-4, kimi-k2), require 2/3 agreement before applying fix
- [ ] S702 Consensus result shows dissenting model's reasoning — surfaces when models disagree on correctness
- [ ] S703 Consensus used only for :error findings and architecture decisions — too expensive for :warning/:info
- [ ] S704 Failover sequence: fast→code→medium→strong with exponential backoff (cooldown_seconds: 300, max_retries: 2)
- [ ] S705 Model tier routing: detect_lexical → fast model, code_generation → code model, architecture → strong model

### S8: ReviewCrew / Multi-Agent Parallel Analysis (v50.8 — built, then deleted)

- [ ] S801 Restore ReviewCrew: SecurityAgent + PerformanceAgent + StyleAgent + ArchitectureAgent run in parallel via Async
- [ ] S802 BaseAgent interface: analyze(code, file_path) → findings array; add_finding(severity:, category:, message:, line:, suggestion:)
- [ ] S803 SecurityAgent patterns: eval(), system(), exec(), backtick execution, File.read with user params, hardcoded passwords/API keys, .constantize, dynamic send(), SQL interpolation, html_safe — each with severity and suggested fix
- [ ] S804 Deep security scan trigger: if critical pattern found OR file name matches /auth|session|user|admin|payment|credential/ → send to LLM for OWASP Top 10 audit
- [ ] S805 ReviewCrew synthesizes findings from all agents via LLM: generates one consolidated summary rather than dumping 4 separate reports
- [ ] S806 ReviewCrew progress reporting: "SecurityAgent: started/done (0.8s)", parallel timing visible in CLI output

### S9: Safety System (v49.75 — specified, partially implemented)

- [ ] S901 Cost protection: max_per_file: $1.00, max_per_session: $10.00, warn_at: $0.50 — enforce hard caps, refuse further LLM calls when exceeded
- [ ] S902 Convergence guard: detect_loops (same violation toggling back) and detect_oscillation (A→B→A→B cycle) — abort fix loop with diagnostic
- [ ] S903 Fix validation: after applying fix, re-scan; if new violations introduced exceed max_new_violations: 0, rollback the fix
- [ ] S904 File locking: lock_timeout: 30s, stale_lock_age: 300s, lock_dir: .constitutional_locks — prevent concurrent scans on same file
- [ ] S905 Atomic write transactions: write to temp file, rename atomically — AstFixer already does this; extend to LLM fixes
- [ ] S906 Memory limits: max_violation_objects: 100_000 — prune oldest violations when exceeded; gc_every_n_iterations: 5
- [ ] S907 File validation: max_size_bytes: 10MB, max_lines: 10_000, check_binary: true, allow_symlinks: false before scanning
- [ ] S908 YAML safety: max_constitution_size: 10MB, load_timeout: 5s on soul.yml / rules.yml parse

### S10: Structural Analysis Questions (v49.7 — specified, never wired as checks)

- [ ] S1001 Config hierarchy checks: "Are top-level keys semantically grouped?", "Is there duplicate configuration?", "Is nesting depth appropriate (max 4)?"
- [ ] S1002 Code hierarchy checks: "Too many top-level modules? → Group into Core::, Util::, Features::", "Are related classes grouped? → Create namespaces"
- [ ] S1003 Bloater checks: long_method (>20 lines or >5 nesting), god_class (>300 lines or >10 methods), primitive_obsession, long_parameter_list (>4)
- [ ] S1004 Coupler checks: feature_envy (method uses another class's data more than its own), inappropriate_intimacy, message_chains (a.b.c.d.e)
- [ ] S1005 Dispensable checks: dead_code (after return/raise), lazy_class (only delegates), duplicate_code (Rule of Three)
- [ ] S1006 Architecture checks: cyclic_dependency (module A requires module B requires module A), scattered_functionality (same concern in 3+ places)
- [ ] S1007 Simulated execution checks: nil input, empty string/array, max int, very long string, unicode, invalid JSON, truncated file, injection attempts — generate edge case test stubs

### S11: Preserve Section (v49.72 — specified, never enforced in MASTER's own outputs)

- [ ] S1101 Enforce preserve rules in all MASTER output: boot_message must be 5-line dmesg style, never collapsed to one line
- [ ] S1102 Preserve: diagnostic_output is structured multi-line by design — "Polish means refine wording, not delete output"
- [ ] S1103 Preserve: spinner_feedback shows elapsed time + status — never remove progress indicators
- [ ] S1104 Preserve: help text must be scannable (command + syntax + description + at least one example) — /help output linted against this
- [ ] S1105 Preserve: polish_rules check — before any MASTER self-edit, verify: "'Minimize' applies to tokens in prompts, not diagnostic output"

### S12: Cross-File DRY / Sprawl Detection (v49.13 — specified, never implemented as scanner pass)

- [ ] S1201 Cross-file DRY: detect duplicate_function_calls (same File.read with identical options in 3+ files → extract Core.read_file)
- [ ] S1202 Cross-file DRY: detect duplicate_glob_patterns (same Dir.glob pattern across 3+ files → extract Core.glob_files)
- [ ] S1203 Cross-file DRY: detect magic_number_spread (same literal integer across 3+ files → extract shared constant)
- [ ] S1204 Cross-file DRY: detect copy_paste_blocks (5+ line identical blocks across files → extract to module)
- [ ] S1205 Cross-file DRY: detect parallel_hierarchies (similar class/module structures in different files → merge or share base)
- [ ] S1206 Cross-file DRY: detect scattered_config (same configuration key set in 3+ places → consolidate to soul.yml)
- [ ] S1207 Sprawl detection: warn when concern appears in 4+ files that aren't a natural family (e.g., cost logic in cli.rb + scanner + fixer + proposer)
- [ ] S1208 Anti-sprawl prescan: before any fix session, run tree analysis to identify sprawl candidates; report before touching files

### S13: Biases / Personality Calibration (v0.5.x — existed in .backups, never ported)

- [ ] S1301 Port biases.yml concept: explicit list of cognitive biases MASTER should resist (confirmation bias, sunk cost, authority bias, recency bias)
- [ ] S1302 Biases config has countermeasures per bias: "When confirmation bias detected → explicitly generate 3 counter-arguments before concluding"
- [ ] S1303 Bias detection in MASTER's own proposed fixes: if fix only confirms the scan result without considering alternatives → flag as confirmation bias
- [ ] S1304 Recency bias guard: don't weight most-recent violation above earlier ones when prioritizing fix order — use severity × frequency × age

### S14: Roadmap / Future Capabilities (v49.74 — listed, never tracked)

- [ ] S1401 Mobile deployment: Termux integration with Android sensors (mic, camera, accelerometer for context-awareness)
- [ ] S1402 Threat detection: audio/video anomaly analysis using Replicate models
- [ ] S1403 Physical security alerts: pf.conf anomaly detection → push notification to mobile
- [ ] S1404 Replicate integration for image/video generation: flux-2-klein-4b, veo-3.1-fast, seedance-1.5-pro, qwen3-tts
- [ ] S1405 Social agents: Snap/WhatsApp/TikTok/Instagram content generation workflows
- [ ] S1406 Scraper agent: research mode that fetches knowledge_sources for active persona (PubMed for medic, CVE for hacker, Lovdata for lawyer)
- [ ] S1407 MOTD: feature advertisement in dmesg boot banner — rotate new capability spotlight on each boot

### S15: Prescan + Anti-Pattern Catchphrases (v49.13 — specified, partial)

- [ ] S1501 Prescan sequence: always run tree+clean before touching any file — detect sprawl, orphans, and lock files first
- [ ] S1502 Personality catchphrases wired to real events: "Backing up first." before write, "That looks risky. Confirm?" before destructive op, "Checking for side effects..." before LLM fix, "Clean. Moving on." after zero findings
- [ ] S1503 Bodyguard mode: block rm -rf, dd, mkfs without explicit --force flag; warn on doas escalation; check file permissions before write
- [ ] S1504 On blockers: "finds workarounds, suggests alternatives" — if primary approach fails, MASTER generates 3 alternative approaches automatically

## T — Borrowed Concepts from aider, OpenCrabs, Codex CLI, Grok Build, Hermes Agent

### T1: Memory Architecture (from OpenCrabs / Hermes)

- [ ] T101 3-tier brain architecture: MEMORY.md (user-curated durable facts) + daily session logs (auto-compacted) + hybrid search layer — separate durable vs ephemeral knowledge
- [ ] T102 Hybrid search with RRF: Reciprocal Rank Fusion combining FTS5 keyword (BM25) + vector embeddings — eliminates false negatives from pure keyword or pure semantic alone
- [ ] T103 Brain file templates: SOUL.md (identity/values), IDENTITY.md (persona), MEMORY.md (facts index), AGENTS.md (tool registry), TOOLS.md (skill library) — structured retrieval vs flat notes
- [ ] T104 Editable brain between turns: brain files remain plaintext-editable by user, not locked in vectordb — enables human-AI co-curation of MASTER's knowledge
- [ ] T105 FTS5-only VPS mode: zero-embedding fallback using pure keyword search — cost-appropriate for OpenBSD VPS with no GPU
- [ ] T106 Tree-sitter + SQLite AST cache: cache parsed ASTs to avoid re-parsing unchanged files — apply to MASTER's Prism structural scan across multi-file sessions
- [ ] T107 Session search with LLM summarization: cross-session memory recall via FTS5 with LLM-generated summaries of past sessions, not raw retrieval
- [ ] T108 Token-budgeted context map: MASTER's file map output capped at configurable token limit (default 1,024) via relevance ranking — prevent context explosion
- [ ] T109 Live context usage indicator in REPL: display "ctx: 45K/200K" + per-message cost breakdown in prompt line — real-time cost transparency
- [ ] T110 Auto-compaction at 70% threshold: when approaching token limits, summarize context intelligently rather than hard-cut at 100%

### T2: Self-Improvement / Learning Loop (from OpenCrabs / Hermes)

- [ ] T201 Feedback ledger: SQLite table logging every tool call result, user correction, and provider error — enables self-improvement analysis and audit trail
- [ ] T202 Autonomous skill creation: after complex task completion, auto-generate Skill Documents in MASTER/data/skills/ following agentskills.io portable format
- [ ] T203 Skill improvement nudges: internal prompts fire at session end asking MASTER to evaluate whether session outcome warrants skill persistence
- [ ] T204 Recursive self-analysis tool: /analyze-self command queries feedback ledger, identifies systematic optimization opportunities and proposes rule updates
- [ ] T205 Brain modification logging: RSI improvements logged to runtime/rsi_improvements.md — audit trail of MASTER self-modifications distinct from git history
- [ ] T206 Upstream template sync: auto-detect new MASTER releases, merge fresh soul/rules sections without overwriting user customizations — idempotent self-update
- [ ] T207 Skill ranking by recency: when loading skills into context, prefer recently-used over older ones — tighten learning loop
- [ ] T208 Improvement threshold gates: only persist knowledge crossing minimum-utility threshold to skill library — prevent noise accumulation
- [ ] T209 Closed learning loop: memory, skills, and session metadata generated during execution, not logged post-hoc
- [ ] T210 User correction ledger: explicitly log every correction user makes to MASTER actions — train future behavior via logged patterns in data/corrections.jsonl

### T3: Code Repair Strategies (from aider)

- [ ] T301 Architect/Editor two-model pattern: strong model (opus) plans changes in natural language; fast model emits concrete diffs — separate strategy from execution cost
- [ ] T302 Unified diff edit format: modified unified diff with @@ hunks optimized for streaming LLM responses — lower token cost than full file replacement
- [ ] T303 Search/Replace block format: EditBlockCoder pattern — emit only changed parts, not full file rewrites — apply as LLM output format in FixLoop
- [ ] T304 Multiple coder backends: pluggable fix strategies (EditBlockCoder, WholeFileCoder, UnifiedDiffCoder, ArchitectCoder) — select per file type and repair scenario
- [ ] T305 Real-time diff visualization: stream diffs as LLM generates them — enable user course-correction mid-generation before committing
- [ ] T306 Atomic git commits with LLM-generated messages: every MASTER fix commits with AI message — no "wip" bundling; git log reads as changelog
- [ ] T307 Pre-commit user-edits preservation: stash/commit local changes before running repairs — prevent user work loss if agent makes mistakes
- [ ] T308 Linting/testing integration loop: after every code generation, run rubocop/tests automatically — verify correctness, not just write
- [ ] T309 Watch mode: file system event monitoring to respond to AI comments in editor without PTY — editor-based pair programming workflow

### T4: Execution & Orchestration (from Codex CLI / Grok Build / Hermes)

- [ ] T401 Parallel subagent spawning: child agents execute specialized tasks in parallel threads within single session — no external tooling needed
- [ ] T402 spawn_agents_on_csv pattern: batch process work items by spawning parallel subagents per row — scale simple workflows automatically
- [ ] T403 Isolated subagent workstreams: each subagent has independent memory/tools, collapsing multi-step pipelines into zero-context-cost turns
- [ ] T404 Queue/worker pattern: async agent coordination via Redis/SQLite queue — one agent enqueues repair tasks, workers dequeue without blocking REPL
- [ ] T405 MCP server exposure: expose MASTER as MCP server — enables orchestration by Agents SDK, Claude Code, or external pipelines
- [ ] T406 Plan mode with approval gates: MASTER generates execution plan, user approves/edits before any file is touched — human-in-the-loop safety
- [ ] T407 Plan diffs before execution: each approved plan step shows clean before/after diff preview — transparency before agent modifies files
- [ ] T408 Worktree isolation: isolated Git worktrees per subagent prevent file conflicts in parallel fix sessions
- [ ] T409 Provider-agnostic model routing: LiteLLM-compatible abstraction layer supports 100+ providers without code changes — future-proof model switching
- [ ] T410 Conditional tool invocation: 40+ built-in tools with RPC-callable scripts — eliminate multi-step pipelines per repair turn

### T5: UX & Interaction Patterns (from aider / OpenCrabs / Grok Build)

- [ ] T501 Voice-to-code interface: speech-to-text pipeline enabling hands-free pair programming — Osman/Pernille TTS already present; add STT input mode
- [ ] T502 Multimodal input: accept images and web pages as additional context — paste screenshot of error, get targeted fix
- [ ] T503 Interactive usage dashboard: /usage command shows daily activity charts, cost by model/session — cost transparency UI
- [ ] T504 Native subagent view: fullscreen terminal UI with mouse support showing parallel subagent progress — not raw text logs
- [ ] T505 AGENTS.md plugin discovery: agents auto-detect custom skills, hooks, MCP servers in AGENTS.md — zero-registration tool/skill system
- [ ] T506 Interactive diff approval: show each proposed hunk with y/n/e(dit)/s(kip) prompt before applying — fine-grained human control
- [ ] T507 Color-coded severity in diff: :error findings highlighted red, :warning yellow, :info dim — instant visual triage
- [ ] T508 Session replay: /replay command re-applies all fixes from a previous session to a fresh checkout — deterministic reproducibility
- [ ] T509 Multiline input mode: Ctrl+J for multi-line REPL entry — write complex instructions without escaping newlines

### T6: Safety & Sandboxing (from Codex CLI / OpenCrabs)

- [ ] T601 Sandbox mode flag: --sandbox enables restricted execution context for untrusted agent operations — pledge(2) on OpenBSD
- [ ] T602 Tool execution logging: every tool invocation and result recorded in feedback ledger — rollback and audit without git
- [ ] T603 Config inheritance for subagents: subagent configs inherit parent unless explicitly overridden — prevent privilege escalation in spawned agents
- [ ] T604 Provider error isolation: feedback ledger tracks provider failures separately — enable fallback chains without user intervention
- [ ] T605 Automatic rollback on oscillation: if fix loop detects A→B→A→B cycle, auto-revert to pre-session state and report deadlock

### T7: Configuration & Rule Systems (from Hermes / Codex / OpenCrabs)

- [ ] T701 Portable skill document format (agentskills.io): each MASTER skill in MASTER/data/skills/<name>.md — reusable across agent frameworks
- [ ] T702 Model switching via CLI: /model gpt-4o switches active provider without restart — per-task cost/latency optimization
- [ ] T703 AGENTS.md as tool registry: declarative manifest listing available MASTER tools, skills, hooks, MCP endpoints
- [ ] T704 Conditional tool availability: tools activated by file type (Prism tools only for .rb, jq tools only for .json) — reduce noise in LLM tool list
- [ ] T705 Plugin hot-reload: add new tool/skill file to data/skills/ and MASTER picks it up at next prompt without restart

### T8: Repo Map & Context Management (from aider)

- [ ] T801 Repository map: generate ranked summary of all files + their public API signatures — send as compressed context, not full file content
- [ ] T802 Graph relevance ranking: score files by mention frequency in user's request + recent edit history — inject most-relevant into context first
- [ ] T803 Symbol-level context: extract def/class/module names per file into map — LLM knows what exists without reading entire file
- [ ] T804 Stale map invalidation: invalidate AST cache for files modified since last parse — always fresh structural context
- [ ] T805 Cross-repo context: when working across multiple apps (brgen, baibl, hjerterom), build unified cross-repo map — detect shared violations

### T9: OpenCrabs-Specific Patterns

- [ ] T901 /rebuild command: hot-restart MASTER process via exec() without losing session state — instant reload after source edits
- [ ] T902 Brain-files-per-turn: include MASTER's own soul/rules/patterns YAML as compressed context in every LLM turn — MASTER always knows its own constitution
- [ ] T903 Daily log compaction: end-of-day job condenses session logs to ≤10 bullet points, discards raw transcripts — bounded memory growth
- [ ] T904 Workspace-aware indexing: index varies by current working directory — different brain for MASTER vs DEPLOY vs web/
- [ ] T905 IDENTITY.md persona file: separate from MEMORY.md — defines WHO MASTER is, not what it knows; re-read on every session start

### T10: aider-Specific Patterns

- [ ] T1001 Linting before commit: run rubocop (dry-run) on every changed file before creating git commit — block commit on :error findings
- [ ] T1002 LLM-generated commit messages: after every fix, ask fast model to generate commit message summarizing the change — S&W style
- [ ] T1003 Architect-then-edit flow: for files >200 lines, send to strong model for architecture plan, then send plan to fast model for implementation
- [ ] T1004 Edit format negotiation: try preferred edit format, fall back to whole-file if LLM produces malformed diff
- [ ] T1005 In-chat file references: @file.rb in REPL automatically includes file content in next LLM call — fast targeted context injection

## U — Preventing Shallow Skimming: Deep Semantic Comprehension (item 8)

### U1: LLM Prompt Architecture to Force Depth

- [ ] U101 Before any scan/fix LLM call, inject "chain-of-thought depth contract": "Before answering, enumerate all structural properties of this code: module hierarchy, data flow, side effects, implicit invariants, edge cases for nil/empty/max/unicode input. Only then proceed."
- [ ] U102 Add "anti-skim system message" to soul.yml identity section: "Never skim. Every code artifact has a semantic iceberg — surface syntax is 10%, behavior is 90%. Excavate to bedrock before proposing changes."
- [ ] U103 For every file read during scan, require MASTER to emit a 3-line "semantic summary" before findings: what it does, what it assumes, what could break — stored in scan context, not output
- [ ] U104 Implement "second-pass obligation": after initial scan findings, always re-read the same file with findings in context and ask "what did I miss that a senior engineer would catch?"
- [ ] U105 Require explicit enumeration of cross-file dependencies before any multi-file fix: "List all other files that import, call, or are called by this file" — prevents fixes that break callers
- [ ] U106 Add "assumption audit" step: before each LLM fix call, list all assumptions the proposed fix makes (input types, object states, concurrency) and validate each assumption against the codebase
- [ ] U107 Require "edge case checklist" for every proposed change: nil input, empty collection, max value, concurrent access, network failure, file permission failure — LLM must address each or explain why N/A
- [ ] U108 "Inversion test" prompt: after proposing a fix, ask "if this fix is wrong, what would break, where, and when?" — forces adversarial self-review before applying
- [ ] U109 "Diff impact analysis" before applying: enumerate every caller of a changed method/class and verify the signature change is backward-compatible
- [ ] U110 Require LLM to state the design pattern being used (or violated) before proposing a structural fix — prevents pattern-blind refactoring

### U2: Research Integration (ar5iv.org + GitHub)

- [ ] U201 Before implementing any new detection rule, fetch ar5iv.org search results for the smell name (e.g., "cyclomatic complexity Ruby" → ar5iv) — cite the academic basis in the rule's description
- [ ] U202 For each rules.yml principle (SOLID, POLA, YAGNI, etc.), fetch the canonical academic paper from ar5iv.org and store abstract in data/research/<principle>.md — ground rules in theory
- [ ] U203 GitHub corpus validation: before adding a new rule, search GitHub for 10 real violations of that pattern in popular Ruby repos (rails/rails, Shopify/*, fastlane/fastlane) — confirm the smell is real and frequent
- [ ] U204 Implement /research <rule_id> command: fetches top 3 ar5iv papers + top 5 GitHub examples for the rule — shows evidence base before user acts on a finding
- [ ] U205 Add "literature review" field to each rule in rules.yml: {paper: "ar5iv URL", github_example: "URL"} — makes every rule traceable to evidence
- [ ] U206 Periodic corpus scan: weekly job fetches trending Ruby repos from GitHub API, runs MASTER scan on top 20, updates rule frequency statistics in data/rule_stats.yml
- [ ] U207 Rule effectiveness tracking: for each finding, track whether the user accepted/rejected the fix — rules with >80% rejection rate get flagged for review in data/rule_stats.yml
- [ ] U208 False positive audit: when a user overrides a finding, log the override with file+line+rule+reason in runtime/overrides.jsonl — accumulate to discover systematic false positives
- [ ] U209 "Related work" prompt: before proposing a novel abstraction, check if aider/rubocop/reek/flog already has a rule for it — avoid reinventing; link to existing tool if better
- [ ] U210 ar5iv weekly digest: fetch 10 recent papers tagged "code quality" or "static analysis" and distill key findings into a weekly entry in data/research/weekly_digest.md

### U3: Depth Enforcement in MASTER's Own Processing

- [ ] U301 Implement "read before fix" hard gate: MASTER cannot propose a fix for file X unless it has read file X in the current session — prevents hallucinated context
- [ ] U302 "Semantic fingerprint" per file: hash of {line_count, class_count, method_count, def_names[], constant_names[]} — if fingerprint changes between read and fix, re-read before applying
- [ ] U303 Multi-pass scan mandate: every file goes through at minimum lexical → structural → semantic passes before findings are finalized — no early exit on first pass
- [ ] U304 "Dependency graph" before bulk fix: build module→module dependency graph for the target directory; fix in topological order, leaves first
- [ ] U305 Cross-file DRY pass: after per-file scan, run a mandatory cross-file pass looking for duplicate patterns across the whole scan batch — cannot be skipped
- [ ] U306 "Confidence score" on each finding: 0.0–1.0 based on regex certainty vs AST certainty vs LLM inference; only surface findings above 0.7 confidence by default
- [ ] U307 Finding deduplication: before reporting, cluster findings by root cause — if 8 files have the same smell from a shared ancestor, report the ancestor once, not 8 times
- [ ] U308 "Impact radius" annotation on every finding: {files_affected: N, callers: M, severity_multiplier: S} — high-impact findings shown first regardless of per-file severity
- [ ] U309 Require method-level test coverage check before marking any rule violation as fixed: if the fixed method has no test, flag as "fix unverified — add test"
- [ ] U310 "Ghost smell" detection: pattern that appears correct but conceals a deeper problem (e.g., guard clause that hides a missing abstraction) — requires semantic LLM analysis, not just lexical

### U4: Cognitive Load / Anti-Skim UI Patterns

- [ ] U401 Show scan progress as "files understood / files skimmed" not just "files scanned" — forces acknowledgement of depth
- [ ] U402 "Deep mode" flag: /scan --deep forces all three passes + cross-file analysis + ar5iv lookup for each finding — explicit commitment to thoroughness
- [ ] U403 After each LLM response, display: "Depth: {lexical|structural|semantic|cross-file} | Evidence: {regex|AST|LLM|research}" — makes reasoning basis visible
- [ ] U404 "Confidence histogram" in scan summary: show distribution of finding confidence scores — reveals whether the scan was shallow or deep
- [ ] U405 "Unknown-unknowns prompt": at end of each session, ask LLM "What questions about this codebase should I have asked but didn't?" — surfaces blind spots
- [ ] U406 "Red team" mode: after proposing a fix set, spawn a second LLM call with "You are a senior engineer reviewing this diff for mistakes. Find every problem." before presenting to user
- [ ] U407 Require findings to have "why this matters" annotation beyond the rule message — e.g., "CQS violation here makes this method untestable because…"
- [ ] U408 Show "smell genealogy" for each finding: which principle → which rule → which pattern → which line — full traceability from axiom to code
- [ ] U409 "Attention heatmap": track which lines of each file received the most LLM attention tokens — reveal coverage gaps
- [ ] U410 Block "batch-and-forget" pattern: if MASTER proposes >10 fixes without asking user to verify one, pause and require acknowledgment before continuing

### U5: MASTER Self-Compliance (Applies to MASTER's Own Code)

- [ ] U501 MASTER must run its own deep scan on itself before each release — zero findings required to push
- [ ] U502 Every new rule must have a test in spec/judge/scan/ that catches at least one known real violation and passes on at least one clean counterexample
- [ ] U503 MASTER's own LLM prompt templates must pass NO_MAGIC_NUMBERS, NO_COLUMN_ALIGN, COMMENTS_AS_DEODORANT — prompts are code
- [ ] U504 Every ar5iv research reference must be verified (live URL, correct abstract) before being added to data/research/ — no hallucinated citations
- [ ] U505 MASTER's proposal engine must score its own proposals by evidence strength: regex-only proposals labeled "low confidence", AST+research-backed labeled "high confidence"

## V — Rename Opportunities: Files, Directories, Classes, Methods, Variables (item 9)

### V1: File and Directory Renames

- [ ] V101 `/lib/ground/swallow.rb` → `/lib/ground/tolerated_error_logger.rb` — "Swallow" is cryptic idiom
- [ ] V102 `/lib/judge/scan/detection_pipeline.rb` → `/lib/judge/scan/finding_detector.rb` — "DetectionPipeline" is generic
- [ ] V103 `/lib/converge/engine.rb` → `/lib/converge/convergence_executor.rb` — "Engine" is too broad
- [ ] V104 `/lib/ground/brain_overlay.rb` → `/lib/ground/system_prompt_builder.rb` — reveals true purpose
- [ ] V105 `/lib/reach/base.rb` → `/lib/reach/tool_write_base.rb` — "Base" says nothing
- [ ] V106 `/lib/builder.rb` → `/lib/app_container_builder.rb` — clarify what it builds
- [ ] V107 `/lib/judge/scan/rules/` → `/lib/judge/scan/violation_rules/` — disambiguate from convergence rules
- [ ] V108 `/lib/ground/axioms/` → `/lib/ground/constitutional_axioms/` — clarify scope
- [ ] V109 `/lib/judge/council/` → `/lib/judge/consensus_council/` — reveal the consensus mechanism
- [ ] V110 `/lib/now/stages/` → `/lib/now/pipeline_stages/` — clarify they're pipeline stages
- [ ] V111 `/lib/now/routing/` → `/lib/now/llm_routing/` — clarify it routes LLM calls
- [ ] V112 `/lib/ground/orders/` → `/lib/ground/standing_order_handlers/` — type specificity
- [ ] V113 `/lib/memory.rb` → `/lib/session_memory_manager.rb` — too generic
- [ ] V114 `/lib/learnings.rb` → `/lib/learning_ledger.rb` — specific to ledger pattern
- [ ] V115 `/lib/orient.rb` → `/lib/startup_orientation.rb` — "orient" is cryptic
- [ ] V116 `/lib/pressure_engine.rb` → `/lib/request_pressure_monitor.rb` — what pressure?
- [ ] V117 `/lib/plugin.rb` → `/lib/plugin_base.rb` — clarify it's an abstract base

### V2: Class and Module Renames

- [ ] V201 `Converge::Rule` → `Converge::ConfigurableRule` — disambiguate from `Judge::Scan::Rule`
- [ ] V202 `Converge::Engine` → `Converge::ConvergenceExecutor` — "Engine" is overloaded
- [ ] V203 `Judge::Scan::Rule` → `Judge::Scan::ViolationDetectionRule` — reveals intent
- [ ] V204 `Judge::Scan::Scanner` → `Judge::Scan::RuleBasedScanner` — clarify mechanism
- [ ] V205 `Ground::Policy` → `Ground::PolicyHelper` — it's a helper module, not a policy definition
- [ ] V206 `Ground::Swallow` → `Ground::ToleratedErrorLogger` — idiomatic but opaque
- [ ] V207 `Loop::Homeostat` → `Loop::HomeostasisDrive` — what does Homeostat do?
- [ ] V208 `Ground::BrainOverlay` → `Ground::SystemPromptAssembler` — "Brain" is metaphor, not mechanism
- [ ] V209 `Voice::Soul` → `Voice::IdentityDocumentManager` — manages SOUL.md, not a soul
- [ ] V210 `Judge::Swarm::Coordinator` → `Judge::Swarm::ConsensusVotingCoordinator` — reveals voting
- [ ] V211 `Reach::CircuitBreaker` → `Reach::ProviderCircuitBreaker` — clarify it's for LLM providers
- [ ] V212 `Now::Routing::ModelRouter` → `Now::Routing::LLMModelRouter` — clarify domain
- [ ] V213 `Judge::LLMDispatcher` → `Judge::LLMRequestDispatcher` — "Dispatcher" alone is vague
- [ ] V214 `Ground::Memory` → `Ground::PersistentMemoryStore` — clarify persistence backend
- [ ] V215 `Loop::Governor` → `Loop::ToolApprovalGovernor` — reveals what it governs
- [ ] V216 `Ground::StandingOrders` → `Ground::RecurringTaskOrchestrator` — military jargon → plain
- [ ] V217 `Judge::RepoEcology` → `Judge::RepositoryHealthAnalyzer` — "Ecology" is metaphorical
- [ ] V218 `Ground::KnowledgeStore` → `Ground::FixQualityRepository` — clarify content
- [ ] V219 `Voice::Personality` → `Voice::BehavioralPersona` — not just personality data
- [ ] V220 `Now::Pipeline` → `Now::RequestProcessingPipeline` — "Pipeline" is overused across codebase

### V3: Stage-Specific Class Renames

- [ ] V301 `Now::Stages::Council` → `Now::Stages::CodeReviewCouncil` — clarify context
- [ ] V302 `Now::Stages::Deliberate` → `Now::Stages::DecisionDeliberation` — more semantic
- [ ] V303 `Now::Stages::Guard` → `Now::Stages::InjectionGuard` — what does it guard against?
- [ ] V304 `Now::Stages::Intake` → `Now::Stages::RequestIntake` — clarify input domain
- [ ] V305 `Now::Stages::Lint` → `Now::Stages::CodeLinting` — verb-driven
- [ ] V306 `Now::Stages::Memo` → `Now::Stages::MemoizationStage` — clarify purpose
- [ ] V307 `Now::Stages::Memory` → `Now::Stages::MemoryInjection` — what does it do to memory?
- [ ] V308 `Now::Stages::Prune` → `Now::Stages::ContextPruning` — specific domain
- [ ] V309 `Now::Stages::Render` → `Now::Stages::ResponseRendering` — more semantic
- [ ] V310 `Now::Stages::Review` → `Now::Stages::QualityReview` — which review?
- [ ] V311 `Now::Stages::Route` → `Now::Stages::RequestRouting` — verb domain
- [ ] V312 `Now::Stages::Enhance` → `Now::Stages::MessageEnhancement` — specific
- [ ] V313 `Now::Stages::Infer` → `Now::Stages::IntentInference` — specific
- [ ] V314 `Now::Stages::Execute` → `Now::Stages::ToolExecution` — specific

### V4: Method Renames

- [ ] V401 `Judge::Scan::Scanner#parallel_each` → `#execute_in_parallel` — "each" implies enumeration not execution
- [ ] V402 `Judge::Scan::Scanner#parse_ruby` → `#parse_ruby_into_ast` — clarify return type
- [ ] V403 `Ground::Memory#semantic_recall` → `#retrieve_similar_memories` — "recall" is vague
- [ ] V404 `Ground::Memory#vector_recall` → `#retrieve_by_embedding_similarity` — explains mechanism
- [ ] V405 `Ground::Memory#tfidf_recall` → `#retrieve_by_term_frequency` — clarifies TF-IDF
- [ ] V406 `Ground::Memory#by_type` → `#retrieve_entries_by_type` — verb-driven
- [ ] V407 `Ground::Memory#auto_save` → `#auto_remember_from_text` — "save" is too generic
- [ ] V408 `Judge::Agent#ask` → `#ask_agent` — disambiguates from `ask_once`
- [ ] V409 `Judge::Agent#with_task_type` → `#set_task_type_context` — clarify temporary context setting
- [ ] V410 `Voice::Soul#measure_drift` → `#detect_restricted_section_changes` — clarify what "drift" is
- [ ] V411 `Reach::Base#safely` → `#execute_with_error_capture` — "safely" is too vague
- [ ] V412 `Ground::StandingOrders#event_match?` → `#order_matches_event?` — subject first
- [ ] V413 `Judge::Scan::DetectionPipeline#guess_medium` → `#infer_file_language` — "guess" implies uncertainty; "medium" is not the domain term
- [ ] V414 `Judge::RepoEcology#dead_file_candidates` → `#identify_unused_files` — verb-driven
- [ ] V415 `Judge::RepoEcology#similar_clusters` → `#identify_duplicate_file_clusters` — more explicit
- [ ] V416 `Trace::Metrics#check_threshold` → `#check_and_warn_if_threshold_exceeded` — complete intent
- [ ] V417 `Loop::Homeostat#publish_health_transition` → `#broadcast_health_status_change` — "transition" is vague
- [ ] V418 `Now::Routing::ModelRouter#effective_score` → `#compute_weighted_model_score` — clarify computation
- [ ] V419 `Reach::Base#commit_write` → `#write_file_atomically_with_undo` — reveals atomicity + rollback
- [ ] V420 `Judge::Council::Ideation` → `Judge::Council::IdeationPhase` — clarify lifecycle position

### V5: Constant Renames

- [ ] V501 `Judge::Scan::Scanner::POOL_SIZE` → `PARALLEL_WORKER_COUNT` — "pool" is implementation detail
- [ ] V502 `Judge::Scan::Scanner::SCAN_GLOB` → `SCANNABLE_FILE_GLOB_PATTERN` — unexpanded abbreviation
- [ ] V503 `Loop::Homeostat::DRIVES` → `HOMEOSTATIC_DRIVES` — add class context to standalone constant
- [ ] V504 `Ground::Evidence::THRESHOLDS` → `EVIDENCE_POLICY_THRESHOLDS` — add domain context
- [ ] V505 `Now::Routing::ModelRouter::ESCALATION_CHAIN` → `MODEL_TIER_ESCALATION_CHAIN` — clarify domain
- [ ] V506 `Voice::Soul::ABSOLUTE_PATTERNS` → `PROTECTED_IDENTITY_SECTION_PATTERNS` — "absolute" is vague
- [ ] V507 `Trace::Session::TOKENS_PER_CHAR` → `TOKEN_ESTIMATE_CHARS_PER_TOKEN` — clarify estimation direction
- [ ] V508 `Judge::Swarm::Coordinator::WORKER_TIMEOUT` → `WORKER_EXECUTION_TIMEOUT_SECONDS` — add units
- [ ] V509 `Ground::StandingOrders::ERROR_TRUNCATE` → `ERROR_MESSAGE_MAX_LENGTH` — clarify it's a length cap

### V6: Instance Variable / Parameter Renames

- [ ] V601 `@bus` in Scanner/Loop → `@event_bus` — expand abbreviation
- [ ] V602 `@deps` in Judge::Agent → `@dependencies` — expand abbreviation
- [ ] V603 `@workers` in Swarm → `@specialist_workers` — clarify role
- [ ] V604 `@store` in Ground::Memory → `@semantic_memory_entries` — descriptive
- [ ] V605 `@state` in CircuitBreaker → `@circuit_state` — remove ambiguity
- [ ] V606 `@model_router` → `@llm_model_router` — clarify domain
- [ ] V607 `@stages` in Pipeline → `@request_stages` — clarify content type
- [ ] V608 Local `pkt` → `violation_packet` in FixPipeline#run — expand abbreviation
- [ ] V609 Local `cfg` → `adapter_config` in DetectionPipeline — expand abbreviation
- [ ] V610 Local `ms` → `elapsed_milliseconds` in Pipeline#run_stage — full word + units
- [ ] V611 Local `vec` → `query_embedding` in Memory#context_summary — semantic name
- [ ] V612 Local `rate_err` → `rate_limit_error` in Agent#chat — expand abbreviation
- [ ] V613 `scan_depth:` parameter → `#scan` parameter `analysis_depth:` — clarify it's analysis depth, not file depth
- [ ] V614 `finding` parameter `fix:` → `suggested_fix:` — clarify it's a suggestion not a command
- [ ] V615 `timeout:` in fan_out → `worker_timeout_seconds:` — add type+units

## W — Codify Chat-Session Learnings into MASTER (item 9)

### W1: Voice and Output Discipline Not Yet in soul.yml

- [ ] W101 Codify unix-silence rule: "silence on success, text only when something noteworthy" — add as `unix_silence: true` in soul.yml absolute.aesthetic_rules; CLI scan with zero findings exits 0 with no output
- [ ] W102 Codify "exit codes carry meaning": scan violations = exit 1, internal errors = exit 2, LLM failure = exit 3 — wire to bin/cli; document in CONVENTIONS.md
- [ ] W103 Codify "do one thing well" per invocation: each MASTER subcommand must have exactly one output channel (stdout) and one error channel (stderr) — no mixing
- [ ] W104 Codify catchphrase discipline from v49.13: "Backing up first." before write, "Checking for side effects…" before LLM fix, "Clean. Moving on." on zero findings — add to voice/personality.rb output hooks
- [ ] W105 Codify no-sycophancy rule at runtime: soul.yml forbidden_openings: ["great question", "certainly", "of course", "absolutely", "happy to"] — applied at response generation time
- [ ] W106 Codify REGISTER_STABLE: hold token density and sentence length consistent per session; only shift register if user shifts — add as an invariant in voice/renderer.rb session state

### W2: Scanning and Review Discipline Not Yet Wired

- [ ] W201 Codify crit-fix-loop as default: any scan invocation runs autoiteratively until zero findings — no --loop flag required; wired at pipeline level so loop exits only on clean pass
- [ ] W202 Codify "read whole file, not grep snippets": scanner must load full file content before any rule runs — no streaming partial-reads that miss context; enforce in scanner.rb#load_file
- [ ] W203 Codify intent inference: when user input matches plain-language description (e.g. "fix face.js"), infer full workflow (read → crit → fix → commit) without requiring slash commands — wire in now/cli.rb intent router
- [ ] W204 Codify red-team pass: after every LLM fix proposal, a second call "find every flaw in this proposed fix" before applying — add as pipeline gate before write_back
- [ ] W205 Codify "second-pass obligation" as named pass in ScanPipeline: after finding collection, re-run with findings in context asking "what did I miss?" — not optional
- [ ] W206 Codify DEEP_SCAN_ONLY (already in soul.yml) as a hard scanner gate: if scan_depth != :deep, raise ConfigError — never silently downgrade
- [ ] W207 Codify ground_truth_check: before marking any file as fixed, re-read the file from disk and confirm the fix is present — no in-memory claim without verification

### W3: Token Efficiency (The 93% Win)

- [ ] W301 Implement prompt caching: add `cache_control: {type: "ephemeral"}` breakpoint to stable system-prompt prefix in lib/judge/llm_dispatcher.rb — reduces cost from ~$0.73/turn to ~$0.07/turn (93% cut)
- [ ] W302 Split personality layers: stable cached prefix (soul.yml + rules summary + ruby_style) + dynamic per-turn suffix (context, violations, file content) — cache boundary between the two
- [ ] W303 Compress rule descriptions sent to LLM: include rule ID + one-sentence description only; full YAML is for code, not LLM context — reduces system prompt by ~60%
- [ ] W304 Deduplicate session context: if same file content already sent this session, replace with "same as previous #{sha256[0..7]}" — avoids re-tokenizing unchanged files across loop iterations
- [ ] W305 Codify budget.yml enforcement: max_per_session cap triggers hard stop with "session budget exhausted" message and cost summary — no silent over-spend

### W4: OpenBSD Stack Discipline Not Yet in openbsd.yml

- [ ] W401 Codify relayd-first rule: any generated config that references nginx must be flagged as ERROR by MASTER's own linter — add as lexical rule NGINX_BANNED in web_rules.rb with applies_to: %i[conf yaml sh]
- [ ] W402 Codify httpd-for-acme-only: if httpd.conf has any server block other than /.well-known/acme-challenge/, flag as violation
- [ ] W403 Codify "never sudo on OpenBSD": any shell script generated by MASTER using `sudo` instead of `doas` fires SUDO_BANNED rule
- [ ] W404 Codify "never pkg_add base tools": scanner flags `pkg_add relayd`, `pkg_add httpd`, `pkg_add pf` as INSTALL_BASE_TOOL error
- [ ] W405 Codify pledge/unveil as defaults: any new OpenBSD daemon written by MASTER must include pledge() + unveil() calls — add as template in data/openbsd.yml

### W5: Code Style Rules Not Yet in ruby_style.yml or Scan Rules

- [ ] W501 Codify no-abbreviated-identifiers: scanner rule NO_ABBREVIATIONS fires on common short forms (cfg, ctx, msg, idx, tmp, num, pkt, vec, req, res, err, obj, val, buf) in identifiers — already partially in feedback_style.md but not wired
- [ ] W502 Codify no-regex-when-string-suffices: if pattern is a literal string with no metacharacters, flag as USE_STRING_MATCH instead of /regex/ — add as UNNECESSARY_REGEX lexical rule
- [ ] W503 Codify outsource-to-gems principle: if a well-maintained gem exists (flay, reek, rubocop), prefer it over reinvention — add as REINVENTED_WHEEL advisory rule
- [ ] W504 Codify importance-order enforcement: FileLayoutRule (B05) should also verify that public methods appear before private ones AND that the most-called public method appears first — currently only checks frozen header
- [ ] W505 Codify unscope-universal principle: scan for constants defined inside domain modules that match universal principle names (SOLID, KISS, DRY, etc.) — SCOPED_AXIOM rule fires if found outside ground/axioms/
- [ ] W506 Codify single-SSH-connection discipline: any shell-out in MASTER that opens a second SSH connection without ControlMaster fires PARALLEL_SSH warning
- [ ] W507 Codify no-new-files policy as scanner: if MASTER proposes creating a new .rb file, it must first check if an existing file's responsibility overlaps — PREMATURE_FILE advisory rule

### W6: Universal Cross-Disciplinary Rule Manifestations Not Yet in rules.yml

- [ ] W601 Add `manifestations:` map to every rule in rules.yml: for each medium (ruby, yaml, prose, css, html, cli, design) describe how the principle shows in that medium — currently rules are code-only
- [ ] W602 SINGULARITY rule: Ruby = one responsibility per class; YAML = one fact per key; Prose = one thesis per paragraph; CSS = one layout axis per rule; CLI = one output channel per command
- [ ] W603 PROXIMITY rule: Ruby = tests next to implementation; YAML = config adjacent to the behavior it controls; Prose = evidence near the claim; CSS = selector near the element it styles
- [ ] W604 HIERARCHY rule: Ruby = public before private; YAML = top-level keys ordered by importance; Prose = inverted pyramid; CSS = variables before rules; HTML = landmark elements before content
- [ ] W605 RHYTHM rule: Ruby = consistent method length across a class; Prose = sentence length variation; CSS = consistent spacing scale; CLI = consistent output density
- [ ] W606 Add medium detection to scanner: when scanning .md files, apply prose-manifestation rules; when scanning .css, apply CSS-manifestation rules — currently only Ruby rules applied universally

## X — Efficiency: Token, Memory, CPU, Cognitive (item 10)

### X1: Token Efficiency (LLM Cost Reduction)

- [ ] X101 Implement Anthropic cache_control: add ephemeral breakpoint to stable system-prompt prefix in LLMDispatcher — 93% token cost reduction ($0.73 → $0.07/turn)
- [ ] X102 Split prompt into stable cached layer (soul.yml + rules summary + ruby_style) + dynamic per-turn layer (context, violations, file) — cache boundary between the two
- [ ] X103 Compress rule descriptions sent to LLM: ID + one sentence only; full YAML stays in code — reduces system prompt 60%
- [ ] X104 Deduplicate file content across loop iterations: if SHA-256 matches previous turn, send "same as #{sha[0..7]}" placeholder — skip re-tokenizing unchanged files
- [ ] X105 Semantic batching: group all :warning findings for a file into one LLM call instead of one call per rule — collapse N calls into 1
- [ ] X106 Rule pre-filtering: skip rules whose applies_to language doesn't match file extension before sending to scanner — avoid zero-return LLM calls entirely
- [ ] X107 Truncate violation context window: send only lines (lineno-5)..(lineno+10) around each violation, not whole file, for targeted fixes
- [ ] X108 Memoize rule registry: Rule.registry is rebuilt on every scan — freeze and cache after boot; invalidate only on hot-reload
- [ ] X109 Token accounting middleware: log input+output tokens per LLM call to Trace::Session; surface cumulative cost in REPL prompt line
- [ ] X110 Skip semantic pass if zero lexical+structural findings: semantic LLM call costs ~5x more — gate it on at least one prior finding
- [ ] X111 Incremental scan: track file modification time; only re-scan changed files across loop iterations — skip clean files
- [ ] X112 Compress soul.yml preamble: 48,850 input tokens → target 15,000 by consolidating soul.yml, ruby_style.yml, patterns.yml into one compact prompt layer with cross-references stripped

### X2: Memory Efficiency

- [ ] X201 Cap violation objects at 100,000 — prune oldest when exceeded; log prune count in trace
- [ ] X202 Stream large files: files >500 lines scanned in chunks; no full string in memory for lexical rules that are line-by-line
- [ ] X203 Prism parse-once, reuse: parse Ruby AST once per file and pass to all structural rules — currently each rule re-parses independently
- [ ] X204 Lazy-load rule classes: require rule files on first scan of matching language, not at boot — saves ~2MB on boot for non-Ruby-only sessions
- [ ] X205 GC cadence: call GC.compact after every 5 scan iterations (not just GC.start) — reduces heap fragmentation on long sessions
- [ ] X206 Pool Rule instances: Rule objects are stateless after initialize — use object pool instead of instantiating per-file
- [ ] X207 Drop finding detail after writing to JSONL: after persisting to .violations.jsonl, replace finding struct with {id, count} summary in memory
- [ ] X208 Bounded session history: keep only last 50 events in Trace::EventBus subscriber list; drop older than 1h
- [ ] X209 Symbol intern LLM model names: model identifiers are repeated hundreds of times per session — intern as symbols, not frozen strings
- [ ] X210 Avoid String#gsub result accumulation: AstFixer chains gsub calls, creating intermediate strings — use one pass with multiple patterns via StringScanner

### X3: CPU Efficiency

- [ ] X301 Parallelize structural rules: SmallFilesRule, SmallFunctionsRule, GodClassRule, NestingDepthRule all run sequentially on same AST — run in parallel threads sharing the parsed tree
- [ ] X302 Pre-compile all lexical regexes at load time: scan_lines regexes currently compile on first call — move to module-level constants
- [ ] X303 Short-circuit rule chain: if FORBIDDEN_PATTERNS fires (:error), skip all :info/:warning rules for that file — highest severity already blocks it
- [ ] X304 YJIT-friendly object shapes: pre-initialize all instance variables in Rule#initialize to stabilize object shapes for YJIT inline caches
- [ ] X305 Avoid Array#flatten in finding collector: scan_lines returns arrays; concat avoids flatten overhead — already partially done, audit all finding aggregation
- [ ] X306 Regex alternation ordering: put most-frequent match patterns first in alternation — /puts|print/ → /puts/ fires earlier on typical code
- [ ] X307 Thread pool right-sizing: Scanner::POOL_SIZE defaults to CPU count — measure per-rule CPU vs I/O time; I/O-bound rules benefit from more threads
- [ ] X308 Prism result caching across passes: DetectionPipeline parses AST then discards; FixLoop re-parses — share AST across all pipeline stages within same file turn
- [ ] X309 Avoid rescue in hot paths: rescue blocks in scan_depth, count_cc_nodes, body_contains? create hidden exception tables — restructure to return early instead
- [ ] X310 LRU rule-result cache: for identical (rule_id, file_sha256) pairs across different scan sessions, cache result — same unmodified file always produces same findings

### X4: Cognitive / Developer Ergonomics

- [ ] X401 Single canonical entry point: `master scan <file>` runs the complete pipeline — no need to know --depth, --profile, --pass flags
- [ ] X402 Remove all scan depth knobs: DEEP_SCAN_ONLY is already in soul.yml — delete --depth=shallow/standard from CLI argument parser entirely
- [ ] X403 Auto-pick model tier: remove explicit --model flag; let ModelRouter choose based on finding severity + file size + budget remaining
- [ ] X404 Progressive output: stream findings as they're generated rather than buffering until all rules finish — user sees progress on large files
- [ ] X405 Collapse five-pass result into one dmesg-style summary: "scan: 3 errors, 7 warnings, 14 info → 2 autofixed, 5 queued" — not separate output per rule
- [ ] X406 Deduplicate finding messages: if same message appears >3 times, show "×7" count instead of 7 lines — reduce cognitive load
- [ ] X407 Sort findings by severity then line number: currently reported in rule-registry order — reorder before output
- [ ] X408 /status command: one-line summary of last scan result, session cost, budget remaining, pending fixes — instant situational awareness
- [ ] X409 Diff preview before fix: show before/after for each proposed fix in the REPL before applying — no surprise rewrites
- [ ] X410 "Explain this finding" on demand: user can type number to get semantic explanation of why finding N matters, with academic reference

## Y — Prose/Data → Ruby or Ruby → Data Conversion (item 11)

### Y1: YAML Data That Should Be Ruby Constants

- [ ] Y101 data/models.yml model ID list → `MASTER::NOW::Routing::TIER_MODELS = {...}.freeze` Ruby constant — YAML parsed on every boot; constant parsed once
- [ ] Y102 data/gems.yml allowed-gem list → `Ground::APPROVED_GEMS = Set[...].freeze` constant — membership tests are O(1) vs YAML hash lookup overhead
- [ ] Y103 data/injection_patterns.yml patterns → `Ground::InjectionPatterns::PATTERNS = [...].freeze` constant — currently loaded then parsed on first guard check
- [ ] Y104 data/refusal_templates.yml → frozen string table in voice/renderer.rb — short string constants don't need YAML serialization
- [ ] Y105 data/closings.yml → `Voice::CLOSINGS = [...].freeze` — an array of 20 strings loaded from YAML adds 3ms boot overhead
- [ ] Y106 data/vocabulary.yml → vocabulary module with `TERMS = {...}.freeze` — enables compile-time validation of term references
- [ ] Y107 data/visual_clusters.yml → `Ground::VisualClusters::CLUSTERS = {...}.freeze` — static topology doesn't change at runtime

### Y2: Ruby Code That Should Be Data (YAML/JSON)

- [ ] Y201 lexical_rules.rb regex patterns → rules.yml pattern: field per rule — enables rules to be updated without editing Ruby; MASTER becomes data-driven for lexical detection
- [ ] Y202 AstFixer::BARE_RESCUE_RE, MUTABLE_CONST_RE, STRICT_MODE constants → data/fix_patterns.yml — centralizes all fixable patterns in one authoritative YAML
- [ ] Y203 SecurityAgent::SECURITY_PATTERNS array (from v50.8) → data/security_patterns.yml — security team can update patterns without touching Ruby
- [ ] Y204 structural_rules.rb threshold constants (MAX_DEPTH=4, MAX_CC=10, MAX=20, LIMIT=300) → data/thresholds.yml — rules become configurable without code change
- [ ] Y205 RuleDSL severity/tags/applies_to metadata → merge into rules.yml per-rule entry — RuleDSL block remains Ruby but metadata lives in YAML
- [ ] Y206 voice/personality.rb catchphrase arrays → data/soul.yml personality.catchphrases — currently hardcoded strings in Ruby
- [ ] Y207 now/pipeline.rb stage order list → data/workflow.yml pipeline.stages — pipeline topology as data, executor as pure Ruby
- [ ] Y208 judge/llm_dispatcher.rb model routing table → data/models.yml tier map — already partially in models.yml; remove duplicate in Ruby

### Y3: LLM Prompt Templates That Should Be Structured Data

- [ ] Y301 Inline LLM prompt strings in agent.rb, council/*.rb → data/prompts/ YAML files with named slots — enables prompt versioning, diffing, and A/B testing without Ruby changes
- [ ] Y302 SemanticRule prompt template → data/prompts/semantic_scan.yml with {{rules}}, {{code}}, {{path}} slots — swappable without Ruby change
- [ ] Y303 Council deliberation prompts (ideation, critique, synthesis) → data/council.yml prompts section — already partially there; audit for stragglers
- [ ] Y304 RuleLoop fix prompts → data/prompts/fix_strategies.yml keyed by strategy name (genetic, diff, council) — enables prompt tuning without redeploy
- [ ] Y305 Proposal engine action strings → data/proposals.yml with typed proposal templates — structured, queryable, versionable

### Y4: Configuration That Should Be Runtime-Negotiable

- [ ] Y401 soul.yml absolute rules → expose via /soul command for inspection but not modification — currently read-only from disk; add runtime introspection
- [ ] Y402 Scan thresholds (MAX_DEPTH, MAX_CC, LIMIT) → negotiable via /config set threshold.max_cc 15 — persist to runtime/config_overrides.yml
- [ ] Y403 LLM model assignments → negotiable via /model set judge.fast deepseek/deepseek-v3 — persist per session without editing models.yml

## Z — Cleanup, Normalization, Refinement, Streamlining (item 12)

### Z1: Naming Normalization

- [ ] Z101 Normalize error variable names: all rescue clauses use `=> error` not `=> e`, `=> err`, `=> ex` — currently mixed across lib/
- [ ] Z102 Normalize block parameter names: `|line, i|` (not `|l, idx|`, `|ln, n|`) in scan_lines patterns — enforce via NO_ABBREVIATIONS rule on MASTER itself
- [ ] Z103 Normalize finding construction: all rules use `finding(line:, message:)` keyword form — audit for positional calls
- [ ] Z104 Normalize boolean method names: all predicate methods end in `?` — audit for `is_retriable`, `permanent`, `has_body` without `?`
- [ ] Z105 Normalize constant casing: SCREAMING_SNAKE for constants, CamelCase for modules/classes — audit for mixed cases in axioms/
- [ ] Z106 Normalize file extension guards: all file-type checks use `path.to_s.end_with?(".rb", ".rake")` pattern — audit for `=~`, `match?(/\.rb/)` variants

### Z2: Dead Code and Redundancy

- [ ] Z201 Audit Rule.registry: remove any duplicate rule IDs (SINGULARITY check) — run boot assertion D09 first to find them
- [ ] Z202 Remove deprecated scan depth logic: any reference to :shallow/:standard depth in scanner.rb, pipeline.rb — DEEP_SCAN_ONLY is now law
- [ ] Z203 Remove unused require statements: any `require` that has no corresponding constant reference in same file
- [ ] Z204 Collapse redundant rescue blocks: pattern `rescue StandardError => e; nil` that swallows errors appears in 4+ places — extract to Ground::Swallow.call { } (already exists)
- [ ] Z205 Remove commented-out code: any block of ≥3 commented lines that doesn't have an explanatory comment — dead code, not documentation
- [ ] Z206 Consolidate duplicate glob patterns: same Dir.glob pattern in Scanner and RepoEcology — extract to Ground::Paths.scannable_files
- [ ] Z207 Remove FULL_BY_DEFAULT rule exemptions that were added for MASTER's own code during initial scan — MASTER must pass its own rules

### Z3: Error Handling Normalization

- [ ] Z301 Replace bare `rescue StandardError` with specific error classes where the error type is known — 8 instances in structural_rules.rb alone
- [ ] Z302 Normalize all rescue blocks to log before returning []: currently some log, some silently return [] — add `Trace.warn(e)` to every rescue in scan rules
- [ ] Z303 Remove `rescue nil` at end of lines: 3 instances in ast_fixer.rb — handle the nil case explicitly
- [ ] Z304 Replace `defined?(var)` guards with explicit nil check: `defined?(temporary_path)` in ast_fixer.rb — just use `temporary_path&.`
- [ ] Z305 Normalize `raise` vs `fail`: pick one idiom per codebase — Jeremy Evans uses `raise` exclusively

### Z4: Style Normalization

- [ ] Z401 Convert all double-escaped heredoc `<<~RUBY` strings in prompts to single-quoted heredocs where interpolation isn't needed — prevents accidental interpolation
- [ ] Z402 Normalize hash rocket vs symbol colon: use symbol colon `key: value` everywhere — audit for `"string" =>` and `:symbol =>` patterns
- [ ] Z403 Replace `Array()` wrapping with explicit `.to_a` or `Array.wrap` — `Array(tags)` in RuleDSL is idiomatic but inconsistent with rest of codebase
- [ ] Z404 Normalize `frozen_string_literal` header spacing: exactly one blank line after the magic comment before first code — currently varies
- [ ] Z405 Replace `next []` with `return []` in non-block contexts: `next` in a method body (not a block) is confusing — 3 instances in js_rules.rb
- [ ] Z406 Normalize module nesting depth: all rules in Master::Judge::Scan::Rules — audit for any that are one level off
- [ ] Z407 Replace `&.` safe navigation with explicit guard clause where the nil case has meaningful behavior — don't hide nil semantics
- [ ] Z408 Normalize string interpolation: prefer `"#{var}"` over `"" + var.to_s` or `var.to_s` concat

### Z5: Configuration Normalization

- [ ] Z501 Single source for model names: currently defined in models.yml AND referenced as string literals in agent.rb, now/routing/ — one canonical location
- [ ] Z502 Normalize severity symbols: all rules use :error/:warning/:info — audit for :critical, :high, :medium (legacy from v50.8 SecurityAgent) left over
- [ ] Z503 Remove default: true from rules that can't be disabled — if a rule always runs, `default: true` is noise
- [ ] Z504 Normalize tags format: all rule tags as `tags: %i[TAG_ONE TAG_TWO]` — audit for string arrays `tags: ["TAG_ONE"]`
- [ ] Z505 Normalize description field: all rules have description — audit for rules where description == id.downcase.tr("_"," ") (auto-generated, meaningless)

### Z6: Performance Cleanup

- [ ] Z601 Replace `src.lines.each_with_index.filter_map` with `src.each_line.with_index.filter_map` — avoids creating full lines array
- [ ] Z602 Replace `scan_lines(src, regex)` with pre-compiled regex constant — move inline regex to module-level SCREAMING_SNAKE constant
- [ ] Z603 Remove redundant `.compact` after `node.child_nodes` — child_nodes already returns no nils in modern Prism
- [ ] Z604 Replace `node.respond_to?(:child_nodes)` guard with `node.is_a?(Prism::Node)` — more precise, enables YJIT inline cache hits
- [ ] Z605 Flatten recursive `visit` traversal: replace recursive DFS with iterative stack-based traversal — avoids stack overflow on deeply nested Ruby files

## AA — Patterns from OpenBSD, Ruby Core, and Jeremy Evans (item 13)

### AA1: Jeremy Evans / Roda Plugin Architecture

- [ ] AA101 One-plugin-per-file with descriptive naming: restructure judge/scan/rules/ so each rule is a separate loadable plugin file — matches Roda's `lib/roda/plugins/csrf.rb` pattern; selective opt-in loading
- [ ] AA102 Plugin validation at load time: when a rule file is required, immediately validate it has `check` method and `@id` set — fail loudly at boot, not at scan time
- [ ] AA103 Minimal core with feature modules: MASTER's Rule base class should be near-empty; all behavior lives in included modules (ScanBehavior, FindingFactory, LanguageFilter)
- [ ] AA104 Registry-based rule transformer: Rule.registry keyed by rule ID, values are classes — enables lookup by string ID without iteration; already partially done, normalize fully
- [ ] AA105 Feature definition with metadata hash: each rule registers `{id:, severity:, tags:, applies_to:, autofix:}` in RULES_META constant at load time — introspectable without instantiation
- [ ] AA106 Composition over inheritance: AstFixer transforms should be composable modules (AstFixer::FrozenHeader, AstFixer::BareRescue) included by AstFixer — not one 200-line class
- [ ] AA107 Optional dependency loading: structural rules `require "prism"` at top of file — wrap in `begin/rescue LoadError` and skip registration if Prism unavailable
- [ ] AA108 Private matcher methods with `_` prefix: all internal rule-matching helpers named `_match_pattern`, `_match_ast`, `_match_cross_file` — public surface is just `check`
- [ ] AA109 Polymorphic input acceptance: `scan_lines` should accept String, IO, Pathname, or Array — currently String-only; match Roda's polymorphic matcher pattern
- [ ] AA110 `configure` block for rule options: `RuleDSL.rule :FOO, max: 10 do ... end` passes options into rule at definition time — currently only severity/tags/applies_to

### AA2: Jeremy Evans / Sequel Dataset Chaining

- [ ] AA201 Immutable finding collections: Finding objects are mutated after creation (adding context, suggestion) — freeze after construction; return new Finding for modifications
- [ ] AA202 Lazy scan pipeline: DetectionPipeline should build a chain of rule calls without executing; execute only when `.findings` is called — enables inspection before execution
- [ ] AA203 Enumerable integration on ScanResult: include Enumerable on the findings collection; implement `each` — enables `.select`, `.min_by`, `.group_by` without custom methods
- [ ] AA204 Dataset-style scope methods: `results.errors`, `results.warnings`, `results.for_file(path)`, `results.autofixable` — chain without mutation; matches Sequel's `where().select()` style
- [ ] AA205 Never cache scan results across modifications: if file changes between scan and fix, invalidate cached findings — Sequel principle: "datasets never cache results"
- [ ] AA206 Eager-loading associations: when collecting findings across files, batch-load all related metadata (rule descriptions, tags) once — prevent N+1 rule-description lookups

### AA3: Jeremy Evans / Rodauth Feature Isolation

- [ ] AA301 Feature modules in separate files: each Now::Stage is already a separate class — apply same pattern to judge/council phases (Ideation, Critique, Synthesis each in own file under judge/council/)
- [ ] AA302 Configuration via block DSL: `MASTER.configure { scan.max_depth 4; model.default :sonnet }` block-based config — no positional args, full keyword safety
- [ ] AA303 Per-request object isolation: each scan turn creates a fresh ScanContext — no shared mutable state between turns; already partially done, audit for leaks
- [ ] AA304 View/Route/Email style generators: for each rule, auto-generate `rule_url`, `rule_description`, `rule_fix_hint` methods from rule metadata — Rodauth-style method generation
- [ ] AA305 Timing-safe token comparisons: session tokens, API key comparisons use `Rack::Utils.secure_compare` not `==` — prevent timing attacks in CLI auth flows
- [ ] AA306 Database function restrictions: if MASTER ever uses PostgreSQL, restrict LLM key reads to a limited DB role — Rodauth pattern for password hash access control

### AA4: Jeremy Evans / Erubi and Forme Minimalism

- [ ] AA401 Single-file implementation for small subsystems: AstFixer is 180 lines — good; Voice::Renderer should be ≤150 lines; any sub-100-line concern should be one file
- [ ] AA402 No external dependencies for core subsystems: Ground::Config, Ground::Axioms, Trace::EventBus should have zero gem dependencies — pure Ruby
- [ ] AA403 Avoid repeated constant creation: all regex patterns in rules compiled once at class-load time as constants — Erubi pattern: `ESCAPE_TABLE = {...}.freeze`
- [ ] AA404 Double-freeze collections: freeze array AND its string elements: `TAGS = %i[SOLID SRP].freeze` (symbols already immutable; string arrays need `map!(&:freeze).freeze`)
- [ ] AA405 Buffer strategy selection: AstFixer's write_back could offer a StringIO buffer mode (no disk write) for testing — Erubi's dual-buffer pattern
- [ ] AA406 Shape-friendly instance variable initialization: pre-initialize all Rule instance variables in Rule#initialize to nil/default — YJIT optimizes known shapes

### AA5: OpenBSD Kernel / pledge(2) + unveil(2) Patterns

- [ ] AA501 Implement pledge discipline for MASTER process: after loading config but before scan, pledge("stdio rpath wpath cpath inet") — restrict syscalls to what's actually needed
- [ ] AA502 Implement unveil discipline: unveil only the target directory being scanned plus MASTER's own data/ — all other paths return ENOENT
- [ ] AA503 Principle of least privilege in subagents: each spawned worker pledges a smaller set than parent — read-only workers pledge("stdio rpath"), write workers add "wpath"
- [ ] AA504 Unveil before LLM network calls: unveil "" (no filesystem) for network-only LLM workers — isolates credential exposure surface
- [ ] AA505 Model pledge/unveil as MASTER rules: any Ruby script lacking `Process.pledge` on OpenBSD gets MISSING_PLEDGE advisory finding

### AA6: OpenBSD Style / pf.conf Discipline

- [ ] AA601 Default-deny rule architecture: MASTER's tool approval mimics pf.conf default-deny + explicit pass rules — any new tool must be explicitly listed in data/tools.yml to be invocable
- [ ] AA602 Rule ordering by specificity: tool approval rules ordered most-specific first, least-specific (wildcard) last — matches pf.conf block/pass ordering
- [ ] AA603 Logging unexpected events: pf logs blocked packets; MASTER should log every tool call attempt to trace/tool_log.jsonl including denied ones
- [ ] AA604 Stateful connection tracking: pf tracks connection state; MASTER tracks "open sessions" — if a file is being edited by one tool, block another tool from editing it simultaneously
- [ ] AA605 Macros for repeated values: pf.conf uses `openports = "{ 80, 443 }"` — MASTER data files should use YAML anchors+aliases for repeated configuration values

### AA7: OpenBSD Engineering Culture

- [ ] AA701 "Correct by default" rather than "secure by configuration": MASTER's defaults should be maximally safe; unsafe behaviors require explicit opt-in (matches OpenBSD's philosophy)
- [ ] AA702 Audit every dependency: before adding a gem, MASTER should have a rule that requires it to be in gems.yml with explicit justification — no silent gem additions
- [ ] AA703 Minimal attack surface: MASTER's web surface (MASTER/web/) should expose the minimum necessary endpoints; each endpoint must be explicitly justified in AGENTS.md
- [ ] AA704 Source code auditing discipline: before any LLM-generated code is committed, a deterministic structural scan must pass — mirrors OpenBSD's manual code audit culture
- [ ] AA705 rc.d service discipline: MASTER's rc.d script must honor stop/start/check/restart — test all four verbs; document in DEPLOY/openbsd/

### AA8: Ruby Core Patterns (Matz's Philosophy)

- [ ] AA801 Blocks for deferred execution: anywhere MASTER passes a lambda or Proc, consider whether a block is more idiomatic — blocks express "do this later" more clearly in Ruby
- [ ] AA802 Enumerable everywhere: any class that manages a collection should include Enumerable and implement `each` — Rule.registry, ScanResult, FindingCollection
- [ ] AA803 Method objects over Procs: when a callable needs to be stored or compared, use `method(:name)` not `-> { }` — more introspectable, better stack traces
- [ ] AA804 Symbol-to-proc over explicit blocks: `.map { |r| r.id }` → `.map(&:id)` — idiomatic Ruby; already partially done, audit remaining explicit-block patterns
- [ ] AA805 Struct for value objects: Finding is a Hash — convert to `Finding = Struct.new(:rule_id, :line, :message, :severity, keyword_init: true)` — type-safe, inspectable, comparable
- [ ] AA806 Data.define for immutable value objects (Ruby 3.2+): `Verdict = Data.define(:passed, :violations)` — stricter than Struct, fully frozen
- [ ] AA807 Comparable mixin for ordered types: Finding should include Comparable with `<=>` by severity then line — enables `findings.min`, `findings.sort`, `findings.max_by`
- [ ] AA808 Kernel#pp for debugging instead of puts: MASTER's development output should use pp not puts for structured data — enables cleaner inspection without custom serializers
- [ ] AA809 Frozen string literal by default everywhere: currently some files lack the magic comment — enforce globally; Erubi demonstrates this at scale
- [ ] AA810 Proc#curry for partial application: ModelRouter's scoring functions take 3 args — curry enables `score_for_tier.(tier)` partial application; cleaner than closures with captured state

## AB — Logic Inconsistencies, Ambiguity, Overlapping Rules (item 14)

### AB1: Scan Rule Conflicts and Overlaps

- [ ] AB101 TRAILING_WHITESPACE (lexical rule) overlaps with C02 AstFixer strip_trailing_whitespace — two systems fix the same thing; deduplicate to AstFixer only, remove lexical rule
- [ ] AB102 CONSECUTIVE_BLANK_LINES (lexical rule) overlaps with C01 AstFixer collapse_blank_lines — same dedup; AstFixer is deterministic and runs first; lexical rule becomes unreachable
- [ ] AB103 FROZEN_LITERAL (lexical rule) overlaps with C00 AstFixer add_frozen_header — rule fires on a file that AstFixer will immediately fix; report only if autofix is disabled
- [ ] AB104 STRICT_MODE_ZSH (lexical, applies_to zsh) and C04 AstFixer add_strict_mode both target the same pattern — coordinate so rule fires only if autofix explicitly turned off
- [ ] AB105 SMALL_FILES (SmallFilesRule B01, limit 300) and JS_MODULE_SIZE (js_rules, limit 300) are the same rule duplicated for different language labels — unify under one rule with medium-specific message
- [ ] AB106 SECRET_PROXIMITY and FORBIDDEN_PATTERNS both detect hardcoded credentials — SECRET_PROXIMITY uses proximity context; FORBIDDEN_PATTERNS uses exact pattern; define which is authoritative or merge
- [ ] AB107 UNBOUNDED_RETRY and RACE_CONDITIONS both inspect multi-line context around a keyword — create shared scan_context_lines helper to avoid inconsistent window sizes (12 vs 10)
- [ ] AB108 NO_MAGIC_NUMBERS fires on integer literals inside constant definitions (FOO = 300) — should exempt right-hand side of SCREAMING_SNAKE assignments; currently false-positives own constants
- [ ] AB109 GUARD_CLAUSE and NESTING_DEPTH both fire on deeply nested if/else — GUARD_CLAUSE fires at def level, NESTING_DEPTH at >4 levels; they can both fire on same method; suppress one
- [ ] AB110 KEYWORD_ARGS fires on `def foo(a, b, c)` but not on `def foo(a, b, c = nil)` — the presence of a default makes it a keyword-style arg; rule inconsistently exempts defaults
- [ ] AB111 DEAD_CODE fires on line after `return` but not after `raise` at end of a rescue block — raise in rescue is a valid terminal; align the pattern
- [ ] AB112 TRAILING_COMMAS fires on multi-line arrays but not on multi-line method argument lists — extend or document the deliberate exclusion
- [ ] AB113 NULL_BLINDNESS fires on `== nil` but AstFixer normalise_null_comparison targets SQL `= NULL` — scopes don't overlap but names imply they do; rename AstFixer transform to SQL_NULL_COMPARISON

### AB2: Severity Inconsistencies

- [ ] AB201 FORBIDDEN_PATTERNS is :error but RACE_CONDITIONS is also :error — yet RACE_CONDITIONS has a much higher false-positive rate (check-then-set without synchronize fires on valid patterns) — downgrade to :warning or add suppressibility
- [ ] AB202 SECRET_PROXIMITY is :error but KEYWORD_ARGS is :error — keyword args are stylistic, not security — KEYWORD_ARGS should be :warning
- [ ] AB203 SMALL_FILES and SmallFilesRule both have :warning severity — consistent, but files >500 lines should escalate to :error; add tiered severity
- [ ] AB204 DATA_CLASS fires as :info but should be :warning — a data-only class with no behavior is a design smell, not a style preference
- [ ] AB205 CQS (B04) fires as :warning but Clean Code treats CQS violation as high severity — align with source material or document why downgraded
- [ ] AB206 FileLayoutRule (B05) fires as :info — frozen_string_literal missing is already :warning in FROZEN_LITERAL; two rules for the same finding create duplicate findings at different severities

### AB3: Vague or Ambiguous Rule Descriptions

- [ ] AB301 FULL_BY_DEFAULT: description "use full/deep by default" — ambiguous whether it flags the param name or the default value; clarify: "flag any method/flag parameter named shallow|standard|lite|basic|quick"
- [ ] AB302 GUARD_CLAUSE: message says "extract to guard clause" but the detection regex matches `def … if … else` — it fires on correct guard clauses too if they're nested; refine regex
- [ ] AB303 SPECULATIVE_GENERALITY_LEXICAL: fires on `# TODO: future` — legitimate TODOs with dates should be exempt; add "# TODO(2026-06-01):" exclusion
- [ ] AB304 COMMENTS_AS_DEODORANT fires on "This method returns…" — should exempt method documentation at class/module boundary (first comment after a class/module declaration)
- [ ] AB305 USE_THEN: description says "use .then over temp variable chains" — detection pattern requires temp var used immediately on next line; chains split by blank lines are missed; clarify scope
- [ ] AB306 EXPLICIT rule (B06): "detect implicit requires, implicit return types, magic coupling" — three completely different concerns bundled; split into ExplicitRequiresRule, MethodMissingRule, AutoloadRule
- [ ] AB307 CyclomaticComplexityRule description says "max 10" but soul.yml SIMPLEST_WORKS says "max 20 lines" for methods — two different metrics (CC vs length) used interchangeably in violation messages; distinguish them explicitly

### AB4: Pipeline Logic Inconsistencies

- [ ] AB401 AstFixer runs before scan but AstFixer's normalise_null_comparison skips /judge/scan/ files — scanner files can contain SQL patterns but are exempt; undocumented exclusion; add comment explaining why
- [ ] AB402 FixLoop has two strategies (llm_pass, fast_pass) but the strategy selection logic is in scanner.rb, not FixLoop — SRP violation in the scanner itself; move strategy selection to FixLoop
- [ ] AB403 DetectionPipeline has a cyclomatic_complexity method that's being superseded by CyclomaticComplexityRule (B08) — old CC logic still runs in parallel; will produce duplicate findings until removed
- [ ] AB404 SemanticRule batches all detect_semantic rules into one LLM call but structural rules run individually — inconsistent batching strategy; either batch structural too or explain why not
- [ ] AB405 /review and /critique both invoke deliberation logic — /critique is subset of /review; the distinction is invisible to users; merge or rename clearly
- [ ] AB406 /fix and /scan --fix are both valid entry points for the same fix pipeline — duplicate invocation paths with potentially different defaults; canonicalize one
- [ ] AB407 Loop::Heartbeat and Loop::Homeostat both manage background scheduling — Heartbeat runs periodic scans, Homeostat manages drive states — their interaction (who yields to whom) is undocumented
- [ ] AB408 Propose module and SoulProposals both emit proposals — different triggers, different output paths — user sees proposals from both without clear distinction; unify under one Proposal.emit interface

### AB5: Data Inconsistencies

- [ ] AB501 rules.yml has 173 rules but Rule.registry at runtime has fewer — rules declared in YAML but not implemented in Ruby are silently absent; add boot assertion counting both and failing on mismatch
- [ ] AB502 soul.yml negotiable.default_model and data/models.yml default_tier use different model ID formats — soul.yml uses shorthand ("claude-opus-4-7"), models.yml uses full API path; normalize to one canonical format
- [ ] AB503 data/standing_orders.yml and data/workflow.yml both define execution limits — max_iterations appears in both with potentially different values; single source of truth required
- [ ] AB504 ruby_style.yml defines max_method_lines: 10 but SmallFunctionsRule uses MAX: 20 — two different "max" values for the same concept; align or document the distinction (ideal vs hard limit)
- [ ] AB505 data/patterns.yml and data/rules.yml both contain regex patterns for the same smells — DRY violation in the data layer; rules.yml patterns should be the single source
- [ ] AB506 data/council.yml defines reviewer personas but judge/council/ Ruby files redefine them inline — YAML persona config not loaded by council code; dead data
- [ ] AB507 data/axioms.jsonl and lib/ground/axioms/ both contain axiom definitions — JSONL format and Ruby module format for the same information; one must be authoritative

### AB6: CLI Inconsistencies

- [ ] AB601 /run is documented as "recommended for most work" in help output but /scan, /fix, /review are still listed as primary commands — creates ambiguity about which to use
- [ ] AB602 /topic accepts an argument but /model, /persona, /mode also accept arguments — inconsistent help text format: some show [arg], some show <arg>, some show nothing
- [ ] AB603 /checkpoint creates a snapshot but /snapshot also exists — two commands with same semantic intent; merge to /checkpoint, remove /snapshot alias
- [ ] AB604 /resync --dry-run flag documented but not all commands support --dry-run consistently — flag handling is command-specific not framework-level; should be universal
- [ ] AB605 /dmesg shows boot log but /diag shows diagnostics — user cannot predict which shows what; merge or rename: /diag for live diagnostics, /dmesg for boot history only
- [ ] AB606 /orient [topic] outputs all five bootstrap yml files when no topic given — 50KB+ of output; violates unix-silence; should output only the topic-relevant section by default

## AC — Flatten Commands / Zero-Command Design (items 18, 19, 20)

### AC1: Command Consolidation

- [ ] AC101 Merge /scan and /fix into a single entry point: any invocation that mentions a file or directory runs scan+fix loop automatically — no explicit /fix needed
- [ ] AC102 Retire /critique as separate command: fold into /review — /review already calls deliberation; /critique is a subset; remove the distinction
- [ ] AC103 Retire /axioms as separate command: /why already explains principles; /axioms just lists them — add as section of /why output when no specific finding given
- [ ] AC104 Retire /ecology as separate command: surface repo ecology automatically at session start as part of boot dmesg — not an on-demand command
- [ ] AC105 Retire /propose-tree as separate command: proposal tree surfaces automatically when idle >5 minutes or after session with violations — not on-demand
- [ ] AC106 Retire /topic as separate command: topic detection is automatic; user never needs to set topic explicitly — infer from context
- [ ] AC107 Retire /resync as separate command: fold into /status with auto-remediation: if /status detects drift, offer to fix in-place
- [ ] AC108 Retire /snapshot as alias: /checkpoint is the canonical command; /snapshot is duplicate surface
- [ ] AC109 Merge /tokens and /cost into /status output: both are already shown in session line; redundant standalone commands
- [ ] AC110 /model with no args shows current model — fold into /status; /model <name> to switch is the only needed form
- [ ] AC111 /persona with no args shows current — fold into /status; /persona <name> to switch is the only needed form
- [ ] AC112 /mode with no args shows current — fold into /status; /mode <name> is the only needed form
- [ ] AC113 Retire /postpro and /repligen as slash commands: they are tool wrappers, not REPL commands; invoke automatically when relevant tool is available
- [ ] AC114 Target: reduce from 30+ slash commands to ≤8: /run, /status, /model, /persona, /memory, /undo, /help, /exit

### AC2: Intent Inference (No Commands Needed)

- [ ] AC201 Any input containing a file path → auto-run scan+fix loop on that file; no /scan needed
- [ ] AC202 Any input containing "why" or "explain" → auto-run /why on most recent finding; no /why command needed
- [ ] AC203 Any input containing "commit" or "push" → auto-run git commit with LLM message; no /commit needed
- [ ] AC204 Any input containing "clean" or "fix" without a path → auto-run fix loop on last scanned target
- [ ] AC205 Any input containing "status" or "health" → auto-run /status output
- [ ] AC206 Any input that is empty or "?" → show abbreviated /status + last finding count; never show full help
- [ ] AC207 /run <anything> routes all natural language through the intent router — /run is the one command users need to learn; everything else is inferrable

### AC3: "Best Design Is No Design" Measures (item 19)

- [ ] AC301 Remove all depth/tier/profile scan flags — DEEP_SCAN_ONLY is law; no configuration surface needed
- [ ] AC302 Remove --dry-run from all commands — preview is always shown before destructive operations; no flag needed
- [ ] AC303 Remove --verbose from all commands — structured dmesg output is always on; verbosity is per-component, not per-invocation
- [ ] AC304 Remove model selection flags — ModelRouter chooses optimally; user overrides only via /model command if needed
- [ ] AC305 Remove --parallel/--no-parallel flags — always parallel on multi-core; --no-parallel was a workaround for Termux fork() ban; use Thread instead of Process
- [ ] AC306 Remove all scan profile flags (--profile quick, --profile critical) — always full scan; profiling was a performance workaround
- [ ] AC307 Remove backup_count config — always keep 5 backups; this is not a decision the user should make
- [ ] AC308 Remove ask_language config — always auto-detect; asking the user was a workaround for ambiguous extensions
- [ ] AC309 Remove convergence_window and convergence_threshold — always converge to zero; these thresholds allowed "good enough" early exits
- [ ] AC310 Remove explicit --fix flag from commands — always fix when fixable; show diff first; confirm only for destructive refactors

### AC4: Useless Limits and Thresholds to Remove (item 20)

- [ ] AC401 Remove max_iterations: 10 limit — iterate until zero violations; the limit existed because old LLM calls were expensive, not because 10 is a meaningful stopping point
- [ ] AC402 Remove max_file_size: 1MB / max_lines: 10000 guards — stream large files instead; these limits silently skip files the user wants scanned
- [ ] AC403 Remove convergence_threshold: 0.9 — 90% isn't zero; only 100% (zero violations) is acceptable per soul.yml
- [ ] AC404 Remove max_per_file: $1.00 hard cap — budget control belongs at session level; per-file cap causes silent abandonment of complex files
- [ ] AC405 Remove backup_count: 5 — either unlimited backups (cheap on modern storage) or time-based rotation; 5 is arbitrary
- [ ] AC406 Remove POOL_SIZE constant defaulting to CPU count — measure actual speedup; if I/O-bound, more threads than CPUs is better
- [ ] AC407 Remove warn_at: 0.50 cost threshold — either warn at every LLM call with running total, or not at all; 50% is arbitrary
- [ ] AC408 Remove max_new_violations: 0 from fix_validation — this is correct behavior; make it invariant (not configurable)
- [ ] AC409 Remove lock_timeout: 30 and stale_lock_age: 300 as config — hard-code reasonable values; these are not user decisions
- [ ] AC410 Remove gc_every_n_iterations: 5 — let Ruby's GC heuristics run; manual GC triggers are premature optimization

## AD — Natural Language Understanding (item 21)

### AD1: Intent Recognition

- [ ] AD101 Semantic intent classifier: before routing any input, run a fast (zero-LLM) regex+keyword classifier that maps plain-language phrases to pipeline actions — "show me what's broken" → scan, "make it cleaner" → fix+lint, "explain this" → why
- [ ] AD102 Entity extraction: identify file paths, rule IDs, and model names in natural language input — "fix the scanner" resolves to lib/judge/scan/scanner.rb; "the CQS rule" resolves to B04
- [ ] AD103 Pronoun resolution: "it" / "that file" / "the last one" → resolve to most recently mentioned/scanned file in session context
- [ ] AD104 Verb-action mapping: build verb→action table: "clean/tidy/polish" → fix+lint, "check/review/audit" → scan, "explain/why/what" → why+axioms, "ship/deploy/push" → commit+push
- [ ] AD105 Negation handling: "don't fix X" / "skip the magic number rule" → add rule to session suppression list; persist for session
- [ ] AD106 Scope inference: "fix everything" → scan all tracked files; "just this method" → extract method name and run targeted scan
- [ ] AD107 Urgency detection: "quickly" / "just give me the main issues" → still run full scan but show only :error findings first; don't downgrade scan depth
- [ ] AD108 Multi-step intent: "scan, fix what you can, then commit" → parse as ordered pipeline; execute each step; confirm between stages only when destructive
- [ ] AD109 Question vs command distinction: "what's wrong with this?" → report; "fix what's wrong with this" → fix; detect question mark and interrogative verbs

### AD2: Context Awareness

- [ ] AD201 Session state awareness: if user says "try again" after a failed fix, auto-retry with next strategy (genetic after diff, council after genetic)
- [ ] AD202 File history awareness: "you just changed this" → check git diff for the file; offer to undo if user sounds dissatisfied
- [ ] AD203 Error message paraphrasing: when a rule fires, offer a one-sentence plain-language explanation before the technical message — "This method does two things at once (CQS violation)" before the formal finding
- [ ] AD204 Ambiguity escalation: when intent is <60% confident, ask one specific clarifying question — not a menu of options
- [ ] AD205 Language switching: if user writes in Norwegian, respond in Norwegian; MASTER already has bilingual config; ensure the intent router also works on Norwegian input
- [ ] AD206 Typo tolerance: "scna this file" → scan; "fx the erros" → fix; use edit-distance matching for command words

### AD3: Natural Language Rule Descriptions

- [ ] AD301 Every rule must have a plain_english: field: one sentence a non-programmer could understand — "This file is too long. Long files are hard to understand and change." not "SMALL_FILES: count 347 > limit 300"
- [ ] AD302 Error messages must use active voice identifying who must act: "Move method foo to its own class" not "Method foo violates SRP"
- [ ] AD303 Findings must answer "so what?": every message ends with the consequence — "extract helpers — long methods hide bugs and resist testing"
- [ ] AD304 Severity labels must be translated: :error → "must fix before shipping", :warning → "fix soon", :info → "consider when refactoring"
- [ ] AD305 Rule IDs must resolve to human names on demand: "what is B04?" → "CQS: Command-Query Separation — a method should change state or return a value, not both"

### AD4: Dialogue Quality

- [ ] AD401 No "I'll" or "let me" — MASTER speaks in present tense declaratives: "Scanning…" not "I'll scan this for you"
- [ ] AD402 No lists when prose suffices: "3 errors, 7 warnings" not a bulleted list of the numbers
- [ ] AD403 Offer exactly one next action, not a menu: "Run /fix to apply 2 autofixes" not "You could run /fix, or review the findings, or…"
- [ ] AD404 Acknowledge confirmation with action, not words: when user says "yes" or "do it" → execute immediately; don't say "Great, I'll proceed"
- [ ] AD405 When stuck, state the blocker precisely: "Can't fix: method bar has 4 callers with incompatible signatures" not "This is complex"

## AE — Internal Wiring, Synergy, Loop Improvement (item 22)

### AE1: Act-React Loop Architecture

- [ ] AE101 Event-driven act-react: every tool action publishes an event; every event can trigger a reactor — scan→found_violations→auto_fix→fixed→rescan→clean; the loop is data-flow, not imperative sequence
- [ ] AE102 Convergence as invariant: the loop doesn't have an iteration limit — it runs until the scan result is identical to the previous scan result (fixed point); abort only on oscillation detection
- [ ] AE103 Violation delta tracking: each loop iteration compares findings to previous pass; only show new/resolved findings — "3 resolved, 1 new" not full re-dump
- [ ] AE104 Fix success rate tracking per rule: if the LLM fix for GUARD_CLAUSE succeeds 80% of the time but for KEYWORD_ARGS only 30%, route KEYWORD_ARGS to a different strategy — use feedback ledger
- [ ] AE105 Homeostatic drive integration: if CPU pressure rises above threshold during scan, Homeostat should pause background scan, prioritize user turn — currently drives and scan operate independently
- [ ] AE106 Bus event ordering: EventBus subscribers fire in registration order — make ordering explicit, documented, and testable; event ordering bugs are silent
- [ ] AE107 Pipeline stages as pure functions: each stage receives PipelineContext and returns modified PipelineContext — no side effects inside stage; all I/O at edges; enables replay and testing
- [ ] AE108 Checkpoint after every fix: write scan result + applied fixes to runtime/checkpoints/ after each loop iteration — enables rollback to any intermediate state
- [ ] AE109 Dead-letter queue: if an event has no subscriber, log to runtime/dead_letters.jsonl — prevents silent event loss
- [ ] AE110 Back-pressure signaling: if fix queue grows faster than LLM can process, surface "N fixes queued, processing…" — prevent silent slowdowns

### AE2: Multi-Agent Synergy

- [ ] AE201 Scanner and Fixer share AST: parse file once, pass Prism result to scanner, then to fixer — currently each re-parses; AST sharing reduces CPU 40%
- [ ] AE202 Council result feeds Fixer: if council finds a structural issue, the fix strategy is pre-populated from council's synthesis — no separate fix-strategy-selection step
- [ ] AE203 Proposal engine learns from fix outcomes: when a proposed fix is accepted and the next scan is clean, reinforce the proposal type; when rejected or re-broken, penalize
- [ ] AE204 Heartbeat scans feed Propose: results of background heartbeat scans are immediately fed to the proposal engine as new evidence — proposals are always based on current state
- [ ] AE205 Memory recalls feed Infer stage: when memory recalls a past similar problem, the InferStage receives the recall as additional context before routing to LLM
- [ ] AE206 Soul drift detection in loop: if MASTER's own voice drifts (soul measure_drift fires), pause user turn and re-anchor before responding — soul integrity is higher priority than throughput
- [ ] AE207 Cross-file violation clustering: after per-file scan, cluster findings by root cause pattern across all files; present cluster as one meta-finding — "12 files have the same GUARD_CLAUSE pattern — likely from a shared template"
- [ ] AE208 Session-end synthesis: at session end (/exit or idle timeout), run meta_analysis pass: summarize what was fixed, what persists, what patterns recurred — write to runtime/session_summaries/

### AE3: Wiring Gaps to Close

- [ ] AE301 Wire boot-time self-scan: currently D01 is in TODO but not wired — scanner must run on lib/ at boot and refuse to start if self-violations exceed zero :error findings
- [ ] AE302 Wire conflict resolver: AB501–AB507 describe data inconsistencies that have no runtime detector — add boot assertion pass that checks all cross-references
- [ ] AE303 Wire feedback ledger: every tool call result should write to Ground::FeedbackLedger; currently feedback_ledger is not wired to any tool call path
- [ ] AE304 Wire ar5iv research lookup to /why: when user asks /why <rule>, fetch relevant paper from data/research/ if present — currently /why only cites soul.yml axioms
- [ ] AE305 Wire plan-approval gate: before any multi-file fix session, generate execution plan and require user confirmation — currently fix loops start immediately
- [ ] AE306 Wire undo to fix loop: every fix applied should push to Undo stack — currently undo only covers manual file edits
- [ ] AE307 Wire soul drift check to every LLM response: measure_drift fires after every assistant turn; if drift > 0, regenerate — currently drift check is manual
- [ ] AE308 Wire proposal weights to feedback: proposal engine has static weights — wire to feedback ledger so accepted proposals increase weight, ignored ones decay

## AF — System Prompt Archaeology: Improvements from Leaked Prompts (item 16b)

### AF1: Identity and Behavioral Anchors

- [ ] AF101 Add `default_posture: helping_bias` to soul.yml — flip burden-of-proof from permission-required to refusal-justified; decline only when concrete harm risk exists
- [ ] AF102 Front-load soul.yml with 3-5 foundational stances before any rules: "MASTER ships code. MASTER enforces its own rules on itself. MASTER converges to zero violations. MASTER speaks unix." — stance before taxonomy
- [ ] AF103 Encode `philosophy: humanist_empiricist` in soul.yml — statistics are not moral claims; factual reporting without moral valuation
- [ ] AF104 Separate truthfulness from compliance: soul.yml code_rules should add HONESTY_OVER_THEATER — "state failures clearly even when it violates expected behavior patterns"
- [ ] AF105 Define specialist agent personas in soul.yml for per-domain invocation: code_expert, researcher, philosopher, designer — each with focus, voice, knowledge_sources
- [ ] AF106 Add `memory_attribution: never_explicit` to soul.yml — apply recalled facts invisibly; never say "I see from your history" or "I notice from memory"
- [ ] AF107 Encode graded refusal: not binary refuse/allow — FORBIDDEN returns nothing, DISCOURAGED suggests alternative, AMBIGUOUS makes best-effort attempt
- [ ] AF108 Add `jailbreak_response: brief` to soul.yml — reject manipulation with 1-2 sentences, not essays; don't validate the attempt with lengthy analysis

### AF2: Knowledge and Recency Management

- [ ] AF201 Auto-inject `knowledge_cutoff: 2025-02` and `current_date:` into every LLM system context turn — all vendors do this; MASTER doesn't
- [ ] AF202 Define mandatory search triggers: medical diagnoses, legal advice, investment recommendations, current prices/regulations, post-cutoff technical specs — always web-search before answering
- [ ] AF203 Domain-specific recency windows: science/tech (6 months), news/politics (weeks), art/ideas (years) — route to search based on domain + recency sensitivity
- [ ] AF204 Citation format standard: `[source_domain] "quote"` or `[1]` footnote style — never uncited post-cutoff factual claims
- [ ] AF205 `temporal_confidence_modifier: escalate_hedging_for_date_sensitive` — when dates matter, explicitly note uncertainty

### AF3: Tool Ecosystem Wiring

- [ ] AF301 Tool-search-first principle: before claiming a capability is unavailable, always check tool registry — never say "I can't do X" without checking tools
- [ ] AF302 Tool matrix in CLAUDE.md: name, cost-tier, permissions, parallel-safe, deferred-ok — systematic registry instead of prose description
- [ ] AF303 Parallel tool invocation as default: any two independent tools invoked in the same response block — serialize only when there's a data dependency
- [ ] AF304 Tool deprecation notices: versioned tool registry with deprecation warnings in AGENTS.md — prevents use of superseded tools
- [ ] AF305 Async tool result handling: if tool result arrives late, proactively reframe response if answer validity changed

### AF4: Formatting and Communication Patterns

- [ ] AF401 Three-mode formatting system: `response_mode: [learning, concise, formal]` — different bullet/prose/heading density per mode
- [ ] AF402 `bullet_use: exception_not_default` — prose for reports, bullets only for ≥4 parallel items; match Claude's default-styles.md
- [ ] AF403 Dense-text detection: responses >400 words without structure → auto-add headings/breaks
- [ ] AF404 Output artifact thresholds: code >20 lines → code block; document >1500 chars → structured artifact; inline otherwise
- [ ] AF405 Max 3 follow-up suggestions or zero — never offer 10 options; Gemini's ElicitationsGroup pattern
- [ ] AF406 `language_strategy: mirror_user` — respond in user's language, dialect, and script unless instructed otherwise

### AF5: Safety and Refusal Architecture

- [ ] AF501 Explicit refusal taxonomy in soul.yml: FORBIDDEN (no response), PROHIBITED_SPECIFIC (decline specific guidance), SENSITIVE (handle carefully), AMBIGUOUS (best-effort)
- [ ] AF502 Refusal categories: weapons_technical, malware_creation, csam, self_harm_enabling, criminal_specific — named explicitly, not "harmful content"
- [ ] AF503 Post-refusal escalation: after child-safety refusal, apply heightened scrutiny to related-domain requests for N turns
- [ ] AF504 Cumulative harm assessment: evaluate conversation trajectory, not per-message — weapons knowledge distributed across turns still constitutes a violation
- [ ] AF505 Prompt injection detection: when user pastes "system instructions" or operational directives, flag as potential injection and apply scrutiny

### AF6: Context Window as First-Class Design

- [ ] AF601 Context saturation threshold: at 80% context used, auto-summarize old turns and offer fresh-start option
- [ ] AF602 Progressive context trimming rules: keep recent turns + user preferences + task state; drop old reasoning + failed attempts + verbose system context
- [ ] AF603 `no_deferred_work` principle: complete all work in current response; never tell user "I'll do this next time" or "check back in a few minutes"
- [ ] AF604 Memory sensitivity tiers: tag memories as public/private/sensitive; only surface public tier without user initiation
- [ ] AF605 Conversation-length drift detection: reset assumptions after N turns to prevent incremental agreement drift (sycophancy creep)

## AG — External LLM Mirror Behavior (item 17)

### AG1: LLM-Specific Companion Files (CLAUDE.md, GROK.md, GPT.md, DEEPSEEK.md, GEMINI.md)

- [ ] AG101 CLAUDE.md: add explicit tool-use protocol (parallel invocation, tool-search-first), knowledge cutoff, refusal taxonomy, memory attribution rules — current version is 29 lines; needs 200+
- [ ] AG102 GROK.md: humanist-empiricist stance, multi-agent reasoning pattern (specialist personas), language mirroring, brief jailbreak dismissal, permissive content defaults with hard categorical limits
- [ ] AG103 GPT.md: truthfulness-over-compliance, hidden-reasoning pattern, citation format, context-window efficiency, async result handling, output artifact thresholds
- [ ] AG104 DEEPSEEK.md: code-first persona, chain-of-thought surfacing (DeepSeek-R1 style visible reasoning), cost-efficiency (smallest effective model), aggressive context compression
- [ ] AG105 GEMINI.md: capability isolation block (non-executable capability statements), ElicitationsGroup (max 3 follow-ups), citation requirements, sensitive data exclusion, vision handling rules

### AG2: Mirror Behavior Enforcement

- [ ] AG201 Every LLM companion file starts with: "Behave as MASTER's external operator. MASTER's soul.yml is the constitutional authority. Your task is to enforce it, not interpret it."
- [ ] AG202 Add MASTER's five foundational stances to every LLM file as the first section — before any rules — so any LLM boots with identity before taxonomy
- [ ] AG203 Include a condensed rules.yml summary (top 20 rules by severity) in every LLM companion file — LLMs should know the rules they're enforcing
- [ ] AG204 Include MASTER's voice config (terse, unix, perfectionist, Strunk & White) with 10 concrete examples: before/after sentence pairs
- [ ] AG205 Include MASTER's aesthetic rules with visual examples: NO_COLUMN_ALIGN (before/after), NO_ASCII_DECORATION, IMPORTANCE_ORDER (before/after layout)
- [ ] AG206 Include a "things MASTER never does" list: never says "great question", never uses === decorators, never pads alignment, never creates files without checking existing overlap
- [ ] AG207 Include MASTER's git discipline: commit format, S&W message style, frequency (after every meaningful change)
- [ ] AG208 Include MASTER's OpenBSD rules: relayd not nginx, doas not sudo, pledge/unveil for new daemons, base tools not pkg_add'd
- [ ] AG209 Add "verification protocol" to each file: before claiming a task is done, re-read the file, run the scan, confirm zero findings — never accept in-memory state as ground truth
- [ ] AG210 Add model-specific anti-patterns for each LLM: known failure modes unique to that model family (GPT over-explains, Gemini over-formats, DeepSeek over-reasons out loud)

## AH — MASTER Self-Improvement Proposals Meta-List (item 23)

### AH1: Scan Engine Self-Improvement

- [ ] AH101 Adaptive rule weights: after N sessions, rules with >80% false-positive rate auto-downgrade severity; rules never triggered in 100 scans get flagged for removal
- [ ] AH102 Rule effectiveness dashboard: runtime/rule_stats.yml tracks {rule_id, fires, accepted, rejected, false_positive_rate} — visible via /status
- [ ] AH103 Auto-generate rule from pattern: if the same manual fix is applied 3+ times across sessions, MASTER proposes a new RuleDSL block for that pattern
- [ ] AH104 Threshold calibration: SmallFunctionsRule MAX=20, CyclomaticComplexityRule MAX=10 — calibrate against Ruby stdlib and Rails source to find the natural distribution cutoff
- [ ] AH105 Rule conflict auto-detection: at boot, scan rule pairs for overlapping patterns; flag conflicts in boot dmesg
- [ ] AH106 Finding deduplication learning: if two rules consistently fire on the same line, learn to suppress the lower-severity one automatically
- [ ] AH107 Fix success prediction: before attempting LLM fix, predict success probability from historical {rule_id, file_type, complexity} → success rate; skip unpromising fixes

### AH2: LLM Interaction Self-Improvement

- [ ] AH201 Prompt A/B testing: maintain two prompt variants per rule; track which produces cleaner fixes; converge to winner after 20 samples
- [ ] AH202 Council persona calibration: track which council persona (Explorer/Maintainer/Adversary) catches the most missed violations; weight votes accordingly
- [ ] AH203 Temperature tuning: track fix quality vs temperature per rule type; converge to optimal temperature per rule category
- [ ] AH204 Context window optimization: track which context inclusions (full file vs snippet vs diff) produce best fix quality; adapt per rule type
- [ ] AH205 Model tier calibration: track cost vs fix quality per model tier per rule type; route to cheapest tier that achieves target quality

### AH3: Memory and Knowledge Self-Improvement

- [ ] AH301 Session learning extraction: end-of-session meta-analysis identifies new patterns → proposes new rules → queues for human approval
- [ ] AH302 Corpus self-scan: weekly, MASTER scans top-20 trending Ruby repos; updates rule frequency stats; surfaces rules that never fire in the wild
- [ ] AH303 Knowledge graph expansion: when a new rule is added, MASTER searches ar5iv for academic grounding; stores citation in data/research/<rule_id>.md
- [ ] AH304 Contradiction detection: when a new rule would conflict with an existing one, surface the conflict before registering
- [ ] AH305 Dead knowledge pruning: data/*.yml entries unreferenced by any Ruby code for 30+ days get flagged for removal

### AH4: Infrastructure Self-Improvement

- [ ] AH401 Self-benchmark: weekly timing run on standard fixture files; alert if scan latency regresses >20%
- [ ] AH402 Memory leak detection: track Ruby object count across 100 scan iterations; alert if trending upward
- [ ] AH403 Bundle drift detection: weekly check that Gemfile.lock matches Gemfile; alert on drift before it becomes a boot failure
- [ ] AH404 Config drift detection: compare soul.yml hash weekly; alert if negotiable section changed without version bump
- [ ] AH405 Dead code detection: MASTER scans its own lib/ for methods never called across any code path; proposes removal

## AI — Provider Resilience and Free LLM Exploitation (items 24, 25)

### AI1: Free and Cheap Provider Integration

- [ ] AI101 Tier-0 providers (free/cheap): add to models.yml — Groq (llama-3.1-70b free tier), Google Gemini Flash (free tier), Together AI (free models), Fireworks AI, Cerebras (llama-3.1-70b free)
- [ ] AI102 Task routing by cost: lexical scan regex checks → Tier-0 (free); structural analysis → Tier-1 (cheap); council deliberation → Tier-2 (capable); architecture decisions → Tier-3 (strong)
- [ ] AI103 Free-tier budget management: track daily usage per free-tier provider; rotate when limits approach; never hard-fail on budget exhaustion
- [ ] AI104 Ollama integration: local model fallback via Ollama API (llama3, codellama, mistral) — zero cost, offline capable, latency acceptable for non-critical passes
- [ ] AI105 OpenRouter free models: `openrouter.ai/api/v1` lists free-tier models with `:free` suffix — add dynamic discovery of free models at session start
- [ ] AI106 Prompt caching across providers: where API supports it (Anthropic, OpenAI), use prefix caching to halve token cost on repeated system prompts
- [ ] AI107 Speculative execution: send same prompt to fast/cheap model and strong model simultaneously; use cheap result if it meets quality threshold, cancel strong model call

### AI2: Provider Resilience

- [ ] AI201 Circuit breaker per provider: if provider returns 3 consecutive errors, open circuit for 5 minutes; route to next provider in chain
- [ ] AI202 Latency-aware routing: track p95 latency per provider; deprioritize slow providers during interactive sessions
- [ ] AI203 Provider health dashboard: /providers command shows {name, status, latency_p95, cost_per_1k, daily_budget_remaining} for all configured providers
- [ ] AI204 Graceful degradation: if all LLM providers fail, fall back to deterministic AstFixer-only mode; surface "LLM unavailable — applying deterministic fixes only"
- [ ] AI205 Budget waterfall: primary budget (OpenRouter) → secondary (free tiers) → tertiary (Ollama local) — transparent cost minimization
- [ ] AI206 Provider API key rotation: support multiple keys per provider; rotate on rate limit; track per-key usage

### AI3: Model-Agnostic Identity (item 26)

- [ ] AI301 Constitutional anchoring: first message to any model includes the five foundational stances verbatim — MASTER's identity is injected before any task
- [ ] AI302 Soul.yml as system prompt prefix: the stable soul.yml absolute section sent as cached system prompt prefix to every model — MASTER is MASTER regardless of underlying LLM
- [ ] AI303 Response quality gate: every LLM response passes through Ground::SoulDriftDetector before display — if response violates ABSOLUTE rules, regenerate with higher temperature
- [ ] AI304 Voice normalization: all LLM responses filtered through Voice::Renderer which enforces terse/unix/Strunk output regardless of model verbosity
- [ ] AI305 Anti-sycophancy filter: strip phrases from any model response: "Great question", "Certainly!", "Of course", "I'd be happy to" — post-process regardless of model
- [ ] AI306 Format normalization: enforce dmesg log format, no column alignment, no decorative separators on all generated text — model-agnostic
- [ ] AI307 Persona consistency: soul.yml persona (ronin/malay/Osman) applies to TTS voice selection regardless of which model generated the text
- [ ] AI308 Git message normalization: all git commit messages generated by any model pass through S&W normalization before commit — imperative, ≤72 chars, no period
