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
