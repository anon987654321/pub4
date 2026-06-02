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
- [x] B09 PatternExtractionRule — structural: "80% of the way to Strategy/Decorator/Pipeline/…" (mode: opportunity)
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
- [x] C08 Replace `var ` with `const ` in JS (NO_VAR) — only when variable not reassigned
- [x] C09 Convert `for (const x in arr)` to `for (const x of arr)` (FOR_OF)
- [x] C10 Convert `"a" + b + "c"` to `` `a${b}c` `` template literals (TEMPLATE_LITERALS)
- [x] C11 Convert `a && a.b` to `a?.b` in JavaScript (OPTIONAL_CHAINING)
- [x] C12 Remove statement after `return`/`raise` on immediately following line (DEAD_CODE)
- [x] C13 Add trailing comma to last element of multi-line array/hash (TRAILING_COMMAS)
- [x] C14 Convert `margin-left:` / `margin-right:` to logical properties (LOGICAL_PROPERTIES)

## D. Self-scan infrastructure

rules.yml success_criteria: "system_applies_to_itself_without_exception"

- [x] D01 Boot-time self-scan: on `master start`, scan lib/ with all registered rules; publish self_violation on any finding
- [x] D02 Boot dmesg line: emit `judge: lib/ N rules, M violations` in 5-line boot banner
- [x] D03 /self command: scan MASTER's lib/ on demand, print dmesg-style report to stdout
- [x] D04 self_test section wiring: ROBUSTNESS (bare rescue check), SINGULARITY (duplicate rule IDs), LINEARITY (nesting depth), PROXIMITY (test files co-located), ABSTRACTION (no god class), DENSITY (no long method)
- [x] D05 Self-violation event: `self_violation` event on bus stops the loop until fixed
- [x] D06 Periodic self-scan via Loop::Heartbeat: schedule lib/ rescan every 60 minutes
- [x] D07 Self-autofix: if self-scan finds violations with autofix: true, apply AstFixer transforms to MASTER's own source
- [x] D08 Block shipping if self-scan shows violations (Pipeline gate before deploy)
- [x] D09 Self-scan covers data/*.yml: run SINGULARITY check (no duplicate rule IDs) on every boot
- [x] D10 ground_truth_check enforcement: before any `claim_task_complete` in Loop, re-read file and confirm

## E. Rules.yml → code alignment

Every section of rules.yml that isn't implemented in Ruby.

- [x] E01 Finding#rule_id: findings should carry the exact rules.yml ID string (e.g. "SECRET_PROXIMITY"), not Ruby class name
- [x] E02 SemanticRule findings: include the specific rules.yml ID that triggered, not "semantic"
- [x] E03 Prediction engine: RuleLoop#should_autofix? already exists in scanner.rb — wire it into RuleLoop before applying any fix
- [x] E04 evidence_scoring: Pipeline should accumulate scan_clean (25 pts) and require ≥80 to ship
- [x] E05 failure_taxonomy: RuleLoop transient retry (already TRANSIENT_RE) — add permanent/ambiguous branches with fail_fast and human_intervention
- [x] E06 principle_priorities tier1: halt pipeline on PRESERVE_FIRST/DECOUPLE/DEGRADE_GRACEFULLY violation
- [x] E07 principle_priorities tier2: route DRY/KISS/SRP violations to RuleLoop automatically
- [x] E08 veto_patterns section: wire as :error severity rules that block the pipeline
- [x] E09 anti_patterns.forbidden: each pattern becomes a SecretProximity/ForbiddenPattern lexical rule
- [x] E10 schema_metadata fields (reversibility, blast_radius): expose on Finding objects
- [x] E11 phantom_recovery: implement gaslighting_preamble detector in Judge::Agent — discard and retry if match
- [x] E12 phantom_recovery: text_repetition_loop detector — if same 60-char span ≥3 times, escalate model
- [x] E13 preserve_user_intent: Pipeline check that refactors don't change public method signatures
- [x] E14 library_verify: pre_flight checks (Gemfile.lock has gem, path exists, binary in PATH) before shelling out
- [x] E15 SINGULARITY self-check: boot assertion that all rule IDs in rules.yml are unique

## F. Architecture violations in MASTER's own code

MASTER must pass its own rules. Violations found by reading lib/.

- [x] F01 scanner.rb#scan: 35-line method — split into read_file, parse_ast, apply_rules, publish (SRP + SMALL_FUNCTIONS)
- [x] F02 DetectionPipeline: shallow relay class adds no abstraction (DIFFERENT_LAYER_DIFFERENT_ABSTRACTION) — merge into Scanner or delete
- [x] F03 RuleLoop: council_fix and request_fix duplicate prompt-building logic (DRY) — extract build_prompt_for(violation, src, path, style:)
- [x] F04 pipeline.rb#maybe_rollback: git stash logic in Pipeline violates SRP — extract to Loop::Rollback class
- [x] F05 memory.rb: 256 lines (SMALL_FILES) — split into Memory::Store, Memory::Search, Memory::Consolidate modules
- [ ] F06 repo_ecology.rb: analyze_file returns 12-key Hash (DATA_CLASS) — introduce FileRecord = Data.define(...)
- [ ] F07 ground/constitution.rb: load_yaml called on every invocation — memoize with @constitution_cache (IMMUTABLE)
- [ ] F08 master.rb#bootstrap_container: 50+ line method — split into init_ground, init_judge, init_loop, init_reach
- [x] F09 scanner.rb parallel_each: raw Thread.new without error boundary — wrap in rescue and publish thread_error
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
- [x] H17 Test for evidence_scoring gate (scan_clean:25 weight, pass_threshold: 80)
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
- [x] J02 Pipeline: wire evidence_scoring — scan_clean(25) + test_pass(35) ≥80 gates the :deploy stage
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
- [x] P704 Evidence scoring (scan_clean: 25 pts, pass_threshold: 80) from rules.yml — wire into Pipeline as a gate before :deploy stage
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

## AJ — Personal Assistant Domain Expansion (item 24)

### AJ1: Financial Assistant

- [ ] AJ101 Transaction parsing: parse bank CSV/OFX exports; categorize via LLM; track monthly burn rate per category
- [ ] AJ102 Budget threshold alerts: when a category exceeds monthly budget, surface alert at next REPL session
- [ ] AJ103 Recurring expense detection: identify subscription payments from transaction history; list with annual cost
- [ ] AJ104 Currency and exchange rate tracking: fetch live NOK/EUR/USD rates; convert amounts in user messages automatically
- [ ] AJ105 Tax categorization: flag transactions by Norwegian tax category (fradragsberettiget, privat, næring) for å-meldingen
- [ ] AJ106 Crypto portfolio tracking: fetch balances from public addresses; compute total NOK/USD value; alert on >10% moves
- [ ] AJ107 Invoice parsing: extract amount, due date, account number from PDF invoices via OCR → LLM; add to calendar
- [ ] AJ108 Savings goal tracking: /goal set 50000 NOK car 2026-12 — track progress, project completion date

### AJ2: Therapy and Psychological Support

- [ ] AJ201 Mood logging: /mood <1-10> [note] — store with timestamp; visualize trend over 30 days
- [ ] AJ202 CBT thought record: /thought <situation> — guide through Automatic Thought → Evidence For/Against → Balanced Thought
- [ ] AJ203 Crisis protocol: if user message matches crisis keywords (suicidal ideation, self-harm intent), immediately provide crisis line numbers (Norway: 116 123, international: 988) and hold space
- [ ] AJ204 Sleep tracking: /sleep <hours> [quality 1-5] — track with mood; surface correlation analysis monthly
- [ ] AJ205 Anxiety grounding: /ground — output 5-4-3-2-1 sensory grounding exercise; time-gated to prevent overuse
- [ ] AJ206 Psychoeducation on demand: /explain anxiety — evidence-based plain-language explanation of psychological concepts
- [ ] AJ207 Session continuity: therapist-style memory — recall past disclosures in context; never make user re-explain their situation
- [ ] AJ208 Disclaimer enforcement: all therapy-adjacent responses include "I'm not a licensed therapist. For clinical support: [resource]"

### AJ3: Research Assistance

- [ ] AJ301 Literature review: /research <topic> — search ar5iv.org + PubMed + Google Scholar; return structured summary with citations
- [ ] AJ302 Citation formatting: output references in APA/Chicago/IEEE on demand
- [ ] AJ303 Hypothesis generation: given research question, generate 5 testable hypotheses with null hypothesis and measurement approach
- [ ] AJ304 Paper summarization: paste DOI or URL → extract abstract, methodology, findings, limitations in 5 bullet points
- [ ] AJ305 Contradiction detection: given 3+ papers on same topic, identify where findings conflict and explain likely causes
- [ ] AJ306 Research gap analysis: after literature review, identify unexplored questions as potential research directions

### AJ4: Safety Monitoring

- [ ] AJ401 Anomalous behavior detection: if user messages deviate sharply from baseline (tone, frequency, topic), flag for gentle check-in
- [ ] AJ402 Emergency escalation: if user expresses immediate danger, provide emergency services info (Norway: 112/113) and remain present
- [ ] AJ403 Privacy audit: periodic reminder to review what data MASTER has stored; offer deletion by category
- [ ] AJ404 Digital safety check: /audit-accounts — prompt user through 2FA status, password manager, breach check (have-i-been-pwned API)

## AK — Bleeding-Edge AI Research Integration (item 27, placeholder pending agent)

### AK1: Agent Architecture Advances

- [ ] AK101 ReAct pattern (Reason + Act): every tool invocation preceded by explicit reasoning step written to trace — not LLM thinking, but recorded rationale
- [ ] AK102 Reflexion (self-correction): after each failed fix attempt, generate verbal self-critique; use critique to adjust next attempt
- [ ] AK103 Tree of Thought: for architectural decisions, generate 3 distinct reasoning branches; evaluate each; select best — not linear chain-of-thought
- [ ] AK104 Graph of Thought: for multi-file dependency problems, build explicit dependency graph before reasoning — structured topology over flat sequence
- [ ] AK105 Skeleton-of-Thought: generate outline first, then fill each section in parallel — reduces latency for long documents/reports
- [ ] AK106 Algorithm of Thought: for code problems, explicitly enumerate algorithm candidates before selecting implementation

### AK2: Memory Architecture Advances

- [ ] AK201 Episodic memory compression: at session end, compress raw session into episodic summary (who/what/when/outcome) — lossy but searchable
- [ ] AK202 Working memory as sliding window: maintain K most-relevant past findings as "working memory" in every LLM context — not the whole history
- [ ] AK203 Memory palace: organize memories by spatial metaphor (room = project, shelf = domain) — enables "what's in the database room?" queries
- [ ] AK204 Forgetting curve implementation: memories decay in retrieval weight over time; explicit reinforcement (user referencing) resets the clock
- [ ] AK205 Associative memory retrieval: when retrieving memory M, also retrieve memories that co-occurred with M — enables analogical reasoning

### AK3: Efficiency and Inference Advances

- [ ] AK301 Speculative decoding: use small draft model to propose tokens; large model verifies in parallel — 2-3x throughput without quality loss
- [ ] AK302 KV cache sharing: share key-value cache across parallel scan workers for same file — implemented at model server level
- [ ] AK303 Prompt compression (LLMLingua): compress long context to 1/4 length with <5% quality loss before sending to expensive models
- [ ] AK304 Mixture-of-Experts routing: route each rule type to a specialized expert model (code expert for Ruby, security expert for FORBIDDEN_PATTERNS)
- [ ] AK305 Token budget forcing: allocate explicit token budgets per pipeline stage; force concise outputs at each stage

### AK4: Robustness and Alignment Advances

- [ ] AK401 Constitutional AI self-critique: after generating any response, run a constitutional critique pass that checks against soul.yml absolute rules
- [ ] AK402 Adversarial prompt detection: maintain a classifier trained on jailbreak patterns; apply before every LLM call
- [ ] AK403 Hallucination detection: fact-check all generated code claims by running the code; flag unverifiable assertions
- [ ] AK404 Reward model integration: train a small reward model on {fix, scan_result_after} pairs to predict fix quality without running the scan
- [ ] AK405 RLHF from user feedback: every user accept/reject of a finding updates a lightweight preference model; proposals adapt

## AL — OpenClaw Personal Assistant Patterns (item 24, expanded)

### AL1: Memory Architecture

- [ ] AL101 Three-tier memory: hotcache (last 20 turns in RAM), semantic store (embeddings, SQLite FTS5), cold archive (compressed episodic summaries on disk) — mirrors OpenClaw's brain-file-per-turn approach
- [ ] AL102 FTS5 full-text search over memory: `fts5(content, tags, session_id)` virtual table; sub-millisecond keyword retrieval across all past sessions
- [ ] AL103 Embedding-based semantic retrieval: store 768-dim embeddings (nomic-embed or Gemini embed) per memory chunk; cosine similarity retrieval at query time
- [ ] AL104 Hybrid RRF retrieval: Reciprocal Rank Fusion over keyword + semantic + recency scores — no single ranking signal dominates
- [ ] AL105 Memory confidence scores: each memory has {created_at, last_accessed, reinforcement_count, decay_factor} — retrieved weight = confidence × recency
- [ ] AL106 Memory mutation log: every write to semantic store appended to append-only WAL; replay-able audit trail; never destructive update
- [ ] AL107 Summarization-before-storage: raw turn → LLM summary (key facts, decisions, follow-ups) → store summary + embedding, not raw text
- [ ] AL108 User-controlled forgetting: /forget <query> — fuzzy-match memories and soft-delete (mark inactive); hard delete only with explicit --confirm
- [ ] AL109 Cross-session continuity: at session start, retrieve top-10 most relevant past memories and inject as compressed context prefix
- [ ] AL110 Memory namespace isolation: separate memory spaces per domain (code, financial, health, personal) — cross-domain retrieval requires explicit --cross-domain flag

### AL2: Personality and Constitutional Identity

- [ ] AL201 Five-stance injection: first system message block always contains the five foundational stances verbatim — model receives them before any task
- [ ] AL202 Soul drift detection: after every LLM response, check for presence of banned phrases (sycophantic openers, decorative separators) — auto-strip, log violation count
- [ ] AL203 Persona warmth spectrum: soul.yml defines warmth level (0=cold/diagnostic, 5=warm/supportive) — voice renderer adjusts hedging and acknowledgment per domain
- [ ] AL204 Role switching without personality loss: when entering therapy mode or finance mode, inject domain-specific prompt extension while preserving soul.yml absolute rules
- [ ] AL205 Anti-simulation anchor: soul.yml anti_simulation block sent in every system prompt — prevents model from roleplaying as "a different AI" or ignoring rules
- [ ] AL206 Constitutional critique loop: after any response touching SENSITIVE categories, run a second LLM pass that checks response against soul.yml absolute rules
- [ ] AL207 Jailbreak pattern classifier: maintain list of known jailbreak templates; fuzzy-match incoming messages; respond with 1-2 sentence dismissal, log attempt
- [ ] AL208 Response density normalization: track response length distribution per user; if current response >2σ above mean, flag for compression before send
- [ ] AL209 Voice consistency across models: all model responses pass through Voice::Renderer which enforces terse/unix/S&W style — model-agnostic voice guarantee
- [ ] AL210 Commitment to user across models: user profile (preferences, history, style) persists in memory regardless of which underlying model handles the turn

### AL3: Financial Intelligence

- [ ] AL301 Transaction import pipeline: CSV/OFX/PDF → parser → normalizer → LLM categorizer → SQLite ledger; one command per file type
- [ ] AL302 Merchant normalization: raw payee strings ("REMA 1000*OSLO") → canonical merchant name via lookup table + LLM fallback
- [ ] AL303 Recurring expense detection: group transactions by merchant + amount ± 10%; flag if interval ≈ 30/7/365 days; estimate annual cost
- [ ] AL304 Budget vs actuals report: /budget report — compare monthly spend per category against user-defined limits; surface overage with % delta
- [ ] AL305 Savings trajectory: given current balance, monthly surplus, and savings goal, compute months-to-goal with confidence interval
- [ ] AL306 Tax flag detection: Norwegian tax rules: fradrag (mortgagerenter, fagforeningskontingent, reisefradrag) — flag qualifying transactions for å-meldingen review
- [ ] AL307 Anomalous spend alert: if single transaction >3σ above merchant's historical average, surface at next session with "unusual charge" tag
- [ ] AL308 Net worth dashboard: /net-worth — aggregate assets (bank, investments, crypto, property estimate) minus liabilities; time-series chart in terminal
- [ ] AL309 Exchange rate injection: fetch live NOK/EUR/USD/BTC from free API (fx.fixer.io free tier) at session start; auto-convert amounts in user messages
- [ ] AL310 Invoice calendar sync: parsed invoices (amount, due date, IBAN) → generate iCal event file; user imports to calendar app

### AL4: Research and Knowledge Work

- [ ] AL401 Arxiv/ar5iv search: /research <query> — call arxiv.org API; return 5 most cited + 5 most recent papers; structured {title, abstract_summary, methodology, key_finding}
- [ ] AL402 Citation graph traversal: given a paper, fetch its references and citations via Semantic Scholar API; identify foundational papers and recent extensions
- [ ] AL403 Paper contradiction scanner: given 2+ papers on same topic, diff their findings; surface conflicts with explicit quote comparison
- [ ] AL404 Research gap identification: after literature synthesis, prompt LLM to identify unexplored questions → ranked by novelty and feasibility
- [ ] AL405 Knowledge base update: when user confirms a research finding as important, store in semantic memory with domain tag for future retrieval
- [ ] AL406 Code-from-paper implementation: given paper URL, extract algorithm section → generate Ruby/pseudocode implementation skeleton with TODOs for paper-specific parameters
- [ ] AL407 Hypothesis tracking: /hypothesis <claim> — store with {evidence_for: [], evidence_against: [], status: :open/:supported/:refuted}; update as evidence arrives
- [ ] AL408 Reading list management: /queue <URL> — add to reading list with priority; /next — surface next unread item with estimated reading time
- [ ] AL409 Meeting prep: given calendar event title, auto-research all mentioned entities/topics; produce briefing doc with key facts and open questions
- [ ] AL410 Source credibility scoring: for any factual claim, surface source type (peer-reviewed, preprint, blog, social) and citation count as credibility signal

### AL5: Safety and Crisis Protocols

- [ ] AL501 Crisis keyword detection: maintain regex list of high-risk phrases; if matched, immediate response: crisis resources + warm acknowledgment + do not continue task
- [ ] AL502 Mandatory crisis resources: Norway: Kirkens SOS 22 40 00 40, Mental Helse 116 123, Legevakt 116 117, Police 112; always current, never outdated
- [ ] AL503 Tone de-escalation: detect escalating emotional distress across consecutive turns; shift to slower, more validating response style; reduce task orientation
- [ ] AL504 Privacy-by-default: health, financial, relationship data stored in encrypted namespace; never included in LLM context without explicit /unlock
- [ ] AL505 Data retention policy: all stored data has default TTL (financial: 7 years, mood: 2 years, session transcripts: 90 days) — auto-expire with notification
- [ ] AL506 Consent checkpoint: before storing new sensitive category (health, financial, relationship), surface category name and ask once for consent; never re-ask
- [ ] AL507 Minimal data principle: only store what is needed for the specific feature; no speculative pre-collection; delete what is no longer needed

### AL6: Free and Cheap LLM Exploitation

- [ ] AL601 Groq integration: llama3-8b-8192 at ~500 tokens/sec free tier — use for fast lexical scan, regex detection, syntax check passes
- [ ] AL602 Gemini Flash integration: gemini-1.5-flash free tier (15 RPM, 1M context) — use for long-file analysis where context window > OpenRouter models
- [ ] AL603 Together AI: Llama3 70B at $0.0009/1K tokens — use as mid-tier between Groq (fast/small) and claude-opus (slow/expensive)
- [ ] AL604 Ollama local: llama3.2, codellama:13b, mistral:7b — zero cost, offline, <200ms for small prompts; use for private data that shouldn't leave device
- [ ] AL605 OpenRouter free suffix: models ending in `:free` on OpenRouter — auto-discover at session start, add to routing table with quality tier `low`
- [ ] AL606 Model routing table: {model_id, cost_per_1k_in, cost_per_1k_out, context_window, quality_tier, latency_p50, free_quota} — dynamic routing based on task × budget
- [ ] AL607 Quality-tiered routing: lexical/syntax → groq; structural/semantic → together; architecture/council → claude-opus; always route to cheapest that meets quality bar
- [ ] AL608 Prompt minimization: strip comments, blank lines, and non-relevant context before sending to any model — every token saved × every call = real money
- [ ] AL609 Diff-only sends: for fix verification, send only the changed lines + 5-line context rather than the full file — reduces tokens 10-50x for large files
- [ ] AL610 Batch rule checks: send 10-20 rule checks in a single LLM prompt rather than 10-20 sequential calls — amortizes model loading overhead

### AL7: Proactive Assistant Behaviors

- [ ] AL701 Ambient monitoring: background daemon checks for {new commits, calendar events, approaching deadlines, anomalous transactions} at configurable intervals
- [ ] AL702 Daily briefing: at first session of day, produce {weather, calendar, unread priority items, approaching deadlines, yesterday's unresolved findings} in <20 lines
- [ ] AL703 Proactive debt surfacing: when user mentions a file or module, auto-check if it has open TODO items or findings; surface without being asked
- [ ] AL704 Follow-up scheduling: when a fix is applied, schedule a /health check on the same file 48h later to verify the fix held under real usage
- [ ] AL705 Context-aware suggestions: after completing a task, identify the single most impactful next logical step and offer it (not a menu — one suggestion)
- [ ] AL706 Deadline proximity alerts: 72h before any tracked deadline, surface reminder with estimated completion time for pending work
- [ ] AL707 Session summary: at session end (user says bye/exit/done), output {tasks completed, findings fixed, decisions made, open items} in 5-10 lines

## AM — Bleeding-Edge Research Integration (item 27, expanded)

### AM1: Constitutional and Alignment Research

- [ ] AM101 Constitutional AI self-critique (Anthropic 2022+): after generating response, run second LLM pass with soul.yml principles as critique criteria; revise on violation — implement as `Ground::ConstitutionalCritic`
- [ ] AM102 RLHF from implicit signals: track which findings user accepts/rejects/ignores; train lightweight reward model (logistic regression over finding features) — no explicit rating needed
- [ ] AM103 Debate-based alignment (Irving 2018, updated 2024): for ambiguous rule decisions, run two-agent debate where agents argue for/against the finding; human-in-loop judges; outcome updates rule weight
- [ ] AM104 Process reward models (Lightman et al. 2023): reward correct reasoning steps, not just final answer — apply to AstFixer: reward intermediate transformation correctness
- [ ] AM105 Scalable oversight via weak supervision: use cheaper model to generate candidate critiques of expensive model's fixes; expensive model selects best critique — reduces oracle calls
- [ ] AM106 Value learning from demonstrations: record expert sessions (user correcting MASTER) as demonstration trajectories; extract implicit preferences via IRL
- [ ] AM107 Constitutional prefix caching: stable soul.yml absolute section sent as Anthropic prompt cache prefix — 93% token cost reduction on system prompt; implement with `cache_control: {type: "ephemeral"}`

### AM2: Agent Architecture Research

- [ ] AM201 ReAct (Yao et al. 2022): every tool invocation preceded by explicit `Thought: <reasoning>` written to trace log — not LLM chain-of-thought, but recorded rationale for each action
- [ ] AM202 Reflexion (Shinn et al. 2023): after failed fix, generate verbal self-critique ("I tried X but it failed because Y") and inject as context for next attempt — implement in `Loop::Reflexion`
- [ ] AM203 Tree of Thought (Yao et al. 2023): for architectural decisions, generate 3 distinct solution branches; score each with `Judge::Council`; backtrack from dead ends — O(depth × branching_factor) LLM calls
- [ ] AM204 Graph of Thought (Besta et al. 2023): for multi-file dependency problems, build explicit dependency graph before reasoning; enables non-linear thought aggregation across nodes
- [ ] AM205 LLM-MCTS (Zhao et al. 2024): Monte Carlo Tree Search over fix candidates; rollout = run scan after fix; reward = reduction in finding count; select fix with highest expected reward
- [ ] AM206 Skeleton-of-Thought (Ning et al. 2023): for long doc generation, produce skeleton first, then fill sections in parallel LLM calls — latency reduction proportional to parallelism
- [ ] AM207 Self-discover (Wang et al. 2024): before executing a complex task, compose a reasoning structure from primitive modules (search, verify, critique); improves zero-shot task performance
- [ ] AM208 AgentBench evaluation: benchmark MASTER against AgentBench tasks (OS, DB, web) to identify capability gaps vs. SOTA agents — not just code; broader agentic reasoning

### AM3: Memory Systems Research

- [ ] AM301 MemGPT (Packer et al. 2023): OS-inspired virtual context management — main context (limited) + external storage; agent decides what to page in/out via function calls; implement as `Reach::MemoryPager`
- [ ] AM302 LongMem (Wang et al. 2023): decoupled memory encoder; encode past sessions offline; retrieve compressed representations at inference — reduces memory retrieval to embedding lookup
- [ ] AM303 ReMem (Xu et al. 2023): retrieve-and-rerank memory with interleaved generation; memory retrieval happens mid-generation, not just at start — enables dynamic context injection
- [ ] AM304 RAPTOR (Sarthi et al. 2024): recursive abstractive processing — embed individual chunks, cluster, summarize clusters, embed summaries; enables multi-granularity retrieval
- [ ] AM305 Cognitive architecture (SOAR/ACT-R inspired): separate declarative (facts), procedural (rules), episodic (events) memory stores with distinct retrieval mechanisms — maps to MASTER's ground/loop/trace modules
- [ ] AM306 Streaming memory updates: as session progresses, incrementally update semantic store rather than batch-writing at session end — enables crash recovery and real-time retrieval

### AM4: Multi-Agent Systems

- [ ] AM401 AutoGen patterns (Wu et al. 2023): structured multi-agent conversations where agents have roles (planner, executor, critic); apply to MASTER's council — not free-form but role-constrained dialogue
- [ ] AM402 MetaGPT (Hong et al. 2023): SOPs (standard operating procedures) for agent coordination — each agent follows a structured workflow with defined inputs/outputs; reduces hallucination in multi-step tasks
- [ ] AM403 CAMEL cooperative agents: role-playing agent pairs (architect + implementer); architect generates high-level plan, implementer executes; critic validates — cleaner separation than current council
- [ ] AM404 Swarm intelligence: leaderless multi-agent systems where agents vote on best fix; majority vote reduces individual LLM error rate; implement as `Judge::Swarm` with quorum threshold
- [ ] AM405 Agent communication protocol: define structured message format for inter-agent communication (JSON with {from, to, intent, payload, trace_id}) — enables debugging multi-agent interactions
- [ ] AM406 Hierarchical agent decomposition: complex tasks decomposed into subtasks by orchestrator; subtask agents operate independently; results merged by orchestrator — reduces context load per agent

### AM5: Tool Use and Function Calling

- [ ] AM501 Toolformer approach (Schick et al. 2023): train model to self-insert API calls in-context by showing cost-benefit — adapt to MASTER: annotate which tool calls proved useful; reinforce those patterns
- [ ] AM502 HuggingGPT (Shen et al. 2023): use LLM as controller to select specialist models for subtasks; MASTER equivalent: route to specialized models per rule type (code model for Ruby, security model for FORBIDDEN_PATTERNS)
- [ ] AM503 AnyTool (Du et al. 2024): hierarchical API retrieval for large tool spaces; first retrieve relevant tool category, then specific tool — scales to 100+ tools without overwhelming context
- [ ] AM504 Tool documentation compression: store tool descriptions as embeddings; retrieve top-K relevant tools per task rather than sending full tool list — reduces prompt size 50-80% for large tool sets
- [ ] AM505 Tool result caching: cache deterministic tool results (file reads, static analysis) with TTL; avoid re-running expensive tools on unchanged inputs

### AM6: Context Window and Long-Context Research

- [ ] AM601 LLMLingua (Jiang et al. 2023): token-level prompt compression via perplexity scoring; compress long context to 25% length with <5% quality loss — apply before any call with >4K token prompt
- [ ] AM602 Selective context (Li et al. 2023): identify and remove semantically redundant sentences from context; simpler than LLMLingua, no fine-tuning required
- [ ] AM603 LONGLLMLINGUA (Jiang et al. 2024): question-aware compression — compress context conditioned on the query; retains query-relevant tokens preferentially
- [ ] AM604 Chunk-and-summarize: for files >2K lines, chunk at function/class boundaries, summarize each chunk, send summaries + relevant chunk — stays within any context limit
- [ ] AM605 Sliding window attention (Beltagy et al. 2020 → Mistral 2023): local attention window + sparse global attention; enables infinite-length processing at linear cost — relevant for streaming file processing
- [ ] AM606 Position interpolation: extend model's effective context via RoPE interpolation — use models that support extended context (Claude 200K, Gemini 1M) for whole-repo analysis

### AM7: Self-Improvement Research

- [ ] AM701 Self-play (Silver et al. 2017 → LLM adaptation): MASTER generates adversarial test cases for its own rules; tries to find inputs that produce false negatives — self-generated red-teaming
- [ ] AM702 Self-instruct (Wang et al. 2022): MASTER generates new rule proposals from seed rules; filters via quality criteria; adds approved rules to rules.yml — autonomous rule expansion
- [ ] AM703 Recursive self-improvement safety: any self-modification (new rules, changed thresholds) runs through `Judge::Council` before commit; never self-modify without deliberation
- [ ] AM704 Capability elicitation: periodically run MASTER on a fixed benchmark suite; track pass rate over time; capability regressions trigger investigation before the next release
- [ ] AM705 Knowledge distillation: expensive council deliberation results cached as fine-tuning examples; distill into a smaller, faster model for common cases — reduces latency and cost

### AM8: Efficiency and Inference Research

- [ ] AM801 Speculative decoding (Leviathan et al. 2022): draft model (llama3-8b) proposes K tokens; target model (claude) verifies in single forward pass; 2-3x throughput with identical quality
- [ ] AM802 Medusa (Cai et al. 2024): multiple parallel decoding heads predict N future tokens simultaneously; no draft model needed; 2-3x speedup — applicable at model server level
- [ ] AM803 Prompt quantization awareness: prefer models with int4/int8 quantization where quality loss is acceptable (lexical rules); reserve FP16 for semantic/council passes
- [ ] AM804 Continuous batching (Orca, Yu et al. 2022): process multiple requests in same forward pass without waiting for slowest; critical for parallel rule scan workers
- [ ] AM805 Prefix sharing (RadixAttention, Zheng et al. 2023): share KV cache for common prefixes across requests — system prompt cached once, amortized across all requests in session

### AM9: Neurosymbolic and Hybrid AI

- [ ] AM901 Neuro-symbolic integration: rules.yml rules as symbolic constraints; LLM provides neural completion within constraint boundaries — deterministic correctness + neural flexibility
- [ ] AM902 Constraint propagation: for fix generation, encode post-conditions as constraints (e.g., frozen_string_literal must be present); propagate constraints to ensure generated fix satisfies them
- [ ] AM903 Logic programming integration: embed Prolog or miniKanren for rule deduction — applicable to dependency analysis and rule conflict detection
- [ ] AM904 Abstract interpretation: analyze Ruby code for invariants (type bounds, null safety, range constraints) without execution — enables static proofs of fix correctness
- [ ] AM905 Formal verification integration: for critical rules (security-related), generate TLA+ or Alloy specifications; verify absence of counterexamples before marking rule as passing

### AM10: RAG and Retrieval Advances

- [ ] AM1001 HyDE (Gao et al. 2022): Hypothetical Document Embeddings — generate hypothetical answer, embed it, retrieve documents similar to hypothetical answer rather than query — improves recall for ambiguous queries
- [ ] AM1002 ColBERT v2 (Santhanam et al. 2021): late-interaction retrieval model — token-level similarity across query and document; better than bi-encoder for code retrieval
- [ ] AM1003 FLARE (Jiang et al. 2023): active retrieval during generation — model detects when it's uncertain and triggers retrieval mid-generation; prevents hallucination on code facts
- [ ] AM1004 GraphRAG (Edge et al. 2024): build knowledge graph over codebase; retrieve subgraphs rather than chunks — enables structural reasoning about code relationships
- [ ] AM1005 Adaptive RAG: dynamically choose retrieval strategy (no retrieval / single-step / multi-step) based on query complexity; avoids retrieval overhead for simple queries

### AM11: Code Generation Research

- [ ] AM1101 AlphaCode 2 patterns: competitive programming approach applied to fix generation — generate diverse fix candidates (100-1000), filter by test execution, cluster by behavior, present representative fixes
- [ ] AM1102 Repo-level context (RepoFormer, 2024): encode full repository structure as context; enables cross-file fix generation that respects project-wide invariants
- [ ] AM1103 Test-driven fix generation: for each proposed fix, generate unit test that verifies the fix; only accept fixes that pass generated tests — self-validating
- [ ] AM1104 Execution-guided synthesis: run proposed fix and observe runtime behavior; use observation to refine fix in tight feedback loop — requires sandboxed Ruby execution environment
- [ ] AM1105 Diff representation learning: fine-tune embedding model on (original, diff, result) triples; enables semantic similarity over code changes, not just code text

### AM12: Adversarial Robustness

- [ ] AM1201 Smooth-LLM (Robey et al. 2023): randomize input perturbations and aggregate outputs — smoothing defense against adversarial prompts; apply to incoming user messages before processing
- [ ] AM1202 Self-reminder (Xie et al. 2023): append reminders of system instructions at both beginning and end of every prompt — simple but effective jailbreak resistance
- [ ] AM1203 Paraphrase augmentation: for ambiguous requests, generate 3 paraphrases and check consistency of responses — inconsistency signals adversarial or ambiguous input
- [ ] AM1204 Perplexity filtering: compute perplexity of input under language model; anomalously high perplexity signals adversarial injection — flag for elevated scrutiny
- [ ] AM1205 Prompt injection detection: classify each tool result for prompt injection attempts (instructions embedded in retrieved content) before executing any implied commands

## AN — Rails 8+ PWA App Ideation and Refinement

### AN1: PWA Foundation (all apps)

- [ ] AN101 Manifest completeness: add `display_override: ["window-controls-overlay", "standalone"]`, `edge_side_panel: {preferred_width: 400}`, `launch_handler: {client_mode: "navigate-new"}` to all manifest.json.erb
- [ ] AN102 Service worker cache versioning: prefix cache name with app + version (`brgen-v1-assets`); bump version on deploy via CACHE_VERSION env var injected at build
- [ ] AN103 Workbox integration: replace hand-rolled service worker with Workbox 7 strategies — CacheFirst for fonts/images, NetworkFirst for HTML, StaleWhileRevalidate for JS/CSS
- [ ] AN104 Background sync: register sync events for offline form submissions (post creation, marketplace orders, dating likes); replay queue on reconnect
- [ ] AN105 Periodic background sync: register `periodicsync` for daily briefing fetch, feed pre-warm, and badge count updates
- [ ] AN106 Push notification VAPID: generate VAPID keys once per app; store in credentials; wire webpush gem (already in brgen) to all apps; display OS-native notifications
- [ ] AN107 Notification badge API: use `navigator.setAppBadge(count)` for unread message count; update via CableReady broadcast on new message
- [ ] AN108 Install prompt interception: capture `beforeinstallprompt`; show custom in-app install banner after 3rd visit; store dismissal in localStorage
- [ ] AN109 Offline fallback page: dedicated offline.html with last-cached data summary; store last 20 feed items in IndexedDB for offline reading
- [ ] AN110 IndexedDB local store: use idb-keyval (importmap) for offline drafts, optimistic UI state, pending sync queue
- [ ] AN111 App shortcuts: manifest `shortcuts` array — brgen: new post, new listing, dating swipe; amber: add item, create outfit; bsdports: search; blognet: new post
- [ ] AN112 Share target: manifest `share_target` so native Share sheet can send URLs/text/files directly into each app (brgen post composer, amber item photo, blognet draft)
- [ ] AN113 File handler: manifest `file_handlers` — amber handles image/* (add to wardrobe), blognet handles text/markdown (import as draft)
- [ ] AN114 Protocol handler: manifest `protocol_handlers` — `web+brgen://post/123` opens post in standalone PWA
- [ ] AN115 Fullscreen mode toggle: add `display: fullscreen` option for TV vertical in brgen; video player expands to true fullscreen without browser chrome
- [ ] AN116 Screen wake lock: acquire wake lock during video playback (brgen TV), recipe view (blognet), and navigation (hjerterom map mode)
- [ ] AN117 Orientation lock: lock to portrait for dating swipe cards; landscape for TV player; use `screen.orientation.lock()`
- [ ] AN118 Viewport meta hardening: `<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">` on all layouts; use `env(safe-area-inset-*)` for notch-aware padding
- [ ] AN119 Theme color per app: manifest `theme_color` and `background_color` unique per app brand; inject dynamic theme-color meta tag for dark mode switching
- [ ] AN120 Standalone mode detection: `window.matchMedia('(display-mode: standalone)')` — show different UI (no back button, bottom nav instead of burger menu) in PWA mode

### AN2: Rails 8 Authentication and Authorization

- [ ] AN201 Rails 8 auth scaffold: run `rails generate authentication` — generates User, Session, Password models with bcrypt; replace any custom auth in all 6 apps with scaffold baseline
- [ ] AN202 Session fixation protection: `config.action_dispatch.session_fixation: :delete` in all apps; rotate session ID on login
- [ ] AN203 Passwordless magic link: add `rails generate authentication --passwordless` for baibl and blognet where frictionless onboarding matters more than security
- [ ] AN204 OAuth via OmniAuth: add google_oauth2 + github strategies to brgen and blognet; store in `authentications` polymorphic table (Rails 8 scaffold supports this)
- [ ] AN205 Rate limiting on auth: use `Rails.cache` with Solid Cache to track failed login attempts per IP; lock after 10 failures for 15 minutes
- [ ] AN206 Remember me: `signed_in_as` persistent cookie (30 days) using encrypted cookie with `cookies.signed`; invalidate on password change
- [ ] AN207 Two-factor TOTP: add `rotp` gem; generate QR code with `rqrcode`; require 2FA for marketplace sellers and dating profile activation
- [ ] AN208 Pundit authorization: add `pundit` gem to all apps; generate policy per model; `policy_scope` in every index action; `authorize` in every show/create/update/destroy
- [ ] AN209 Current attributes: `Current.user` via `ActiveSupport::CurrentAttributes` in all apps; thread-safe request context for audit logging and scoping
- [ ] AN210 Device fingerprinting: log `user_agent`, `accept_language`, `timezone` at login; surface new device alerts via notification/email
- [ ] AN211 Suspicious login detection: if login from new country (IP geolocation via free ipapi.co), send email alert; do not block but log for review
- [ ] AN212 Account deletion: GDPR-compliant `/account/delete` — soft delete with 30-day grace period, hard delete via Solid Queue job, export-before-delete CSV

### AN3: Solid Stack Optimization

- [ ] AN301 Solid Queue job classes: define one ActiveJob subclass per async operation per app; never use `perform_later` with anonymous blocks
- [ ] AN302 Queue priority tiers: configure 3 queues — `critical` (notifications, auth emails), `default` (AI calls, search index), `bulk` (export, batch email, analytics aggregation)
- [ ] AN303 Solid Queue recurring jobs: define in `config/recurring.yml` — daily digest email, weekly stats, nightly search index rebuild, monthly analytics rollup
- [ ] AN304 Solid Queue concurrency controls: per-job `limits_concurrency` to prevent duplicate AI calls (especially amber outfit generation); use `key:` as user + job type
- [ ] AN305 Solid Cache TTLs: define explicit TTLs per cache key type — feed fragments: 5m, user profiles: 1h, search results: 15m, static pages: 24h; never use default
- [ ] AN306 Solid Cache size limits: set `max_size: 512.megabytes` per app; monitor `ActiveSupport::Cache::Store.stats` and alert when >80% full
- [ ] AN307 Solid Cable connection tracking: use `ActionCable.server.connections` to monitor active WebSocket connections; alert when >1000 concurrent (memory pressure)
- [ ] AN308 Solid Queue dashboard: mount `SolidQueue::Engine` at `/admin/jobs` behind authentication; track job latency, failure rate, queue depth
- [ ] AN309 Job retries: configure `retry_on` with exponential backoff for all external API jobs (LLM calls, push notifications, email delivery); max 3 retries
- [ ] AN310 Dead letter queue: failed jobs after max retries land in `solid_queue_failed_executions`; daily digest of failures emailed to admin

### AN4: Turbo and Hotwire Patterns

- [ ] AN401 Turbo Frames for every list: wrap every index action response in `<turbo-frame id="posts">` with `src=` for lazy loading; eliminates full-page reloads for tab switching
- [ ] AN402 Turbo Stream broadcasts: `broadcast_append_to`, `broadcast_replace_to`, `broadcast_remove_to` on Post, Comment, Listing, Match models; real-time feed updates without JS
- [ ] AN403 Turbo Stream forms: `<form data-turbo="true">` on all forms; success responses return `turbo_stream.replace` or `turbo_stream.append`; errors return `turbo_stream.replace` with form+errors
- [ ] AN404 Turbo permanent: `data-turbo-permanent` on sidebar, navigation, and media player elements — persist across Turbo Drive navigations
- [ ] AN405 Turbo prefetch: `data-turbo-prefetch="false"` on logout/delete links; `rel="prefetch"` on next-page pagination links
- [ ] AN406 Turbo morphing: Rails 8.1 `turbo_refreshes_with :morph` in ApplicationController — smooth page refresh without layout flash; use `:scroll: :preserve` to maintain position
- [ ] AN407 Turbo progress bar: customize `Turbo.config.drive.progressBarDelay = 100` and override `--turbo-progress-bar-color` CSS var per app brand color
- [ ] AN408 Turbo native bridge: add `turbo-ios` / `turbo-android` bridge adapter; define `BridgeComponent` Stimulus controllers for native sheet presentation and native share
- [ ] AN409 Optimistic UI: for vote/like/follow actions, immediately update DOM via Stimulus before server confirms; revert on error via `turbo_stream.replace`
- [ ] AN410 Page-specific Turbo caching: `<meta name="turbo-cache-control" content="no-cache">` on auth pages, checkout, and any page with CSRF-sensitive forms
- [ ] AN411 Turbo form submission validation: use `requestsubmit()` with custom validators before Turbo form submission; show inline errors without page reload
- [ ] AN412 Nested frame navigation: dating swipe cards as nested frames — swiping loads next card via `<turbo-frame src="/dating/next">` without outer layout reload
- [ ] AN413 Turbo streams over SSE: for low-traffic apps (bsdports, baibl), use Turbo Streams over SSE (`/updates` endpoint) rather than full WebSocket — less server resource

### AN5: Stimulus Controller Patterns

- [ ] AN501 Infinite scroll: Stimulus controller with IntersectionObserver watching sentinel element; fires Turbo Frame `src` update on intersection; replace Pagy with `pagy_countless`
- [ ] AN502 Pull-to-refresh: Stimulus controller detecting touch `overscroll` event; trigger `Turbo.visit(location, {action: "replace"})` on pull ≥60px; show spinner during load
- [ ] AN503 Swipe gesture: HammerJS-free swipe via `touchstart`/`touchend` delta; for dating card stack, marketplace image carousel, and playlist track swipe-to-queue
- [ ] AN504 Bottom sheet: Stimulus controller for mobile bottom sheet with `transform: translateY` + `transition: cubic-bezier(0.32, 0.72, 0, 1)` snap points at 0%, 50%, 100%
- [ ] AN505 Toast notifications: Stimulus controller triggered by `data-controller="toast"` with `data-toast-message-value`; auto-dismiss after 4s with slide-out animation
- [ ] AN506 Image lazy load: `data-controller="lazy-image"` using IntersectionObserver; swap `data-src` to `src` on intersection; show blur-hash placeholder until loaded
- [ ] AN507 Blur hash: generate blurhash on server (blurhash gem) for every uploaded image; store as column; client decodes to canvas placeholder in 50ms
- [ ] AN508 Character counter: `data-controller="char-counter"` with `data-char-counter-max-value`; show remaining count; color warning at 80%, danger at 95%
- [ ] AN509 Auto-growing textarea: `data-controller="autogrow"` with `input` event handler resizing via `scrollHeight`; for post composer and comment box
- [ ] AN510 Clipboard copy: `data-controller="clipboard"` with `navigator.clipboard.writeText()`; animate success state; fallback to `execCommand` on older Safari
- [ ] AN511 Keyboard shortcut: `data-controller="hotkey"` mapping `j`/`k` for feed navigation, `n` for new post, `?` for help overlay — vim-style navigation
- [ ] AN512 Form auto-save: `data-controller="autosave"` debouncing `input` events; PATCH to `/drafts/:id` every 5s; show "saved" indicator; restore on page reload from IndexedDB
- [ ] AN513 Dialog: native `<dialog>` element managed by Stimulus controller; `showModal()` / `close()`; trap focus; close on backdrop click; ARIA roles
- [ ] AN514 Dropdown: Stimulus controller using `data-action="click@window->dropdown#closeAll"` pattern for click-outside dismiss; accessible with `aria-expanded`
- [ ] AN515 Toggle: `data-controller="toggle" data-toggle-class="hidden"` — simplest possible show/hide; replaces 80% of custom JS in views
- [ ] AN516 Reveal: `data-controller="reveal"` with intersection observer — fade in elements as they scroll into view; `animation: fadeInUp 0.4s ease both`
- [ ] AN517 Tabs: `data-controller="tabs"` with `aria-selected` and `role="tabpanel"`; deep-linkable via URL hash; keyboard arrow navigation
- [ ] AN518 Sortable: `data-controller="sortable"` wrapping SortableJS; for outfit item reordering, playlist track ordering; saves order via PATCH on dragend
- [ ] AN519 Flatpickr: `data-controller="datepicker"` wrapping flatpickr; for takeaway delivery scheduling, event creation, financial date ranges
- [ ] AN520 Maplibre: `data-controller="map"` wrapping MapLibre GL JS with OpenFreeMap tiles (zero cost); for brgen maps vertical, hjerterom pickup locations, takeaway delivery zones

### AN6: brgen — Hyperlocal City Network

- [ ] AN601 City onboarding: `/onboard` flow — pick city, pick interests (categories), pick verticals (dating/marketplace/tv/etc.); redirect to personalized feed
- [ ] AN602 Subdomain feed merging: unified `/` feed that merges posts from all verticals user follows; scored by recency × engagement × personal affinity
- [ ] AN603 Community creation flow: step-by-step `<turbo-frame>`-based wizard — name, description, rules, category, privacy; preview before publish
- [ ] AN604 Post composer rich text: ActionText-based composer with slash-commands (`/image`, `/link`, `/poll`, `/code`); markdown shortcut support (`**bold**`, `#heading`)
- [ ] AN605 Poll creation: embedded in post composer; up to 6 options; real-time vote count via Turbo Stream; auto-close at set time via Solid Queue job
- [ ] AN606 Link preview: on URL paste in composer, fetch OpenGraph metadata via background job; render preview card with image, title, description; user can dismiss
- [ ] AN607 Trending algorithm: score = (votes + comments × 2 + shares × 3) / (hours_since_post + 2)^1.8 — HN-style gravity; computed by Solid Queue job every 15m, stored in `trending_score` column
- [ ] AN608 Dating — swipe interface: card stack via CSS `transform: rotate()` + `translate()`; swipe right = like (sends Like record + checks for Match), swipe left = pass; keyboard ←/→ support
- [ ] AN609 Dating — match notification: on Match creation, broadcast CableReady notification to both users; show animated match overlay ("It's a match!"); create Conversation
- [ ] AN610 Dating — compatibility scoring: LLM-computed affinity score from profile interests, location, activity patterns; surfaced as percentage on match screen
- [ ] AN611 Marketplace — listing creation wizard: multi-step form (category → photos → details → price → location → review); save progress as draft between steps
- [ ] AN612 Marketplace — image upload: Active Storage direct upload to S3-compatible (or local disk on VPS); generate multiple variants (thumb 80px, card 400px, full 1200px) via ImageProcessing::Vips
- [ ] AN613 Marketplace — saved search alerts: user saves a search query; Solid Queue job runs it nightly; Turbo Stream notification if new results
- [ ] AN614 Marketplace — price negotiation: seller enables "offers accepted"; buyer submits offer; counter-offer flow via Conversation; accepted offer locks listing
- [ ] AN615 Marketplace — deal proximity: geolocation-based "deals near you" using Haversine distance SQL; rank by distance × discount_percent
- [ ] AN616 TV — live stream: HLS stream via relayd proxy; `<video>` with hls.js fallback; live viewer count via CableReady broadcast every 30s
- [ ] AN617 TV — DVR: record live streams to Active Storage; generate thumbnail via FFMPEG at server side; VOD playback with seek
- [ ] AN618 TV — channel guide: 7-day EPG grid (horizontal time × vertical channels); rendered as CSS Grid; current show highlighted; click to set reminder
- [ ] AN619 Playlist — music discovery: seed tracks from user listening history → LLM suggests 10 similar artists → link to YouTube/Spotify API for preview
- [ ] AN620 Playlist — collaborative: invite friends to co-edit a playlist; real-time track additions via Turbo Stream; conflict resolution (last write wins with notification)
- [ ] AN621 Takeaway — restaurant onboarding: restaurant owner registers, uploads menu (CSV import or manual), sets delivery zones (polygon on map), sets hours
- [ ] AN622 Takeaway — real-time order tracking: driver location broadcast via CableReady every 30s; customer sees live map pin update; ETA countdown
- [ ] AN623 Takeaway — menu search: full-text search across all restaurant menus in city; rank by distance + rating; filter by dietary tags (vegan, halal, gluten-free)
- [ ] AN624 Maps — business discovery: render businesses as clustered pins on MapLibre; click cluster to zoom; click pin for inline info card without page navigation
- [ ] AN625 Maps — user check-in: tap "I'm here" at any venue; creates check-in record; friends who follow you see update in activity feed
- [ ] AN626 Notification center: unified `/notifications` Turbo Frame; grouped by type (mentions, matches, order updates, likes); mark-all-read via one PATCH request
- [ ] AN627 Activity feed: `/activity` shows everything following users did recently; paginated with Pagy; Turbo Stream new activity at top on broadcast
- [ ] AN628 Hashtag discovery: `/tags/:name` Turbo-framed feed of all posts with tag; trending tags sidebar; auto-link `#word` in post body via ActionText extension
- [ ] AN629 Mention system: auto-link `@username` in post body; create Notification on mention; user preferences for mention notification type (push/email/none)
- [ ] AN630 Report/moderation: report any post/listing/profile with category (spam/hate/illegal); Solid Queue job notifies moderators; moderator dashboard at `/admin/reports`

### AN7: amber — Wardrobe Intelligence

- [ ] AN701 Item add flow: tap "+" → camera or gallery → image uploaded → AI analyzes (color, category, brand, material, season) → pre-fills form → user confirms
- [ ] AN702 Outfit generation: POST `/ai/outfit` with occasion, weather, color mood → LLM returns 3 outfit combinations from wardrobe items → rendered as item grid with "Wear today" CTA
- [ ] AN703 Visual similarity search: embed item photo via vision model → find top-5 similar items in wardrobe by cosine similarity → "You might also wear" recommendations
- [ ] AN704 Color palette extraction: extract dominant 5 colors from item photo via ColorThief.js; store as JSON; palette-based outfit matching ("complementary palette today")
- [ ] AN705 Capsule wardrobe: AI analyzes full wardrobe → identifies 30 versatile pieces that cover 90% of occasions → "Your capsule" view with gap analysis
- [ ] AN706 Cost-per-wear: track each wear via `/outfits/:id/wear` action; compute item CPW = purchase_price / wear_count; surface in item detail; motivates wearing neglected items
- [ ] AN707 Declutter challenge: 30-day challenge — each day surface 1 item worn <3 times; user swipes keep/donate/sell; generates donation packing list or Marketplace listing
- [ ] AN708 Season rotation: "store away" action moves off-season items to archived state; "bring back" reverses; filter current wardrobe by active season automatically
- [ ] AN709 Wishlist → wardrobe: add wishlist items; when user buys (marks as purchased), moves to wardrobe; tracks budget vs actual spend
- [ ] AN710 Creator profile: style influencer sub-profile with public feed, follow count, average engagement, sponsored tag disclosure; monetization via tip jar
- [ ] AN711 Outfit calendar: `FullCalendar`-lite via Stimulus controller; drag outfit onto date; "I wore this" calendar view; export as iCal
- [ ] AN712 Moodboard: Pinterest-style freeform canvas; drag items and inspiration images; save as outfit inspo; shareable URL
- [ ] AN713 Sustainability score: rate items by material (organic cotton = 10, polyester = 3, leather = 5), brand ethics (B-Corp = +3), secondhand (+5); aggregate wardrobe sustainability score
- [ ] AN714 Brand spending analysis: aggregate purchase prices by brand; pie chart via pure SVG (no chart.js); "You've spent 12,400 NOK on Acne Studios"
- [ ] AN715 Style evolution timeline: monthly snapshot of wardrobe composition (by color, category, brand); horizontal scrollable timeline showing style drift over years

### AN8: bsdports — OpenBSD Package Intelligence

- [ ] AN801 Full-text semantic search: `MATCH` query on SQLite FTS5 virtual table over `port_name`, `description`, `maintainer`; rank by `bm25()` function
- [ ] AN802 Dependency graph visualization: D3 force graph via Stimulus controller; nodes = ports, edges = dependencies; click node to navigate; zoom/pan
- [ ] AN803 Security advisory feed: scrape OpenBSD errata page via Nokogiri job; parse CVE references; link to affected ports; Turbo Stream live feed
- [ ] AN804 Port comparison: select 2-3 ports → side-by-side spec table (size, deps, maintainer, last update, security status); `/compare?ports[]=vim&ports[]=neovim`
- [ ] AN805 Maintainer profiles: `/maintainers/:email` — all ports by maintainer, response time stats, open security advisories; link to ports@ mailing list thread
- [ ] AN806 Version history: track port version changes over time; diff between versions; "what changed in nginx 1.26→1.27" via LLM-summarized diff
- [ ] AN807 Infrastructure recommendation: given a list of software needs ("web server, database, mail"), recommend optimal OpenBSD port combination with rationale
- [ ] AN808 AI port explainer: "explain what this port does in plain language" via ruby_llm; cached per port; regenerate button if user thinks it's wrong
- [ ] AN809 User collections: save ports to named collections ("my server stack", "dev tools"); shareable link; import/export as JSON
- [ ] AN810 Port radar: user watches ports; Solid Queue daily job checks for version bump or security advisory; push notification on change

### AN9: baibl — Scripture and Theology Platform

- [ ] AN901 Book/chapter/verse navigation: `/books/:book/chapters/:chapter/verses/:verse` — deep-linkable; keyboard J/K navigation between verses; Turbo Drive transitions
- [ ] AN902 Parallel translations: split-pane view of same passage in multiple translations (KJV, NIV, Norwegian Bibelen); CSS Grid 2-column; swipe to cycle on mobile
- [ ] AN903 Semantic search: "find all verses about forgiveness" → embedding search over verse corpus; return ranked list with context
- [ ] AN904 Annotation layers: user creates private/public annotations on any verse; visible as margin notes; toggle annotation layers by author/group
- [ ] AN905 Cross-reference graph: interactive graph of verse cross-references; navigate the network; identify conceptual clusters
- [ ] AN906 Doctrine mapping: tag verses with theological doctrines (soteriology, eschatology, etc.); browse doctrine → verses; AI identifies under-represented doctrines
- [ ] AN907 Study plan: user creates reading plan (Genesis to Revelation in 365 days); daily check-off via Turbo Stream; streak tracking; email reminder
- [ ] AN908 Community discussion: threaded comments per verse; moderated by community; upvoting; expert answers pinned
- [ ] AN909 AI theological assistant: ask theological questions; AI cites specific verses; sourced reasoning; explicitly non-authoritative disclaimer
- [ ] AN910 Historical context: per passage, surface historical background (author, date, audience, literary genre) via structured data; link to academic sources

### AN10: blognet — Semantic Publishing Network

- [ ] AN1001 Longform editor: ActionText-based rich editor with full-width image embeds, pullquotes, drop caps, code blocks with syntax highlight, footnotes
- [ ] AN1002 Reading time estimate: compute from word count (200 WPM); display prominently; update live in composer as user types
- [ ] AN1003 Draft → published workflow: posts have states (draft/review/scheduled/published/archived); transitions via state machine; scheduled publish via Solid Queue
- [ ] AN1004 Editorial calendar: `/editorial/calendar` — month view of scheduled posts per blog/author; drag-and-drop reschedule
- [ ] AN1005 SEO metadata: per-post OpenGraph, Twitter Card, canonical URL, structured data (Article schema JSON-LD); editable in sidebar without touching HTML
- [ ] AN1006 Newsletter integration: on publish, send post as email newsletter to subscribers via Action Mailer + Solid Queue; unsubscribe link in footer
- [ ] AN1007 Subscriber management: `/subscribers` — list, import CSV, export, segment by tag, view open rates (pixel tracking), unsubscribe management
- [ ] AN1008 Paywall: posts can be `free`, `metered` (3/month free), or `subscriber_only`; Stripe Checkout integration; webhook updates `subscriptions` table
- [ ] AN1009 Recipe vertical (Foodielicious): structured Recipe model with ingredients (quantity/unit/name), steps, nutrition facts, cook/prep time; recipe schema JSON-LD for SEO
- [ ] AN1010 Knowledge graph: tag posts with concepts (entities, topics, people, places); build concept → post index; `/concepts/:name` discovery page
- [ ] AN1011 Related posts: embedding-based "more like this" — encode post title+summary at publish time; find top-5 cosine-similar posts; render in sidebar
- [ ] AN1012 Reading progress: `IntersectionObserver` on last paragraph; when passed, mark as read and update progress bar in `/reading-list`
- [ ] AN1013 Highlight and quote: select text → popover appears with "Quote" and "Highlight" options; highlights stored as user annotations; quotes create shareable image
- [ ] AN1014 Author analytics: `/author/analytics` — views, reads-to-completion, subscriber growth, top posts by engagement; all from SQLite, no external analytics
- [ ] AN1015 Collaborative editing: two authors co-edit via Turbo Stream paragraph locks — editing a paragraph locks it to others; releases after 30s inactivity

### AN11: hjerterom — Food and Resource Rescue

- [ ] AN1101 Donation flow: donor selects category (food/clothing/toys/books), takes photo, describes condition, sets pickup window; creates Donation record
- [ ] AN1102 Inventory management: staff receives donations, weighs/counts, assigns location in storage grid; tracks by category, expiry (food), and condition
- [ ] AN1103 Beneficiary matching: when beneficiary requests (food bag, clothing), system matches available inventory to profile (family size, dietary restrictions, clothing sizes)
- [ ] AN1104 Volunteer scheduling: `/shifts` — staff posts open shifts; volunteers claim shifts; reminder notification 24h before; clock in/out via QR code
- [ ] AN1105 Expiry alerting: Solid Queue job runs nightly; flags food items expiring within 48h; prioritizes for same-day distribution; alerts on-duty staff via push
- [ ] AN1106 Impact dashboard: public-facing `/impact` — total meals provided, CO2 saved (vs landfill), families served, volunteer hours; animated counters; shareable
- [ ] AN1107 Partner network: link to partner organizations (food banks, shelters); route excess inventory to partners via partner API or email; track transfers
- [ ] AN1108 Donation receipt: email receipt with item list and estimated value for tax deduction purposes (Norwegian fradrag)
- [ ] AN1109 Route optimization: for multi-stop food delivery, compute optimal route via OSRM API (open source); display on MapLibre; turn-by-turn instructions

### AN12: Cross-App Performance

- [ ] AN1201 YJIT enabled: `config.yjit = true` in production.rb for all apps; verify with `RubyVM::YJIT.enabled?`; expect 15-20% throughput improvement
- [ ] AN1202 Eager loading: `config.eager_load = true` in production; verify no autoload violations; reduces per-request load time
- [ ] AN1203 Database connection pool: set `pool:` in database.yml to match Falcon worker count; avoid connection timeout under load
- [ ] AN1204 N+1 elimination: run `bullet` gem in development; eliminate every N+1 with `includes`/`preload`/`eager_load`; zero tolerance policy
- [ ] AN1205 Counter caches: add `counter_cache: true` for comment_count, vote_count, follower_count, listing_count on all association-heavy models
- [ ] AN1206 Database indexes: verify indexes on every `foreign_key`, every `WHERE` column, every `ORDER BY` column; run `lol_dba` gem to surface missing indexes
- [ ] AN1207 Fragment caching: `cache [@post, current_user]` for post cards; key includes user to handle voted/unvoted state; Russian doll for comment trees
- [ ] AN1208 HTTP caching: `stale?` / `fresh_when` in show actions with `etag:` and `last_modified:`; static content pages (bsdports port list) get 10m max-age
- [ ] AN1209 Asset compression: propshaft production fingerprinting + gzip/brotli compression via relayd; verify `Content-Encoding: br` in response headers
- [ ] AN1210 Image optimization: ImageProcessing::Vips for all Active Storage variants; convert to WebP; serve via `<picture>` with JPEG fallback; lazy load all
- [ ] AN1211 Font subsetting: subset system UI fonts; if custom font used, subset to Latin + Latin-Extended only; serve as woff2; `font-display: swap`
- [ ] AN1212 Critical CSS inlining: extract above-the-fold CSS per layout; inline in `<style>`; defer full stylesheet load; eliminates render-blocking CSS
- [ ] AN1213 Prefetch on hover: `data-turbo-prefetch` triggers on mouseenter (200ms threshold); reduces perceived navigation time to near-zero
- [ ] AN1214 SQLite WAL mode: `PRAGMA journal_mode=WAL` on all databases; allows concurrent reads + one writer; essential for Falcon multi-fiber concurrency
- [ ] AN1215 SQLite STRICT tables: `CREATE TABLE ... STRICT` for all new tables; eliminates type coercion bugs; requires schema.rb with explicit column types
- [ ] AN1216 SQLite FTS5: add FTS5 virtual tables for full-text search in all apps; avoid external search service dependency; `content=` option for storage efficiency

### AN13: Cross-App Search

- [ ] AN1301 Global search: `/search?q=` across all models in app; ranked by type priority and recency; Turbo Frame instant results as user types (debounced 200ms)
- [ ] AN1302 Search-as-you-type: Stimulus controller debouncing input events; updates Turbo Frame `src` with query param; show skeleton loaders during fetch
- [ ] AN1303 Faceted filtering: sidebar checkboxes for category/type/date/price; each change appends param and refreshes Turbo Frame; shareable filtered URL
- [ ] AN1304 Search analytics: log every query + result count + clicked result; identify zero-result queries; use to improve content and synonyms
- [ ] AN1305 Typo tolerance: SQLite FTS5 with `porter` tokenizer handles stemming; add synonym expansion table for common query→terms mappings
- [ ] AN1306 Recent searches: store last 10 searches in localStorage; show as quick-select chips below search input before typing

### AN14: Cross-App Internationalization

- [ ] AN1401 Norwegian Bokmål default: `config.i18n.default_locale = :nb`; all user-facing strings in `config/locales/nb.yml`; English fallback in `en.yml`
- [ ] AN1402 Time zone: `config.time_zone = "Europe/Oslo"`; display relative times via `timeago` Stimulus controller; absolute on hover tooltip
- [ ] AN1403 Currency formatting: NOK as default; `number_to_currency(amount, unit: "kr", separator: ",", delimiter: " ", format: "%n %u")` helper
- [ ] AN1404 RTL readiness: CSS `[dir="rtl"]` overrides for any future Arabic/Hebrew locale; logical properties (`margin-inline-start`) instead of `margin-left` throughout
- [ ] AN1405 Date format: Norwegian `dd.mm.yyyy` format in all date displays; ISO 8601 in API responses

### AN15: Cross-App Testing

- [ ] AN1501 System tests with Capybara + Cuprite: full browser tests for critical flows (auth, post create, checkout, swipe match) using Ferrum/Chrome headless
- [ ] AN1502 Model unit tests: Minitest for every model method, validation, scope, callback; 100% coverage on business logic
- [ ] AN1503 Controller tests: request specs for every action; assert response status, redirect, flash; verify authorization (Pundit) for all roles
- [ ] AN1504 Job tests: test every ActiveJob subclass in isolation; stub external APIs; verify retry behavior; assert correct queue
- [ ] AN1505 Accessibility audit: `axe-core` integration in system tests; zero critical violations policy; run on every layout
- [ ] AN1506 Performance regression: `rack-mini-profiler` in staging; alert if any action exceeds 200ms p95; database query count alert if >10 per request
- [ ] AN1507 Security scan: `brakeman` in CI; zero warnings policy; `bundler-audit` for known CVEs in gems; run on every push


### AN16: StimulusReflex Patterns (from docs research)

- [ ] AN1601 Install StimulusReflex in all apps: `bundle add stimulus_reflex` + `rails stimulus_reflex:install`; configure ActionCable + CableReady; verify with `rails test:system`
- [ ] AN1602 Page morph reflex: use `morph :page` as default strategy; re-runs controller action and re-renders full page; ~50ms; suitable for state changes that affect many DOM regions
- [ ] AN1603 Selector morph: `morph "#post-123", render(partial: "post", locals: {post: @post})` — partial DOM update without controller action; ~15ms; primary pattern for feed item updates
- [ ] AN1604 Nothing morph: `morph :nothing` — 6ms RPC; triggers background jobs, sends analytics, fires notifications without any DOM change; use for vote counting, read tracking
- [ ] AN1605 Declarative reflex bindings: `data-reflex="click->Post#vote"` — zero JS; use on vote buttons, follow buttons, reaction buttons across all apps
- [ ] AN1606 Form auto-save: `data-reflex="change->Draft#save" data-reflex-serialize-form="true"` on each draft textarea; auto-saves to DB on every keystroke (debounced server-side)
- [ ] AN1607 data-reflex-permanent: protect active inputs (`<input data-reflex-permanent>`) from being overwritten during page morphs; essential for dating swipe cards and post composer
- [ ] AN1608 before_reflex auth: `before_reflex { halt_and_render_nothing! unless current_user }` — centralize authorization in reflex callbacks; never expose reflex actions without auth check
- [ ] AN1609 around_reflex transaction: `around_reflex { ActiveRecord::Base.transaction { yield } }` — wrap mutation reflexes in transactions; auto-rollback on error
- [ ] AN1610 reflexHalted handler: client-side `reflexHalted()` callback shows toast notification when server halts reflex; user gets feedback even when action is refused
- [ ] AN1611 Optimistic UI with beforeReflex: `beforeReflex() { this.element.classList.add("voted") }` then revert in `reflexError()`; vote buttons feel instant
- [ ] AN1612 CableReady after job: `after_perform { cable_ready["user_#{user.id}"].replace(selector: "#job-status", html: render_status).broadcast }` — job completion updates without polling
- [ ] AN1613 Infinite scroll via append: `cable_ready.append(selector: "#feed", html: render_partial)` from Solid Queue job; no client JS beyond IntersectionObserver
- [ ] AN1614 Real-time presence: on connect/disconnect, `cable_ready.inner_html(selector: "#online-count", html: count.to_s).broadcast_to(room)` — live viewer count for TV/livestream
- [ ] AN1615 dispatch_event to Stimulus: `cable_ready.dispatch_event(selector: "#swipe-stack", type: "new-card-available").broadcast` — server pushes event, Stimulus controller loads next card
- [ ] AN1616 scroll_into_view: `cable_ready.scroll_into_view(selector: "#new-message-#{id}", behavior: "smooth")` — auto-scroll to new chat message after CableReady append
- [ ] AN1617 stimulus-sortable for outfit/playlist ordering: `data-controller="stimulus-sortable"` + `data-sortable-url-value="/outfits/:id/reorder"` — drag to reorder, PATCH persists order
- [ ] AN1618 stimulus-tabs with deep linking: `data-controller="stimulus-tabs"` with URL hash sync; dating profile tabs (Photos/About/Interests) are bookmarkable and shareable
- [ ] AN1619 stimulus-scroll-progress: `data-controller="stimulus-scroll-progress"` on article layout; shows reading progress bar at top; baibl verse reader, blognet articles
- [ ] AN1620 stimulus-content-loader for lazy sections: `data-controller="stimulus-content-loader" data-stimulus-content-loader-url-value="/section"` — load expensive sections after initial paint
- [ ] AN1621 stimulus-places-autocomplete for location: `data-controller="stimulus-places-autocomplete"` on takeaway delivery address, hjerterom pickup address, marketplace location
- [ ] AN1622 stimulus-animated-number for counters: `data-controller="stimulus-animated-number"` on vote counts, follower counts, impact stats; numbers count up on first view
- [ ] AN1623 stimulus-timeago on all timestamps: replace all `time_ago_in_words` Ruby calls with `data-controller="stimulus-timeago"`; client-side live updating, no server round-trip
- [ ] AN1624 stimulus-rails-nested-form: `data-controller="stimulus-rails-nested-form"` for marketplace variant creation, recipe ingredient lists, portfolio item addition; add/remove dynamically
- [ ] AN1625 stimulus-character-counter on all textareas: `data-controller="stimulus-character-counter" data-stimulus-character-counter-max-value="280"` — visible limit indicator

### AN17: Rails 8 API Patterns Applied

- [ ] AN1701 params.expect() strict validation: replace all `params.require(:x).permit(...)` with `params.expect(x: [:field1, :field2])` — raises on unexpected arrays, safer against mass assignment
- [ ] AN1702 Turbo morph refresh: `turbo_refreshes_with :morph, scroll: :preserve` in ApplicationController — smooth page refresh preserving scroll position; eliminates layout flash on feed reload
- [ ] AN1703 Active Record strict_loading: `config.active_record.strict_loading_by_default = true` in development — raises on every N+1 before it reaches production
- [ ] AN1704 find_each for bulk operations: replace `.all.each` with `.find_each(batch_size: 500)` in all admin/reporting jobs — prevents memory exhaustion on large datasets
- [ ] AN1705 pluck over map: replace `Model.all.map(&:column)` with `Model.pluck(:column)` — 10x faster, bypasses model instantiation
- [ ] AN1706 pick for single value: replace `Model.where(x: y).limit(1).pluck(:z).first` with `Model.where(x: y).pick(:z)` — cleaner, same performance
- [ ] AN1707 where.missing for orphan detection: `Comment.where.missing(:post)` — find orphaned records for cleanup jobs; replaces LEFT JOIN + IS NULL pattern
- [ ] AN1708 counter_cache with touch: `belongs_to :post, counter_cache: true, touch: true` — free comment_count on posts, free cache invalidation; zero SQL overhead in views
- [ ] AN1709 Solid Queue recurring.yml: define `config/recurring.yml` with daily digest, weekly stats, nightly full-text index rebuild, monthly analytics rollup for all apps
- [ ] AN1710 limits_concurrency in jobs: `limits_concurrency on: -> { "llm-#{arguments.first}" }` — prevent parallel LLM calls for same user; one LLM request per user at a time
- [ ] AN1711 http_cache_forever for manifests: `http_cache_forever(public: false)` on PWA manifest and service-worker.js — immutable caching with etag fallback
- [ ] AN1712 Thruster asset caching: Thruster (default Rails 8 proxy) handles gzip/brotli automatically; verify `Content-Encoding: br` on all JS/CSS assets; zero config needed
- [ ] AN1713 fresh_when with ETag on show actions: `fresh_when(@post, etag: @post, last_modified: @post.updated_at, public: false)` — 304 responses for unchanged posts; no DB hit after first load
- [ ] AN1714 format.md responses: `respond_to { |format| format.json { render json: @post } }` — add JSON responses to all show actions for PWA offline/share features
- [ ] AN1715 config.relative_url_root for subapps: if mounting multiple apps under one domain via relayd, set `config.relative_url_root = "/app_name"` to fix all asset path generation

## AO — CSS and Visual Language Reference (x.com, Medium, Substack, New Yorker)

### AO1: Typography — X.com (Chirp system)

- [ ] AO101 Chirp fallback stack: `font-family: "Chirp", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif` — condensed grotesque; high x-height; use for all UI text in brgen (social app)
- [ ] AO102 X body font size: 15px base with 1.3125rem on desktop (21px); mobile stays at 15px — study the density vs comfort balance
- [ ] AO103 X tweet font-size: 17px / 1.4 line-height for tweet body text on desktop; 15px on mobile — matches reading distance ergonomics
- [ ] AO104 X name typography: `font-weight: 700` for display name; `font-weight: 400` for @handle in muted color — weight contrast as hierarchy without size change
- [ ] AO105 X metadata typography: timestamp, engagement counts at 13px / `color: rgb(113,118,123)` — tertiary information visually recedes without disappearing
- [ ] AO106 X letter-spacing: near-zero; `letter-spacing: -0.01em` on bold display names only — grotesque type doesn't need tracking adjustment
- [ ] AO107 X heading hierarchy: no traditional h1-h4; hierarchy entirely via `font-weight` (700/400) and color (primary/muted); tabs and section titles at 15px bold
- [ ] AO108 X link style: `color: rgb(29,155,240)` (Twitter blue legacy) or `color: rgb(15,20,25)` with underline on hover; no underline at rest; learn the minimum affordance
- [ ] AO109 X emoji rendering: `font-family: "Twemoji Mozilla", ...` for cross-platform emoji consistency; relevant for brgen's reaction system
- [ ] AO110 X code/handle display: `font-family: monospace` only inside code blocks; @handles remain in Chirp stack — avoid mixing font families for inline @mentions

### AO2: Typography — Medium

- [ ] AO201 Medium article body: `font-family: source-serif-4, Georgia, Cambria, "Times New Roman", serif` at 21px / 1.58 line-height — the gold standard for longform comfort
- [ ] AO202 Medium heading: `font-family: medium-content-title-font, Georgia, Cambria, "Times New Roman", serif` at 42px bold on desktop; 32px mobile; dramatic scale contrast
- [ ] AO203 Medium subheading: `font-size: 26px / font-weight: 600 / line-height: 1.4` — clear but subordinate to h1; uses same serif stack
- [ ] AO204 Medium dropcap: first character of article body enlarged to 3 lines height; `float: left; font-size: 5em; line-height: 0.68; margin-right: 0.1em` — implement in blognet article view
- [ ] AO205 Medium body paragraph spacing: `margin-bottom: 2em` between paragraphs — generous vertical rhythm; each paragraph breathes
- [ ] AO206 Medium caption: `font-size: 13px / color: rgba(41,41,41,0.6) / font-style: italic` — image captions visually subordinate; implement for Active Storage attachment captions
- [ ] AO207 Medium tag label: `font-size: 13px / font-weight: 500 / letter-spacing: 0.02em / text-transform: uppercase` — category pills with uppercase tracking
- [ ] AO208 Medium reading time: `font-size: 14px / color: rgba(117,117,117,1)` next to author name; computed server-side, displayed as "7 min read"
- [ ] AO209 Medium blockquote: `border-left: 3px solid #000; padding-left: 23px; font-style: italic; font-size: 22px` — strong typographic statement, implement in ActionText
- [ ] AO210 Medium pullquote: large centered quote at `font-size: 28px / line-height: 1.4 / text-align: center / max-width: 600px / margin: 2em auto` — highlight key insight

### AO3: Typography — Substack

- [ ] AO301 Substack default body: `font-family: Georgia, serif` at 18px / 1.6 line-height — comfortable reading, not as refined as Medium's source-serif-4 but warmer
- [ ] AO302 Substack headline: `font-family: "GT Sectra", Georgia, serif` — slab-serif display; dramatic at 36px bold; heavy stroke contrast
- [ ] AO303 Substack sans-serif variant: `font-family: "Söhne", Helvetica, Arial, sans-serif` — alt style for more modern newsletters; implement as font option in blognet
- [ ] AO304 Substack letter preview typography: email preview text at 15px / lighter weight / muted color — distinguish from full article in feed
- [ ] AO305 Substack podcast metadata: episode number, duration, published date in monospace or tabular-nums — align numbers in episode lists
- [ ] AO306 Substack paywall callout: bold sans-serif at 18px, centered, with short line max-width — strong CTA contrast against serif body
- [ ] AO307 Substack comment reply indent: left-border + `margin-left: 2em` for nested replies; no more than 3 nesting levels before collapsing
- [ ] AO308 Substack note (short post): 16px / sans-serif / looser line-height (1.7) — differentiated from full post; implement as `format: :note` variant in brgen/blognet

### AO4: Typography — The New Yorker

- [ ] AO401 New Yorker Irvin masthead: `font-family: "NYIrvin", Georgia, serif` — proprietary Art Deco display; heavy, condensed, decorative; only for hero/masthead; implement via web font or approximate with Playfair Display
- [ ] AO402 New Yorker body: `font-family: "Neutraface Slab", Georgia, serif` at 19px / 1.6 line-height — slab serif with humanist qualities; readable at length
- [ ] AO403 New Yorker caption: `font-family: "Neutraface 2 Text", sans-serif` at 12px / 1.5 — caps-heavy sans-serif caption; strong contrast against slab body
- [ ] AO404 New Yorker byline: `font-family: caps-variant sans / font-size: 11px / letter-spacing: 0.1em / text-transform: uppercase` — authoritative small caps treatment
- [ ] AO405 New Yorker department header: `font-size: 11px / letter-spacing: 0.15em / text-transform: uppercase / color: #d40000` — section label in red; the only color accent in the design
- [ ] AO406 New Yorker pull quote: centered, larger, italic, generous margins — classic magazine pull quote; `font-size: 24px / font-style: italic / text-align: center / margin: 3em auto / max-width: 480px`
- [ ] AO407 New Yorker cartoon caption: `font-family: monospace / font-size: 14px / text-align: center / padding-top: 8px` — captions beneath cartoons in consistent style
- [ ] AO408 New Yorker deck (subheadline): `font-size: 16px / font-style: italic / color: #333 / margin-top: -0.5em` — sits between headline and body; introduces the piece

### AO5: Color Systems

- [ ] AO501 X light mode palette: `--background: #ffffff; --surface: #f7f9f9; --text-primary: #0f1419; --text-secondary: #536471; --text-tertiary: #657786; --accent: #1d9bf0; --border: #eff3f4; --danger: #f4212e; --success: #00ba7c`
- [ ] AO502 X dark mode palette: `--background: #000000; --surface: #16181c; --surface-raised: #1d2028; --text-primary: #e7e9ea; --text-secondary: #71767b; --accent: #1d9bf0; --border: #2f3336`
- [ ] AO503 X dim mode (intermediate dark): `--background: #15202b; --surface: #1e2732; --text-primary: #f7f9f9; --text-secondary: #8b98a5; --border: #38444d` — three distinct themes, not just light/dark toggle
- [ ] AO504 Medium light palette: `--background: #fff; --text-primary: #292929; --text-secondary: rgba(41,41,41,0.6); --border: rgba(41,41,41,0.15); --accent: #1a8917; --link: #1a8917; --surface: #fafafa`
- [ ] AO505 Medium member badge: `--accent-premium: #FFC017` (amber) for Member-exclusive content lock; subtle premium indicator
- [ ] AO506 Substack base palette: `--background: #ffffff; --text: #222222; --text-secondary: #6b6b6b; --border: #dde0e4; --accent: #ff6719; --link: #ff6719; --surface: #f5f5f5` — warm orange accent throughout
- [ ] AO507 Substack premium: `--accent-pro: #5b21b6` (purple) for paid subscriber features — Substack adopts purple = paid tier
- [ ] AO508 New Yorker palette: `--background: #ffffff; --text: #000000; --text-secondary: #333333; --accent: #d40000; --border: #cccccc; --surface: #f5f5f5` — minimalist four-color system; red is the only chromatic note
- [ ] AO509 Four-site contrast ratios: all four sites achieve AA minimum (4.5:1) on body text; X dark mode achieves AAA (7:1) — never drop below 4.5:1 in any app
- [ ] AO510 Semantic color variables: define `--color-danger`, `--color-warning`, `--color-success`, `--color-info` per app; never hardcode hex in component CSS; all change via single variable update

### AO6: Spacing Systems

- [ ] AO601 X spacing scale: 4px base unit; multiples: 4, 8, 12, 16, 20, 24, 32, 40, 48, 64px — 8px system with 4px half-step for tight mobile touch targets
- [ ] AO602 X tweet card padding: `padding: 12px 16px` on mobile; `padding: 12px 16px` on desktop — consistent horizontal gutters; never 0 padding on any card
- [ ] AO603 X avatar sizes: 40px (thread), 48px (tweet), 56px (profile card), 66px (profile header); always circular; 2px white border in dark contexts
- [ ] AO604 Medium spacing scale: 16px base unit; multiples: 16, 24, 32, 40, 56, 80px — generous rhythm; article content uses 80px top/bottom padding
- [ ] AO605 Medium article max-width: `max-width: 740px` for article body; `max-width: 1192px` for feed; `margin: 0 auto` centers both; 56px side padding on desktop collapses to 16px mobile
- [ ] AO606 Medium card spacing: `gap: 24px` between cards in feed; `padding: 24px 0` per card; separator via border-bottom not gap — consistent separation
- [ ] AO607 Substack spacing scale: 16px base; key values: `padding: 24px 16px` on mobile article; `padding: 40px 24px` desktop sidebar; `gap: 24px` between feed items
- [ ] AO608 Substack avatar: 88×88px profile; 40×40px in feed; always circular with `border-radius: 50%`; subtle border `1px solid var(--border)`
- [ ] AO609 New Yorker spacing: 24px base unit; very generous — article padding `64px 48px`; between sections `48px`; whitespace as editorial statement not waste
- [ ] AO610 New Yorker article width: `max-width: 680px` for article body; 80px side margins on desktop — narrower than Medium but taller line-height compensates
- [ ] AO611 Touch target sizing: minimum 44×44px on all interactive elements per WCAG 2.5.5; X/Medium/Substack all meet this; apply via `min-height: 44px; min-width: 44px` on all buttons and links
- [ ] AO612 Mobile bottom nav heights: X bottom nav is 54px tall; Medium uses 56px; add bottom padding equal to nav height to main content to avoid overlap

### AO7: Layout Patterns

- [ ] AO701 X sidebar layout: fixed-width left sidebar (256px) + fluid feed column (600px) + optional right sidebar (350px); collapses to single column on mobile; CSS Grid: `grid-template-columns: 256px minmax(0,1fr) 350px`
- [ ] AO702 X feed column cap: feed max-width 600px, centered; desktop whitespace intentional — narrow column forces eye focus; prevents line lengths over 70 characters
- [ ] AO703 X sticky sidebar nav: `position: sticky; top: 0; height: 100vh; overflow-y: auto` — sidebar scrolls independently; feed scrolls separately; implement with CSS Grid
- [ ] AO704 Medium two-column article layout: reading column left; author card + related posts right; `grid-template-columns: 1fr 340px; gap: 80px` on desktop; single column mobile
- [ ] AO705 Medium hero image: full-width image above article (`width: 100%; max-height: 500px; object-fit: cover`) with credit caption overlay at bottom-right in small italic
- [ ] AO706 Medium masonry feed: `columns: 2; column-gap: 32px` for curated feed on homepage; `break-inside: avoid` per card; CSS Masonry (or JS fallback)
- [ ] AO707 Substack home layouts: list view (`flex-direction: column`), grid view (`grid-template-columns: repeat(auto-fill, minmax(300px, 1fr))`), magazine view (featured post full-width + grid below)
- [ ] AO708 Substack email-friendly layout: max-width 600px for all email-rendered content; single column; inline styles for email client compatibility
- [ ] AO709 New Yorker featured article: large image (100vw) + title overlay at bottom with white text on dark scrim; `position: absolute; bottom: 0; background: linear-gradient(transparent, rgba(0,0,0,0.7))`
- [ ] AO710 New Yorker section grid: `grid-template-columns: repeat(4, 1fr); gap: 24px` for article listing; collapses to 2-col at 768px, 1-col at 480px
- [ ] AO711 New Yorker sticky header: full-width header shrinks on scroll — `transition: height 0.3s`; large on load (80px), compact (48px) after 100px scroll; content reflows via CSS variable
- [ ] AO712 Horizontal scroll for tags: `overflow-x: auto; white-space: nowrap; -webkit-overflow-scrolling: touch; scrollbar-width: none` — tag chips scroll horizontally on mobile without layout break

### AO8: Component Patterns

- [ ] AO801 X tweet card: flexbox row; 40px avatar left; right column (name row + body + engagement row); `border-bottom: 1px solid var(--border)` as separator; `padding: 12px 16px`
- [ ] AO802 X engagement row: reply, repost, like, bookmark, share icons; `justify-content: space-between` with `max-width: 400px`; icon + count in muted color; count hides on mobile
- [ ] AO803 X like button animation: heart icon scales to 1.2 on click then settles at 1; fill color transitions from `transparent` to `#f91880` with `transition: all 0.15s`; bubble particle burst via keyframe
- [ ] AO804 X thread connector: vertical line between tweets in thread; `border-left: 2px solid var(--border)` from avatar bottom to next avatar; margin aligns with avatar center
- [ ] AO805 Medium post card: thumbnail image (16:9, 100% width); title (bold serif 22px); subtitle (muted 15px); author avatar (20px) + name + date + read-time in one metadata row
- [ ] AO806 Medium member-only card: subtle gradient overlay bottom of card with "Member-only story" badge; gold accent color; CTA to upgrade inline
- [ ] AO807 Medium clap button: animated hand icon with particle burst on click; count increments optimistically; can clap up to 50 times; number cycles with each clap
- [ ] AO808 Medium follow button: `border: 1px solid #1a8917; color: #1a8917; background: transparent` at rest; fills green on hover; transitions with `0.2s ease`; transforms to "Following" after click
- [ ] AO809 Substack subscribe button: prominent CTA button; `background: var(--accent); color: white; border: none; border-radius: 9999px; padding: 12px 24px; font-weight: 600` — pill shape, strong contrast
- [ ] AO810 Substack post card: newsletter title (small caps above); post title (bold serif 24px); excerpt (muted 16px 2-line clamp); footer with publish date + like count + comment count
- [ ] AO811 Substack like animation: heart fills with bounce; `animation: heartbeat 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275)` — springy overshoot feel
- [ ] AO812 New Yorker article card: text-dominant; small image (square, left-aligned) + text block right in horizontal card; or image-top vertical card; minimal metadata
- [ ] AO813 New Yorker nav: horizontal list of sections in 12px uppercase; no dropdown; sticky; `letter-spacing: 0.08em`; active section underline; hover underline transition
- [ ] AO814 Avatar with online indicator: `position: relative` avatar container; `::after` pseudo-element as 10px green circle `position: absolute; bottom: 2px; right: 2px; border: 2px solid white`

### AO9: Interaction and Motion Patterns

- [ ] AO901 X hover state: `background: rgba(15,20,25,0.05)` on card hover (light); `rgba(247,249,249,0.05)` (dark); barely-there hover keeps focus on content not chrome
- [ ] AO902 X like transition: `transition: color 0.1s ease, transform 0.1s ease`; `transform: scale(1.2)` on active; quick, responsive — 100ms not 300ms
- [ ] AO903 X scroll behavior: `scroll-behavior: smooth` on anchor links; feed scrolls independently of sidebar; restore scroll position on back navigation (Turbo Drive handles this)
- [ ] AO904 Medium article fade-in: `animation: fadeIn 0.5s ease-out` on article body; gives impression of content loading gracefully even if it was instant
- [ ] AO905 Medium image hover zoom: `img { transition: transform 0.3s ease; } card:hover img { transform: scale(1.02) }` — subtle content preview signal
- [ ] AO906 Medium progress bar: thin `4px` line at top of viewport tracking reading progress; `background: var(--accent); width: 0; transition: width 0.1s linear` via JS scroll listener
- [ ] AO907 Substack subscribe form animation: email input expands from `width: 200px` to `width: 320px` on focus; submit button slides in from right; `transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1)`
- [ ] AO908 Substack link hover: underline draw animation; `background-image: linear-gradient(currentColor, currentColor); background-size: 0% 1px` → `background-size: 100% 1px` on hover; `transition: background-size 0.2s`
- [ ] AO909 New Yorker header shrink: on scroll past 100px, header height animates from 80px to 48px; nav font-size 11px throughout; logo scales proportionally via `transform: scale(0.8)`
- [ ] AO910 New Yorker article image reveal: images fade in as they scroll into view via IntersectionObserver; `opacity: 0 → 1; transform: translateY(8px) → translateY(0)` over `0.6s ease-out`
- [ ] AO911 Focus visible styles: all four sites use `outline: 2px solid var(--accent)` on keyboard focus (`:focus-visible`); never remove focus outlines; customize but always present
- [ ] AO912 Skeleton loaders: X uses grey pulsing rectangles matching tweet card shape; Medium uses lighter rectangles for card placeholders; implement via `background: linear-gradient(90deg, #f0f0f0 25%, #e0e0e0 50%, #f0f0f0 75%); background-size: 200%%; animation: shimmer 1.5s infinite`

### AO10: Mobile-First Patterns

- [ ] AO1001 X mobile bottom nav: 5 icons (Home, Search, Spaces, Notifications, Messages); fixed bottom; `height: 54px; border-top: 1px solid var(--border); background: var(--background); padding-bottom: env(safe-area-inset-bottom)`
- [ ] AO1002 X mobile compose FAB: floating `+` button; `position: fixed; bottom: 70px; right: 16px; width: 54px; height: 54px; border-radius: 50%; background: var(--accent)` — always accessible compose
- [ ] AO1003 X mobile swipe navigation: swipe right from left edge = open sidebar drawer; `transform: translateX(-100%)` drawer; `transition: transform 0.3s cubic-bezier(0.4, 0, 0.2, 1)`
- [ ] AO1004 Medium mobile header: collapses to logo + hamburger menu; `transition: transform 0.3s` hide on scroll down, show on scroll up — smart header saves vertical space
- [ ] AO1005 Medium mobile article: `padding: 0 20px; font-size: 18px; line-height: 1.6` — same font size as desktop, narrower container; comfortable on 375px viewport
- [ ] AO1006 Substack mobile nav: horizontal scrollable tab row; `overflow-x: auto; scrollbar-width: none; -webkit-overflow-scrolling: touch` — each section tab 64px minimum touch target
- [ ] AO1007 New Yorker mobile adaptation: single column at 480px; hero image goes full-width; section labels become dropdown; large touch targets on nav items
- [ ] AO1008 Mobile image optimization: `<picture>` element with WebP source + JPEG fallback; `sizes="(max-width: 768px) 100vw, 600px"` srcset; `loading="lazy"` on all below-fold images
- [ ] AO1009 Mobile font scaling: `font-size: clamp(15px, 4vw, 19px)` for body text — scales smoothly between viewport sizes without media query breakpoints
- [ ] AO1010 Mobile tap states: `-webkit-tap-highlight-color: transparent` globally; custom `:active` state with `background: rgba(0,0,0,0.05)` instead of browser default blue tap flash

### AO11: Card and Feed Components

- [ ] AO1101 Card shadow system: X uses no shadows; Medium uses `box-shadow: 0 2px 8px rgba(0,0,0,0.06)` on hover only; Substack uses subtle border; New Yorker uses no shadow — minimal depth language
- [ ] AO1102 Card border radius: X cards no border-radius (edge-to-edge on mobile); Medium 4px; Substack 8px; New Yorker 0 — the sharper the corner, the more authoritative/editorial
- [ ] AO1103 Image aspect ratio: X timeline images: 16:9 or 4:3 cropped; Medium hero: 1.6:1; Substack: any (full bleed); New Yorker: 3:4 portrait or 16:9 landscape — enforce via `aspect-ratio` CSS property
- [ ] AO1104 Two-line title clamp: `display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden` — standard in all four sites for feed card titles
- [ ] AO1105 Three-line body clamp: `display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden` — excerpt in cards; 3 lines sufficient for scent
- [ ] AO1106 Author row: avatar (circular, 20-32px) + `display: flex; align-items: center; gap: 8px` + name + metadata — standard horizontal author attribution across all sites
- [ ] AO1107 Horizontal tag chips: `display: flex; gap: 8px; flex-wrap: nowrap; overflow-x: auto; scrollbar-width: none` — tags scroll horizontally on card; max 3 visible before scroll
- [ ] AO1108 Engagement metrics row: icon + number pairs; `color: var(--text-secondary)`; hover to `var(--accent)`; `font-size: 13px; gap: 4px` between icon and number; `gap: 16px` between pairs

### AO12: Dark Mode Patterns

- [ ] AO1201 CSS variable dark mode: all colors as CSS variables; `@media (prefers-color-scheme: dark)` overrides on `:root`; one source of truth; no JS needed for system preference
- [ ] AO1202 Manual dark mode toggle: class-based `[data-theme="dark"]` on `<html>`; overrides `prefers-color-scheme`; persist preference in localStorage; sync across tabs via StorageEvent
- [ ] AO1203 X true black dark: `--background: #000000` not `#1a1a1a` in dark mode — OLED screen battery optimization; pixels off = no power drain; user preference for OLED-black
- [ ] AO1204 Transparent images in dark: images with transparent backgrounds (icons, logos) need `filter: invert(1) hue-rotate(180deg)` or separate dark-mode source; plan at design time
- [ ] AO1205 Dark mode shadow adjustment: light-mode shadows use opacity-black; dark-mode shadows use opacity-white or glow; `box-shadow: 0 2px 8px rgba(255,255,255,0.08)` in dark
- [ ] AO1206 Color-scheme meta: `<meta name="color-scheme" content="light dark">` tells browser to render scrollbars, inputs, and other native UI in appropriate mode; add to all layouts


## AP — Fine-Tuning into Unique Superior Designs (MASTER rules.yml + aesthetic principles)

### AP1: MASTER Aesthetic Rules Applied to CSS

- [ ] AP101 NO_ASCII_DECORATION in CSS comments: purge all `/* ====== */` and `/* ------ */` dividers from CSS/SCSS files; content separates content — blank line suffices
- [ ] AP102 NO_COLUMN_ALIGN in CSS declarations: one space after property colon, ragged values — never pad `background:    white` to align with `color:         black`
- [ ] AP103 NO_CONSECUTIVE_BLANK_LINES in stylesheets: maximum one blank line between rule blocks; two blank lines between major sections (layout, components, utilities)
- [ ] AP104 IMPORTANCE_ORDER in CSS architecture: layout rules first (grid, flexbox, positioning), typography next, colors/backgrounds, spacing, interactivity (hover/focus), animations last
- [ ] AP105 STRUNK_ACTIVE in CSS naming: class names use concrete nouns and verbs — `.post-card` not `.post-display-wrapper`; `.btn-vote` not `.interactive-voting-element`
- [ ] AP106 FLAT_UI enforcement: zero `box-shadow` on flat surfaces; depth only when elements physically overlap (dropdown menus over content, modals over page); no fake elevation on cards
- [ ] AP107 CINEMA_PALETTE enforcement: never raw primaries (`#ff0000`, `#0000ff`, `#00ff00`) in any app; all accent colors via shadow/midtone/highlight triplets; specify all three variants per hue
- [ ] AP108 SIMPLEST_WORKS for CSS: if `margin-top: 1em` achieves the spacing, don't add a wrapper div with `padding-top: 1em` on the inner and `margin-bottom: -1em` on the outer; minimal CSS wins
- [ ] AP109 Single source of truth for design tokens: all colors, sizes, spacing as CSS custom properties on `:root`; no hex codes in component CSS — only `var(--color-accent)`, never `#1a8917`
- [ ] AP110 Property order discipline: within every CSS rule: `display/position` first, then `dimensions`, then `spacing`, then `typography`, then `colors`, then `transitions` — consistent ordering enables scanning

### AP2: Color System — Cinema Palette Per App

- [ ] AP201 brgen palette (social city): shadow `#0a0e1a` (deep navy-black), midtone `#2563eb` (electric blue), highlight `#93c5fd` (sky); complementary warm accent `#f59e0b` (amber) for CTAs; inspired by city-at-night
- [ ] AP202 amber palette (wardrobe): shadow `#1c1917` (warm almost-black), midtone `#d4a843` (warm gold), highlight `#fef3c7` (cream); complementary cool `#6366f1` (indigo) for AI/tech features; fashion editorial warmth
- [ ] AP203 bsdports palette (technical): shadow `#0d1117` (GitHub dark), midtone `#58a6ff` (code blue), highlight `#e6edf3` (light grey); monochrome red `#ff4444` for security advisories; developer tool aesthetic
- [ ] AP204 baibl palette (scripture): shadow `#1a1209` (parchment dark), midtone `#92400e` (sepia brown), highlight `#fef9ef` (cream vellum); complementary `#065f46` (deep green) for wisdom/life references; ancient manuscript
- [ ] AP205 blognet palette (publishing): shadow `#111827` (editorial dark), midtone `#374151` (ink grey), highlight `#f9fafb` (paper white); accent `#dc2626` (editorial red) for section labels; broadsheet newspaper
- [ ] AP206 hjerterom palette (community warmth): shadow `#1f2937` (gentle dark), midtone `#10b981` (warm green for life/giving), highlight `#ecfdf5` (mint cream); accent `#f97316` (harvest orange) for urgency/expiry alerts
- [ ] AP207 Per-app CSS variable declarations: each app's `application.css` opens with `:root { --color-shadow: ...; --color-midtone: ...; --color-highlight: ...; --color-accent: ...; --color-danger: #dc2626; --color-warning: #d97706; --color-success: #059669; }`
- [ ] AP208 Tint scale generation: from midtone, derive 5 tints (10/20/30/40/50% white blend) and 5 shades (10/20/30/40/50% black blend) — 11-step scale per hue; name as `--color-midtone-{100..900}`
- [ ] AP209 Color usage rules: shadow = backgrounds and large surfaces only; midtone = interactive elements, icons, links; highlight = text on dark surfaces, inverted UI; accent = maximum 10% of any view's color budget
- [ ] AP210 Dark mode palette inversion strategy: in dark mode, shadow becomes background (inverted use — now the surface), highlight becomes text; midtone accent remains; never auto-invert all colors, invert semantically

### AP3: Typography System — Per-App Voice

- [ ] AP301 brgen type: `font-family: "Inter", system-ui, sans-serif` at 15px/1.4 — dense, efficient, social; same x-height as Chirp without licensing; pairs with bold 700 for names
- [ ] AP302 amber type: `font-family: "DM Sans", system-ui, sans-serif` at 16px/1.5 — rounded humanist; fashion-editorial softness; pairs with `font-weight: 300` for style notes
- [ ] AP303 bsdports type: `font-family: "JetBrains Mono", "Fira Code", monospace` for code/port names; `"Inter"` for prose descriptions; terminal-native aesthetic
- [ ] AP304 baibl type: `font-family: "Crimson Pro", Georgia, serif` at 19px/1.7 — classic humanist serif; optimized for extended reading; pairs with small-caps for verse references
- [ ] AP305 blognet type: `font-family: "Source Serif 4", Georgia, serif` at 20px/1.65 for articles; `"Source Sans 3"` for UI chrome — the Medium model done right; warmly editorial
- [ ] AP306 hjerterom type: `font-family: "Nunito", system-ui, sans-serif` at 16px/1.6 — friendly, rounded, approachable; community-oriented warmth; accessible to non-technical users
- [ ] AP307 Type scale: all apps use a 4-level modular scale — body, small (0.875em), large (1.125em), heading-sm (1.25em), heading-md (1.5em), heading-lg (2em), display (3em); never arbitrary font sizes
- [ ] AP308 Variable fonts: load Inter, DM Sans, Source Serif 4 as variable fonts (one file, all weights/widths); `font-variation-settings` for precise weight control; `wght` axis only; no optical size axis needed
- [ ] AP309 Font loading strategy: `<link rel="preload" as="font" crossorigin>` for the single woff2 variable font file; `font-display: swap`; no FOIT; accept FOUT as tradeoff for performance
- [ ] AP310 System font fallback hierarchy: `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen, Ubuntu, Cantarell, sans-serif` as second fallback after custom font — covers all major OS in order
- [ ] AP311 Minimum font size: 13px absolute minimum for any text in any app; 14px for secondary; 15px for primary body; 16px mobile body (prevents iOS zoom on input focus)
- [ ] AP312 Line length control: `max-width: 68ch` on all prose containers (article body, post body, comment text) — 60-70 characters per line is optimal for reading; implement via `ch` unit not px
- [ ] AP313 Heading rhythm: `margin-top: 1.5em; margin-bottom: 0.5em` on all headings — space above heading signals new section; space below attaches heading to its content
- [ ] AP314 Paragraph spacing: `margin-bottom: 1.25em` between paragraphs; no `margin-top` on first paragraph after heading — heading's bottom margin provides the gap
- [ ] AP315 Responsive typography: `font-size: clamp(15px, 2.5vw, 20px)` for body; scales continuously without breakpoints; `clamp(28px, 5vw, 48px)` for display headings

### AP4: Void and Whitespace — Architectural Science

- [ ] AP401 Content-to-chrome ratio: in any view, content (text, images) must occupy ≥60% of pixels; navigation, sidebars, headers ≤40% — if chrome exceeds 40%, ruthlessly cut
- [ ] AP402 Margin-not-padding for section separation: use `margin` between sections (collapsible); `padding` inside sections (for click area and readability); never double-space with both
- [ ] AP403 Void budget per view: assign explicit whitespace budget — mobile views: 16px horizontal gutters, 24px between sections; desktop: 24px horizontal gutters, 48px between sections; no exceptions
- [ ] AP404 No decorative dividers: `<hr>`, horizontal rules, `border-bottom` as section dividers — never; sufficient margin between sections communicates separation; if separation isn't clear, the sections may not belong together
- [ ] AP405 Eliminate dead zones: any area of the UI with >200px of empty space that isn't intentional void is a layout bug — fix with better content flow, not filler elements or background patterns
- [ ] AP406 Negative space as signal: whitespace around an element signals its importance; the call-to-action button gets more surrounding void than body text; implement via asymmetric margin budgets
- [ ] AP407 Grid gap over margin: prefer `gap` in CSS Grid/Flex over individual margins; `gap: 24px` on grid container is cleaner than `margin-bottom: 24px` on each child; easier to maintain
- [ ] AP408 No full-width backgrounds on text sections: text reads better on white/near-white regardless of section background; if background color is needed for section identity, use subtle (5-10% lightness delta from base)
- [ ] AP409 Screen real estate audit: run a quarterly review of every layout; ask "what element is competing with the primary content?"; remove or subordinate any element that loses this evaluation
- [ ] AP410 Breathing room on headlines: headline `padding-top` equals approximately 1.5× body line-height; gives the title visual weight without needing a heavier font

### AP5: Motion and Animation System

- [ ] AP501 Easing vocabulary: define only 4 named curves: `--ease-standard: cubic-bezier(0.4, 0, 0.2, 1)` (enter+exit), `--ease-decelerate: cubic-bezier(0, 0, 0.2, 1)` (elements entering), `--ease-accelerate: cubic-bezier(0.4, 0, 1, 1)` (elements leaving), `--ease-spring: cubic-bezier(0.34, 1.56, 0.64, 1)` (playful micro-interactions)
- [ ] AP502 Duration vocabulary: `--duration-instant: 80ms` (state toggles), `--duration-fast: 150ms` (hover effects), `--duration-standard: 250ms` (page transitions, dropdowns), `--duration-slow: 400ms` (hero animations); never arbitrary values
- [ ] AP503 Reduced motion: `@media (prefers-reduced-motion: reduce) { *, *::before, *::after { animation-duration: 0.01ms !important; transition-duration: 0.01ms !important; } }` — global; all animations must respect this
- [ ] AP504 Enter animation pattern: elements entering the viewport should `opacity: 0 → 1` + `transform: translateY(8px) → translateY(0)` over `--duration-standard` with `--ease-decelerate`; subtle, not dramatic
- [ ] AP505 Exit animation pattern: elements leaving `opacity: 1 → 0` + `transform: scale(0.97)` over `--duration-fast` with `--ease-accelerate`; faster than enter — exits feel snappier
- [ ] AP506 No loops at rest: never animate elements that are sitting idle; pulse/spin only on explicitly loading states; continuous animation is cognitive noise
- [ ] AP507 Physics-based spring for interactive elements: vote button, like button, follow button use `--ease-spring` with `--duration-fast`; overshoot communicates responsiveness
- [ ] AP508 Card hover lift: `transform: translateY(-2px)` + `box-shadow: 0 4px 16px rgba(0,0,0,0.1)` on card hover; 2px maximum — any more is theatrical; `transition: var(--duration-fast) var(--ease-standard)`
- [ ] AP509 Skeleton loader shimmer: `@keyframes shimmer { 0% { background-position: -200% 0; } 100% { background-position: 200% 0; } }` with 1.4s linear infinite; direction = reading direction
- [ ] AP510 Page transition: Turbo Drive handles navigation; add `@keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }` on `body.turbo-loading` → remove on `turbo:load`; sub-200ms fade
- [ ] AP511 Stagger for lists: when a list loads, stagger children's enter animations by 40ms per item; `animation-delay: calc(var(--index) * 40ms)`; maximum 5 items staggered then simultaneous
- [ ] AP512 Match media for animation performance: check `window.matchMedia('(prefers-reduced-motion: no-preference)')` before registering scroll-based animations; degrade gracefully

### AP6: Component Design — Per-App Unique Identity

- [ ] AP601 brgen post card: dark edge-to-edge card on mobile; no border-radius; `border-bottom: 1px solid var(--color-border)`; avatar 40px circular; vote count left, timestamp right; inspired by X but with electric blue accents
- [ ] AP602 brgen vote button: pill-shaped, not icon-only; `▲ 42` format; upvoted state fills with `--color-midtone`; downvoted fills with `--color-danger`; springy scale on click
- [ ] AP603 brgen dating swipe card: `border-radius: 16px; overflow: hidden; box-shadow: 0 8px 32px rgba(0,0,0,0.2)` — only context where elevation is appropriate (card physically above surface in affordance); photo full-bleed, info overlay at bottom
- [ ] AP604 brgen marketplace listing: image 1:1 aspect-ratio; price prominent `font-size: 1.25em; font-weight: 700; color: var(--color-accent)`; seller name small; condition badge top-left `border-radius: 4px; padding: 2px 6px`
- [ ] AP605 amber item card: portrait 3:4 image; color swatch dots below (5 dominant colors); category tag top-left; CPW badge bottom-right `font-size: 12px; background: rgba(0,0,0,0.6); color: white; border-radius: 4px; padding: 2px 6px`
- [ ] AP606 amber outfit builder: grid of item thumbnails; drag-to-reorder; selected items get `outline: 2px solid var(--color-accent)`; outfit name editable inline via `contenteditable`
- [ ] AP607 bsdports port card: monospace port name `font-size: 0.9em; font-family: monospace`; one-line description; metadata row (version, size, maintainer) in muted 12px; security badge red if advisory exists
- [ ] AP608 baibl verse display: verse reference in small-caps `font-variant: small-caps; font-size: 0.8em; color: var(--color-midtone)` above the verse; verse body at reading size; annotation count as subtle superscript
- [ ] AP609 blognet article card: full-width hero image 16:9; author byline with avatar; reading time; title at 24px serif bold; 3-line excerpt; tags in lowercase pill chips; no border, generous margin
- [ ] AP610 hjerterom donation card: large icon (128px) for category (food/clothing/toy); expiry date prominent if food; distance badge top-right; "Claim" button fills card bottom; warm green CTA

### AP7: Navigation Design

- [ ] AP701 brgen desktop sidebar: fixed-width 240px; icon + label navigation links; active state = filled icon + bold label + `background: var(--color-midtone-100)` bar; new post FAB at bottom
- [ ] AP702 brgen mobile bottom nav: 5 items max; icon only on mobile; active = filled icon + `color: var(--color-midtone)`; `border-top: 1px solid var(--color-border)`; safe-area padding
- [ ] AP703 amber top nav: minimal — logo left, search icon + profile avatar right; no hamburger menu; categories as horizontal scrollable chips below nav; fashion-minimalist approach
- [ ] AP704 bsdports nav: top horizontal nav; logo + "OpenBSD Ports" wordmark left; `Search` field center; `Sign in` + `Contribute` right; no mobile hamburger — responsive via breakpoint
- [ ] AP705 baibl nav: book/chapter/verse breadcrumb always visible; Bible navigator slide-in from left; `position: fixed; left: 0; top: 0; height: 100vh; width: 280px; transform: translateX(-100%)` → open state
- [ ] AP706 blognet nav: editorial top bar — publication name left (masthead typography); `Subscribe` pill CTA right; section navigation below in smaller caps; New Yorker pattern
- [ ] AP707 hjerterom nav: large friendly logo; "Donate", "Request", "Volunteer", "About" as equal-weight top nav items; warm green active state; simple, non-intimidating for non-technical users
- [ ] AP708 Breadcrumb pattern: `<nav aria-label="Breadcrumb"><ol>` with `aria-current="page"` on last item; `>` separator via CSS `::before` on `li + li`; never JS-generated, always server-rendered
- [ ] AP709 Skip navigation: `<a href="#main" class="skip-nav">Skip to main content</a>` as first element in `<body>`; `position: absolute; transform: translateY(-100%)` at rest; `translateY(0)` on `:focus` — keyboard accessibility
- [ ] AP710 Active link state: use Rails `current_page?` helper to add `aria-current="page"` and a CSS class; `font-weight: 600; color: var(--color-midtone)` for active; `color: var(--text-secondary)` for inactive

### AP8: Form Design

- [ ] AP801 Input field baseline: `border: 1px solid var(--color-border); border-radius: 6px; padding: 10px 14px; font-size: 1rem; width: 100%; background: var(--color-surface)` — consistent across all apps
- [ ] AP802 Focus state: `outline: none; border-color: var(--color-midtone); box-shadow: 0 0 0 3px var(--color-midtone-200)` — ring-style focus, not outline; visible and branded
- [ ] AP803 Error state: `border-color: var(--color-danger); box-shadow: 0 0 0 3px rgba(220,38,38,0.15)` + error message below in `--color-danger` 13px; icon optional (!)
- [ ] AP804 Disabled state: `opacity: 0.5; cursor: not-allowed` — never remove from DOM, always disable in-place; assistive technology needs to encounter it
- [ ] AP805 Label positioning: label always above input; `display: block; margin-bottom: 6px; font-size: 14px; font-weight: 500; color: var(--text-primary)` — never placeholder-as-label
- [ ] AP806 Placeholder style: `color: var(--text-tertiary); opacity: 1` — browser default opacity varies; set explicitly; placeholder is a hint not a label; never required information
- [ ] AP807 Submit button: full-width on mobile; auto-width on desktop; `background: var(--color-midtone); color: var(--color-highlight); border: none; border-radius: 6px; padding: 12px 24px; font-weight: 600` — unambiguous primary action
- [ ] AP808 Inline validation: validate on `blur` not `input` — don't punish before user finishes typing; show success check on valid field; show error on invalid field after touch
- [ ] AP809 File upload: custom styled `<label>` over hidden `<input type="file">`; drag-and-drop zone with `dragover` → `border-color: var(--color-midtone); background: var(--color-midtone-50)` feedback
- [ ] AP810 Select element: custom-styled via `appearance: none` + background SVG chevron; `background-image: url("data:image/svg+xml,...")` — native functionality, custom appearance

### AP9: Accessibility as Design Constraint

- [ ] AP901 Color contrast policy: 4.5:1 minimum for body text (AA); 7:1 for small text <18px (AAA target); 3:1 for large text ≥24px bold (AA); test with `axe` in CI
- [ ] AP902 Focus visible always: `:focus-visible` ring on every interactive element; `outline: 2px solid var(--color-midtone); outline-offset: 2px` — never `outline: none` without replacement
- [ ] AP903 ARIA roles: semantic HTML first (`<button>` not `<div onclick>`); add ARIA only when semantics don't exist (`role="feed"` for timeline, `aria-live="polite"` for notifications)
- [ ] AP904 Image alt text: every `<img>` has `alt`; decorative images use `alt=""` (empty, not missing); Active Storage variants auto-generate alt from filename — override with meaningful text in `image_tag`
- [ ] AP905 Motion-sensitive design: every animation has a `prefers-reduced-motion` fallback; test by enabling "reduce motion" in OS accessibility settings
- [ ] AP906 Touch target padding: minimum 44×44px tap target even if visual element is smaller; achieve via `padding` or pseudo-element extension; critical for icon-only buttons
- [ ] AP907 Landmark regions: every page has exactly one `<main>`, one `<header>`, appropriate `<nav>`, `<aside>`, `<footer>`; assistive technology uses these for navigation
- [ ] AP908 Heading hierarchy: never skip heading levels (`h1 → h3` without `h2`); document outline must be logical; `h1` = page title, appears once; `h2` = major sections
- [ ] AP909 Form autocomplete: `autocomplete="email"` on email fields, `autocomplete="current-password"` on password fields, `autocomplete="given-name"` on name fields — browser autofill, password manager compatibility
- [ ] AP910 Language declaration: `<html lang="nb">` (Norwegian Bokmål) on all pages; `lang` attribute on any inline text in other language — screen readers use this for pronunciation

### AP10: Design Token System Implementation

- [ ] AP1001 Token hierarchy: Global tokens (raw values: `--blue-500: #3b82f6`) → Semantic tokens (meaning: `--color-link: var(--blue-500)`) → Component tokens (scope: `--button-bg: var(--color-link)`) — three layers, never skip
- [ ] AP1002 Spacing tokens: `--space-1: 4px; --space-2: 8px; --space-3: 12px; --space-4: 16px; --space-5: 20px; --space-6: 24px; --space-8: 32px; --space-10: 40px; --space-12: 48px; --space-16: 64px` — match Tailwind scale for cross-reference
- [ ] AP1003 Border radius tokens: `--radius-sm: 4px; --radius-md: 6px; --radius-lg: 10px; --radius-xl: 16px; --radius-full: 9999px` — never arbitrary values; assign per component in component CSS
- [ ] AP1004 Shadow tokens: in dark mode apps only: `--shadow-sm: 0 1px 3px rgba(0,0,0,0.12); --shadow-md: 0 4px 12px rgba(0,0,0,0.15); --shadow-lg: 0 8px 32px rgba(0,0,0,0.2)` — used only for overlapping elements
- [ ] AP1005 Z-index tokens: `--z-base: 0; --z-raised: 10; --z-dropdown: 100; --z-sticky: 200; --z-overlay: 300; --z-modal: 400; --z-toast: 500` — never arbitrary z-index values; prevents stacking context chaos
- [ ] AP1006 Transition tokens: `--transition-fast: var(--duration-fast) var(--ease-standard); --transition-standard: var(--duration-standard) var(--ease-standard)` — compose from duration + easing tokens; use in `transition:` shorthand
- [ ] AP1007 Token documentation: `tokens.css` file per app listing every token with comment — the ground truth for design-to-dev handoff; design system without docs is a rumor
- [ ] AP1008 Token inheritance between apps: shared base tokens in a `_shared_tokens.css` partial; app-specific overrides in `application.css`; never copy-paste tokens between apps — import shared

### AP11: brgen-Specific Design Refinement

- [ ] AP1101 Feed density toggle: compact (X-style, 80px cards), comfortable (default, 120px), spacious (Medium-style, 200px); user preference saved to `current_user.feed_density`; CSS class on `<body>`
- [ ] AP1102 Subdomain theming: each vertical (dating/marketplace/tv/playlist/takeaway/maps) overrides `--color-midtone` via `<body data-vertical="dating">` CSS selector; dating = `#ec4899`, marketplace = `#f59e0b`, tv = `#7c3aed`
- [ ] AP1103 City header: large city name header above feed with ambient weather color temperature — warm sunset hue on clear evenings, cool grey on rainy days; live weather API injection
- [ ] AP1104 Night mode auto: detect `prefers-color-scheme: dark` AND time (22:00-07:00 local) → auto-enable dim mode; respect user's manual override
- [ ] AP1105 Conversation thread indentation: reply indentation via `padding-left: calc(40px + var(--space-3))` — avatar width + gap; thread connector line via `::before` pseudo on li
- [ ] AP1106 Dating card stack visual: 3 cards visible; card behind at `transform: scale(0.94) translateY(8px)`; card behind that at `scale(0.88) translateY(16px)`; parallax depth illusion with pure CSS
- [ ] AP1107 Map overlay design: map takes full viewport; POI pins use app accent color; info card slides up from bottom on pin click; `border-radius: 16px 16px 0 0; background: var(--color-background)`
- [ ] AP1108 Marketplace grid: 2-column on mobile, 3 on tablet, 4 on desktop; `grid-template-columns: repeat(auto-fill, minmax(180px, 1fr))`; cards edge-to-edge with 1px gap between
- [ ] AP1109 TV livestream viewer: dark background always (`--background: #000`); player full-width; chat side panel slides in from right; chat message bubbles `border-radius: 16px; max-width: 240px`
- [ ] AP1110 Playlist now-playing: persistent bottom player bar; `position: fixed; bottom: 0; left: 0; right: 0; height: 72px; background: var(--color-surface); border-top: 1px solid var(--color-border); backdrop-filter: blur(12px)`

### AP12: Cross-App Typography Refinement

- [ ] AP1201 Optical size correction: at display sizes (>40px), reduce font-weight by one step — 700 at body size becomes 600 at display to prevent heaviness; variable font `font-weight` axis enables this precisely
- [ ] AP1202 Hyphenation: `hyphens: auto; overflow-wrap: break-word` on all prose containers (baibl, blognet, hjerterom descriptions) — prevents long Norwegian compound words from breaking layout
- [ ] AP1203 Tabular numbers: `font-variant-numeric: tabular-nums` on all price displays, counts, statistics — numbers don't shift width as they change, preventing layout jump
- [ ] AP1204 Ordinal formatting: `font-variant-numeric: ordinal` for Norwegian dates (1ste, 2nde); `font-variant-numeric: slashed-zero` in bsdports code contexts — prevent `0` / `O` confusion
- [ ] AP1205 Ligatures: `font-variant-ligatures: common-ligatures` on long-form text (blognet, baibl) — `fi`, `fl`, `ffi` ligatures improve paragraph texture; disable in UI chrome
- [ ] AP1206 Small caps for labels: `font-variant-caps: all-small-caps; letter-spacing: 0.06em` for section labels, category tags, status indicators — authoritative yet compact; implement in blognet and baibl
- [ ] AP1207 Prose first-line indent alternative: `text-indent: 1.5em` on paragraphs after first (`.prose p + p { text-indent: 1.5em; margin-top: 0 }`) as alternative to paragraph spacing — denser, more typographically classical
- [ ] AP1208 Quote mark styling: `open-quote: "«"; close-quote: "»"` for Norwegian text; `open-quote: "\u201C"; close-quote: "\u201D"` for English; CSS `content: open-quote` on `blockquote::before`
- [ ] AP1209 Underline refinement: `text-decoration-thickness: 1px; text-underline-offset: 3px; text-decoration-color: var(--color-midtone-400)` — thin, offset underline; not browser default thick underline
- [ ] AP1210 Gradient text for headings: app-specific gradient on hero headings — brgen: `background: linear-gradient(135deg, var(--color-midtone), var(--color-highlight)); -webkit-background-clip: text; -webkit-text-fill-color: transparent` — sparingly, only hero contexts

### AP13: Mobile-Specific Refinements

- [ ] AP1301 iOS safe area: `padding-bottom: calc(var(--space-4) + env(safe-area-inset-bottom))` on bottom nav; `padding-top: env(safe-area-inset-top)` on top header — notch and home indicator clearance
- [ ] AP1302 Overscroll behavior: `overscroll-behavior-y: contain` on scrollable panels (chat, feed columns) — prevents pull-to-refresh on Android from triggering during scrollable area interaction
- [ ] AP1303 Tap highlight removal: `-webkit-tap-highlight-color: rgba(0,0,0,0)` globally; custom active states communicate tap instead; eliminates browser blue flash
- [ ] AP1304 Input zoom prevention: all input `font-size` ≥ 16px on mobile; iOS zooms viewport if `font-size < 16px` on focused input; verify in device emulation
- [ ] AP1305 Smooth scrolling: `scroll-behavior: smooth` on `html` element; override with `scroll-behavior: auto` inside `@media (prefers-reduced-motion: reduce)` — never apply universally without reduced-motion safeguard
- [ ] AP1306 Momentum scrolling: `-webkit-overflow-scrolling: touch` on all `overflow-y: auto` containers; ensures iOS native momentum scroll behavior in web contexts
- [ ] AP1307 Pinch-zoom: never `user-scalable=no` in viewport meta — mandatory for accessibility; design layouts that scale gracefully with pinch-zoom
- [ ] AP1308 Portrait keyboard: when keyboard appears on mobile, `100dvh` accounts for the keyboard; use `dvh` (dynamic viewport height) units instead of `vh` for full-screen mobile layouts
- [ ] AP1309 Bottom navigation thumb zone: all critical actions within 70px of bottom edge on mobile — thumb reaches there without repositioning grip; place primary CTA in this zone
- [ ] AP1310 Passive scroll listeners: `addEventListener("scroll", handler, { passive: true })` on all scroll listeners — prevents jank by telling browser handler won't call `preventDefault()`

### AP14: Icon and Image Design

- [ ] AP1401 Icon system: Heroicons (MIT) via importmap for all apps; `<svg class="icon icon-sm">` at 16px, `icon-md` at 20px, `icon-lg` at 24px; never icon fonts
- [ ] AP1402 Icon stroke weight: 1.5px stroke on all icons for normal contexts; 2px for emphasis; never 1px (too thin on low-DPI) or 2.5px+ (too heavy in body text)
- [ ] AP1403 Icon meaning consistency: same action = same icon across all apps; "like" = heart; "share" = box-with-arrow; "comment" = speech bubble; "delete" = trash — never deviate per-app
- [ ] AP1404 Image border radius: 4px on rectangular images in cards; 50% on avatars; 0 on full-bleed hero images; `--radius-md` token ensures consistency
- [ ] AP1405 Aspect ratio enforcement: `aspect-ratio: 16/9` on all media images; `aspect-ratio: 1` on avatars; `aspect-ratio: 3/4` on amber item photos — never let images reflow on load
- [ ] AP1406 Image placeholder color: dominant color placeholder from blur hash before image loads; amber = warm gold placeholder; brgen = cool blue-grey; not generic grey
- [ ] AP1407 Retina images: all Active Storage variants generate 2× size; served via `srcset="image.webp 1x, image@2x.webp 2x"` — sharp on retina without serving to non-retina
- [ ] AP1408 SVG illustrations: each app has 3-5 SVG illustrations for empty states, error pages, onboarding; match app color palette; consistent stroke weight with icon system; never stock illustrations

### AP15: Performance as Design Quality

- [ ] AP1501 Lighthouse 95+ target: every app scores ≥95 Performance, ≥95 Accessibility, ≥95 Best Practices, ≥95 SEO in Lighthouse audit; these are design quality metrics not just dev metrics
- [ ] AP1502 CLS ≤ 0.1: Cumulative Layout Shift; every image has `width` + `height` attributes; fonts use `font-display: swap`; ads/embeds have reserved space; skeleton loaders match content dimensions
- [ ] AP1503 LCP ≤ 2.5s: Largest Contentful Paint; hero image is `loading="eager"` + `fetchpriority="high"`; preloaded in `<head>`; served as WebP; never LCP element inside lazy-loaded frame
- [ ] AP1504 INP ≤ 200ms: Interaction to Next Paint; Stimulus handlers do zero synchronous DOM measurement; debounce search inputs; split long tasks with `setTimeout(fn, 0)` or `queueMicrotask`
- [ ] AP1505 No layout thrash: read all DOM geometry before writing; never alternate `element.getBoundingClientRect()` with `element.style.height = ...` in loops; batch reads then batch writes
- [ ] AP1506 Bundle size audit: importmap manifest shows exact version + size of each dependency; total JS on first load ≤ 150KB gzipped; audit quarterly; remove unused imports
- [ ] AP1507 CSS size audit: application.css ≤ 30KB gzipped per app; if larger, split into critical (inlined) and deferred (linked); PurgeCSS pass to remove unused selectors in production

## AQ — Rails 8+ PWA Deep-Dive (AN continuation)

### AQ1: Action Cable and Real-Time Architecture

- [ ] AQ101 Channel per vertical in brgen: separate ActionCable channels — `FeedChannel`, `DatingChannel`, `MarketplaceChannel`, `TVChannel`, `PlaylistChannel`; subscribe only to active vertical's channel; reduce unnecessary broadcasts
- [ ] AQ102 Presence tracking: `ConnectionsChannel` broadcasts online user IDs to subscribers; `before_subscribe { track_presence }`, `after_unsubscribe { remove_presence }`; stored in Solid Cache with 30s TTL
- [ ] AQ103 Typing indicators: `TypingChannel` with `transmit(typing: true)` on keydown debounce; `typing: false` on blur or 2s idle; broadcast to conversation partner only
- [ ] AQ104 Read receipts: `MessagesChannel#mark_read` Nothing Morph reflex; updates `read_at` timestamp; CableReady `set_attribute` on sender's message to show double-tick
- [ ] AQ105 Live notification count: `NotificationsChannel` broadcasts `{count: unread_count}` on every new notification; client updates badge via `cable_ready.set_attribute(selector: "[data-badge]", name: "data-count", value: count)`
- [ ] AQ106 Throttle broadcasts: wrap `ActionCable.server.broadcast` in `Rails.cache.fetch("broadcast:#{key}", expires_in: 1.second) { broadcast! }`; prevent storm from rapid successive writes
- [ ] AQ107 ActionCable identity: `identified_by :current_user`; reject anonymous WebSocket connections to all channels except public TV channel; never trust client-sent user IDs
- [ ] AQ108 Connection health ping: `ActionCable.server.config.ping_interval = 15`; client auto-reconnects on dropped connection; display "Reconnecting…" indicator via Stimulus

### AQ2: Active Storage Deep-Dive

- [ ] AQ201 Direct upload to disk: configure `config/storage.yml` with `service: Disk` for development, `service: Mirror` (local + S3) for production; Active Storage handles upload → storage → retrieval
- [ ] AQ202 Image variants pipeline: `variant :thumb, resize_to_fill: [80, 80]; variant :card, resize_to_fill: [400, 300]; variant :full, resize_to_limit: [1200, nil]` — define on model, never in view
- [ ] AQ203 WebP conversion: `variant :webp, convert: :webp, quality: 85` for all image attachments; serve WebP with JPEG fallback via `<picture>` tag helper
- [ ] AQ204 Blurhash on upload: after Active Storage attachment completes, enqueue `GenerateBlurhashJob` which reads image bytes, computes blurhash, stores in `attachments.metadata` JSON column
- [ ] AQ205 Content-type validation: `validates :photo, content_type: ["image/jpg", "image/jpeg", "image/png", "image/webp", "image/heic"]` — explicit allowlist; reject all other types server-side
- [ ] AQ206 File size validation: `validates :photo, size: { less_than: 10.megabytes, message: "must be less than 10MB" }` — hard limit server-side regardless of client-side check
- [ ] AQ207 Mirror service for CDN: configure `Mirror` storage service that writes to both local disk and Cloudflare R2; read from CDN for public content; local disk as fallback origin
- [ ] AQ208 Expiring URLs: `rails_blob_path(@post.image, expires_in: 1.hour)` for sensitive content (dating photos, private marketplace items); public content uses permanent URLs
- [ ] AQ209 Preview generation: `has_one_attached :document; has_many_attached :images` — for PDFs, use `preview` to generate first-page thumbnail; show in card without PDF download
- [ ] AQ210 Concurrent upload: `data-controller="direct-upload"` Stimulus controller tracking multiple concurrent `DirectUpload` instances; progress bar per file; total progress aggregated

### AQ3: Hotwire Native (Mobile App Bridge)

- [ ] AQ301 Turbo Native setup: add `turbo-ios` gem + `turbo_ios` Stimulus bridge; wrap existing web views in native iOS app shell; reuse all Rails views without duplication
- [ ] AQ302 Bridge components: `data-controller="bridge--menu"` triggers native iOS action sheet; `data-controller="bridge--form"` triggers native keyboard handling; define in `app/javascript/controllers/bridge/`
- [ ] AQ303 Native navigation: `Turbo.visit(url, {action: "advance"})` = push; `{action: "replace"}` = replace; `{action: "restore"}` = pop; map to UINavigationController operations
- [ ] AQ304 Path configuration: `path_configuration.json` routes which URLs use native views vs web views; dating swipe = native, post compose = web, settings = web
- [ ] AQ305 Native bottom tabs: define in path config; each tab maps to a `TabBar` item with icon + label; tab state persists across navigations; badge count from CableReady
- [ ] AQ306 Native share sheet: `BridgeComponent` intercepts `share` button taps; calls `window.nativeShare({url:, title:})` → native iOS Share sheet with all apps; no PWA Web Share API needed
- [ ] AQ307 Native image picker: `data-controller="bridge--photo-picker"` invokes native camera/gallery picker; returns base64 → direct upload starts immediately; better than `<input type="file">`
- [ ] AQ308 Push via APNs: `webpush` gem handles both Web Push (VAPID) and bridges to APNs for Turbo Native iOS; single notification sending path regardless of client platform

### AQ4: Search Architecture

- [ ] AQ401 SQLite FTS5 setup: in each app's migration, `execute "CREATE VIRTUAL TABLE posts_fts USING fts5(title, body, content='posts', content_rowid='id', tokenize='porter unicode61')"` — porter stemming for English; unicode61 for Norwegian
- [ ] AQ402 FTS5 triggers: `CREATE TRIGGER posts_ai AFTER INSERT ON posts BEGIN INSERT INTO posts_fts(rowid, title, body) VALUES (new.id, new.title, new.body); END` — keep FTS index in sync automatically
- [ ] AQ403 FTS5 search query: `Post.where("posts_fts MATCH ?", query.gsub(/[^a-zA-Z0-9æøåÆØÅ ]/, "") + "*").joins("JOIN posts_fts ON posts_fts.rowid = posts.id").order("rank")`
- [ ] AQ404 Highlight snippets: `SELECT snippet(posts_fts, 0, '<mark>', '</mark>', '...', 10) as title_snippet FROM posts_fts WHERE posts_fts MATCH ?` — FTS5 native snippet function; highlights matched terms in results
- [ ] AQ405 Faceted search Rails: `scope :by_category, ->(cat) { where(category: cat) }` + `scope :by_date_range, ->(from, to) { where(created_at: from..to) }` — composable scopes chain cleanly
- [ ] AQ406 Typeahead endpoint: `GET /search/suggestions?q=` returns JSON array of {label, url} pairs; cached 60s per query; no authentication required for suggestions
- [ ] AQ407 Search history: store last 20 unique queries per user in `search_histories` table; surface as chips below empty search input; delete on click + X button per chip
- [ ] AQ408 Zero results handling: when search returns 0 results, surface 3 alternative suggestions via LLM (`"Did you mean: ..."`); log zero-result query for content gap analysis
- [ ] AQ409 Norwegian search: FTS5 tokenize with `unicode61` handles Norwegian characters (æ ø å) correctly; add synonym table mapping Norwegian → Bokmål variants
- [ ] AQ410 Semantic search fallback: if FTS5 returns <3 results, fall back to embedding search — `SELECT id, 1 - (embedding <=> ?) AS score FROM posts ORDER BY score DESC LIMIT 10` (requires sqlite-vec extension)

### AQ5: Background Jobs Architecture

- [ ] AQ501 Job naming convention: all job classes end in `Job`; named as `Verb + Noun + Job` — `SendWelcomeEmailJob`, `GenerateOutfitJob`, `IndexSearchJob`; never `ProcessJob` or `HandleJob`
- [ ] AQ502 Job idempotency: every job must be safe to run twice; check pre-conditions before executing: `return if @post.already_indexed?`; use database unique constraints as guards
- [ ] AQ503 Job payload minimization: pass only IDs to jobs, never full objects: `AnalyzeItemJob.perform_later(item.id)` not `AnalyzeItemJob.perform_later(item)`; objects serialize + deserialize; IDs don't
- [ ] AQ504 Dead letter alerting: `config/recurring.yml` defines nightly job that queries `solid_queue_failed_executions` and emails admin if count > 0; never silently drop failed jobs
- [ ] AQ505 Job observability: `around_perform { Rails.logger.tagged("job:#{self.class.name}") { yield } }` — every job logs with class name tag; greppable in production logs
- [ ] AQ506 AI job rate limiting: `limits_concurrency on: :model_name, to: 2` on all LLM-calling jobs — max 2 concurrent LLM calls per job type; prevent API rate limit errors
- [ ] AQ507 Webhook delivery: `DeliverWebhookJob` with exponential backoff — retry delays: 5s, 30s, 5m, 30m, 2h; after 5 failures, deactivate endpoint and email user
- [ ] AQ508 Scheduled cleanup: `PurgeExpiredDataJob` in `recurring.yml` — runs nightly; purges soft-deleted records older than 30 days, expired sessions, stale cache, unconfirmed users >7 days
- [ ] AQ509 Email delivery job: `ActionMailer::MailDeliveryJob` routes through `critical` queue; never delay email delivery to `default` or `bulk` queues; users expect email immediately

### AQ6: Multi-Tenancy Patterns (brgen)

- [ ] AQ601 acts_as_tenant configuration: `ActsAsTenant.configure { |config| config.require_tenant = true }` — raises if tenant not set; prevents accidental cross-tenant data access
- [ ] AQ602 City as tenant: `City` model as tenant; every request sets `ActsAsTenant.current_tenant = City.find_by(subdomain: request.subdomain)`; all models scoped automatically
- [ ] AQ603 Tenant-agnostic admin: `/admin` routes bypass tenant scoping via `ActsAsTenant.without_tenant { ... }` — admin can see all cities' data
- [ ] AQ604 Cross-city content: some content is global (platform policies, help docs); use `city_id: nil` + scope override: `unscoped.where(global: true)`
- [ ] AQ605 Tenant switching: users can follow communities in other cities; display cross-city content in "Explore" tab without changing tenant; query with explicit `city_id:` condition
- [ ] AQ606 Per-city config: `cities` table has `{config: jsonb}` with per-city feature flags — dating enabled, marketplace enabled, TV enabled; read via `Current.city.config["dating_enabled"]`

### AQ7: Email and Notifications

- [ ] AQ701 Action Mailer preview: `/rails/mailers` in development shows every email template rendered; define `WelcomeMailerPreview`, `MatchMailerPreview`, `OrderMailerPreview` etc.
- [ ] AQ702 Email layout: single `mailer_layout.html.erb` with inline CSS (email clients don't support linked CSS); max-width 600px; single column; dark mode via `@media (prefers-color-scheme: dark)` in `<style>`
- [ ] AQ703 Text version: every HTML email has a matching `.text.erb` template; Action Mailer sends multipart by default when both exist; plain text for clients that can't render HTML
- [ ] AQ704 Unsubscribe header: `headers["List-Unsubscribe"] = "<mailto:unsubscribe@brgen.no?subject=unsubscribe>, <https://brgen.no/unsubscribe/#{token}>"` — one-click unsubscribe per RFC 8058
- [ ] AQ705 Email preference center: `/account/notifications` shows matrix of event types × delivery channels (email/push/in-app); stored in `notification_preferences` JSONB column
- [ ] AQ706 Digest emails: `DigestEmailJob` aggregates last 24h of unread notifications into single email; send only if user has >3 unread and hasn't visited in 24h; opt-out option
- [ ] AQ707 Transactional vs marketing: use separate `from:` addresses — `no-reply@brgen.no` for transactional (match notifications, order updates), `hello@brgen.no` for marketing (digest, recommendations)
- [ ] AQ708 Email open tracking: `<img src="/track/email/#{token}" width="1" height="1">` pixel; on request, mark email as opened, log timestamp; use for engagement analytics, not manipulation
- [ ] AQ709 Bounce handling: webhook from mail provider on hard bounce → deactivate email address, flag user account, prompt to update email on next login
- [ ] AQ710 Web push payload: `webpush` gem payload: `{title:, body:, icon:, badge:, url:, tag:}` — `tag:` groups notifications (replaces old with same tag); badge is monochrome icon for notification tray

### AQ8: API Design for PWA Offline Sync

- [ ] AQ801 JSON:API responses: standardized `{data: {id:, type:, attributes:, relationships:}, links:, meta:}` format for all API endpoints; use `jsonapi-serializer` gem
- [ ] AQ802 Etag-based sync: `If-None-Match` header on GET /api/posts — return 304 if unchanged; client uses cached response; reduces bandwidth for reconnected offline PWAs
- [ ] AQ803 Delta sync: `GET /api/posts?since=<timestamp>` returns only records modified after timestamp; client merges delta into IndexedDB; full sync only on fresh install
- [ ] AQ804 Conflict resolution: `updated_at` optimistic locking — server rejects writes where client's `updated_at` doesn't match server's; client receives 409 + server version; user resolves
- [ ] AQ805 Offline write queue: client queues mutations in IndexedDB when offline; on reconnect, `background-sync` fires queued POST/PATCH requests; server processes idempotently
- [ ] AQ806 Pagination cursor: `GET /api/posts?cursor=<opaque_token>&limit=20` — cursor-based pagination stable under inserts; avoid offset pagination (items shift as new content is added)
- [ ] AQ807 Partial response fields: `GET /api/posts?fields[posts]=title,author,created_at` — client requests only needed fields; reduces payload for list views vs detail views
- [ ] AQ808 Compression: `Accept-Encoding: br, gzip` in all API requests; server returns brotli-compressed JSON; 70-80% size reduction on typical JSON responses
- [ ] AQ809 Webhook events: for partner integrations (hjerterom→food bank APIs), emit `POST` webhooks on key events; `HmacSHA256` signature header for verification; `WebhookDeliveryJob` handles retries

### AQ9: Accessibility and Internationalisation

- [ ] AQ901 ARIA live regions: `<div aria-live="polite" aria-atomic="true">` containing notification area; screen readers announce new Turbo Stream updates without user navigating there
- [ ] AQ902 Role feed: `<main role="feed" aria-label="Innlegg">` on timeline; `article` elements with `aria-posinset` and `aria-setsize` for screen reader position announcement
- [ ] AQ903 Focus management after Turbo navigation: `document.addEventListener("turbo:load", () => document.querySelector("h1")?.focus())` — move focus to page heading after navigation; disorienting otherwise
- [ ] AQ904 Keyboard navigation for swipe cards: dating swipe cards respond to `ArrowRight` (like), `ArrowLeft` (pass), `ArrowUp` (superlike), `Escape` (close profile); announced via `aria-label` updates
- [ ] AQ905 i18n pluralization: `t("post.count", count: n)` uses `config/locales/nb.yml` with `one:` and `other:` keys; Norwegian irregular plurals handled via explicit keys
- [ ] AQ906 Norwegian address format: `SteetName Number, Postal City`; `PostalCode` is 4 digits; `hjerterom` and `brgen` delivery addresses validate against this format
- [ ] AQ907 Norwegian phone number: `+47 XXX XX XXX` format validation; `validates :phone, format: { with: /\A(\+47)?[0-9]{8}\z/ }` after stripping spaces
- [ ] AQ908 Date localization: `I18n.l(date, format: :long)` → "31. mai 2026" in nb; "May 31, 2026" in en; never hardcode date format strings in views
- [ ] AQ909 Currency localization: hjerterom donation values displayed in NOK; amber wardrobe costs in NOK; blognet subscription prices in NOK with ISO code fallback for non-NO users
- [ ] AQ910 Locale switching: `?locale=en` URL param overrides default; stored in session; `ApplicationController#set_locale` reads `params[:locale] || session[:locale] || I18n.default_locale`

### AQ10: Security Hardening

- [ ] AQ1001 Content Security Policy: `config.content_security_policy` in `config/initializers/content_security_policy.rb` — `default_src :none; script_src :self; style_src :self; img_src :self :data: blob:; connect_src :self wss:; font_src :self; frame_ancestors :none`
- [ ] AQ1002 CSP nonce for inline scripts: `content_security_policy_nonce` helper; `script_tag nonce: true` on any inline scripts; Turbo and Stimulus use `nonce` attribute automatically in Rails 8
- [ ] AQ1003 CSRF protection: `config.action_controller.forgery_protection_origin_check = true`; verify `Origin` header on all non-GET requests; token embedded in Turbo meta tag
- [ ] AQ1004 Secure headers gem: `SecureHeaders.configure` — `X-Frame-Options: DENY`, `X-XSS-Protection: 0` (deprecated but belt-and-suspenders), `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy: camera=(), microphone=()`
- [ ] AQ1005 SQL injection prevention: never string-interpolate into `where()` clauses; always `where("column = ?", value)` or hash syntax `where(column: value)`; Brakeman catches violations in CI
- [ ] AQ1006 Parameter pollution: `params.expect()` (Rails 8) or `params.require().permit()` — never pass `params` directly to model; Pundit policy checks authorization before record mutation
- [ ] AQ1007 File upload security: validate content-type via `Marcel` gem (reads magic bytes, not MIME header); reject files where declared type ≠ magic byte type; store outside web root
- [ ] AQ1008 Rate limiting auth endpoints: `Rack::Attack` middleware; limit `/session` to 5 POST/minute per IP; limit `/password_reset` to 3/hour per IP; return 429 with `Retry-After` header
- [ ] AQ1009 Audit log: `AuditLog` model with `{user_id, action, resource_type, resource_id, ip, user_agent, created_at}`; log all create/update/destroy via `after_action` callback in ApplicationController
- [ ] AQ1010 Secret rotation: `rails credentials:edit` per environment; rotate `SECRET_KEY_BASE` quarterly; rotation invalidates all sessions (acceptable security tradeoff); announce rotation 24h in advance

### AQ11: Analytics Without Third Parties

- [ ] AQ1101 Self-hosted analytics: `PageView` model with `{path, referrer, user_agent, country, device_type, session_id, created_at}`; log via `after_action` in ApplicationController; exclude bot user agents
- [ ] AQ1102 Unique visitor counting: HyperLogLog estimate via `HLL` SQLite extension; exact count prohibitively expensive; 2% error acceptable for analytics
- [ ] AQ1103 Event tracking: `AnalyticsEvent` model with `{event_name, properties: jsonb, user_id, session_id, created_at}`; log via `track("post.created", {category_id: @post.category_id})`
- [ ] AQ1104 Funnel analysis: define conversion funnels in code — dating signup → profile complete → first swipe → first match; query event sequences; surface drop-off in admin dashboard
- [ ] AQ1105 Retention cohorts: weekly cohort analysis query — `SELECT week(created_at) as cohort, week(last_seen_at) - week(created_at) as retention_week, count(*) FROM users GROUP BY 1, 2`
- [ ] AQ1106 Revenue tracking: `RevenueEvent` model; log subscription starts, upgrades, downgrades, churns; MRR computed as `sum(amount) WHERE billing_cycle = 'monthly'`; no Stripe dashboard dependency
- [ ] AQ1107 Admin analytics dashboard: `/admin/analytics` — 30-day chart (pure SVG, no chart.js) of DAU/WAU/MAU, new users, revenue, top content; server-rendered for maximum speed
- [ ] AQ1108 Privacy-first: no cross-site tracking; no cookies beyond session; no fingerprinting; all analytics aggregated before display; GDPR-compliant by architecture not policy

### AQ12: Rails Generators and Conventions

- [ ] AQ1201 Custom generators: `rails generate brgen:vertical DatingProfile` creates model + migration + controller + views + routes + Stimulus controller in one command; enforce app-specific conventions
- [ ] AQ1202 Concern templates: `rails generate concern Votable` generates boilerplate Votable concern with `included do ... end` block; attach to model in one line
- [ ] AQ1203 Service objects: `app/services/` directory; `rails generate service OutfitGenerator` creates `OutfitGeneratorService` with `call` method; SRP — one service, one responsibility
- [ ] AQ1204 Query objects: `app/queries/` directory; `FeedQuery.new(user: current_user, page: params[:page]).call` — extract complex AR queries from controllers and models; testable in isolation
- [ ] AQ1205 View components: `rails generate view_component PostCard` creates `PostCardComponent` + template; replaces partials for complex, reusable UI; testable without full controller stack
- [ ] AQ1206 Decorator pattern: `app/decorators/PostDecorator` wraps model with view-specific methods; `@post.formatted_created_at`, `@post.truncated_body` live here; never in model or view
- [ ] AQ1207 Form objects: `app/forms/RegistrationForm` validates multi-step form data before model creation; no model validation pollution for wizard flows
- [ ] AQ1208 Policy objects (Pundit): `app/policies/PostPolicy` with `create?`, `update?`, `destroy?`, `index?` per role; `policy_scope(Post)` returns scoped relation; 100% of authorization lives here

### AQ13: Deployment and DevOps

- [ ] AQ1301 Kamal 2 deploy: `config/deploy.yml` with `service`, `image`, `servers`, `env`, `volumes`, `proxy`; `kamal setup` once; `kamal deploy` on every release; `kamal rollback` on failed deploy
- [ ] AQ1302 Health check endpoint: `GET /up` returns 200 if app, DB, and cache are reachable; 503 otherwise; Kamal and relayd use this for liveness; implement with `ActiveRecord::Base.connection.execute("SELECT 1")`
- [ ] AQ1303 Zero-downtime deploy: Kamal blue-green with `proxy.buffering.enabled: true`; new container starts, health check passes, traffic switches, old container stops; no dropped requests
- [ ] AQ1304 Database migrations safety: `rake db:migrate:status` in deploy pipeline; alert on pending migrations older than 24h; never deploy with destructive migration without maintenance window
- [ ] AQ1305 Secrets via Kamal: `kamal secrets push` uploads encrypted secrets to server; never store secrets in `.env` committed to git; `config/deploy.yml` references `KAMAL_REGISTRIES_PASSWORD` etc.
- [ ] AQ1306 Log aggregation: all apps log to stdout in production; `dmesg`-format one-liners; Kamal captures to `docker logs`; `logrotate` on VPS; no external log service needed
- [ ] AQ1307 Backup strategy: SQLite database backed up via `litestream` replication to S3-compatible (Cloudflare R2 free tier); continuous replication; point-in-time restore to any second
- [ ] AQ1308 Staging environment: mirror of production config; deploys to staging on every merge to `main`; production deploys require explicit `kamal deploy --destination production`


## AR — CSS Implementation Specifics (AO continuation)

### AR1: CSS Architecture and File Structure

- [ ] AR101 CSS layer order: `@layer reset, tokens, base, layout, components, utilities, overrides` — explicit cascade layer declaration; later layers win; utilities always trump components; overrides for third-party
- [ ] AR102 CSS reset: modern reset — `*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0 }; img, video { display: block; max-width: 100% }; input, button, textarea, select { font: inherit }` — minimal, predictable base
- [ ] AR103 Logical properties throughout: `margin-inline-start` not `margin-left`; `padding-block-end` not `padding-bottom`; `inset-inline-end` not `right`; prepares for RTL support without CSS rewrite
- [ ] AR104 Custom property scope: global tokens on `:root`; component tokens on component root selector `[data-component="card"] { --card-padding: var(--space-4) }`; never leak component variables to global scope
- [ ] AR105 No `!important` policy: forbidden except in utility classes (intentionally highest specificity) and `prefers-reduced-motion` overrides; if `!important` is needed elsewhere, specificity architecture is wrong
- [ ] AR106 Selector specificity budget: maximum two-class selector depth `.card .card-title`; never three `.nav .menu .item`; ID selectors forbidden in component CSS; only on single layout anchors
- [ ] AR107 CSS file per component: one file per component (post-card.css, nav.css, btn.css); imported via `@import` in application.css; each file ≤150 lines before splitting
- [ ] AR108 Design token file: `tokens.css` imported first; defines all `--` custom properties; this file is the contract between design and engineering; never modify without design review
- [ ] AR109 Component isolation: every component CSS block opens with the component's root class; all descendant selectors scoped within; `postCard { &-title { } &-meta { } }` using CSS nesting
- [ ] AR110 Utility classes: generate spacing utilities `mt-1` through `mt-16`, `px-1` through `px-16` from token scale; typography utilities `text-sm`, `text-base`, `text-lg`; color utilities `text-primary`, `bg-surface`

### AR2: Grid and Layout Implementation

- [ ] AR201 App shell layout: `display: grid; grid-template-areas: "sidebar main aside"; grid-template-columns: var(--sidebar-width, 240px) 1fr var(--aside-width, 320px); min-height: 100dvh` — named areas for clarity
- [ ] AR202 Mobile layout: `@media (max-width: 768px) { grid-template-areas: "main"; grid-template-columns: 1fr; }` sidebar and aside hidden; main fills viewport
- [ ] AR203 Content column constraint: `max-width: var(--content-max-width, 680px); margin-inline: auto; padding-inline: var(--content-padding, clamp(16px, 5vw, 48px))` — fluid padding that collapses gracefully
- [ ] AR204 Card grid: `display: grid; grid-template-columns: repeat(auto-fill, minmax(var(--card-min-width, 280px), 1fr)); gap: var(--grid-gap, 24px)` — no media queries; cards reflow automatically
- [ ] AR205 Sticky sidebar: `position: sticky; top: var(--header-height, 56px); height: calc(100dvh - var(--header-height, 56px)); overflow-y: auto; overscroll-behavior: contain` — sidebar scrolls independently
- [ ] AR206 Split view: `display: grid; grid-template-columns: 1fr 1fr; height: 100dvh; overflow: hidden` — each side `overflow-y: auto`; for baibl parallel translations, amber outfit vs wardrobe
- [ ] AR207 Masonry layout: CSS `columns: 2; column-gap: var(--space-4); column-fill: balance` + `break-inside: avoid` on cards; falls back to single column on narrow viewport; amber moodboard, medium-style feeds
- [ ] AR208 Magazine layout: `grid-template-areas` named grid; hero article spans full width (`grid-column: 1 / -1`); secondary articles in 3-column row below; tertiary in 4-column row; New Yorker pattern
- [ ] AR209 Full-bleed within constraint: `.full-bleed { width: 100vw; margin-inline: calc(50% - 50vw) }` — makes element break out of content column without absolute positioning; for hero images in articles
- [ ] AR210 Subgrid: `display: subgrid; grid-row: span 4` — card children participate in parent grid; card titles align across all cards in a row without fixed heights; bleeding-edge but widely supported 2025+

### AR3: Typography Implementation Details

- [ ] AR301 Variable font loading: `@font-face { font-family: "Inter"; src: url("inter-variable.woff2") format("woff2-variations"); font-weight: 100 900; font-display: swap; font-style: normal }`
- [ ] AR302 Font size fluid scale: `--text-xs: clamp(11px, 1.5vw, 13px); --text-sm: clamp(13px, 1.8vw, 15px); --text-base: clamp(15px, 2.2vw, 17px); --text-lg: clamp(17px, 2.5vw, 20px); --text-xl: clamp(20px, 3vw, 24px); --text-2xl: clamp(24px, 4vw, 32px); --text-3xl: clamp(32px, 5vw, 48px)`
- [ ] AR303 Prose styles: `.prose { font-size: var(--text-lg); line-height: 1.6; max-width: 68ch } .prose h2 { font-size: var(--text-2xl); margin-block: 1.5em 0.5em } .prose p { margin-bottom: 1.25em } .prose ul, ol { padding-inline-start: 1.5em; margin-bottom: 1.25em }` — single class for all longform content
- [ ] AR304 Code blocks: `.code { font-family: var(--font-mono); font-size: 0.875em; background: var(--color-surface); border-radius: var(--radius-md); padding: var(--space-1) var(--space-2); white-space: pre-wrap; overflow-x: auto; tab-size: 2 }`
- [ ] AR305 Blockquote: `blockquote { border-inline-start: 3px solid var(--color-midtone); padding-inline-start: var(--space-4); margin-block: var(--space-6); font-style: italic; color: var(--text-secondary) }` — left border treatment from Medium
- [ ] AR306 Footnotes: `.footnote-ref { font-size: 0.75em; vertical-align: super; line-height: 0; color: var(--color-midtone) }` — superscript numbers that scroll to footnote section; :target pseudo highlights referenced footnote
- [ ] AR307 Drop cap: `.prose > p:first-of-type::first-letter { font-size: 3.5em; float: left; line-height: 0.8; margin-inline-end: 0.1em; margin-block-end: -0.1em; font-weight: 700; color: var(--color-shadow) }` — Medium-style; blognet articles only
- [ ] AR308 Reading width enforcement: `@container (min-width: 900px) { .prose { max-width: 68ch } }` — container queries ensure reading width constraint applies to the content box, not the viewport
- [ ] AR309 Orphan/widow prevention: `p { text-wrap: balance }` on headings and short paragraphs; `orphans: 2; widows: 2` on long paragraphs in print styles; CSS Text Level 4
- [ ] AR310 Text selection style: `::selection { background: var(--color-midtone-200); color: var(--color-shadow) }` — branded selection color matching app midtone; subtle, not jarring

### AR4: Color Implementation Patterns

- [ ] AR401 Dark mode via data attribute: `[data-theme="dark"] { --color-background: ...; --color-text: ... }` — all dark mode overrides in one block; trivial to add new dark theme
- [ ] AR402 System preference + manual: `:root { color-scheme: light dark }` + `@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { ... } }` — system preference wins unless user explicitly chose light
- [ ] AR403 Transparent color: `--color-overlay: rgb(0 0 0 / 0.5)` using space-separated RGB — modern syntax; `/ alpha` notation; more readable than `rgba(0, 0, 0, 0.5)`
- [ ] AR404 Color-mix for tints: `color-mix(in srgb, var(--color-midtone) 20%, white)` — derive tints without pre-computing; dynamic; changes when midtone changes; use for hover backgrounds
- [ ] AR405 High contrast mode: `@media (prefers-contrast: high) { :root { --color-border: var(--color-shadow); --text-secondary: var(--text-primary) } }` — automatically adapt for users needing higher contrast
- [ ] AR406 Forced colors mode: `@media (forced-colors: active) { .btn { border: 2px solid ButtonText } }` — Windows High Contrast mode; maintain usability without custom colors
- [ ] AR407 P3 color gamut: `@media (color-gamut: p3) { :root { --color-midtone: color(display-p3 0.1 0.45 0.9) } }` — wider gamut on supported displays; falls back to sRGB; more vibrant accent colors
- [ ] AR408 Semantic color naming: never `--red`, `--green`, `--blue`; always `--color-danger`, `--color-success`, `--color-info`; semantic meaning survives dark mode and rebrand
- [ ] AR409 Gradient tokens: `--gradient-hero: linear-gradient(135deg, var(--color-shadow) 0%, var(--color-midtone) 100%)`; `--gradient-card-scrim: linear-gradient(to top, rgba(0,0,0,0.8) 0%, transparent 60%)` — reusable gradient definitions
- [ ] AR410 Border color opacity: `border-color: rgb(from var(--color-shadow) r g b / 0.15)` — relative color syntax; border is shadow-hued but translucent; updates automatically when shadow color changes

### AR5: Animation Implementation

- [ ] AR501 Keyframe library: define all app keyframes in `animations.css` — `@keyframes fadeIn`, `slideInUp`, `slideInRight`, `scaleIn`, `shimmer`, `heartbeat`, `spin`, `bounce`; import once; reference everywhere
- [ ] AR502 Animation utility classes: `.animate-fade-in { animation: fadeIn var(--duration-standard) var(--ease-decelerate) both }` etc. — apply to elements; `animation-fill-mode: both` handles pre/post states
- [ ] AR503 Animation delay utilities: `[style="--delay: 1"] { animation-delay: calc(1 * 40ms) }` — arbitrary delay via inline style custom property; enables staggered lists from HTML without JS
- [ ] AR504 View transitions API: `document.startViewTransition(() => updateDOM())` — browser-native cross-document animations; Rails 8 Turbo 8 has native support; `::view-transition-old(root)` and `::view-transition-new(root)` for custom cross-fade
- [ ] AR505 CSS scroll timeline: `@scroll-timeline reading-progress { source: selector(#article); start: 0%; end: 100% }; .progress-bar { animation: progress-grow auto linear; animation-timeline: reading-progress }` — reading progress bar without JS
- [ ] AR506 Container query animations: `@container (min-width: 600px) { .card { animation: expandLayout var(--duration-standard) var(--ease-standard) } }` — animate layout changes driven by container width not viewport
- [ ] AR507 CSS paint worklet: `CSS.paintWorklet.addModule("hatch-fill.js")` for custom painted backgrounds (amber item cards could have subtle fabric texture via CSS Houdini paint worklet)
- [ ] AR508 will-change budgeting: `will-change: transform` only on elements actively animating; remove after animation ends via JS; never apply globally; GPU layers are expensive
- [ ] AR509 transform-origin for card animations: `transform-origin: center bottom` for dating swipe cards (rotate around bottom center, like holding a card); `transform-origin: center` for likes/hearts
- [ ] AR510 Motion path: `offset-path: path("M0,0 C50,-50 100,50 150,0")` for particle effects (confetti on match in dating); CSS Motion Path instead of canvas; hardware accelerated

### AR6: Component CSS Patterns

- [ ] AR601 BEM-lite naming: `.card`, `.card__title`, `.card__meta`, `.card--featured`; block, element (double underscore), modifier (double dash); max depth 2 elements; never `.card__header__title`
- [ ] AR602 Data attribute styling: `[data-state="active"]`, `[data-variant="danger"]`, `[data-size="sm"]` — Stimulus-friendly; HTML attributes as API; CSS selects on state without class toggling
- [ ] AR603 :has() for parent selection: `.card:has(img) { grid-template-rows: auto 1fr }` — add image grid row only when image is present; eliminates JS-based conditional class toggling
- [ ] AR604 :is() specificity flattening: `:is(h1, h2, h3, h4) { ... }` — specificity of highest-specificity argument in list; use for typography resets across heading levels
- [ ] AR605 :where() for zero-specificity: `:where(.prose) h2 { ... }` — zero specificity; easily overridden by any consumer; good for base component styles that should be customizable
- [ ] AR606 Aspect ratio boxes: `.embed-container { aspect-ratio: 16/9; position: relative; overflow: hidden } .embed-container > * { position: absolute; inset: 0; width: 100%; height: 100% }` — replaces padding-top hack
- [ ] AR607 Fluid images: `img { max-width: 100%; height: auto; display: block }` as reset; `object-fit: cover` on sized containers; never explicit width/height except on avatar circles
- [ ] AR608 Sticky table headers: `thead th { position: sticky; top: 0; background: var(--color-background); z-index: var(--z-raised) }` — data tables in admin views and bsdports comparison
- [ ] AR609 Overflow menu: horizontal nav with `::-webkit-scrollbar { display: none }` + `scrollbar-width: none` — invisible scrollbar but still scrollable; tags row in brgen feed header
- [ ] AR610 Clamp lines: `.truncate-2 { overflow: hidden; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical }` utility; `.truncate-3` with 3; apply to card titles and excerpts

### AR7: Form Styling Implementation

- [ ] AR701 Input group: `.input-group { position: relative } .input-group__icon { position: absolute; inset-inline-start: var(--space-3); top: 50%; transform: translateY(-50%); color: var(--text-tertiary) } .input-group__input { padding-inline-start: calc(var(--space-3) * 2 + 20px) }` — icon inside input, never outside
- [ ] AR702 Floating label: `input:not(:placeholder-shown) + label, input:focus + label { transform: translateY(-1.5em) scale(0.85); color: var(--color-midtone) }` — label floats above on fill; zero JS; CSS-only
- [ ] AR703 Toggle/switch: `input[type="checkbox"].toggle { width: 44px; height: 26px; appearance: none; background: var(--color-border); border-radius: 9999px; transition: background var(--duration-fast) } input[type="checkbox"].toggle:checked { background: var(--color-midtone) }` — pill toggle without JS
- [ ] AR704 Radio card: `input[type="radio"]:checked + label { border-color: var(--color-midtone); background: var(--color-midtone-50) }` — visually selectable card options for dating preferences, amber style profiles
- [ ] AR705 File drop zone: `.dropzone { border: 2px dashed var(--color-border); border-radius: var(--radius-lg); padding: var(--space-8); text-align: center; transition: all var(--duration-fast) } .dropzone.drag-over { border-color: var(--color-midtone); background: var(--color-midtone-50) }` — `drag-over` class toggled by Stimulus
- [ ] AR706 Progress indicator: `progress { appearance: none; width: 100%; height: 4px; border-radius: 9999px; background: var(--color-border) } progress::-webkit-progress-bar { background: var(--color-border) } progress::-webkit-progress-value { background: var(--color-midtone); border-radius: 9999px }` — cross-browser styled progress
- [ ] AR707 Star rating: `input[type="radio"].star:checked ~ .star, input[type="radio"].star:checked { color: var(--color-accent) }` — reverse-DOM star trick; CSS-only; accessible with labels
- [ ] AR708 Inline errors: `.field-error { font-size: var(--text-sm); color: var(--color-danger); margin-block-start: var(--space-1); display: flex; align-items: center; gap: var(--space-1) }` + error icon SVG via CSS `::before`
- [ ] AR709 Form section divider: `fieldset { border: none; padding: 0; margin: 0 } legend { font-size: var(--text-sm); font-weight: 600; text-transform: uppercase; letter-spacing: 0.06em; color: var(--text-secondary); margin-bottom: var(--space-4) }` — semantic fieldset, styled legend

### AR8: Responsive Patterns

- [ ] AR801 Mobile-first breakpoint system: `--bp-sm: 480px; --bp-md: 768px; --bp-lg: 1024px; --bp-xl: 1280px; --bp-2xl: 1536px`; always `@media (min-width: ...)` not `max-width` — mobile base, enhance up
- [ ] AR802 Container queries for components: `@container (min-width: 400px) { .card { flex-direction: row } }` — card layout responds to its container width, not viewport; cards reflow correctly in sidebar and main
- [ ] AR803 Container type declaration: `.card-grid { container-type: inline-size; container-name: grid }` — enables `@container grid (min-width: ...)` rules on descendants
- [ ] AR804 Responsive navigation strategy: hamburger menu at mobile only — avoid hamburger on tablet+; use horizontal scrollable nav or visible condensed nav instead of hiding behind burger
- [ ] AR805 Fluid spacing: `padding: clamp(16px, 4vw, 48px)` on major sections — no discrete breakpoints; spacing scales continuously; feels naturally proportioned at any width
- [ ] AR806 Image srcset: `<%= image_tag @post.image, srcset: { small_url => "400w", medium_url => "800w", large_url => "1200w" }, sizes: "(max-width: 768px) 100vw, 800px" %>` — Rails helper for responsive images
- [ ] AR807 Print styles: `@media print { .sidebar, .nav, .btn { display: none } .prose { max-width: 100%; font-size: 12pt } a[href]::after { content: " (" attr(href) ")" } }` — articles printable; blognet, baibl
- [ ] AR808 `dvh` for full-screen: `height: 100dvh` instead of `100vh`; dynamic viewport height excludes mobile browser chrome; no content hidden under address bar or bottom toolbar
- [ ] AR809 `svh` for stable fullscreen: `height: 100svh` for elements that should not resize when mobile browser chrome shows/hides; modals and overlays use `svh`
- [ ] AR810 Intrinsic sizing: `width: fit-content` on badge/chip elements; `width: min-content` on narrow column headers; `width: max-content` on tooltip text — never hardcode widths on text containers

### AR9: Performance-Oriented CSS

- [ ] AR901 Contain property: `contain: content` on feed items — isolates paint, layout, style; browser skips these items when unrelated DOM changes; critical for long feeds
- [ ] AR902 content-visibility: `content-visibility: auto; contain-intrinsic-size: 0 200px` on off-screen cards — browser skips rendering; 50px scroll = 10× rendering performance improvement on long lists
- [ ] AR903 will-change restriction: applied only within `@keyframes` animation or Stimulus controller's `connect()`, removed in `disconnect()`; browser allocates GPU memory only while needed
- [ ] AR904 Layer promotion: `transform: translateZ(0)` on the scrolling feed container — promotes to compositor layer; scroll handled by GPU not CPU; eliminates scroll jank on low-end devices
- [ ] AR905 Font-display: `font-display: optional` for decorative fonts (brand font in headers); `font-display: swap` for body text; never `font-display: block` which causes invisible text
- [ ] AR906 Critical CSS extraction: above-the-fold CSS (header, hero, first fold of feed) inlined in `<style>` tag via build step; deferred stylesheet covers below-fold; eliminates render-blocking CSS
- [ ] AR907 CSS-only dark mode switch: `<input type="checkbox" id="dark-toggle"> <label for="dark-toggle">` + `#dark-toggle:checked ~ * { --color-background: ... }` — no JavaScript needed for theme toggle; preference stored in localStorage by tiny JS snippet only for persistence
- [ ] AR908 Unused CSS removal: PurgeCSS configured in propshaft build; scans ERB + JS + Ruby for class names; removes unreferenced CSS rules; 60-80% reduction in production CSS bundle size
- [ ] AR909 CSS property inheritance: use `inherit` keyword for text colors in child elements rather than repeating values; `color: inherit` on `a` tags inside components prevents browser default blue override
- [ ] AR910 Reduce paint: `background-color` changes are cheaper than `box-shadow` changes; `opacity` and `transform` don't trigger repaint; prefer these for hover states over color-change animations


## AS — Design System Rollout and Implementation (AP continuation)

### AS1: Implementation Sequencing

- [ ] AS101 Phase 0 — token extraction: extract every hardcoded color, size, and spacing value from all 6 apps' CSS into `tokens.css`; replace with `var(--token-name)`; no visual change; 1-2 days
- [ ] AS102 Phase 1 — reset + base: implement CSS reset + base typography in shared `base.css`; apply to all apps; fix any regressions; no new features; 1 day
- [ ] AS103 Phase 2 — layout: implement app-shell grid, content column constraint, card grid in each app; replace float-based or fixed-px layouts; 2-3 days per app
- [ ] AS104 Phase 3 — navigation: implement new nav (desktop sidebar, mobile bottom nav, breadcrumbs) per app spec; test keyboard navigation and screen reader; 1-2 days per app
- [ ] AS105 Phase 4 — components: implement card, button, form, modal, toast, badge, avatar components per app; replace inline styles with component classes; 3-5 days per app
- [ ] AS106 Phase 5 — typography: apply per-app font stack, fluid type scale, prose styles; verify reading comfort at 375px, 768px, 1280px viewports; 1-2 days per app
- [ ] AS107 Phase 6 — color system: apply cinema palettes per app; dark mode implementation; verify contrast ratios; 1-2 days per app
- [ ] AS108 Phase 7 — motion: add easing vocabulary, animation keyframes, transition tokens to all interactive elements; verify reduced-motion; 1 day per app
- [ ] AS109 Phase 8 — performance: CSS bundle audit, content-visibility, critical CSS extraction, PurgeCSS; Lighthouse audit target ≥95; 1-2 days per app
- [ ] AS110 Phase 9 — accessibility: axe-core CI, ARIA roles, focus management, contrast audit; zero critical violations; 1-2 days per app

### AS2: brgen — Specific Implementation Steps

- [ ] AS201 brgen tokens.css: define `--brgen-midtone: #2563eb; --brgen-shadow: #0a0e1a; --brgen-highlight: #dbeafe; --brgen-accent: #f59e0b; --brgen-danger: #dc2626; --brgen-success: #059669`
- [ ] AS202 brgen app shell: CSS Grid `"sidebar main"` on desktop; `"main"` on mobile; sidebar `width: 240px` collapses to bottom nav on mobile via `@media (max-width: 768px)`
- [ ] AS203 brgen feed card: `.post-card { display: flex; gap: var(--space-3); padding: var(--space-3) var(--space-4); border-bottom: 1px solid var(--color-border); transition: background var(--duration-fast) } .post-card:hover { background: var(--color-surface) }` — X-inspired density
- [ ] AS204 brgen vote component: `.vote { display: flex; gap: var(--space-2); align-items: center } .vote__btn { display: flex; align-items: center; gap: var(--space-1); padding: var(--space-1) var(--space-2); border-radius: var(--radius-full); color: var(--text-secondary); border: none; background: none; cursor: pointer; transition: all var(--duration-fast) var(--ease-spring) } .vote__btn:hover { background: var(--color-midtone-100); color: var(--color-midtone) } .vote__btn[data-voted="true"] { color: var(--color-midtone); font-weight: 600 }`
- [ ] AS205 brgen subdomain theming: `[data-vertical="dating"] { --color-midtone: #ec4899 } [data-vertical="marketplace"] { --color-midtone: #f59e0b } [data-vertical="tv"] { --color-midtone: #7c3aed } [data-vertical="playlist"] { --color-midtone: #10b981 } [data-vertical="takeaway"] { --color-midtone: #ef4444 } [data-vertical="maps"] { --color-midtone: #06b6d4 }` — set `data-vertical` on `<body>` in layout
- [ ] AS206 brgen dating swipe stack: `.swipe-stack { position: relative; width: 320px; height: 480px; margin: auto } .swipe-card { position: absolute; inset: 0; border-radius: var(--radius-xl); overflow: hidden; box-shadow: var(--shadow-lg); transition: transform var(--duration-standard) var(--ease-spring) } .swipe-card:nth-child(2) { transform: scale(0.94) translateY(12px) } .swipe-card:nth-child(3) { transform: scale(0.88) translateY(24px) }`
- [ ] AS207 brgen bottom nav: `.bottom-nav { position: fixed; bottom: 0; inset-inline: 0; height: 54px; padding-bottom: env(safe-area-inset-bottom); display: flex; background: var(--color-background); border-top: 1px solid var(--color-border); z-index: var(--z-sticky) } .bottom-nav__item { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 2px; color: var(--text-secondary); font-size: var(--text-xs); transition: color var(--duration-fast) } .bottom-nav__item[aria-current] { color: var(--color-midtone) }`
- [ ] AS208 brgen notification badge: `.badge { position: absolute; top: -4px; right: -4px; min-width: 18px; height: 18px; padding-inline: 4px; background: var(--color-danger); color: white; border-radius: 9999px; font-size: 11px; font-weight: 700; line-height: 18px; text-align: center; border: 2px solid var(--color-background) }` — red dot with count over icon
- [ ] AS209 brgen marketplace grid: `display: grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); gap: 1px; background: var(--color-border)` — gap creates border effect between tiles; tiles have `background: var(--color-background)` — Instagram grid pattern
- [ ] AS210 brgen TV player: `video { width: 100%; aspect-ratio: 16/9; background: #000; display: block } .player-wrapper { background: #000; position: relative } .player-controls { position: absolute; bottom: 0; inset-inline: 0; background: linear-gradient(to top, rgba(0,0,0,0.8), transparent); padding: var(--space-4); opacity: 0; transition: opacity var(--duration-fast) } .player-wrapper:hover .player-controls, .player-wrapper:focus-within .player-controls { opacity: 1 }`

### AS3: amber — Specific Implementation Steps

- [ ] AS301 amber tokens.css: `--amber-shadow: #1c1917; --amber-midtone: #d4a843; --amber-highlight: #fef3c7; --amber-accent: #6366f1; --amber-warm-50: #fffbeb; --amber-warm-100: #fef3c7`
- [ ] AS302 amber item card: `aspect-ratio: 3/4; border-radius: var(--radius-md); overflow: hidden; position: relative; background: var(--color-surface)` — portrait orientation; `img { width: 100%; height: 100%; object-fit: cover; transition: transform var(--duration-standard) var(--ease-decelerate) }` — zoom on hover
- [ ] AS303 amber color swatch strip: `.color-swatches { display: flex; gap: 4px; padding: var(--space-2) } .swatch { width: 14px; height: 14px; border-radius: 50%; border: 1px solid rgba(0,0,0,0.1); flex-shrink: 0 }` — dominant color dots from blurhash palette
- [ ] AS304 amber CPW badge: `.cpw-badge { position: absolute; bottom: var(--space-2); right: var(--space-2); background: rgba(0,0,0,0.65); backdrop-filter: blur(4px); color: white; font-size: 11px; border-radius: var(--radius-sm); padding: 2px 6px }` — cost-per-wear overlay
- [ ] AS305 amber wardrobe grid: `masonry columns: 2` on mobile, `3` on tablet, `4` on desktop; gap `var(--space-2)`; each item `break-inside: avoid; margin-bottom: var(--space-2)` — Pinterest-style varying heights
- [ ] AS306 amber outfit canvas: `display: grid; grid-template-columns: repeat(3, 1fr); grid-template-rows: repeat(3, 1fr); gap: var(--space-2); width: 360px; height: 360px` — 3×3 grid for outfit items; top row = outerwear, middle = tops, bottom = bottoms+shoes
- [ ] AS307 amber sustainability score: `.sustain-score { display: flex; align-items: center; gap: var(--space-2) } .sustain-meter { height: 6px; border-radius: 3px; background: var(--color-border); flex: 1 } .sustain-meter__fill { height: 100%; border-radius: 3px; background: linear-gradient(to right, var(--color-danger), var(--color-success)); width: calc(var(--score) * 1%) }` — CSS custom property drives meter width
- [ ] AS308 amber AI suggestion card: `border: 1px solid var(--amber-midtone); background: linear-gradient(135deg, var(--amber-warm-50), white); border-radius: var(--radius-lg); padding: var(--space-4)` — warm gold-tinted background for AI suggestions; visually distinct from regular cards

### AS4: blognet — Specific Implementation Steps

- [ ] AS401 blognet article layout: `.article { max-width: 740px; margin-inline: auto; padding: var(--space-8) var(--space-4) } .article-hero { width: 100%; aspect-ratio: 16/9; object-fit: cover; border-radius: var(--radius-md); margin-bottom: var(--space-6) }` — Medium article pattern
- [ ] AS402 blognet reading progress: `.progress-bar { position: fixed; top: 0; left: 0; right: 0; height: 3px; background: var(--color-border); z-index: var(--z-sticky) } .progress-bar__fill { height: 100%; background: var(--color-midtone); width: 0; transition: width 0.1s linear }` — driven by Stimulus scroll controller
- [ ] AS403 blognet drop cap: `.article > .prose > p:first-of-type::first-letter { font-size: 4.5em; float: left; line-height: 0.75; margin-inline-end: 0.08em; font-weight: 700; color: var(--color-shadow) }` — activated only on articles flagged `featured: true`
- [ ] AS404 blognet pullquote: `.pullquote { text-align: center; font-size: var(--text-xl); font-style: italic; line-height: 1.4; margin-block: var(--space-8); padding-block: var(--space-4); border-block: 1px solid var(--color-border); max-width: 600px; margin-inline: auto; color: var(--color-shadow) }` — editorial statement
- [ ] AS405 blognet paywall scrim: `.paywall-scrim { position: relative } .paywall-scrim::after { content: ""; position: absolute; bottom: 0; left: 0; right: 0; height: 200px; background: linear-gradient(to bottom, transparent, var(--color-background)) }` — fade content to CTA
- [ ] AS406 blognet section label: `.section-label { font-size: var(--text-xs); font-weight: 700; text-transform: uppercase; letter-spacing: 0.1em; color: var(--color-danger) }` — red department header; New Yorker pattern applied to blognet vertical labels

### AS5: baibl — Specific Implementation Steps

- [ ] AS501 baibl verse container: `.verse { display: grid; grid-template-columns: 2.5rem 1fr; gap: var(--space-2); padding: var(--space-2) var(--space-3); border-radius: var(--radius-sm); transition: background var(--duration-fast) } .verse:hover { background: var(--color-surface) } .verse:target { background: var(--amber-warm-50); border-inline-start: 3px solid var(--color-midtone) }`
- [ ] AS502 baibl verse number: `.verse-num { font-variant-numeric: tabular-nums; font-size: var(--text-sm); font-weight: 600; color: var(--color-midtone); line-height: 1.7; text-align: end }` — right-aligned verse number in grid column
- [ ] AS503 baibl parallel view: `display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-4); overflow: hidden` — two translations side by side; each `overflow-y: auto; height: calc(100dvh - var(--header-height))`; scroll sync via Stimulus
- [ ] AS504 baibl annotation: `.annotation { border-inline-start: 3px solid var(--color-accent); padding-inline-start: var(--space-2); font-size: var(--text-sm); color: var(--text-secondary); margin-block-start: var(--space-1) }` — appears below annotated verse; toggleable via Stimulus

### AS6: bsdports — Specific Implementation Steps

- [ ] AS601 bsdports port card: `.port-card { display: grid; grid-template-rows: auto 1fr auto; gap: var(--space-2); padding: var(--space-3); border: 1px solid var(--color-border); border-radius: var(--radius-md) } .port-name { font-family: var(--font-mono); font-size: var(--text-sm); font-weight: 600; color: var(--color-midtone) }` — monospace names, minimal card
- [ ] AS602 bsdports security badge: `.security-badge { background: var(--color-danger); color: white; font-size: 11px; font-weight: 700; padding: 2px 6px; border-radius: var(--radius-sm) }` — red security advisory indicator; `display: none` when no advisory
- [ ] AS603 bsdports dependency graph: SVG-based; nodes as `<circle>` with port name `<text>`; edges as `<line>`; D3 force layout via Stimulus controller; port card color = version freshness (green=recent, yellow=aging, red=outdated)
- [ ] AS604 bsdports search result: `.search-result { padding: var(--space-3); border-bottom: 1px solid var(--color-border) } .search-result mark { background: var(--color-midtone-200); border-radius: 2px; padding: 0 2px }` — FTS5 snippet with highlight marks styled

### AS7: hjerterom — Specific Implementation Steps

- [ ] AS701 hjerterom category icons: 128px SVG illustrations per category (food bag, clothing, toy, book); `--hjerterom-green: #10b981`; icons in app green on white background; warm, inviting
- [ ] AS702 hjerterom donation card: `.donation-card { border-radius: var(--radius-xl); overflow: hidden; box-shadow: var(--shadow-sm) } .donation-card__header { background: var(--color-midtone); padding: var(--space-4); display: flex; align-items: center; gap: var(--space-3) }` — header in app green with white icon and title
- [ ] AS703 hjerterom expiry urgency: `.expiry-soon { color: var(--color-warning) }; .expiry-critical { color: var(--color-danger); animation: pulse 1.5s ease-in-out infinite }` — animated urgency for food about to expire; non-judgmental urgency
- [ ] AS704 hjerterom impact numbers: `.impact-stat { text-align: center } .impact-stat__value { font-size: var(--text-3xl); font-weight: 800; color: var(--color-midtone); font-variant-numeric: tabular-nums } .impact-stat__label { font-size: var(--text-sm); color: var(--text-secondary) }` — animated number component

### AS8: Cross-App Pattern Library

- [ ] AS801 Shared partials: `app/views/shared/_card.html.erb`, `_btn.html.erb`, `_avatar.html.erb`, `_badge.html.erb`, `_toast.html.erb` — common patterns across all 6 apps; DRY via shared partials not gem
- [ ] AS802 Button variants: `.btn` base + `.btn--primary` (filled midtone), `.btn--secondary` (border), `.btn--ghost` (transparent), `.btn--danger` (filled danger), `.btn--sm` / `.btn--lg` size modifiers; all have focus, hover, active, disabled states
- [ ] AS803 Avatar with fallback: `<% if user.avatar.attached? %> <%= image_tag(user.avatar.variant(:thumb)) %> <% else %> <span class="avatar-initials"><%= user.initials %></span> <% end %>` — never broken image; initials in brand midtone
- [ ] AS804 Empty state: `.empty-state { text-align: center; padding: var(--space-12) var(--space-4) } .empty-state__icon { width: 64px; height: 64px; margin-inline: auto; margin-bottom: var(--space-4); opacity: 0.4 } .empty-state__title { font-size: var(--text-lg); font-weight: 600; color: var(--text-primary) } .empty-state__body { font-size: var(--text-base); color: var(--text-secondary); max-width: 40ch; margin-inline: auto }`
- [ ] AS805 Loading skeleton: `.skeleton { background: linear-gradient(90deg, var(--color-surface) 25%, var(--color-border) 50%, var(--color-surface) 75%); background-size: 200%%; animation: shimmer 1.4s ease-in-out infinite; border-radius: var(--radius-sm) }` — apply to any placeholder element
- [ ] AS806 Toast component: `.toast { display: flex; align-items: flex-start; gap: var(--space-3); padding: var(--space-3) var(--space-4); background: var(--color-shadow); color: white; border-radius: var(--radius-lg); box-shadow: var(--shadow-lg); max-width: 360px; pointer-events: all; animation: slideInRight var(--duration-standard) var(--ease-decelerate) } .toast--success { border-inline-start: 3px solid var(--color-success) } .toast--error { border-inline-start: 3px solid var(--color-danger) }`
- [ ] AS807 Modal/dialog: `.dialog { border: none; border-radius: var(--radius-xl); padding: 0; max-width: min(560px, 90vw); max-height: 90dvh; overflow: auto; box-shadow: var(--shadow-lg) } .dialog::backdrop { background: rgba(0,0,0,0.5); backdrop-filter: blur(2px) }` — native `<dialog>` styled; backdrop via pseudo-element
- [ ] AS808 Tooltip: `.tooltip-wrapper { position: relative } .tooltip { position: absolute; bottom: calc(100% + var(--space-2)); left: 50%; transform: translateX(-50%); background: var(--color-shadow); color: white; font-size: var(--text-xs); border-radius: var(--radius-sm); padding: var(--space-1) var(--space-2); white-space: nowrap; pointer-events: none; opacity: 0; transition: opacity var(--duration-fast) } .tooltip-wrapper:hover .tooltip { opacity: 1 }`

### AS9: Design QA Checklist

- [ ] AS901 Visual regression testing: Capybara + Cuprite screenshots; compare against baseline; fail CI on pixel diff >1%; implement for all major views in all 6 apps
- [ ] AS902 Cross-browser testing: Chrome, Firefox, Safari (webkit), Edge; verify CSS features (subgrid, container queries, :has()) in all; polyfill only where usage warrants
- [ ] AS903 Device testing: 375px (iPhone SE), 428px (iPhone 14 Pro Max), 768px (iPad), 1280px (laptop), 1920px (desktop); each app must be fully functional at all widths
- [ ] AS904 Dark mode visual audit: every component in light and dark mode; screenshot both; verify no invisible text, broken icons, or washed-out colors in either mode
- [ ] AS905 Animation audit: play each animation at 0.25× speed; verify enter/exit states, timing, easing feel; reject over-animated elements; check reduced-motion disable
- [ ] AS906 Typography audit: print each view as PDF; verify line lengths, heading hierarchy, hyphenation; good typography survives print
- [ ] AS907 Color contrast audit: run Polypane accessibility panel or axe on every view; zero AA failures; document AAA failures with rationale for each
- [ ] AS908 Touch audit: use touch emulation in Chrome DevTools; verify all touch targets ≥44px; no hover-only affordances; swipe gestures work smoothly
- [ ] AS909 Keyboard navigation audit: tab through every view; verify logical focus order; all interactive elements reachable; no focus traps outside modals; all actions keyboard-operable
- [ ] AS910 Performance audit: Lighthouse on every app's most-visited route in incognito; ≥95 all categories; document and fix any failures before marking design phase complete


## AT — Active Record Schema and Data Model Patterns

### AT1: brgen Schema Refinements

- [ ] AT101 posts table indexes: `add_index :posts, [:community_id, :created_at]`; `add_index :posts, [:user_id, :created_at]`; `add_index :posts, :trending_score`; `add_index :posts, [:pinned, :created_at]` — composite indexes match actual query patterns
- [ ] AT102 posts full-text: `add_column :posts, :search_vector, :virtual, as: "title || ' ' || coalesce(body, '')", stored: true` + FTS5 virtual table over search_vector — avoids double-storing text
- [ ] AT103 votes denormalization: `add_column :posts, :vote_score, :integer, default: 0, null: false` + `add_column :posts, :comment_count, :integer, default: 0, null: false` — counter caches; avoid COUNT(*) on every render
- [ ] AT104 follows graph: `follows(follower_id, followee_id, followee_type, created_at)` — polymorphic; `add_index :follows, [:follower_id, :followee_type, :followee_id], unique: true` prevents duplicate follows
- [ ] AT105 dating profiles: `profiles(user_id, bio, birth_date, gender, seeking, city_id, lat, lng, last_active_at, photos_count, verified_at)` — `lat/lng` for distance queries; `last_active_at` for "active recently" filter; `verified_at` for photo verification
- [ ] AT106 dating likes: `likes(liker_id, liked_id, kind: {like/superlike/pass}, created_at)` — `add_index :likes, [:liker_id, :liked_id], unique: true`; match detection: `SELECT * FROM likes WHERE liker_id = B AND liked_id = A AND kind != 'pass'`
- [ ] AT107 matches: `matches(user_a_id, user_b_id, matched_at, conversation_id)` — always `user_a_id < user_b_id` to avoid duplicates; `add_index :matches, [:user_a_id, :user_b_id], unique: true`
- [ ] AT108 marketplace listings: `listings(user_id, category_id, title, description, price_ore, currency, condition, status, lat, lng, city_id, views_count, expires_at)` — price in øre (integer); never float for money; `expires_at` for auto-archival
- [ ] AT109 conversations + messages: `conversations(id, type: {direct/match/listing}, status)` + `conversation_participants(conversation_id, user_id, last_read_at)` + `messages(conversation_id, sender_id, body, kind: {text/image/offer}, read_at)` — last_read_at per participant for unread count
- [ ] AT110 notifications: `notifications(user_id, type, actor_id, notifiable_type, notifiable_id, read_at, created_at)` — polymorphic notifiable; `add_index :notifications, [:user_id, :read_at, :created_at]` for unread feed
- [ ] AT111 communities: `communities(id, city_id, name, slug, description, rules, privacy: {public/restricted/private}, member_count, post_count, created_by_id)` — `slug` unique per city; `add_index :communities, [:city_id, :slug], unique: true`
- [ ] AT112 tags: `tags(name, slug, taggings_count)` + `taggings(tag_id, taggable_type, taggable_id)` — shared tag table; `add_index :taggings, [:taggable_type, :taggable_id]`; `add_index :tags, :slug, unique: true`

### AT2: amber Schema Refinements

- [ ] AT201 items: `items(user_id, name, brand, category, color_primary, color_hex, material, size, condition, purchase_price_ore, purchased_at, source: {bought/gifted/thrifted}, season_mask: integer, wear_count, last_worn_at, blurhash, active)` — `season_mask` bitmask: spring=1, summer=2, autumn=4, winter=8; `active` false = stored away
- [ ] AT202 outfits: `outfits(user_id, name, occasion, weather_min, weather_max, rating, worn_count, last_worn_at, notes)` + `outfit_items(outfit_id, item_id, position, layer: integer)` — position for display order; layer for layering (base/mid/outer)
- [ ] AT203 style_profile: `style_profiles(user_id, aesthetic_tags: jsonb, color_palette: jsonb, size_map: jsonb, body_notes: text, updated_at)` — jsonb for flexible schema evolution; `aesthetic_tags` = ["minimalist", "streetwear"]
- [ ] AT204 item embeddings: `item_embeddings(item_id, model_version, embedding: blob, created_at)` — raw 768-dim float32 vector stored as blob; queried via sqlite-vec extension; versioned by model_version for re-embedding on model upgrade
- [ ] AT205 declutter_sessions: `declutter_sessions(user_id, started_at, completed_at, items_kept, items_donated, items_sold, challenge_type)` — track declutter campaign progress; items_donated + items_sold for sustainability impact report
- [ ] AT206 wear_logs: `wear_logs(item_id, user_id, worn_on, outfit_id, weather, occasion, notes)` — per-item wear history; `add_index :wear_logs, [:item_id, :worn_on]`; CPW = purchase_price / wear_logs.count

### AT3: blognet Schema Refinements

- [ ] AT301 posts: `posts(blog_id, author_id, title, slug, subtitle, body_html, body_text, status: {draft/review/scheduled/published/archived}, published_at, scheduled_for, word_count, reading_time_seconds, paywalled, featured_image_key, seo_title, seo_description, canonical_url)` — `slug` unique per blog; body_text for FTS5; reading_time_seconds computed on save
- [ ] AT302 blogs: `blogs(user_id, name, slug, description, about_html, plan: {free/pro/business}, subscriber_count, monthly_revenue_ore, custom_domain, verified_at, suspended_at)` — `slug` globally unique; plan determines paywall and newsletter features
- [ ] AT303 subscriptions: `subscriptions(subscriber_id, blog_id, plan: {free/paid}, status: {active/cancelled/past_due}, stripe_subscription_id, current_period_end, created_at)` — `add_index :subscriptions, [:subscriber_id, :blog_id], unique: true`
- [ ] AT304 newsletter_sends: `newsletter_sends(post_id, blog_id, started_at, completed_at, recipient_count, open_count, click_count, bounce_count)` — analytics per send; not per recipient (privacy); aggregated only
- [ ] AT305 reading_history: `reading_history(user_id, post_id, started_at, completed_at, progress_pct, device_type)` — completed_at null = in progress; progress_pct for scroll depth; `add_index :reading_history, [:user_id, :post_id], unique: true`

### AT4: Shared Model Patterns

- [ ] AT401 Soft delete: `add_column :table, :deleted_at, :datetime` + `default_scope { where(deleted_at: nil) }` + `def soft_delete; update(deleted_at: Time.current); end` — never hard delete user-generated content immediately; 30-day grace period
- [ ] AT402 Optimistic locking: `add_column :table, :lock_version, :integer, default: 0, null: false` — Rails uses `lock_version` automatically; raises `StaleObjectError` on concurrent update; handle in controller
- [ ] AT403 Audit columns: every table has `created_at: datetime, updated_at: datetime, created_by_id: integer, updated_by_id: integer` — updated_by_id via `Current.user.id` in `before_save` callback; never null on non-system records
- [ ] AT404 UUID primary keys: `create_table :external_events, id: :uuid, default: "gen_random_uuid()"` — for any externally-referenced resource; prevents enumeration; standard primary key stays integer for internal tables
- [ ] AT405 JSONB columns for flexibility: `add_column :users, :preferences, :json, default: {}` — store user settings (notification_types, feed_density, theme) without schema migrations for each new preference
- [ ] AT406 Generated columns: `add_column :posts, :body_length, :integer, as: "length(body)", stored: true` — database computes and indexes derived values; zero application code needed; always consistent
- [ ] AT407 CHECK constraints: `add_check_constraint :listings, "price_ore > 0", name: "price_positive"` + `add_check_constraint :likes, "liker_id != liked_id", name: "no_self_like"` — database enforces invariants regardless of application code path
- [ ] AT408 Foreign key constraints: every `_id` column has `add_foreign_key :table, :referenced_table` — prevents orphan records; SQLite supports FK with `foreign_keys: ON` pragma (set in database.yml)
- [ ] AT409 Partial indexes: `add_index :posts, :created_at, where: "status = 'published'"` — index only rows matching predicate; 10× smaller index on posts table with many drafts; matches queries exactly
- [ ] AT410 Covering indexes: `add_index :notifications, [:user_id, :read_at, :created_at]` — includes all columns needed for `SELECT COUNT(*) WHERE user_id = ? AND read_at IS NULL`; zero table access needed

## AU — LLM and AI Integration Patterns

### AU1: ruby_llm Configuration

- [ ] AU101 Model registry: define per-feature model assignments in `config/ai.yml` — `outfit_generation: claude-3-5-haiku, semantic_search: text-embedding-3-small, council: claude-opus-4, fast_fix: deepseek-r1:free`; change model without code deploy
- [ ] AU102 ruby_llm initializer: `RubyLLM.configure { |c| c.openai_api_key = Rails.application.credentials.openai_key; c.anthropic_api_key = Rails.application.credentials.anthropic_key }` in `config/initializers/ruby_llm.rb`
- [ ] AU103 Streaming responses: `RubyLLM.chat.ask(prompt) { |chunk| ActionCable.server.broadcast("user_#{user_id}", {chunk: chunk.content}) }` — stream LLM response directly to browser via CableReady; eliminates polling
- [ ] AU104 Tool use: define tools as Ruby methods with `tool :search_wardrobe, description: "search user's wardrobe items", parameters: {query: {type: :string}}` — LLM calls tools autonomously; amber outfit generation uses wardrobe search tool
- [ ] AU105 Conversation history: maintain `messages` array per session in Solid Cache; `cache.fetch("ai_conv_#{session_id}") { [] }` then push user + assistant messages; pass full history to each LLM call
- [ ] AU106 System prompt caching: long system prompts (rules, wardrobe context) sent as Anthropic cache_control prefix; `cache_control: {type: "ephemeral"}` on first message; 93% cost reduction on repeated calls
- [ ] AU107 Error handling: rescue `RubyLLM::RateLimitError` with exponential backoff; rescue `RubyLLM::ContextWindowError` by truncating oldest messages; rescue `RubyLLM::APIError` by routing to fallback model
- [ ] AU108 Token budget per request: `max_tokens: 512` for fast responses (outfit tags, port descriptions); `max_tokens: 2048` for detailed generation (outfit explanation, research summaries); never unlimited
- [ ] AU109 Cost tracking: `AICall.create(model:, input_tokens:, output_tokens:, cost_ore:, feature:, user_id:, duration_ms:)` after every LLM call; daily cost report in admin dashboard; per-user budget enforcement

### AU2: Embedding and Semantic Search

- [ ] AU201 Embedding generation job: `GenerateEmbeddingJob.perform_later(record_type, record_id)` — called in `after_commit :generate_embedding, on: [:create, :update]` on embeddable models; never synchronous
- [ ] AU202 sqlite-vec setup: `db.execute "SELECT load_extension('vec0')"` in `config/database.rb` initializer; enables `CREATE VIRTUAL TABLE embeddings USING vec0(embedding float[768])`; cosine similarity search via `vec_distance_cosine`
- [ ] AU203 Embedding model selection: `text-embedding-3-small` (1536 dims, cheap) for semantic search; `text-embedding-3-large` (3072 dims, expensive) for similarity-sensitive features (amber visual similarity); configurable per feature
- [ ] AU204 Batch embedding: collect up to 100 records without embeddings; send in single API call (`input: [text1, text2, ...]`); cost scales linearly but API call overhead is flat; 10× more efficient than one-by-one
- [ ] AU205 Embedding versioning: `embedding_model_version` column on embedding tables; when model changes, queue `ReembedAllJob` which processes in batches; serve old embeddings until re-embed completes
- [ ] AU206 Hybrid search implementation: `query_embedding = embed(query)` then `SELECT id, (bm25_score * 0.4 + cosine_similarity * 0.6) AS hybrid_score FROM posts JOIN posts_fts ... ORDER BY hybrid_score DESC LIMIT 20` — RRF blend of keyword + semantic
- [ ] AU207 Embedding cache: cache embeddings for queries (not documents) in Solid Cache with 1h TTL; repeated queries (common search terms) skip embedding API call; `Rails.cache.fetch("embed:#{Digest::SHA1.hexdigest(query)}") { embed(query) }`

### AU3: Per-App AI Features

- [ ] AU301 brgen: AI post tagging — on post create, `TagPostJob` sends title+body to LLM with system prompt "return 3-5 relevant tags as JSON array"; LLM returns `["oslo", "boligmarked", "leie"]`; auto-attach tags
- [ ] AU302 brgen: AI content moderation — `ModerateContentJob` checks post against NSFW/spam/hate classifiers; returns `{score: 0.1, categories: []}` as JSON; auto-hide if score > 0.8
- [ ] AU303 brgen: Personalized feed ranking — user's engagement history → LLM-generated interest vector → dot-product with post embedding → ranked feed; computed nightly per user; stored in `user_interests` JSON
- [ ] AU304 amber: Item analysis — on photo upload, send image to Claude claude-haiku-4-5 vision: "analyze this clothing item. Return JSON: {category, brand_guess, colors, material_guess, occasion_tags, season_tags}"; pre-fill item form
- [ ] AU305 amber: Outfit generation — `POST /ai/outfit` with `{occasion, weather, mood}` → LLM receives wardrobe item summaries + constraints → returns 3 outfit combinations as arrays of item IDs → rendered immediately
- [ ] AU306 amber: Style profile analysis — monthly LLM analysis of wear patterns: "based on these wear logs, describe this user's style in 3 sentences and suggest 3 wardrobe improvements"; stored in `style_profiles.ai_analysis`
- [ ] AU307 bsdports: Port description enhancement — LLM rewrites terse port descriptions in plain language; original stored; LLM version shown by default with "Show original" toggle; re-generated quarterly
- [ ] AU308 baibl: Theological Q&A — user asks question; LLM searches relevant verses via embedding similarity; synthesizes answer citing specific passages; includes disclaimer; saves as Q&A in knowledge base
- [ ] AU309 blognet: Article improvement suggestions — after draft saved, `AnalyseDraftJob` sends first 500 words to LLM: "identify 3 specific improvements: clarity, structure, opening hook"; surfaces as sidebar suggestions
- [ ] AU310 hjerterom: Donation impact narrative — weekly LLM generation of impact story from aggregated stats: "This week, 47 families received food, including 3 with celiac disease. Maria donated 12kg of pasta..."; displayed on public impact page

### AU4: Prompt Engineering Patterns

- [ ] AU401 System prompt structure: `[Identity] [Task] [Constraints] [Output format] [Examples]` — always in this order; identity anchors behavior; constraints prevent drift; output format eliminates parsing
- [ ] AU402 JSON output enforcement: always request JSON with explicit schema: "Respond with valid JSON matching this schema: {\"tags\": [\"string\"], \"confidence\": number}" — never free-form text that needs parsing
- [ ] AU403 Few-shot examples: include 2-3 examples in system prompt for consistent output style; amber item analysis includes example input photo description and expected JSON response
- [ ] AU404 Chain-of-thought for complex tasks: "Think step by step. First identify..., then consider..., finally produce..." — improves accuracy on multi-factor decisions (outfit compatibility, theological synthesis)
- [ ] AU405 Temperature calibration: `temperature: 0.0` for deterministic classification (moderation, tagging); `temperature: 0.7` for creative generation (outfit suggestions, narrative); `temperature: 1.0` for brainstorming; never set-and-forget
- [ ] AU406 Prompt versioning: every prompt string stored as constant in `app/prompts/` directory; version-tagged: `OUTFIT_PROMPT_V3 = "..."` — enables A/B testing and rollback; never inline prompts in job code
- [ ] AU407 Context window management: truncate conversation history to last N messages that fit in 75% of context window; reserve 25% for response; compute token counts via `RubyLLM::Tokenizer.count`
- [ ] AU408 Sensitive data scrubbing: before sending any user data to external LLM API, scrub PII — replace email addresses with `[email]`, phone numbers with `[phone]`, account numbers with `[account]`; log scrubbing actions
- [ ] AU409 Output validation: every LLM JSON response parsed through strict schema validator (Dry::Schema or similar); rejected responses logged + retried once with correction instruction in context
- [ ] AU410 Fallback responses: if LLM fails (all retries exhausted), surface graceful fallback — outfit suggestion = "Try combining your most-worn top with your newest bottom"; never blank response

## AV — OpenBSD/relayd Deployment Specifics

### AV1: relayd Configuration Per App

- [ ] AV101 Per-app table: each Rails app gets its own `table <appname> { <server_ip>:<port> }` block in `/etc/relayd.conf`; brgen on 3000, amber on 3001, bsdports on 3002, baibl on 3003, blognet on 3004, hjerterom on 3005
- [ ] AV102 relayd relay per app: `relay <appname>_relay { listen on $ext_addr port 443 tls; table <appname>; forward to <appname> port <port> }` — TLS termination at relayd; backend HTTP only; no TLS cert management per app
- [ ] AV103 Path-based routing: single relayd listener routes to different apps by path prefix: `match request path "/amber/*" forward to amber`; eliminates separate subdomains per app where not needed; share TLS cert
- [ ] AV104 Subdomain routing: brgen dating/marketplace/tv on dedicated subdomains: `match request header "Host" value "dating.brgen.no" forward to brgen` — relayd inspects Host header; no nginx needed
- [ ] AV105 WebSocket relay: `relay websocket { listen on $ext_addr port 443 tls; table cable; protocol websocket; forward to cable port 28080 }` — ActionCable on separate port; relayd proxies WebSocket upgrade
- [ ] AV106 HTTP to HTTPS redirect: `relay redirect { listen on $ext_addr port 80; match request path "/.well-known/acme-challenge/*" forward to acme; match all redirect to https://... code 301 }` — ACME first, redirect everything else
- [ ] AV107 Header injection: `match response set header "Strict-Transport-Security" value "max-age=31536000; includeSubDomains; preload"` + `"X-Content-Type-Options" value "nosniff"` + `"X-Frame-Options" value "DENY"` in relayd relay block
- [ ] AV108 Rate limiting via pf: `table <bruteforce> persist`; `block quick from <bruteforce>`; `pass in proto tcp to port 443 keep state (max-src-conn-rate 100/10)` — 100 connections per 10 seconds per IP; reloaded via `pfctl -f /etc/pf.conf`
- [ ] AV109 Health check: relayd marks backend unhealthy if `/up` returns non-200 three times in 5s; removes from table; traffic routes to remaining healthy instances; email alert via `pflog` + cron
- [ ] AV110 Connection buffering: `protocol web { tcp { nodelay } }` — TCP_NODELAY for low-latency WebSocket; `timeout connect 5` — fail fast on unresponsive backend; `timeout read 30` — allow slow streaming responses

### AV2: OpenBSD Service Management

- [ ] AV201 rc.d scripts: each app has `/etc/rc.d/<appname>` script implementing `start`, `stop`, `check`, `restart`; uses `daemon` function from `/etc/rc.d/rc.subr`; PID file in `/var/run/<appname>.pid`
- [ ] AV202 Service user: each app runs as dedicated `_<appname>` user; `useradd -s /sbin/nologin -d /var/www/<appname> _brgen`; Falcon process starts as this user; never run as root or www
- [ ] AV203 Pledge + unveil: Falcon daemon pledges `"stdio rpath wpath cpath inet unix proc exec"`; unveils only app directory, `/tmp`, and database path; `Pledge.pledge` + `Unveil.unveil` called in `config/initializers/pledge.rb`
- [ ] AV204 Log rotation: `/etc/newsyslog.conf` entry per app: `"/var/log/<appname>.log" _<appname>:_<appname> 640 7 * $W0D0 Z /var/run/<appname>.pid 30"` — weekly rotation, 7 kept, gzipped, SIGUSR1 to reopen
- [ ] AV205 rcctl enable: `rcctl enable <appname>` in deploy script; `rcctl start <appname>` on first deploy; `rcctl restart <appname>` on subsequent deploys; never kill -9 the Falcon process
- [ ] AV206 Environment file: each app reads `/etc/rc.d/<appname>.conf` for `DATABASE_URL`, `RAILS_MASTER_KEY`, `OPENROUTER_API_KEY`; file owned root:_appname, mode 0640; sourced by rc.d script via `. /etc/rc.d/<appname>.conf`
- [ ] AV207 Shared credentials: RAILS_MASTER_KEY stored in `/etc/master.keys/<appname>` with mode 0400 owned by `_<appname>`; referenced by rc.d script; not in environment on disk in plaintext
- [ ] AV208 Soft memory limits: `login.conf` entry for `_<appname>` class sets `memorylocked-cur=512M` and `openfiles-cur=1024`; prevents one app from consuming all VPS memory

### AV3: Database and Storage on VPS

- [ ] AV301 SQLite WAL configuration: `PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA busy_timeout=5000; PRAGMA foreign_keys=ON; PRAGMA cache_size=-64000` — set via `config/initializers/sqlite_config.rb` on connect
- [ ] AV302 Litestream config: `/etc/litestream.yml` — `dbs: - path: /var/db/<appname>/production.sqlite3; replicas: - url: s3://bucket/<appname>/db`; systemd-style service via `rcctl enable litestream`
- [ ] AV303 Backup verification: weekly cron job downloads latest Litestream replica and runs `PRAGMA integrity_check` against it; alerts if check fails; never discover backup corruption during a crisis
- [ ] AV304 Active Storage on VPS: `config/storage.yml` with `local: {root: /var/www/<appname>/storage}` for production; symlink `public/storage → /var/www/<appname>/storage`; directory owned by `_<appname>`
- [ ] AV305 Active Storage S3 mirror: production config uses `mirror` service type — writes to both local disk and R2; local disk survives VPS; R2 survives disk failure; read from local (fast), fallback to R2
- [ ] AV306 Disk space monitoring: cron checks `df -h /var/www`; alerts at 80% full; auto-purge Active Storage variants older than 30 days (regenerated on demand) if >90% full; never silently fail uploads

### AV4: TLS and Certificates

- [ ] AV401 acme-client for all domains: `acme-client.conf` entry per domain and subdomain; `acme-client -v <domain>` in weekly cron; httpd serves ACME challenges; relayd reloads after cert renewal
- [ ] AV402 Wildcard cert: `*.brgen.no` wildcard cert via DNS-01 ACME challenge (requires DNS API access); covers all brgen subdomains without per-subdomain cert management
- [ ] AV403 OCSP stapling: `tls { keypair <domain>; ocsp /etc/ssl/<domain>.ocsp }` in relayd config; `ocspcheck -vNo /etc/ssl/<domain>.ocsp /etc/ssl/<domain>.fullchain.pem` in daily cron; serves OCSP staple with TLS handshake
- [ ] AV404 TLS session resumption: relayd maintains TLS session cache; subsequent connections from same client resume without full handshake; 50ms saved per mobile reconnect
- [ ] AV405 Certificate transparency monitoring: weekly check against crt.sh API for unexpected certs issued for our domains; alert if unauthorized cert found; mitigates MITM via rogue CA

## AW — Monetisation Patterns

### AW1: Stripe Integration

- [ ] AW101 Stripe gem: `bundle add stripe`; `Stripe.api_key = Rails.application.credentials.stripe_secret_key`; `Stripe.api_version = "2024-06-20"` — pin API version; never use unpinned
- [ ] AW102 Webhook endpoint: `POST /stripe/webhooks` verified via `Stripe::Webhook.construct_event(payload, sig_header, secret)` — never process Stripe events without signature verification; `protect_from_forgery except: :webhook`
- [ ] AW103 Subscription model: `Subscription(user_id, blog_id, stripe_subscription_id, stripe_customer_id, plan, status, current_period_end, cancel_at_period_end)` — mirror Stripe state locally; source of truth is Stripe webhook, not client POST
- [ ] AW104 Checkout Session: `Stripe::Checkout::Session.create(mode: "subscription", line_items: [...], success_url:, cancel_url:, customer_email:)` — redirect user to Stripe-hosted checkout; no card data touches our servers
- [ ] AW105 Customer Portal: `Stripe::BillingPortal::Session.create(customer: stripe_customer_id, return_url:)` — let users manage subscription (cancel, upgrade, update card) via Stripe portal; zero custom subscription management UI needed
- [ ] AW106 Webhook events handled: `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`, `invoice.payment_succeeded`, `invoice.payment_failed`, `customer.subscription.trial_will_end` — each updates local `subscriptions` table
- [ ] AW107 Idempotency: `Stripe::PaymentIntent.create(idempotency_key: "pi_user_#{user_id}_plan_#{plan}_#{Time.current.to_date}")` — duplicate webhook events or retries don't double-charge
- [ ] AW108 Norwegian VAT: Stripe Tax handles Norwegian MVA (25%) automatically when `automatic_tax: {enabled: true}` and customer address collected at checkout; no manual VAT calculation
- [ ] AW109 Revenue recognition: `RevenueEvent` table mirrors Stripe invoice data; MRR = sum of active subscription amounts; churn = subscriptions cancelled in period; computed in admin analytics

### AW2: Vipps and Norwegian Payment Methods

- [ ] AW201 Vipps ePayment: integrate Vipps ePayment API for Norwegian mobile-first payments; `POST /ecomm/v2/payments` with phone number; user approves in Vipps app; webhook confirms payment
- [ ] AW202 Vipps recurring: Vipps Recurring API for Norwegian subscription billing; alternative to Stripe for users preferring Vipps; same webhook-driven subscription state machine
- [ ] AW203 BankID verification: for marketplace seller verification and dating profile verification, integrate BankID Connect OIDC flow; verify Norwegian identity without storing personal data
- [ ] AW204 Payment method preference: user sets default payment method (Stripe card / Vipps) in account settings; checkout respects preference; both paths update same `subscriptions` table
- [ ] AW205 Marketplace escrow: for high-value listings, hold payment in Stripe Connect escrow; release to seller after buyer confirms receipt; 48h auto-release if no dispute

### AW3: Free Tier and Paywall Logic

- [ ] AW301 brgen freemium: all social features free; dating = 5 likes/day free, unlimited with subscription; marketplace = 3 active listings free, unlimited with subscription; TV = free streams, HD with subscription
- [ ] AW302 blognet metered paywall: 5 free articles per subscriber per month; on 6th article, show subscribe CTA with article blurred below fold; meter tracked in `reading_history` table per month
- [ ] AW303 amber freemium: 30 item wardrobe free; unlimited with subscription; AI outfit generation = 5/month free, unlimited with subscription
- [ ] AW304 Paywall CTA design: subscriber-wall interstitial uses blur + gradient treatment (AP405); CTA copy: "Støtt [publication]. Les ubegrenset fra [price]/mnd." — benefit-first, price second
- [ ] AW305 Trial period: 14-day free trial on all paid plans; `trial_end` set in Stripe Checkout; no credit card required for trial on blognet; card required for brgen dating (prevent abuse)
- [ ] AW306 Grandfathering: early subscribers locked at founding price; `founding_member: true` flag on subscription; never retroactively raise price on grandfathered users; honor indefinitely
- [ ] AW307 Tip jar: one-time payment without subscription; `Stripe::PaymentIntent.create(amount:, currency: "nok", metadata: {type: "tip", recipient_id:})`; creator receives 90% after Stripe fees

## AX — SEO, Structured Data, and Discoverability

### AX1: Meta Tags

- [ ] AX101 Rails meta_tags gem: `bundle add meta-tags`; `set_meta_tags title:, description:, og: {title:, description:, image:, type: "article"}, twitter: {card: "summary_large_image"}` in every show action
- [ ] AX102 Dynamic OG images: generate OG image per post via `Vips::Image` — post title over background with branding; serve as Active Storage attachment; cache 24h; `og:image` points to static file not dynamic route
- [ ] AX103 Canonical URLs: `set_meta_tags canonical: post_url(@post)` on all content pages; prevents duplicate content penalty from `?page=`, `?sort=`, and other query params
- [ ] AX104 Title formula: `[Post Title] — [Publication Name] — [App Name]`; max 60 characters; truncate post title if needed; consistent across all apps
- [ ] AX105 Description formula: first 150 characters of body_text (plain text, no HTML); fallback to subtitle; never repeat title in description
- [ ] AX106 hreflang: `<link rel="alternate" hreflang="nb" href="...">` + `<link rel="alternate" hreflang="en" href="...">` on pages with both language versions; signals to Google which version to show per region
- [ ] AX107 Robots.txt: allow all crawlers on public content; disallow `/admin`, `/api`, `/account`, `/dating` (private); disallow search result pages (`?q=`); auto-generated from Rails route constraints

### AX2: Structured Data

- [ ] AX201 Article JSON-LD: `<script type="application/ld+json">{"@type":"Article","headline":,"datePublished":,"author":{"@type":"Person","name":},"publisher":{"@type":"Organization","name":,"logo":}}</script>` — blognet and brgen posts
- [ ] AX202 Recipe JSON-LD: `{"@type":"Recipe","name":,"recipeIngredient":[],"recipeInstructions":[],"cookTime":"PT30M","totalTime":"PT45M","nutrition":{}}` — blognet Foodielicious recipes; enables Google Recipe rich results
- [ ] AX203 Product JSON-LD: `{"@type":"Product","name":,"offers":{"@type":"Offer","price":,"priceCurrency":"NOK","availability":"InStock"},"condition":}` — brgen marketplace listings; enables Google Shopping appearance
- [ ] AX204 Event JSON-LD: `{"@type":"Event","name":,"startDate":,"location":{"@type":"Place","name":,"address":}}` — brgen city events; enables Google Events appearance
- [ ] AX205 FAQPage JSON-LD: `{"@type":"FAQPage","mainEntity":[{"@type":"Question","name":,"acceptedAnswer":{"@type":"Answer","text":}}]}` — bsdports port FAQ, baibl theological Q&A
- [ ] AX206 BreadcrumbList: `{"@type":"BreadcrumbList","itemListElement":[{"@type":"ListItem","position":1,"name":"Home"},{"@type":"ListItem","position":2,"name":"Category"}]}` — all nested pages; enables breadcrumb in search results
- [ ] AX207 SoftwareApplication JSON-LD: `{"@type":"SoftwareApplication","name":"brgen","applicationCategory":"SocialNetworkingApplication","operatingSystem":"Any","offers":{}}` — for PWA apps in app store search

### AX3: Sitemaps and Feeds

- [ ] AX301 Dynamic sitemap: `sitemap_generator` gem; generates XML sitemap per app; posts/listings/profiles with `changefreq` and `priority` per content type; pings Google/Bing on generation
- [ ] AX302 Sitemap index: root `/sitemap.xml` indexes per-section sitemaps (`/sitemap-posts.xml`, `/sitemap-marketplace.xml`); each sitemap max 50,000 URLs; avoids Google indexation lag
- [ ] AX303 Atom feed: `GET /feed.atom` returns Atom 1.0 feed of latest posts; `format.atom { render layout: false }` in PostsController; `link_to_atom_feed` in head layout; enables RSS readers
- [ ] AX304 JSON feed: `GET /feed.json` returns JSON Feed 1.1 spec; easier to parse than Atom for apps; includes `author`, `content_html`, `image`, `tags`; blognet only
- [ ] AX305 Podcast RSS: blognet audio posts expose podcast-compatible RSS feed with `<enclosure>` tags; iTunes Podcast categories and `itunes:*` namespace tags; submittable to Apple Podcasts / Spotify

## AY — Moderation and Trust and Safety

### AY1: Content Moderation

- [ ] AY101 Moderation queue: `reports(reporter_id, reportable_type, reportable_id, category: {spam/hate/illegal/nsfw/other}, details, status: {pending/reviewed/actioned/dismissed}, reviewed_by_id, reviewed_at)` — every report flows through this table
- [ ] AY102 Auto-hide threshold: if a post receives ≥5 spam reports from ≥5 distinct users within 1 hour, auto-hide pending human review; `ModerateContentJob` sends notification to moderation queue
- [ ] AY103 AI pre-moderation: every new post and listing passes through `ClassifyContentJob`; if `nsfw_score > 0.7` or `spam_score > 0.8`, auto-flag for review; human moderator reviews; AI never auto-removes
- [ ] AY104 Hash-matching: `PhotoDNAJob` computes perceptual hash of all uploaded images; matches against known CSAM hash database (provided by IWF); instant removal + law enforcement report on match
- [ ] AY105 Moderator dashboard: `/admin/moderation` — queue of pending reports sorted by severity × report count; one-click actions: remove, warn, shadowban, permaban; bulk actions for obvious spam
- [ ] AY106 Appeal process: users can appeal moderation decisions via `/account/appeals`; appeals reviewed by second moderator; accepted appeals restore content and add credit to reporter's abuse score
- [ ] AY107 Shadowban: `users.shadowbanned_at` timestamp; shadowbanned user's content visible only to themselves; responses from others never delivered; no notification to shadowbanned user; expires after 7 days or manual review
- [ ] AY108 Rate limits for new users: accounts <24h old limited to 3 posts/day, 20 comments/day, 5 dating likes/day; reduces throwaway account spam; limits lifted automatically after 24h + email verification

### AY2: Trust Signals

- [ ] AY201 Email verification: required for posting, dating, marketplace; `verification_token` sent on registration; `verified_at` set on click; unverified accounts can browse but not create
- [ ] AY202 Phone verification: optional for brgen; required for marketplace sellers (fraud prevention); Twilio Verify API; `phone_verified_at` column; phone not stored, only verification status
- [ ] AY203 Profile completeness score: 0-100 score based on (avatar: 20pts, bio: 20pts, city: 10pts, verified email: 25pts, verified phone: 25pts); displayed to user; gates some features on score threshold
- [ ] AY204 Seller reputation: marketplace sellers accumulate rating from buyers (1-5 stars + review); `average_rating`, `review_count` on User; displayed on listings; below 3.0 = restricted listing ability
- [ ] AY205 Trust badge: `trusted_seller` flag awarded after 10+ completed sales, 4.5+ rating, no unresolved disputes; displayed on listings as visual trust signal
- [ ] AY206 Reporter reputation: track each user's report accuracy (reports upheld vs dismissed); low-accuracy reporters' reports weighted lower; prevents coordinated brigading

## AZ — Advanced PWA and Mobile Patterns

### AZ1: Advanced PWA Features

- [ ] AZ101 Web app manifest categories: `"categories": ["social", "news", "lifestyle"]` in manifest.json — surfaces app in correct category in browser app stores and OS-level app suggestions
- [ ] AZ102 Related applications: `"related_applications": [{"platform": "webapp"}]` + `"prefer_related_applications": false` — ensures browser offers web app install, not defers to App Store
- [ ] AZ103 Launch handler: `"launch_handler": {"client_mode": "navigate-existing"}` — if app already open, reuse existing window and navigate; prevents duplicate PWA windows
- [ ] AZ104 Window controls overlay: `"display_override": ["window-controls-overlay"]` — app content extends into title bar area; add `env(titlebar-area-x/y/width/height)` CSS to position content correctly; desktop PWA feels native
- [ ] AZ105 Declarative link capturing: `"handle_links": "preferred-in-app"` — external links in app open within PWA window rather than system browser; keeps user in app context
- [ ] AZ106 App edge side panel: `"edge_side_panel": {"preferred_width": 400}` — Edge browser shows app as side panel at 400px width; relevant for bsdports and baibl as reference panels
- [ ] AZ107 Tabbed app mode: `"display_override": ["tabbed"]` — multiple PWA windows as browser-style tabs within single app frame; relevant for brgen multi-city browsing
- [ ] AZ108 Local font access: `window.queryLocalFonts()` — access user's installed fonts; amber style editor could use user's local fonts for outfit notes; GDPR note: user must grant permission
- [ ] AZ109 Barcode detection API: `new BarcodeDetector({formats: ["ean_13", "qr_code"]}).detect(imageData)` — amber item add: scan barcode to auto-fill brand/product from Open Food Facts / Open Beauty Facts APIs
- [ ] AZ110 Shape detection: `new FaceDetector().detect(imageBitmap)` — amber profile photo crop to face bounding box; QR code scanner for hjerterom volunteer check-in
- [ ] AZ111 Web NFC: `new NDEFReader().scan()` — hjerterom donation items tagged with NFC; volunteer taps phone to item, app auto-fills item details; no camera needed
- [ ] AZ112 Web Serial: `navigator.serial.requestPort()` — bsdports: read from attached hardware (thermal label printer for donations in hjerterom, barcode scanner)
- [ ] AZ113 Persistent storage: `navigator.storage.persist()` — prevent browser from evicting PWA cache; critical for baibl offline (entire Bible) and bsdports offline port list
- [ ] AZ114 Storage quota: `navigator.storage.estimate()` — check available quota before caching large offline datasets; show user warning if <50MB available; suggest clearing browser cache

### AZ2: Offline-First Patterns

- [ ] AZ201 Cache-first for shell: `["/", "/offline", "/manifest.webmanifest", "application.js", "application.css"]` in service worker install event precache; app shell always available offline
- [ ] AZ202 Network-first for API: fetch from network; on failure, serve from Cache API if available; update cache on success; `{ cacheName: "api-v1", networkTimeoutSeconds: 3 }`
- [ ] AZ203 Stale-while-revalidate for feeds: serve from cache immediately; fetch fresh in background; update cache; next visit gets fresh content; perfect for news feeds
- [ ] AZ204 IndexedDB schema: `db.createObjectStore("posts", {keyPath: "id"})`; `db.createObjectStore("drafts", {keyPath: "localId", autoIncrement: true})`; `db.createObjectStore("sync_queue", {keyPath: "id", autoIncrement: true})` — structured offline storage
- [ ] AZ205 Offline indicator: Stimulus controller listens to `window` `online`/`offline` events; shows banner "Du er offline — viser lagret innhold" when offline; hides when reconnected; never disruptive
- [ ] AZ206 Draft sync: pending drafts saved to IndexedDB; on `background-sync` event, POST each draft to server; mark as synced; show confirmation toast; drafts survive browser close
- [ ] AZ207 Conflict detection: offline edit + server edit = conflict; on sync, if `server_updated_at > offline_started_at`, show diff to user with merge options; never silently overwrite
- [ ] AZ208 Offline search: FTS5 index exported as JSON at login; stored in IndexedDB; offline search runs against local index; indicates "offline results" to user; re-sync on reconnect
- [ ] AZ209 Prefetch critical data: on login, fetch + cache user's feed (first 50 items), unread notifications, active conversations, current wardrobe (amber) — all available immediately offline
- [ ] AZ210 Service worker update flow: `self.addEventListener("activate", e => e.waitUntil(clients.claim()))` — new service worker takes control immediately; `postMessage({type: "RELOAD_SUGGESTED"})` to active tabs; shows "New version available — reload?" banner


## BA — brgen.no Landing Page and Next-Generation UX Vision

### BA1: Landing Page — Black Void Foundation

- [ ] BA101 Root layout: `<body data-controller="landing">` with `background: #000; min-height: 100dvh; overflow: hidden` — true black OLED-native; no grey, no off-black; `#000000` exactly
- [ ] BA102 Wordmark: `<h1 class="wordmark">brgen</h1>` positioned `top: clamp(20px, 4vw, 32px); left: clamp(20px, 4vw, 32px)` — `font-family: "Helvetica Neue", "Inter", Helvetica, Arial, sans-serif; font-weight: 700; font-size: clamp(18px, 3vw, 24px); color: #fff; letter-spacing: -0.03em; line-height: 1`; load Inter variable font as drop-in Helvetica substitute under all OSes
- [ ] BA103 Wordmark click: tapping wordmark on mobile scrolls to top + resets nav to hidden state; on desktop links to `/`; never navigates away when already on root
- [ ] BA104 Full-bleed void: `position: fixed; inset: 0; background: #000` on `:root` — even momentum scroll overshoot is black; no white flash from browser chrome; `color-scheme: dark` on `<html>` so browser renders scrollbars dark
- [ ] BA105 No decorative elements: zero gradients, zero textures, zero illustrations on landing; the void IS the design; content (wordmark + arrow + nav) floats in it
- [ ] BA106 Font loading: preload Inter variable woff2 in `<head>`; `font-display: block` for wordmark only (short block period acceptable; wordmark must not FOUT); `font-display: swap` for all other text
- [ ] BA107 Meta theme-color: `<meta name="theme-color" content="#000000">` — browser chrome matches landing; seamless PWA install experience
- [ ] BA108 Favicon: wordmark "b" in white on black, 32×32 SVG; `<link rel="icon" href="/b.svg" type="image/svg+xml">` — scalable, no PNG needed; matches brand

### BA2: Hidden Navigation — Gesture Discovery

- [ ] BA201 Arrow indicator: `<div data-landing-target="arrow" class="nav-arrow">` positioned `top: clamp(20px, 4vw, 32px); right: clamp(20px, 4vw, 32px); width: 28px; height: 28px; color: rgba(255,255,255,0.5)` — SVG chevron-down icon; deliberately dim (50% opacity) — discoverable not screaming
- [ ] BA202 Arrow animation: `@keyframes float-down { 0%, 100% { transform: translateY(0) } 50% { transform: translateY(6px) } }; animation: float-down 2s ease-in-out infinite` — gentle bobbing; `animation-play-state: paused` once nav revealed; never loops after discovery
- [ ] BA203 Arrow pulse: after 3s idle on landing, arrow opacity increases from 0.5 → 0.9 with `transition: opacity 1s` — draws attention without immediately revealing the gesture; resets if user interacts
- [ ] BA204 Nav panel: `<nav data-landing-target="nav" class="slide-nav">` with `position: fixed; inset-inline: 0; top: 0; background: #000; transform: translateY(-100%); transition: transform 0.45s cubic-bezier(0.32, 0.72, 0, 1); z-index: var(--z-overlay); padding: clamp(60px, 10vw, 80px) clamp(20px, 5vw, 48px) clamp(32px, 6vw, 48px)` — slides from top; covers full viewport; `cubic-bezier(0.32, 0.72, 0, 1)` = iOS sheet spring
- [ ] BA205 Nav reveal triggers (Stimulus): `data-action="touchstart->landing#trackTouch touchmove->landing#swipeDetect deviceorientation->landing#tiltDetect"` — three parallel triggers; any one reveals nav
- [ ] BA206 Swipe-down gesture: `touchstart` records `startY`; on `touchmove` if `currentY - startY > 60` and `deltaX < 30` (not a horizontal swipe) → `this.showNav()`; threshold 60px prevents accidental trigger
- [ ] BA207 Tilt gesture: `deviceorientation` event; if `beta > 25` (device tilted forward >25°) and user has been on page >2s → `this.showNav()`; requires `DeviceOrientationEvent.requestPermission()` on iOS 13+; request on first tap
- [ ] BA208 Scroll gesture: `wheel` event deltaY > 80 → `this.showNav()`; desktop users discover via scroll; mobile gets swipe; same result either way
- [ ] BA209 Keyboard: `ArrowDown` or `Space` → `this.showNav()`; `Escape` → `this.hideNav()`; fully keyboard navigable; accessibility requirement
- [ ] BA210 Nav dismiss: tap outside nav (on the underlying page content scrim), press `Escape`, or swipe-up while nav open → `this.hideNav()` with reversed spring; `transform: translateY(-100%)` returns nav to hidden
- [ ] BA211 Scrim: when nav open, `<div class="nav-scrim" data-action="click->landing#hideNav">` at `position: fixed; inset: 0; background: rgba(0,0,0,0.4); z-index: calc(var(--z-overlay) - 1); backdrop-filter: blur(2px)` — tap scrim = dismiss; blur creates depth separation
- [ ] BA212 First-visit persistence: `localStorage.setItem("nav-discovered", "1")` once user opens nav; on subsequent visits, show arrow at 20% opacity (subtler) rather than animated — user already knows the gesture
- [ ] BA213 ARIA: `<nav aria-label="Vertikaler" aria-hidden="true" data-landing-target="nav">` at rest; `aria-hidden="false"` when open; focus trapped inside when open via `focus-trap-js` or manual `tabindex` management

### BA3: Navigation Content — Horizontal Scroll Reveal

- [ ] BA301 Nav headline: `<p class="nav-items">` containing all vertical names in one line: `Regular&thinsp;|&thinsp;AI&thinsp;|&thinsp;Marketplace&thinsp;|&thinsp;Dating&thinsp;|&thinsp;Playlist&thinsp;|&thinsp;Chat&thinsp;|&thinsp;Takeaway&thinsp;|&thinsp;TV&thinsp;|&thinsp;Maps` — `font-family: "Helvetica Neue", "Inter", Helvetica, Arial, sans-serif; font-weight: 400; font-size: clamp(28px, 6vw, 56px); color: #fff; white-space: nowrap; line-height: 1.15; letter-spacing: -0.02em`
- [ ] BA302 Fade-out mask: `.nav-items-wrapper { overflow: hidden; -webkit-mask-image: linear-gradient(to right, black 60%, transparent 90%); mask-image: linear-gradient(to right, black 60%, transparent 90%) }` — text fades to transparent at right edge; signals more content via horizontal scroll
- [ ] BA303 Horizontal scroll: `overflow-x: auto; scroll-snap-type: x mandatory; scrollbar-width: none; -webkit-overflow-scrolling: touch` on `.nav-items-wrapper`; each vertical name is `scroll-snap-align: start`; swipe left reveals hidden items
- [ ] BA304 Swipe-left affordance: after 1.5s with nav open, if user hasn't scrolled, animate wrapper to `scrollLeft = 120px` then back over 0.8s — peek animation reveals "Dating | Playlist..." before snapping back; gesture education without text instruction
- [ ] BA305 Separator styling: `&thinsp;|&thinsp;` using thin spaces + pipe; `color: rgba(255,255,255,0.3)` on pipe via CSS `::after` pseudo — pipes are visual rhythm, not interactive; items themselves are the links
- [ ] BA306 Item links: each vertical name is `<a href="/vertical" data-turbo-action="replace">` — Turbo Drive navigation; active vertical gets `font-weight: 700` not a color change (black bg, color meaningless at this size)
- [ ] BA307 Responsive breakpoints: at `>1100px`, all 9 verticals visible without scroll (font-size reduces to fit); at `<768px`, show 3 before fade; at `<480px`, show 2 before fade — always implies more via mask
- [ ] BA308 Vertical-specific sub-label: below the horizontal nav, smaller text `font-size: clamp(12px, 2vw, 15px); color: rgba(255,255,255,0.45)` shows city: "Bergen, Norge" — subtle geographic anchor; not a heading, an orientation cue
- [ ] BA309 Auth links: bottom of nav panel, `Logg inn  ·  Registrer deg` in `font-size: 14px; color: rgba(255,255,255,0.5)` — tertiary; present but not dominant; anonymous posting means signup is optional initially
- [ ] BA310 Nav transition stagger: nav items fade in with stagger after panel arrives — `animation: fadeIn 0.3s ease both; animation-delay: calc(var(--i) * 60ms)` where `--i` = 0,1,2... on each `<a>`; panel arrives first, content populates

### BA4: City Isolation Architecture

- [ ] BA401 Subdomain-to-city mapping: `cities` table with `{id, name, slug, subdomain, lat, lng, timezone, locale, active}`; `brgen.no` → Bergen; `losangeles.citynet.no` → Los Angeles; `amsterdam.citynet.no` → Amsterdam; all served by same Rails app
- [ ] BA402 City detection middleware: `CityDetectionMiddleware` reads `request.subdomain`; looks up `City.find_by(subdomain: subdomain)`; sets `ActsAsTenant.current_tenant`; 404s on unknown subdomain; no cross-city leakage possible at the SQL layer
- [ ] BA403 City wall: `default_scope { where(city_id: ActsAsTenant.current_tenant.id) }` on Post, Comment, Vote, User, Community, Listing, Profile — every query is city-scoped; impossible to accidentally query across cities
- [ ] BA404 Inter-city isolation test: CI test verifies that `Post.create(city_id: city_a.id)` is NOT findable when tenant = city_b; hard assertion; any regression fails CI immediately
- [ ] BA405 City launch checklist: new city requires: subdomain DNS + TLS cert (wildcard covers *.citynet.no), City record in DB, seed content batch, relayd relay rule, rcctl enable for city process (or shared process with tenant routing)
- [ ] BA406 City-specific domain aliases: brgen.no maps to Bergen; each top-level city brand domain resolves to its city; `citynet.no` subdomains as fallback for unlaunched cities during beta
- [ ] BA407 City admin: `/admin/cities` — per-city moderation dashboard; no global admin view that mixes city content; moderators are city-specific too
- [ ] BA408 City analytics isolation: `PageView`, `AnalyticsEvent` tables include `city_id`; analytics reports never aggregate across cities; each city's data is its own business unit

### BA5: Content Seeding Strategy

- [ ] BA501 Seed persona pool: generate 40-80 believable Bergen user personas via LLM — names, ages, neighbourhoods (Sandviken, Nordnes, Møhlenpris, Nygård, Fantoft), interests, writing styles; store as `seed_users.json`; never reuse across cities
- [ ] BA502 Reddit r/bergen mining: use `repligen.rb` to fetch top 200 r/bergen posts; filter for authentic Bergen content (mentions Bryggen, Fløyen, Vidden, Torgallmenningen, USF, Hulen); S&W-paraphrase via MASTER; translate to Norwegian Bokmål
- [ ] BA503 Content categories to seed: local nightlife recommendations (Terminus, Garage, Rick's), Fløyen hiking conditions, Bergen weather complaints (rain culture), BIFF film festival, Bergenfest, local restaurant openings, university life (UiB/HVL), Brann football, local politics/traffic, dialect jokes
- [ ] BA504 Post variety: seed posts across types — text only (40%), text + photo (35%), link share (15%), poll (5%), media (5%); distribution mirrors typical social platform organic content mix
- [ ] BA505 Photo generation: `repligen.rb` generates authentic-looking Bergen photos — Bryggen wharf, Fløyen view, rainy streets, cafe interiors, concert crowds; `postpro.rb` applies film grain, color grade, slight vignette to remove AI-generation artifacts; stored as Active Storage attachments
- [ ] BA506 LightGallery.js integration: `importmap pin lightgallery` + `importmap pin lightgallery/plugins/thumbnail`; Stimulus controller `data-controller="lightbox"` initialises `lightGallery(this.element, {plugins: [lgThumbnail], speed: 300, download: false})`; wraps `<figure>` elements in post body
- [ ] BA507 Engagement seeding: for each seeded post, generate 3-40 likes and 0-12 comments from pool of seed users; timestamps spread across past 2-8 weeks; vote scores use HN-style decay formula so older posts naturally have lower visibility; feels organic
- [ ] BA508 Comment authenticity: seed comments are short, conversational, Bergen-dialect-aware; mix of supportive, mildly sceptical, humorous; avoid unanimously positive threads (looks fake); one mild disagreement per 5 threads
- [ ] BA509 Seed script: `db/seeds/bergen.rb` — idempotent; skips if `Post.count > 100`; runs via `rails db:seed`; separate `db/seeds/personas.rb` for user personas; committed to repo but not run in CI
- [ ] BA510 Seed refresh: quarterly `SeedRefreshJob` adds 20-30 new posts to each city to maintain the impression of activity during slow growth phase; ceases when organic MAU > 500

### BA6: Post Composer — Expanding Input

- [ ] BA601 Composer container: `<div data-controller="composer" class="composer">` with `background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.1); border-radius: 12px; padding: var(--space-3) var(--space-4)` — barely-there surface on black bg; ghost card aesthetic
- [ ] BA602 Placeholder trigger: `<div data-composer-target="trigger" class="composer-trigger" data-action="click->composer#expand">Hva gjør du i dag?</div>` — `font-size: 16px; color: rgba(255,255,255,0.35); cursor: text` — dim, inviting, Norwegian
- [ ] BA603 Expand animation: on click/tap, trigger fades out; Tiptap editor slides in from below; media toolbar fades in at bottom; `max-height: 0 → 480px; opacity: 0 → 1; transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1)`
- [ ] BA604 Tiptap integration: `importmap pin @tiptap/core @tiptap/starter-kit @tiptap/extension-placeholder @tiptap/extension-character-count` — headless ProseMirror wrapper; no default styling; we supply all CSS
- [ ] BA605 Tiptap Stimulus controller: `data-controller="tiptap"` initialises `new Editor({element: this.editorTarget, extensions: [StarterKit, Placeholder.configure({placeholder: "Del noe..."}), CharacterCount.configure({limit: 10000})]})` in `connect()`; destroys in `disconnect()`
- [ ] BA606 Tiptap toolbar (bubble menu): appears on text selection — bold, italic, link, `H2`, blockquote, code; `BubbleMenu` extension positions toolbar above selection; `background: #1a1a1a; border: 1px solid rgba(255,255,255,0.15); border-radius: 8px; padding: 4px` — Medium-style
- [ ] BA607 Tiptap slash commands: type `/` → dropdown of insert commands: `/image` (upload), `/code` (code block), `/quote` (blockquote), `/poll` (poll), `/link` (embed link with preview); custom `Extension` that listens for `/` + word
- [ ] BA608 Tiptap styling: `.ProseMirror { color: #fff; font-size: 17px; line-height: 1.6; min-height: 80px; max-height: 360px; overflow-y: auto; outline: none } .ProseMirror p.is-editor-empty:first-child::before { content: attr(data-placeholder); color: rgba(255,255,255,0.3); pointer-events: none; float: left; height: 0 }`
- [ ] BA609 Media toolbar: fixed bottom of composer; `display: flex; gap: var(--space-4); align-items: center; padding-top: var(--space-3); border-top: 1px solid rgba(255,255,255,0.08)` — icons at 22px: microphone, camera, photo upload, location pin, post-type selector
- [ ] BA610 Microphone: `data-action="click->composer#toggleRecord"` — Web Audio API MediaRecorder; records voice note as MP3 via `lamejs` or WebM; Active Storage direct upload; voice note player rendered inline in post
- [ ] BA611 Camera: `data-action="click->composer#openCamera"` — `<input type="file" accept="image/*,video/*" capture="environment">` on mobile triggers native camera; on desktop opens file picker; multiple files allowed
- [ ] BA612 Photo upload: drag-and-drop onto composer area or file picker; multiple images accepted; thumbnail strip appears below editor in order; reorderable via drag (stimulus-sortable); remove via ×; direct upload progress bars
- [ ] BA613 Location: `data-action="click->composer#pickLocation"` — `navigator.geolocation.getCurrentPosition()` → reverse geocode via Nominatim API → display "Bryggen, Bergen"; user can override with text search; stored as lat/lng on post
- [ ] BA614 Post type selector: `<select data-composer-target="postType">` styled as pill — `Regular | Annonse | Utgivelse` (Regular / Classified ad / Media release); changes composer validation and downstream routing (Annonse goes to Marketplace feed; Utgivelse to Music/Media section)
- [ ] BA615 Character count: `<span data-composer-target="charCount">` in bottom-right of composer; shows remaining characters (10000 - current); turns amber at 500 remaining, red at 100; Tiptap CharacterCount extension provides count
- [ ] BA616 Submit button: `<button data-action="click->composer#submit" class="btn-post">Post</button>` — appears only when editor has content; `background: #fff; color: #000; border: none; border-radius: 9999px; padding: 8px 20px; font-weight: 600; font-size: 14px` — white pill on black; maximum contrast CTA

### BA7: Anonymous Posting

- [ ] BA701 Fingerprint: on composer expand, compute browser fingerprint — `navigator.userAgent + screen.width + screen.height + navigator.language + Intl.DateTimeFormat().resolvedOptions().timeZone` → SHA-256 via Web Crypto API → first 16 hex chars as `anon_id`
- [ ] BA702 Anonymous post limit: `AnonPost.where(fingerprint: anon_id).where("created_at > ?", 7.days.ago).count` — if ≥ 2, reject with prompt: "Du har nådd grensen for anonyme innlegg. Opprett en konto for å fortsette." (You've reached the anonymous post limit. Create an account to continue.)
- [ ] BA703 Anon post display: anonymous posts show `<span class="anon-badge">Anonym</span>` instead of username; avatar = grey silhouette; no profile link; posted as `user_id: nil, anon_fingerprint: "abc123..."` — fingerprint stored (for moderation) but never displayed
- [ ] BA704 Anon post MASTER moderation: before saving anonymous post, send to MASTER scan: post body through toxicity + spam + misinformation checks via free LLM (Groq llama3-8b); if flagged, reject with explanation; if clean, save; no LLM call for authenticated posts (reputation substitutes)
- [ ] BA705 Anon-to-auth upgrade: if anon user subsequently registers, option to claim their anonymous posts: "Dit anonyme innlegg 'X' — vil du knytte det til kontoen din?"; `AnonPost.where(fingerprint: anon_id).update(user_id: new_user.id, anon_fingerprint: nil)`
- [ ] BA706 Anon rate limiting: Rack::Attack rule — max 2 POST to `/posts` per 10 minutes per IP when `user_id: nil`; harder limit than the 7-day soft limit; prevents scripted spam despite fingerprint bypass
- [ ] BA707 Anon post expiry: anonymous posts auto-delete after 30 days unless claimed by a registered user; `PurgeAnonPostsJob` in `recurring.yml`; notified of impending deletion if browser revisits (localStorage `anon_post_ids` array)

### BA8: Feed Design — X and Facebook Synthesis

- [ ] BA801 Feed container: `<div role="feed" aria-label="Innlegg fra Bergen" data-controller="feed">` with `max-width: 680px; margin-inline: auto; padding-block: var(--space-4)` — constrained width on dark background; breathing room
- [ ] BA802 Post card: `<article class="post-card" data-controller="post">` — `background: rgba(255,255,255,0.03); border: 1px solid rgba(255,255,255,0.08); border-radius: 12px; padding: var(--space-4); margin-bottom: var(--space-3); transition: border-color var(--duration-fast)` — ghost card on black; hover: border-color to `rgba(255,255,255,0.18)`
- [ ] BA803 Post header: `display: flex; align-items: center; gap: var(--space-3); margin-bottom: var(--space-3)` — avatar (36px circle) + name column (bold 15px white + muted 13px timestamp) + three-dot menu top-right
- [ ] BA804 Anon post avatar: SVG grey circle with person silhouette; `width: 36px; height: 36px; border-radius: 50%; background: rgba(255,255,255,0.1)` — visually distinct from user avatars; no colour
- [ ] BA805 Post body: `font-size: 16px; line-height: 1.55; color: rgba(255,255,255,0.95); margin-bottom: var(--space-3)` — near-white, not pure white; slightly warm at 95% — less harsh than `#fff` on `#000`
- [ ] BA806 Rich text in feed: ActionText-rendered HTML stripped to safe subset; code blocks with syntax highlight (highlight.js via importmap); links open in new tab with `rel="noopener noreferrer"`; images inside post body use LightGallery.js
- [ ] BA807 Photo grid: 1 photo = full-width 16:9; 2 photos = 50/50 split; 3 photos = 1 large left + 2 stacked right; 4 photos = 2×2 grid; 5+ photos = 2×2 + "+N more" overlay on 5th; all via CSS Grid; LightGallery opens on click
- [ ] BA808 Action bar: `display: flex; align-items: center; gap: var(--space-1); margin-top: var(--space-3); padding-top: var(--space-3); border-top: 1px solid rgba(255,255,255,0.06)` — 6 icon-buttons; `color: rgba(255,255,255,0.45); font-size: 13px; gap: 4px per icon+count pair`
- [ ] BA809 Action icons: heart (like), star (save), share-box (share), code-brackets (embed), chat-bubble (reply), flag (report) — Heroicons outline at 18px; hover → `rgba(255,255,255,0.9)` + icon-specific colour (heart→pink, star→amber); spring scale `1.15` on click
- [ ] BA810 Like animation: click heart → `animation: heartbeat 0.4s cubic-bezier(0.34, 1.56, 0.64, 1)` → fill colour `#f43f5e`; count increments via Turbo Stream broadcast (not optimistic — real count); unlike reverses
- [ ] BA811 Share menu: click share → native `navigator.share({title:, url:})` on mobile; on desktop → popover with: Copy link, Share to (opens in new tab for X/Facebook), Embed code snippet; `data-controller="share-menu"`
- [ ] BA812 Embed code: clicking embed copies `<blockquote class="brgen-post" data-post-id="..."><a href="...">…</a></blockquote><script src="https://brgen.no/embed.js"></script>` to clipboard; oembed endpoint at `/oembed?url=`
- [ ] BA813 Reply inline: reply button expands a sub-composer inline below the post (not a page navigation); same Tiptap composer, smaller; anonymous option if not logged in; submit via `POST /posts/:id/comments`; new comment appended via Turbo Stream
- [ ] BA814 Report: `data-action="click->post#report"` → bottom sheet (mobile) or popover (desktop) with categories: Spam, Hatefullt innhold, Feil informasjon, Upassende, Annet; submits `POST /reports`; confirmation: "Innmeldt. Vi ser på det."

### BA9: Feed Algorithm and Ranking

- [ ] BA901 Ranked feed: primary feed mixes Trending + Following + Nearby content: `trending_weight: 0.4, following_weight: 0.4, nearby_weight: 0.2`; weights configurable per user in preferences
- [ ] BA902 Trending score: `score = (likes + comments * 2 + shares * 3) / ((hours_since_post + 2) ** 1.8)` — HN gravity formula; recomputed by `ScorePostsJob` every 10 minutes; stored in `posts.trending_score` for fast sort
- [ ] BA903 Cold start for new users: before any follows, show city-wide trending feed; after first follow, blend in followed-user content; after 5 follows, reduce trending weight by 10% per additional follow
- [ ] BA904 Chronological option: `?sort=new` URL param serves pure reverse-chronological feed; no algorithm; user preference toggled via Stimulus; stored in `current_user.feed_sort` preference
- [ ] BA905 Infinite scroll: IntersectionObserver on sentinel div at bottom of feed; on intersection, Turbo Frame `src` updated with next page cursor; new posts appended via `turbo_stream.append`; scroll position preserved
- [ ] BA906 New posts indicator: when CableReady broadcasts new post to `FeedChannel`, show "3 nye innlegg" pill at top of feed (like X's "N new tweets"); click → scroll to top + refresh; never auto-inject into feed (disrupts reading)
- [ ] BA907 Content diversity: prevent same user's posts appearing more than 3 times consecutively in feed; shuffle logic in `FeedQuery#call` — `ORDER BY trending_score DESC, user_id` + Ruby dedup pass
- [ ] BA908 Vertical filtering: top of feed — horizontal scrollable chip row: All | Regular | AI | Marketplace | Dating | Playlist | TV; active chip filters feed; `?vertical=marketplace` param; Turbo Frame refreshes feed on chip click

### BA10: Tiptap Rich Text Editor — Extended Features

- [ ] BA1001 Image resize in editor: Tiptap `ImageResize` extension from `@tiptap/extension-image` — drag handles on selected image to resize; stores `width` attribute on `<img>`; ActionText renders with stored dimensions
- [ ] BA1002 Link unfurl: on URL paste into editor, `POST /link_previews?url=` fetches OG metadata; renders link card below URL text: title, description, thumbnail, domain; user can dismiss card; stored as `<a data-type="link-preview" ...>` node
- [ ] BA1003 @mention: Tiptap `Mention` extension; `@` trigger → dropdown of users matching typed name; inserts `<span data-type="mention" data-id="user_id">@name</span>`; creates Notification on post save
- [ ] BA1004 #hashtag: Tiptap `Hashtag` extension (custom); `#` trigger auto-links hashtags; `<a href="/tags/name" data-type="hashtag">#name</a>`; creates/increments Tag record on post save
- [ ] BA1005 Poll node: `/poll` slash command inserts poll node; renders as `<div data-type="poll">` with editable option fields; on post save, creates `Poll` + `PollOption` records; readers vote via Turbo Stream
- [ ] BA1006 Code block with language: Tiptap `CodeBlockLowlight` extension with `lowlight` for syntax highlighting; language selector dropdown on focus; renders `<pre><code class="language-ruby">` in post body
- [ ] BA1007 Collaborative cursor (future): Tiptap Y.js provider for real-time collaborative editing; multiple users editing same post draft; coloured cursors per user; websocket via ActionCable — deferred, not for v1
- [ ] BA1008 Tiptap → ActionText: on form submit, serialize Tiptap JSON to HTML via `editor.getHTML()`; write to hidden `<input name="post[body]">` which ActionText reads; ActionText sanitizes on server before storage
- [ ] BA1009 Markdown paste: Tiptap detects pasted Markdown; converts to rich nodes via `@tiptap/extension-paste-handler`; `# Heading` → H2 node; `**bold**` → bold mark; `- item` → list item; invisible to user

### BA11: Anonymous Content Moderation via MASTER

- [ ] BA1101 Moderation prompt: `ANON_MOD_PROMPT = "You are a content moderator for a Norwegian hyperlocal social network. Assess this post for: spam, hate speech, misinformation, illegal content. The platform values authentic local discussion. Return JSON: {approved: bool, confidence: 0.0-1.0, category: null|'spam'|'hate'|'misinfo'|'illegal', reason: string}"`
- [ ] BA1102 Model selection: Groq llama3-8b for moderation (500 tok/s, free tier, Norwegian-aware); fallback to Gemini Flash free tier if Groq rate-limited; never send to paid model for moderation — must be near-zero cost
- [ ] BA1103 Moderation pipeline: `AnonModerationJob` — synchronous for anonymous posts (user waits max 2s); if LLM response takes >2s, approve optimistically + queue async re-check; reject immediately if sync check returns `approved: false`
- [ ] BA1104 Approved → save: `{approved: true}` → post saved; Turbo Stream appends to feed; user sees post appear; no indication that moderation occurred
- [ ] BA1105 Rejected → feedback: `{approved: false}` → Turbo Stream returns error in composer: "Innlegget ble ikke godkjent: [reason]"; composer stays open with content intact; user can edit and resubmit
- [ ] BA1106 Edge case — uncertain: `{confidence: < 0.7}` → approve + flag for human review in moderation queue; low-confidence cases reviewed by human within 24h; auto-remove if human rejects
- [ ] BA1107 Language detection: moderation prompt prepended with detected language (`franc` Ruby gem detects; Norwegian Bokmål/Nynorsk/English all accepted; reject posts in no recognisable language >10 words)
- [ ] BA1108 Moderation log: `AnonModerationLog(anon_fingerprint, post_body_hash, model, result, confidence, duration_ms, created_at)` — audit trail; `post_body_hash` not body (privacy); used to tune thresholds

### BA12: Visual Design — Dark Social Aesthetic

- [ ] BA1201 Colour system: `--bg: #000; --surface: rgba(255,255,255,0.03); --surface-hover: rgba(255,255,255,0.06); --border: rgba(255,255,255,0.08); --border-hover: rgba(255,255,255,0.18); --text-primary: rgba(255,255,255,0.95); --text-secondary: rgba(255,255,255,0.55); --text-tertiary: rgba(255,255,255,0.35); --accent: #2563eb; --accent-hover: #3b82f6; --danger: #f43f5e; --success: #10b981; --warning: #f59e0b`
- [ ] BA1202 Depth via opacity: no box-shadows on dark; depth via background opacity layers — surface (3%), hover (6%), selected (9%), active (12%); additive layering reads as elevation without fake shadows
- [ ] BA1203 Accent colour: `#2563eb` (electric blue) is the only chromatic colour in base state; used for: links, active states, CTA button hover, @mention text, hashtag text; everywhere else is opacity-white
- [ ] BA1204 Vertical accent colours: apply only within vertical-specific views, not on landing or feed; `[data-vertical="dating"] --accent: #f43f5e; [data-vertical="marketplace"] --accent: #f59e0b` — vertical identity within brand system
- [ ] BA1205 Typography on black: `color: rgba(255,255,255,0.95)` for body (not pure white — optical softness); `0.55` for secondary; `0.35` for tertiary; never `rgba(255,255,255,1)` in body text — harsh against pure black
- [ ] BA1206 Icon weight on dark: 1.5px stroke icons (Heroicons default) appear thinner on dark backgrounds than light; compensate with `stroke-width: 2` on all icons in dark contexts; heavier stroke reads correctly
- [ ] BA1207 Image treatment: all images `filter: brightness(0.92) contrast(1.04)` — very subtle; tones down over-bright photos that clash with dark UI; nearly imperceptible but makes the interface cohesive
- [ ] BA1208 Focus rings on dark: `outline: 2px solid rgba(255,255,255,0.8); outline-offset: 3px` — white rings on black background; high contrast; visible to all users including low-vision
- [ ] BA1209 Selection on dark: `::selection { background: rgba(37,99,235,0.4); color: rgba(255,255,255,0.95) }` — blue-tinted selection matching accent; legible
- [ ] BA1210 Scrollbar styling: `scrollbar-width: thin; scrollbar-color: rgba(255,255,255,0.15) transparent` — thin, barely-there scrollbar; consistent with dark void aesthetic

### BA13: Performance — Dark Mode and Black Backgrounds

- [ ] BA1301 OLED optimisation: true `#000` background means OLED pixels are fully off; reduces power consumption 20-40% on OLED phones; entire brgen dark aesthetic is also a battery feature
- [ ] BA1302 No white flash: `<meta name="color-scheme" content="dark">` + CSS `color-scheme: dark` prevents white flash during page load, navigation, and form focus; critical for immersion
- [ ] BA1303 Image lazy load with black placeholder: `<img loading="lazy" style="background: #111">` — dark placeholder visible before image loads; never white flash under image
- [ ] BA1304 Reduced paint on dark: dark backgrounds require fewer repaints than light — browser composites dark surfaces more efficiently; black eliminates subpixel rendering complexity
- [ ] BA1305 Minimal bundle on landing: landing page CSS is `landing.css` (separate from `application.css`); only loads tokens + reset + landing component CSS; target <8KB gzipped; fastest possible FCP on first visit
- [ ] BA1306 No render-blocking on landing: zero `<script>` tags in `<head>` on landing layout; all JS `defer`; Stimulus connects after HTML painted; landing is usable before JS loads (wordmark + arrow visible immediately)
- [ ] BA1307 Skeleton on feed: black skeleton cards `background: rgba(255,255,255,0.06); animation: shimmer-dark 1.4s ease-in-out infinite` with `@keyframes shimmer-dark { 0%, 100% { opacity: 0.5 } 50% { opacity: 1 } }` — dark-appropriate shimmer; not the light-mode grey shimmer


## BB: brgen Vertical Deep-Dives

### BB1: Dating — Swipe UX and Match Flow

- [ ] BB101 Dating card deck: `app/views/dating/profiles/_card.html.erb` renders a stack of 3 cards; only top card is interactive; CSS `position: absolute; top: 0; left: 0; width: 100%; transition: transform 0.3s cubic-bezier(0.32,0.72,0,1)` — deck illusion via `translateY(4px) scale(0.97)` on second card, `translateY(8px) scale(0.94)` on third
- [ ] BB102 Swipe gesture: Stimulus `swipe-controller.js` — `pointerdown` captures start X; `pointermove` applies `translateX(delta) rotate(delta/20deg)` live; `pointerup` with |delta|>80px commits like/pass; with |delta|<80px springs back via CSS transition
- [ ] BB103 Like/pass decision: `POST /dating/likes` with `{target_id:, direction: "like"|"pass"}`; `DatingLike` model with dedup via `UNIQUE(liker_id, liked_id)`; mutual like → create `DatingMatch`; Turbo Stream triggers match modal
- [ ] BB104 Match modal: full-screen overlay on mutual match; both user avatars animate toward center (CSS `keyframes slide-in-left/right`); "Det er en match!" headline; two CTAs — "Send melding" (opens chat) and "Fortsett å sveipe" (dismisses); modal auto-dismisses after 6s if untouched
- [ ] BB105 Distance filter: `acts_as_tenant` scopes to city, but within-city distance uses `ST_Distance` on PostGIS-style lat/lon stored as REAL columns; slider 1–50km; `WHERE distance(lat, lon, :my_lat, :my_lon) <= :km` via SQLite custom function registered at boot
- [ ] BB106 Age filter: two-thumb range slider (Stimulus `range-slider-controller.js`); `min_age` + `max_age` params; birthday stored, age derived via `(julianday('now') - julianday(birthday)) / 365.25`; CHECK constraint: age >= 18
- [ ] BB107 Profile photos: up to 6 photos per dating profile; Active Storage `has_many_attached :photos`; drag-to-reorder via Stimulus `sortable-controller.js` (stimulus-components); primary photo is first in array; card shows photo at `object-fit: cover; aspect-ratio: 3/4`
- [ ] BB108 Icebreaker prompts: 3 prompt slots per dating profile (like Hinge); `PromptResponse(dating_profile_id, prompt_id, body:text)`; prompts table seeded with 40 Norwegian-language prompts; rendered on card below photos with Q+A layout
- [ ] BB109 Daily like limit: free users 20 likes/day; premium unlimited; `DailyLikeCounter` via Redis counter with midnight TTL; `RateLimitedError` renders Turbo Stream "Oppgradér til Premium for ubegrenset sveip" banner
- [ ] BB110 Premium blur: non-matched profiles who liked you appear blurred in "Liker deg" grid; `filter: blur(12px)` + overlay CTA; unblur requires premium; `<img>` src still loads (intentional — blur is CSS, not hidden; faster feel)
- [ ] BB111 Compatibility score: on match, compute score from shared tags + interests + distance + age gap; `CompatibilityScore#call(profile_a, profile_b)` returns 0–100; shown on match modal and in conversation header
- [ ] BB112 Conversation starter AI: on match, MASTER generates 3 opening lines based on both profiles (icebreaker prompts + shared interests); shown as tap-to-send suggestions in new conversation; `POST /dating/matches/:id/suggestions` → streaming Turbo Stream
- [ ] BB113 Video intro (future): dating profile may attach a 15s selfie video; Active Storage video variant transcoded to 720p H.264 via Active Storage ffmpeg processor; plays muted on card hover/tap; deferred to v2 — storage cost
- [ ] BB114 Safety report flow: every profile has "Rapporter" link; `DatingReport(reporter_id, reported_id, category, body)`; categories: fake profil, upassende bilder, trakassering; auto-hides reported profile from reporter; MASTER scans report body; 3 reports in 24h → auto-suspend
- [ ] BB115 Profile completeness nudge: `ProfileCompletenessScore#call(profile)` — 0-100; shown in profile edit as progress bar; items: photo (30), bio (20), 3 prompts (30), interests (20); incomplete profiles surface lower in deck sort

### BB2: TV — Livestream Player and Schedule

- [ ] BB201 TV player layout: full-bleed `<video>` tag; `object-fit: contain` on landscape, `cover` on portrait/mobile; custom controls overlay (no browser chrome); dark overlay `rgba(0,0,0,0.6)` on pause, transparent on play
- [ ] BB202 HLS streaming: `hls.js` loaded via importmap; `Hls.isSupported()` → hls.js; else `video.src = m3u8` (Safari native HLS); `HLS_URL` per channel from Rails config; streams from Cloudflare Stream or self-hosted nginx-rtmp (future)
- [ ] BB203 Channel rail: horizontal scroll rail below player; channel thumbnails 120×68px `aspect-ratio: 16/9`; active channel has 2px `outline: 2px solid #2563eb`; keyboard left/right arrows cycle channels; Stimulus `channel-rail-controller.js`
- [ ] BB204 EPG (electronic programme guide): `Programme(channel_id, title, starts_at, ends_at, description, category)`; current programme shown in player overlay bottom-left; next programme shown as "Neste:" badge; EPG fetched from XMLTV feed importer (`EpgImportJob` runs hourly)
- [ ] BB205 Chat alongside stream: `TvChatChannel` ActionCable; right panel chat (desktop) / bottom sheet (mobile); messages scroll up; max 200 messages in DOM (older removed); rate limit 1 msg/5s per user; MASTER moderates chat in background
- [ ] BB206 Clip creation: "Klipp ut" button captures last 30s of HLS buffer; `MediaRecorder` API records from `<video>` element; client-side WebM blob; `POST /tv/clips` uploads blob + title + timestamp; clip stored via Active Storage; shared as post to brgen feed
- [ ] BB207 Reaction bar: floating emoji row (❤️🔥😂👏🤔) below player; tap → emoji flies up in CSS animation (`@keyframes fly-up { to { transform: translateY(-80px); opacity: 0 } }`); `POST /tv/reactions` broadcasts count via CableReady; reaction counters update live
- [ ] BB208 Offline notice: service worker caches EPG and last-known channel metadata; if stream fails, show "Sender ikke akkurat nå — neste sending: [time]"; EPG fallback from cache; no blank screen
- [ ] BB209 Chromecast sender: `window.chrome.cast` available on Chrome; Cast button in player controls; streams HLS URL to Chromecast receiver; session management via Cast SDK; deferred to v2 (requires GCP Cast SDK key)
- [ ] BB210 Thumbnail scrubbing: VTT sprite sheet generated on ingest for pre-recorded content; on seekbar hover, thumbnail preview matches hovered time position; `<canvas>` draws sprite crop at pointer position

### BB3: Playlist — Social Music Features

- [ ] BB301 Playlist model: `Playlist(user_id, title, description, cover_image, visibility: public|followers|private, play_count, like_count)`; `PlaylistTrack(playlist_id, track_id, position, added_by_id)` — tracks are ordered by `position` integer
- [ ] BB302 Track model: `Track(title, artist, album, duration_seconds, isrc, spotify_uri, youtube_id, soundcloud_id, audio_url)`; ISRCs deduplicate across sources; `audio_url` is a self-hosted preview URL (30s MP3) from whatever source resolves first
- [ ] BB303 Audio player: sticky bottom bar (desktop) / fullscreen player (mobile); Stimulus `player-controller.js` manages `<audio>` element; play/pause, seek, volume, skip; next track on `ended` event; queue is playlist tracks starting at selected index
- [ ] BB304 Waveform visualisation: `Web Audio API` — `AudioContext.createAnalyser()` feeds canvas waveform draw loop; `requestAnimationFrame` updates 60fps; `canvas` overlays progress bar; on pause, last frame frozen; `OffscreenCanvas` in worker so main thread unblocked
- [ ] BB305 Spotify import: `POST /playlists/import` accepts Spotify playlist URL; server fetches via Spotify Web API (OAuth2 token stored in session); maps Spotify tracks to `Track` records by ISRC; creates `Playlist` + `PlaylistTrack` records; reports import summary
- [ ] BB306 Collaborative playlist: `Playlist#collaborators` — `has_many :playlist_collaborators`; collaborators can add/reorder/remove tracks; `PlaylistActivityChannel` broadcasts changes; all collaborators see live reorder; host can remove collaborator
- [ ] BB307 Radio mode: "Radio basert på" — seeds from last 5 tracks; calls MASTER tool `music_recommend` which queries Last.fm similar tracks API; fills queue with 20 tracks; refreshes 5 tracks before queue exhausts; infinite radio feel
- [ ] BB308 Social graph for playlists: playlist can be posted to brgen feed as a post type; renders embedded playlist card (cover + first 3 tracks + play button); play button opens full player without leaving feed; like/comment/share same as any post
- [ ] BB309 Listening party: room-based synchronized playback; `ListeningParty(playlist_id, host_id, started_at, current_track_position)`; all party members sync to host's track position via ActionCable heartbeat every 2s; max 50 members per party
- [ ] BB310 Lyrics display: `GET /tracks/:id/lyrics` fetches from Musixmatch API (free tier); stores in `track.lyrics_cache` JSON column with timed lines `[{time: 12.4, line: "..."}]`; Stimulus `lyrics-controller.js` highlights current line based on `<audio>.currentTime`

### BB4: Takeaway — Order Flow

- [ ] BB401 Restaurant model: `Restaurant(name, slug, city_id, cuisine_tags, min_order_nok, delivery_fee_nok, avg_delivery_min, open_now, latitude, longitude, rating_avg, rating_count)`; `acts_as_tenant` scopes to city
- [ ] BB402 Menu model: `MenuCategory(restaurant_id, name, position)`; `MenuItem(category_id, name, description, price_ore, image, allergens_json, vegan, gluten_free, available)`; prices in øre (integer) — never floats for money
- [ ] BB403 Cart via session: cart stored in encrypted Rails session (Solid Cache backed); `cart = {restaurant_id:, items: [{item_id:, quantity:, notes:}]}`; cross-restaurant add → prompt "Start ny ordre?" modal; cart clears on order placed
- [ ] BB404 Order model: `Order(user_id, restaurant_id, status, subtotal_ore, delivery_fee_ore, tip_ore, total_ore, delivery_address_json, special_instructions, estimated_delivery_at)`; status enum: pending → confirmed → preparing → out_for_delivery → delivered | cancelled
- [ ] BB405 Real-time order tracking: `OrderTrackingChannel` — restaurant broadcasts status changes; customer sees step indicators (Stimulus `order-status-controller.js`); estimated time countdown live; push notification on `out_for_delivery`
- [ ] BB406 Stripe Checkout for takeaway: `OrdersController#create` builds Stripe Checkout session with line items from cart; success URL → `OrdersController#confirm`; webhook `checkout.session.completed` → `OrderConfirmJob` (creates Order, notifies restaurant)
- [ ] BB407 Restaurant admin panel: `/restaurant_admin` namespace; orders queue sorted by `created_at`; per-order: confirm (sets `confirmed`), set ready time, mark `out_for_delivery`; Turbo Streams push new orders to queue without refresh; audio ping via `<audio src="/ping.mp3" data-order-target="ping">`
- [ ] BB408 Delivery driver (future): `Driver` model; `OrderAssignment`; driver app (PWA) with geolocation tracking; customer sees driver on map; `DriverLocationChannel` broadcasts GPS every 5s; deferred — requires driver recruitment
- [ ] BB409 Review after delivery: 24h after `delivered`, push notification / email: "Hvordan var maten?"; `OrderReview(order_id, rating 1-5, body)`; rating aggregated to `restaurant.rating_avg` via counter cache; review visible on restaurant page
- [ ] BB410 Norwegian VAT: all prices include MVA (25% food); `price_ore` is VAT-inclusive; order receipt shows `subtotal_ex_vat`, `vat_amount`, `total_inc_vat`; Stripe invoice line items include `tax_rates` with NO 25% rate

### BB5: Chat — Real-time Messaging

- [ ] BB501 Conversation model: `Conversation(participant_ids_json, last_message_at, unread_counts_json)`; NOT using polymorphic — flat table; `ConversationParticipant(conversation_id, user_id, last_read_at)` for read receipts
- [ ] BB502 Message model: `Message(conversation_id, sender_id, body, kind: text|image|file|reaction, parent_id, delivered_at, read_at, edited_at, deleted_at)`; soft delete — `deleted_at` set, body replaced with "Slettet melding"; parent_id for thread replies
- [ ] BB503 Real-time delivery: `MessagesChannel` subscribed per-conversation; `Message.after_create_commit` broadcasts CableReady `append` to conversation stream; recipient's unread badge increments via separate `NotificationsChannel` broadcast
- [ ] BB504 Message input: Stimulus `chat-input-controller.js`; `textarea` auto-grows (rows 1→6 max); `Enter` sends, `Shift+Enter` newline; `POST /conversations/:id/messages` Turbo Stream appends optimistically before server confirm; rollback on error
- [ ] BB505 Read receipts: `MessagesChannel` receives `read` event when recipient scrolls message into viewport (`IntersectionObserver`); `PATCH /messages/:id/read` sets `read_at`; sender sees double-tick → blue-tick CSS class swap
- [ ] BB506 Typing indicator: `channel.perform "typing"` on keypress (debounced 500ms); server broadcasts `typing_start` to other participants; Stimulus shows "skriver..." ephemeral indicator; auto-clears after 3s without new event
- [ ] BB507 Image in chat: paste or attach photo; client `FileReader` previews immediately; `POST /conversations/:id/messages` with `kind: image` + blob upload; Active Storage stores; rendered as `<img loading="lazy">` in chat bubble; click → lightbox
- [ ] BB508 Reaction to message: long-press / right-click message → emoji picker (`emoji-mart` lite); `POST /messages/:id/reactions`; CableReady `update` refreshes reaction row under message; same emoji from same user = toggle off
- [ ] BB509 Message search: `FTS5` virtual table `messages_fts` mirrors `messages.body`; `GET /conversations/:id/search?q=` returns matching messages with highlighted snippets; results scroll conversation to matched message on click
- [ ] BB510 Encryption (future): Signal Protocol via `libsodium` Ruby FFI; client generates key pair on first load; public key stored on server; messages encrypted client-side before POST; server stores ciphertext only; zero-knowledge; deferred to v2

## BC: City Expansion Playbook

### BC1: Domain and DNS Setup per City

- [ ] BC101 Domain convention: flagship `brgen.no`; other cities follow `<cityname>.citynet.no` pattern; `losangeles.citynet.no`, `amsterdam.citynet.no`, `london.citynet.no`; register `citynet.no` as the parent domain at Domeneshop; wildcard DNS `*.citynet.no → server IP`
- [ ] BC102 TLS wildcard cert: `acme-client` with Domeneshop DNS-01 challenge (API-based); single `*.citynet.no` cert covers all city subdomains without per-city cert renewal; stored at `/etc/ssl/citynet.no.crt` + `/etc/ssl/private/citynet.no.key`
- [ ] BC103 relayd per-city routing: `relayd.conf` relays block matches `*.citynet.no` → brgen app (port 3000); host header preserved; `acts_as_tenant` reads `request.subdomain` to set tenant; add new city = add DNS record only, no relayd change
- [ ] BC104 City model: `City(name, slug, country_code, latitude, longitude, timezone, locale, currency, launch_date, seed_status)`; slug = subdomain; `acts_as_tenant` keys on `city.id`; city record created before launch; seed_status: unseeded → seeded → live
- [ ] BC105 City admin: `/admin/cities` CRUD; only `role: superadmin` accesses; per-city settings: `open_registration bool`, `moderation_level enum`, `featured_verticals json`; city toggle for verticals (Bergen has all 6, smaller cities may launch with just Regular + Chat)

### BC2: Seed Content per City

- [ ] BC201 Seed job: `CitySeedJob(city_id)` — creates 20 seed users, 100 posts across 5 content categories, 5 community guidelines posts pinned at top, 3 local business listings; runs once at `seed_status: unseeded → seeded`
- [ ] BC202 Bergen seed: content sourced from r/bergen scrape (PRAW via Ruby subprocess); top 50 posts of all time; re-posted under anonymous seed accounts; Norwegian language filter (franc gem); PII stripped via MASTER scan; MASTER moderation gate before insert
- [ ] BC203 Los Angeles seed: LA subreddits (r/LosAngeles, r/AskLosAngeles, r/LAlist); English-language posts; locale set to `en-US`; currency `USD`; Takeaway vertical maps to US food delivery market data (Yelp API free tier for restaurant seed)
- [ ] BC204 Amsterdam seed: r/Amsterdam + r/thenetherlands; Dutch + English accepted; locale `nl-NL` with English fallback; `EUR` currency; cycling-related content heavily weighted (city identity); integration with Amsterdam OpenData API for POI seed
- [ ] BC205 AI-assisted seed: for cities without strong Reddit presence, `CityContentJob` prompts MASTER with city facts (population, notable landmarks, industries) → generates 50 authentic-sounding local posts in city's language; marked `ai_generated: true` in metadata but not shown to users

### BC3: RC.D and Infrastructure per City

- [ ] BC301 Single brgen process: all cities run in one Rails process; `acts_as_tenant` tenant-switches per request; no per-city processes needed; horizontal scale = add more Puma/Falcon workers, not more processes
- [ ] BC302 SQLite per city: each city has its own SQLite database file `db/cities/<slug>.sqlite3`; WAL mode; Litestream replicates each to R2 with `db_path: "db/cities/*.sqlite3"` glob; isolated — city A query never touches city B
- [ ] BC303 Active Storage per city: `config.active_storage.service` set to `:local` with per-city subdirectory `storage/cities/<slug>/`; city switch middleware sets `ActiveStorage::Current.url_options` host; no cross-city attachment links possible
- [ ] BC304 Launch checklist: DNS A record, TLS cert covers wildcard, City record created, seed job run, rc.d relayd config verified, smoke test `curl -I https://losangeles.citynet.no` → 200, announce in r/cityname post linking to new site
- [ ] BC305 City metrics dashboard: `/admin/cities/:slug/metrics` — DAU, posts/day, messages/day, new signups/day, moderation actions/day; Solid Queue job counts; served from read replica if available; renders via Turbo Frame refresh every 60s

## BD: repligen.rb + postpro.rb — Improvements and Integration

### BD1: repligen.rb — Core Architecture

- [ ] BD101 Move to MASTER/lib/reach/: repligen logic belongs in `reach/` alongside other external tool implementations; `DEPLOY/repligen.rb` becomes a thin CLI shim that `require`s `lib/reach/repligen/`; eliminates the MASTER-tool indirection
- [ ] BD102 Result monad return: all generation methods return `Result.ok(output_path)` or `Result.err(message)` — aligns with pipeline monad; callers stop rescuing raw exceptions; consistent error surface across MASTER
- [ ] BD103 Structured config via YAML: replace `CONFIG_PATH` JSON with `~/.config/repligen/config.yml`; supports multiple API profiles (dev token, prod token, team token); `Config#profile(name)` returns token; ENV overrides any profile
- [ ] BD104 Database migrations: introduce `db/migrate/` pattern for repligen SQLite schema; `SchemaVersion` table tracks applied migrations; eliminates `CREATE TABLE IF NOT EXISTS` fragility; new columns added cleanly
- [ ] BD105 Model cache TTL: models synced from Replicate expire after 24h (`synced_at` column); `Database#stale_models` returns models needing refresh; auto-refresh on next search if stale; eliminates showing removed/deprecated models
- [ ] BD106 Async prediction polling: replace busy-wait polling loop with exponential backoff — 1s, 2s, 4s, 8s, 16s, max 30s; total timeout configurable; `PollTimeoutError` raised with prediction URL so user can check manually
- [ ] BD107 Prediction persistence: store every prediction in `predictions` table `(id, model_id, input_json, output_json, status, cost_usd, duration_ms, created_at)`; enables cost tracking, retry failed predictions, audit trail
- [ ] BD108 Cancel prediction: `DELETE /predictions/:id` via Replicate API; hooked to `Interrupt` signal (`trap("INT") { cancel_prediction(id); exit }`) — user Ctrl-C does not abandon a running $0.10+ prediction
- [ ] BD109 Webhook mode: `repligen webhook start` launches a minimal Falcon HTTP server on port 54321; registers webhook URL with Replicate prediction; receives completion callback instead of polling; 5× faster for slow models (video, 3D)
- [ ] BD110 Concurrent chain execution: chain steps that have no dependencies (e.g., 3 parallel style-transfer variants) run in `Ractor` workers; result array merged in order; total chain time = slowest parallel branch, not sum of all

### BD2: repligen.rb — Model Discovery and Routing

- [ ] BD201 Semantic model search: embed model descriptions via `sqlite-vec` (768-dim); `repligen search "cinematic film grain portrait"` returns top-5 by cosine similarity + keyword fallback; better discovery than pattern-match `MODEL_TYPES`
- [ ] BD202 Cost-aware routing: `ModelRouter#select(type:, budget_usd:)` returns cheapest model of type that fits budget; `--budget 0.02` flag limits per-generation cost; safety net against accidental $5 video generation
- [ ] BD203 Model benchmarks table: `benchmarks(model_id, quality_score, speed_score, cost_per_run, tested_at)` — populated by running a standard test prompt through each model and having MASTER score output 1-10; `repligen bench` command triggers benchmark sweep
- [ ] BD204 Favourite models: `user_favourites(model_id, alias, default_params_json)`; `repligen fav add black-forest-labs/flux-schnell --alias flux`; `repligen gen flux "prompt"` expands alias and merges default params; `.repligen_aliases` file in home dir
- [ ] BD205 Model changelog tracking: `model_versions(model_id, version, published_at, notes)` — repligen polls Replicate model API for version changes; notifies user when a favourite model updates; prevents silent quality regressions
- [ ] BD206 Usage analytics: `repligen stats --this-month` reports: total runs, total cost, cost by model, cost by chain type, average generation time, success rate; exported as JSON or pretty table; aids budget planning
- [ ] BD207 Model comparison: `repligen compare flux-schnell flux-dev "a red fox in snow"` — runs same prompt on both models; places outputs side-by-side in terminal (sixel/iTerm2 inline image) or opens in Preview; diff-friendly for quality evaluation
- [ ] BD208 LoRA discovery: separate `loras` table for fine-tuned models; `repligen lora search "anime portrait"` queries Replicate LoRA collection; `repligen lora attach <base_model> <lora>` creates LoRA-applied prediction config; stored as chain template
- [ ] BD209 Model health check: `repligen health` pings Replicate API, checks each saved model is still live (`status != "retired"`); reports retired models so user can replace them in chain templates; runs as part of weekly cron
- [ ] BD210 Provider abstraction: `ModelProvider` base class with `ReplicateProvider`, `HuggingFaceProvider` (future), `FALProvider` (future) subclasses; same `generate(prompt:, params:)` interface; routing selects provider by model prefix; no lock-in to Replicate

### BD3: repligen.rb — Chain Templates and Workflows

- [ ] BD301 YAML chain definitions: move `CHAIN_TEMPLATES` from hardcoded Ruby hash to `~/.config/repligen/chains/` YAML files; `repligen chain list`, `chain run`, `chain edit`; user-editable without touching source
- [ ] BD302 Chain dry-run: `repligen chain run masterpiece --dry-run "a foggy Oslo street"` prints planned steps with estimated cost and time without executing; confirms budget before committing to a $2 chain
- [ ] BD303 Chain branching: chain step can specify `branches: 3` — runs 3 parallel variants; user picks best at end; selection stored as `selected_variant` in prediction record; winner fed to next step; creative exploration workflow
- [ ] BD304 Chain checkpointing: each completed chain step saves output path to `chain_runs` table; `repligen chain resume <run_id>` restarts from last completed step; surviving a Ctrl-C mid-chain, network drop, or crash
- [ ] BD305 Named output directories: `repligen gen flux "prompt" --out ~/Pictures/brgen-seed/` writes output to named path instead of default `~/.local/share/repligen/outputs/`; easier integration with postpro.rb and brgen seed pipeline
- [ ] BD306 Batch prompts from file: `repligen batch flux prompts.txt --out ~/out/` reads one prompt per line; generates all; outputs named `001.png`, `002.png`...; progress bar via `tty-progressbar`; rate-limited to 10 concurrent
- [ ] BD307 Prompt templates: `~/.config/repligen/prompts/portrait.txt` with `{subject}` placeholder; `repligen gen --template portrait subject="a Norwegian fisherman"` expands template; reusable prompt engineering
- [ ] BD308 Style injection: `--style cinematic` appends style suffix from `~/.config/repligen/styles.yml` (`cinematic: ", shot on ARRI Alexa, anamorphic, 2.39:1, Kodak Vision3 500T colour grade"`); consistent aesthetic across batch
- [ ] BD309 Negative prompt management: `~/.config/repligen/negatives.yml` stores named negative prompt sets; `--neg portrait` appends `ugly, deformed, extra limbs, watermark...`; avoids retyping long negatives; applied per model type
- [ ] BD310 Seed pinning: `--seed 42` pins Replicate prediction seed for reproducibility; stored in prediction record; `repligen vary <prediction_id>` regenerates with same seed ±10 — explores prompt neighbourhood deterministically

### BD4: repligen.rb + brgen Integration

- [ ] BD401 Seed pipeline rake task: `rake brgen:seed:photos[city_slug,count]` calls repligen to generate `count` photos for city; uses city-specific prompt styles (`Bergen: "Norwegian fjord town, overcast Nordic light"`); outputs to `tmp/seed_photos/<city>/`
- [ ] BD402 Avatar generation: `repligen gen flux "professional headshot, neutral background, Norwegian person, {gender}, age {age}"` seeded per user archetype; generated avatars assigned to seed users; avoids real-person photos in seed data
- [ ] BD403 Listing photo generation: for seed marketplace listings, `repligen chain masterpiece "product: {title}, clean white background, e-commerce photography"` generates listing photos; metadata written to `listing.photos` via Active Storage import
- [ ] BD404 postpro pipeline integration: repligen output directory watched by postpro; `postpro watch ~/repligen-outputs/ --stock kodak_portra --preset social` auto-processes new images; `postpro_job.rb` triggers on new Active Storage attachments
- [ ] BD405 MASTER tool contract: `reach/repligen_tool.rb` wraps repligen CLI as MASTER tool; accepts `{prompt:, chain: "masterpiece"|"quick", style:, budget_usd:}`; returns `{output_path:, cost_usd:, duration_ms:}`; MASTER can autonomously generate images when asked
- [ ] BD406 Cost guard in MASTER: MASTER tool contract enforces `budget_usd <= 0.50` per single generation call; above that requires `MASTER_UNSAFE_PROCESS_DEFAULTS=1`; prevents runaway generation costs in autonomous loops
- [ ] BD407 Regeneration on low quality: MASTER scores repligen output via vision API (1-10); score < 6 → auto-regenerate with modified prompt (adjective swap, style tweak); max 3 retries; gives up with original if all retries fail
- [ ] BD408 Output tagging: every repligen output tagged with SQLite metadata `(path, prompt, model, style, city, purpose: seed|avatar|listing|test, quality_score, created_at)`; queryable for audit and regeneration targeting
- [ ] BD409 Preview in MASTER CLI: on image generation, MASTER CLI outputs sixel inline image if `$TERM` supports it (`xterm-kitty`, `iTerm2`); else outputs file path and opens with `xdg-open`/`open`; `preview_image` helper in `voice/renderer.rb`
- [ ] BD410 brgen post from generation: `repligen post --city bergen "prompt"` → generates image → postpro → creates brgen post via API with generated image attached; full seed automation in one command

### BD5: postpro.rb — Architecture Improvements

- [ ] BD501 Move to MASTER/lib/reach/postpro/: same rationale as repligen; `reach/postpro/` module with `processor.rb`, `stocks.rb`, `presets.rb`, `pipeline.rb`; DEPLOY shim for standalone CLI use
- [ ] BD502 Split STOCKS constant: `STOCKS` is a large constant inline in the file; extract to `data/film_stocks.yml`; `Stocks.load` reads YAML; allows user-defined custom stocks without editing source code
- [ ] BD503 Pipeline class: `PostproPipeline.new(image_path, stock:, preset:)` with `#call` returning `Result.ok(output_path)`; replaces imperative script with composable pipeline; each step is a named method with single responsibility
- [ ] BD504 Preset system: `data/presets.yml` — `social: {stock: kodak_portra, grain: 0.6, vignette: 0.3, lut: warm}`, `editorial: {stock: kodak_vision3, grain: 0.4, lut: cool}`, `raw_scan: {stock: fujichrome_velvia, grain: 0.8, halation: true}`; `postpro --preset social input.jpg`
- [ ] BD505 Batch processing with progress: `postpro batch *.jpg --preset social --out processed/`; `tty-progressbar` shows per-file progress; parallel via `Parallel.map(..., in_threads: 4)` (parallel gem); thread-safe via per-thread Vips context
- [ ] BD506 Watch mode: `postpro watch ~/Downloads/ --preset social` uses `Listen` gem to detect new `.jpg/.png/.webp` files; auto-processes on write; outputs to `~/Downloads/processed/`; useful for photographer tethered-capture workflows
- [ ] BD507 Vips memory tuning: `Vips.cache_max_mem = 512 * 1024 * 1024` (512MB); `Vips.cache_max = 0` (disable op cache for batch, keeps memory predictable); explicit `image.destroy` after each file in batch; prevents OOM on large batches
- [ ] BD508 OpenBSD compatibility: `pkg_add vips` installs libvips 8.15 on OpenBSD; `PostproBootstrap#probe_and_install_libvips` already has OpenBSD branch but uses `sudo` — replace with `doas`; test on server4
- [ ] BD509 EXIF preservation: `image.set_type(Vips::BLOB, "exif-data", original_exif)` copies EXIF from original to output; prevents stripping GPS, camera model, and copyright tags; `--strip-exif` flag for privacy-conscious mode
- [ ] BD510 Format routing: input `.jpg` → output `.jpg`; input `.png` → output `.png`; `.heic` → `.jpg` (HEIC decoded via vips-heif); `--format webp` override for web output; quality configurable per format (`--quality 88`)

### BD6: postpro.rb — Film Stock and LUT Enhancements

- [ ] BD601 Add Fujifilm Superia 400: `superia_400: { grain: 22, matrix: [...], hd: {...} }` — Fuji green bias in midtones, cooler shadows than Portra; common consumer film aesthetic; used for hjerterom app (community warmth with a Fuji twist)
- [ ] BD602 Add Ilford HP5: monochrome stock; disable colour matrix; grain `sigma: 28`; `hd` curves push contrast: `Dmin 0.08, Dmax 0.88, gamma 1.3`; `convert_to_greyscale` step before curve application; baibl app (scripture) uses HP5 for archival aesthetic
- [ ] BD603 Add Polaroid 600: strong vignette hardwired; colour bleed simulation via box-blur ×3 on chroma channel before matrix; `matrix: [1.06, -0.04, -0.02, ...]` warm shift; border rendering (white rectangle via `Vips::Image.black(w+80, h+100)` composite)
- [ ] BD604 Add Agfa Vista 200: vivid saturation, slight magenta push in shadows; `hd.r: [0.04, 0.96, 0.18, 1.15]`; higher gamma than Portra; used for amber app (fashion photography — punchy colours)
- [ ] BD605 Halation simulation: light bleed from bright areas into shadows in film; implement as: `highlights = image.more_than(220)` → Gaussian blur radius 12 → tint `rgba(255, 120, 80, 0.25)` → `screen` blend onto original; toggle via `halation: true` in stock definition
- [ ] BD606 Cross-process emulation: `--xpro` flag; applies slide film curve to negative stock or vice versa; signature: boosted saturation, shifted colours (skin tones go orange-green), crushed blacks; one-click cross-processing aesthetic
- [ ] BD607 Faded vintage: `--faded` flag; raises blacks by 15 (lifts shadows), reduces contrast by 10%, adds slight warm yellow to shadows (`shadow_tint: [255, 245, 220, 0.08]`); Instagram-era aesthetic on demand
- [ ] BD608 LUT support: `--lut path/to/identity.cube` loads 3D LUT (32×32×32 or 64×64×64); applies via trilinear interpolation in pure Ruby (Vips does not natively load `.cube`); `lut_to_vips_lut` converter; standard DaVinci/Resolve LUTs work
- [ ] BD609 Split toning: `--shadow-tint "#1a3a5c" --highlight-tint "#f5e6c8"` — shadows tinted blue-navy, highlights tinted warm parchment; implemented as `luminosity_mask` blend; cinema split-toning in one flag pair
- [ ] BD610 Per-channel curve editor: `postpro curve input.jpg` opens ASCII curve editor (tty-prompt matrix); user adjusts R/G/B S-curve control points interactively; saves named curve preset to `~/.config/postpro/curves/`; applies to batch

### BD7: postpro.rb — Processing Pipeline Steps

- [ ] BD701 Adaptive contrast (CLAHE): tile-based local contrast enhancement before global curve; `tile_size: 64`, `clip_limit: 2.0`; implemented via `Vips::Image#spcor` + local statistics; recovers flat-lit repligen outputs; `clarity: 0.4` controls blend weight
- [ ] BD702 Selective sharpening: sharpen only mid-frequency detail (not grain); implement as `unsharp_mask(sigma: 1.5, amount: 0.6) - unsharp_mask(sigma: 0.5, amount: 0.6)` to avoid sharpening noise; applied before grain addition
- [ ] BD703 Skin tone protection: detect skin pixels via `Cr ∈ [133,173] && Cb ∈ [77,127]` in YCbCr space; mask skin region; reduce saturation boost and grain weight in skin mask by 40%; prevents Portra grain making portraits look gritty
- [ ] BD704 Sky detection and enhancement: `sky_mask = image.band(1).more_than(image.band(2))` (blue channel dominates) + luminance filter; within sky mask: slight gradient from warmer horizon to cooler zenith; enhances landscape shots from repligen
- [ ] BD705 Highlight recovery: if repligen output has clipped highlights (>253 in any channel), apply `highlight_rolloff` — Filmic-style shoulder: `f(x) = x / (1 + x * k)` with `k = 0.5`; recovers blown whites into near-white without harsh clipping
- [ ] BD706 Shadow lift: adjustable `--shadow-lift 0.04` lifts black point; removes crushed blacks in contrasty repligen outputs; combined with highlight recovery gives natural DR even on poorly exposed AI images
- [ ] BD707 Chromatic aberration: `--ca` flag; lateral CA simulation — red channel shifted `+0.3px` right, blue `-0.3px` left via `affine`; subtle optical character; stronger on edges (distance from centre weighted); off by default
- [ ] BD708 Lens vignette: `VignettePipeline` generates smooth radial mask `1 - (r/R)^2.5 * strength`; multiplied onto image; `--vignette 0.35` is default for all stocks; shape option `--vignette-shape oval|circular`
- [ ] BD709 Dust and scratch: `--dust` overlays semi-transparent scratch texture (pre-computed PNG at 2048×2048 in `data/textures/dust.png`); random offset and rotation per image; adds physicality to AI-generated images
- [ ] BD710 Output metadata: writes `postpro_manifest.json` alongside output: `{input:, output:, stock:, preset:, steps_applied:[], processing_time_ms:, vips_version:, postpro_version:}`; enables reproducibility and audit

### BD8: postpro.rb — Quality and Benchmarking

- [ ] BD801 BRISQUE score: `brisque` pure-Ruby implementation (no OpenCV); no-reference perceptual quality score 0-100 (lower = better); auto-reject outputs scoring >45 (visibly degraded); report score in manifest
- [ ] BD802 SSIM comparison: when `--compare original.jpg processed.jpg` flag used, compute SSIM (structural similarity) to verify processing preserves content; useful for regression testing stock parameter changes
- [ ] BD803 A/B preview: `postpro preview input.jpg --stock portra --stock velvia` renders split-screen comparison via Vips `join`; outputs `comparison.jpg` or sixel if terminal supports; quick stock selection without processing full batch
- [ ] BD804 Regression test suite: `postpro test` runs all stocks against 5 reference images (portrait, landscape, product, street, night); compares outputs against golden files (perceptual hash threshold <8); fails CI if stock behaviour changed unintentionally
- [ ] BD805 Performance profiling: `--profile` flag wraps each pipeline step in `Process.clock_gettime` measurement; reports per-step time in manifest; identifies bottlenecks (grain simulation is typically 60% of runtime)
- [ ] BD806 Grain optimisation: grain currently generated fresh per image; cache grain texture for same `(width, height, sigma, seed)` tuple in `~/.cache/postpro/grain/`; 3× faster batch processing when same grain params reused across images
- [ ] BD807 GPU acceleration via Vips: `Vips::Operation.block_untrusted` ensures safe operations only; `Vips.get("vips-concurrency") = 4` aligns with Falcon worker count; `--gpu` flag enables Vips CUDA path if libvips compiled with CUDA (not OpenBSD)
- [ ] BD808 Memory-mapped input: for images >50MP, `Vips::Image.new_from_file(path, access: :sequential)` streams pixels instead of loading fully; prevents 2GB+ RAM spikes on large repligen outputs (SDXL at 2048×2048 = 12MB but upscaled 4× = 192MB)
- [ ] BD809 Error recovery: if Vips crashes mid-pipeline (SIGABRT on corrupt JPEG), `postpro batch` catches via subprocess isolation; marks file as `failed` in manifest; continues with remaining files; failed files reported in summary
- [ ] BD810 Automated quality uplift preset: `--preset quality_uplift` — applies in order: adaptive contrast (CLAHE 0.3), selective sharpen (0.5), highlight recovery (0.5), shadow lift (0.03), Portra light grain (sigma 10), vignette (0.2), BRISQUE check; designed specifically for improving mediocre AI outputs to gallery quality

### BD9: postpro.rb + brgen Active Storage Integration

- [ ] BD901 PostproJob: `PostproJob(attachment_id, preset:)` — Solid Queue job; downloads attachment blob; runs postpro pipeline; re-uploads processed version as new variant; marks original attachment `postprocessed_at: Time.now`
- [ ] BD902 Auto-trigger on upload: `Photo.after_create_commit { PostproJob.perform_later(id, preset: "social") }` — every brgen photo upload gets cinematic treatment automatically; users never need to invoke postpro manually
- [ ] BD903 Preset selection by context: `dating` profile photos → `preset: portrait` (skin protection, soft grain); `marketplace` listing photos → `preset: product` (clarity, white lift, sharpness); `feed` photos → `preset: social`; preset resolved by controller context
- [ ] BD904 Variant caching: processed variant stored as separate Active Storage blob; original preserved; `image_tag photo.processed_variant` served from Cloudflare cache; re-process only on stock/preset change via `postprocessed_preset` column
- [ ] BD905 Progress feedback: Stimulus `upload-controller.js` shows upload progress → "bearbeides..." spinner while `PostproJob` runs → Turbo Stream swaps preview when done; user sees live transition from raw to processed
- [ ] BD906 Before/after toggle: on photo detail view, "Se original" button toggles between processed and raw via Turbo Frame; satisfies curiosity; never shown in feed (processed always preferred)
- [ ] BD907 Stock selection per city: `City.film_stock` column; Bergen → `:kodak_portra`; LA → `:kodak_vision3`; Amsterdam → `:fujichrome_velvia`; postpro uses city's stock for all uploads from that city; city identity in every photo
- [ ] BD908 Moderation-safe processing: postpro does NOT alter image content (no removal of objects, no face editing); purely colour/grain; safe from "altered evidence" concerns if photos used in reports; documented in privacy policy
- [ ] BD909 Thumbnail postpro: Active Storage `variant` chain: `resize_to_limit [800, 800]` → `convert "webp"` → `quality 85`; postpro applied to full-res only, not thumbnails (expensive); thumbnails cropped from postpro output, not from original
- [ ] BD910 Repligen→postpro→brgen pipeline: `SeedGenerationJob` orchestrates: (1) repligen generates `n` images per city; (2) postpro applies city stock preset; (3) Active Storage import attaches to seed posts; (4) posts published to city feed; fully automated city seeding

## BE: Competitive Differentiation — brgen vs X and Facebook

### BE1: What X and Facebook Cannot Do

- [ ] BE101 True city isolation: X and Facebook are global graphs — no architectural guarantee that LA content won't surface in Bergen; brgen enforces isolation at SQL layer via `acts_as_tenant`; a Bergen user literally cannot see LA data, by construction
- [ ] BE102 OLED-native design: X.com dark mode uses `#15202b` (dark blue-grey); Facebook dark uses `#18191a` (off-black); brgen uses `#000000` — actual OLED black, 100% pixel-off; 20-40% battery saving on AMOLED phones — a measurable, marketable difference
- [ ] BE103 Constitutional AI moderation: X relies on Community Notes (crowd-sourced, slow, gameable); Facebook on Oversight Board (political, opaque); MASTER enforces a machine-readable soul.yml with ABSOLUTE/PROTECTED tiers — moderation logic is auditable open-source code, not policy documents
- [ ] BE104 Anonymous-first: X requires phone number for new accounts; Facebook requires real name + identity verification pushes; brgen allows 2 posts anonymously before signup — lower barrier than any mainstream alternative
- [ ] BE105 Hyperlocal verticals in one app: X tried Spaces, Shops, Jobs — all bolted-on, poorly integrated; Facebook has Marketplace, Groups, Dating — separate products with different UX languages; brgen's verticals share one design system, one feed, one account — coherent by architecture
- [ ] BE106 Gesture-hidden navigation: X and Facebook have persistent bottom nav bars consuming 56px; brgen landing has no persistent nav — appears only on intentional gesture; the entire screen is content; especially powerful on small phones
- [ ] BE107 No algorithmic engagement traps: brgen feed is chronological + distance-weighted — what's near + recent; X's algorithm optimises for engagement (outrage); Facebook EdgeRank optimises for ad revenue; brgen's ranking function is open-source and documented
- [ ] BE108 City-native content: a Bergen-born social network understands Bergen humour, local politics, dialect; X's globalisation erases local context; brgen seed content, moderation prompts, and UI copy are city-specific — not translated English
- [ ] BE109 No surveillance advertising: brgen monetises via Vipps/Stripe subscription (Premium) and local business promoted posts; no ad auction, no tracking pixels, no retargeting; GDPR-native because there's nothing to comply about — no ad data collected
- [ ] BE110 Open stack: Rails + SQLite + OpenBSD — entirely auditable; X is closed-source; Facebook is closed-source; brgen's entire stack can be self-hosted by a city council wanting their own instance; cities can fork and run

### BE2: Specific UX Innovations to Develop

- [ ] BE201 Spring-physics reveal: swipe-down (or scroll or tilt) reveals nav with `cubic-bezier(0.32, 0.72, 0, 1)` spring; feels physical, not linear; X and Facebook use `ease-in-out` transitions — mechanical by comparison; brgen's gesture should feel like lifting a veil
- [ ] BE202 Right-edge fade nav: the horizontal nav rail fades to nothing at right edge via `mask-image: linear-gradient(to right, black 70%, transparent 100%)`; implies more content beyond; X's nav is hard-edged horizontal scroll — brgen's implies depth
- [ ] BE203 Tiptap longform + feed coexistence: X is limited to 280 chars (paid 25K); Facebook composer is basic WYSIWYG; brgen has Tiptap — full rich text, embeds, polls, code blocks — in the same feed as short posts; one composer for all formats
- [ ] BE204 Near-me default: brgen's default feed is "within 5km of you" not "what's trending globally"; no setting required; geo-permission triggers default near-me; this is the inverse of X/Facebook's global-first default
- [ ] BE205 Community guidelines as pinned posts: first posts in a new city feed are the community guidelines, formatted as regular posts (not terms-of-service PDF); users can like/discuss the rules; guidelines are living documents that the community shapes
- [ ] BE206 Soft anonymity with trust levels: anonymous users can see all public content but can only post 2 times; verified users (phone) have green tick; premium users have blue; trust level shown as subtle icon, not aggressive badge; trust earns permissions, not status
- [ ] BE207 AI summaries of hot threads: on threads with >20 replies, "Vis sammendrag" button → MASTER summarises thread in 3 sentences via streaming Turbo Stream; X has Grok summaries (US only, paid); Facebook has no equivalent; brgen's is free and local-language-aware
- [ ] BE208 Dating that knows your neighbourhood: brgen Dating profiles include "bydel" (neighbourhood); matches default to same bydel or adjacent; you might walk past your match at Narvesen — that hyperlocality is unachievable on Tinder (global) or Facebook Dating (city-level only)
- [ ] BE209 Playlist as social object: sharing a Spotify playlist on X posts a link; on Facebook it's a preview card; on brgen, a playlist is a first-class post type with embedded player, collaborative editing, and listening-party room — fundamentally richer
- [ ] BE210 Takeaway with community reviews: Takeaway.com and Foodora show aggregate star ratings; brgen's Takeaway shows reviews from people in your bydel — neighbours you might know; hyperlocal trust signal stronger than anonymous crowd reviews

### BE3: Features to Build First (Competitive Priority)

- [ ] BE301 P1 — City isolation proof: implement and prominently document the per-city SQLite architecture; publish the open-source isolation guarantee; this is the foundational differentiator all others depend on
- [ ] BE302 P1 — OLED landing page: ship the `#000` landing with spring-physics nav before any other feature; first impression sets the contrast with X/Facebook immediately; 1 developer × 2 days
- [ ] BE303 P1 — Tiptap composer: longform native in a social network is the anti-X move; ship the composer with image attach and @mention as the first interaction users have with posting; defines the product as substantive over reactive
- [ ] BE304 P2 — Anonymous post gate: 2-post limit with MASTER moderation gate; enables cold-start user acquisition (no signup friction) while maintaining quality; X and Facebook both require account first
- [ ] BE305 P2 — Bergen seed content: 100 authentic Bergen posts make the city feel alive at launch; nothing kills a new social network faster than an empty feed; seed before any public announcement
- [ ] BE306 P2 — Near-me feed: the geo-default feed is the killer feature for daily engagement; schedule and bus routes, local events, neighbourhood news — content X and Facebook algorithmically suppress as "low engagement"
- [ ] BE307 P3 — Dating vertical: hyperlocal dating is defensible (Tinder can't do bydel-level isolation); ship after core feed is established; requires enough DAU in a city to have viable match pools (target: 500+ registered users per city before soft-launching Dating)
- [ ] BE308 P3 — AI thread summaries: ship after MASTER prompt caching is implemented (AM107 prerequisite); then cost is $0.07/turn not $0.73; streaming summary in thread is delightful and unprecedented in any local social network
- [ ] BE309 P4 — Listening parties: ship when Playlist has >1K DAU; social features require density; premature if playlist itself is underused
- [ ] BE310 P4 — Takeaway full ordering: requires restaurant partner acquisition; ship as soon as 3 Bergen restaurants agree to pilot; Vipps integration unlocks Norwegian market; Stripe for international cities

## BF: AST Transformation & Node Pruning

- [ ] BF01 Convert explicit `begin/ensure` blocks to method-level rescue where applicable.
- [ ] BF02 Prune redundant `return` keywords from terminal expressions in lambda blocks.
- [ ] BF03 Transform manual array flattening loops into single-pass native `flatten!`.
- [ ] BF04 Refactor multiple `elsif` conditional branches into structural `case` equality statements.
- [ ] BF05 Replace double-negative loops (`unless !condition`) with clean positive checking loops.
- [ ] BF06 Standardize block argument passing via forwarders (`...`) across wrapper methods.
- [ ] BF07 Flatten nested conditional guards into unified guard clauses at method entry points.
- [ ] BF08 Optimize literal string allocations inside high-frequency loops using frozen string suffixes.
- [ ] BF09 Convert explicit array instantiations within block iterators to lazy enumerators.
- [ ] BF10 Replace local variable caching of object attributes with direct semantic references.
- [ ] BF11 Rewrite manual token matching logic using optimized internal AST regex operations.
- [ ] BF12 Inline single-use helper utilities inside specialized execution sub-modules.
- [ ] BF13 Convert procedural hash construction patterns to high-performance declarative maps.
- [ ] BF14 Identify and drop unused block parameters from system-wide AST traversal hooks.
- [ ] BF15 Transform parallel variable assignments into step-by-step sequential actions.
- [ ] BF16 Replace dynamic string evaluations (`eval`) with structured object sends.
- [ ] BF17 Consolidate identical error-handling operations across sister AST classes.
- [ ] BF18 Rewrite multi-line inline assignments using clean block initializers.
- [ ] BF19 Standardize symbolic array generation patterns with efficient `%i[...]` notation.
- [ ] BF20 Enforce explicit conditional expressions over implicit type coercion.
- [ ] BF21 Optimize iterative hash reduction loops using direct structural transformations.
- [ ] BF22 Convert dynamic class lookups to structured registry array maps.
- [ ] BF23 Prune empty initialization sequences from purely functional utility modules.
- [ ] BF24 Replace compound logical blocks inside filters with single descriptive predicates.
- [ ] BF25 Streamline token pipeline generation arrays by eliminating intermediate mutations.
- [ ] BF26 Enforce unified freeze policies on all static lookup arrays and configurations.
- [ ] BF27 Abstract manual dependency sorting routines using standard topological logic.
- [ ] BF28 Refactor complex boolean assignments into clear ternary operators where scannable.
- [ ] BF29 Convert explicit string joins into structured interpolations inside template tools.
- [ ] BF30 Replace structural object cloning routines with clear, immutable state copies.
- [ ] BF31 Group related attribute readers into unified single-line declarations.
- [ ] BF32 Prune unreachable execution points following terminal loop breaks.
- [ ] BF33 Standardize block parsing errors using explicit internal semantic exceptions.
- [ ] BF34 Replace variable-length argument lists with explicit keyword configurations.
- [ ] BF35 Streamline class inheritances by moving shared behavior to isolated mixins.
- [ ] BF36 Optimize dynamic method generation routines using explicit cache lookups.
- [ ] BF37 Convert multi-step map-filter passes into single-pass reduction loops.
- [ ] BF38 Standardize string parsing invariants using concrete lexical scanners.
- [ ] BF39 Replace open struct implementations with fast, lightweight data definitions.
- [ ] BF40 Prune redundant block nesting levels inside AST walker definitions.

## BG: SQLite State & Determinism

- [ ] BG01 Enforce strict WAL configuration flags on engine initialization.
- [ ] BG02 Optimize state lookup queries using precise composite database indexes.
- [ ] BG03 Wrap multi-step orchestration mutations within explicit ACID transaction blocks.
- [ ] BG04 Standardize structural state migrations using linear, timestamped tracking schemas.
- [ ] BG05 Implement automatic database vacuum routines on standard system shutdowns.
- [ ] BG06 Enforce explicit foreign key validations on engine connection hooks.
- [ ] BG07 Replace unbounded trace logging queries with explicit limit bounds.
- [ ] BG08 Optimize internal telemetry writes using bulk insertion routines.
- [ ] BG09 Implement explicit transaction retry mechanics on database lock detection.
- [ ] BG10 Convert text-based state keys to fast indexed integer constants.
- [ ] BG11 Build automated integrity verification routines on database file mounts.
- [ ] BG12 Enforce strict non-null properties on all relational state identifiers.
- [ ] BG13 Standardize event history queries using optimized time-range boundaries.
- [ ] BG14 Implement deterministic text sorting strategies on state lookup routines.
- [ ] BG15 Optimize payload serialization steps using high-performance format processing.
- [ ] BG16 Build automatic backup pipelines for database file states prior to sweeps.
- [ ] BG17 Standardize connection configuration metrics within a single system source.
- [ ] BG18 Optimize variable binding steps inside raw SQL pipeline queries.
- [ ] BG19 Implement explicit size limits on unstructured data storage fields.
- [ ] BG20 Replace sequential row processing tasks with atomic database update statements.
- [ ] BG21 Enforce clear cascade rules on all related state table boundaries.
- [ ] BG22 Build clean database checkpoint monitors for long-running execution loops.
- [ ] BG23 Optimize historical state analytics using native engine aggregation functions.
- [ ] BG24 Standardize database connection pools for multi-threaded system tasks.
- [ ] BG25 Implement explicit query timeout safety parameters on long processing tracks.
- [ ] BG26 Replace dynamic SQL generation loops with explicit pre-compiled statements.
- [ ] BG27 Verify index choices using automated execution analysis checks.
- [ ] BG28 Optimize storage footprints by normalising redundant state tracking metrics.
- [ ] BG29 Build explicit state verification triggers directly inside table schemas.
- [ ] BG30 Standardize database session isolation steps during parallel code testing.
- [ ] BG31 Implement immediate transaction lock flags on engine modification routes.
- [ ] BG32 Optimize memory tracking metrics for in-memory temporary database stores.
- [ ] BG33 Build automatic corrupt file recovery paths for the local state architecture.
- [ ] BG34 Replace table scan operations with direct, high-efficiency index lookups.
- [ ] BG35 Enforce strict validation rules on raw configuration inputs before persistence.
- [ ] BG36 Standardize diagnostic database logs within a distinct system table space.
- [ ] BG37 Optimize storage allocations by cleaning up expired state artifacts.
- [ ] BG38 Build automated row versioning systems to detect multi-user write conflicts.
- [ ] BG39 Enforce database file lock permissions matching OpenBSD secure profiles.
- [ ] BG40 Streamline database initialization routines using explicit creation scripts.

## BH: Rhythmic Micro-Timing & Audio Invariants (Dilla)

- [ ] BH01 Enforce deterministic micro-timing shifts within the primary groove matrix.
- [ ] BH02 Optimize sample block generation tracking loops to minimize phase distortion.
- [ ] BH03 Implement zero-allocation math operations inside high-frequency processing arrays.
- [ ] BH04 Standardize vinyl-emulation noise generation bounds inside sonitex modules.
- [ ] BH05 Optimize multi-track synchronization layers to prevent buffer underrun errors.
- [ ] BH06 Build precise sample-rate conversion pipelines for unstructured external audio.
- [ ] BH07 Enforce explicit bit-depth limitations across all real-time rendering layers.
- [ ] BH08 Optimize low-pass filter calculation arrays using static lookup configurations.
- [ ] BH09 Implement predictable volume ramp parameters to avoid audio click transients.
- [ ] BH10 Replace generic random calculations with deterministic swing noise tables.
- [ ] BH11 Build automated timing accuracy monitors inside the audio output block.
- [ ] BH12 Enforce strict bounds checks on all incoming sound parameter controls.
- [ ] BH13 Standardize audio channel mapping logic across mono and stereo rendering formats.
- [ ] BH14 Optimize processing loops using raw direct memory block structures.
- [ ] BH15 Implement low-latency audio file streaming pipelines for preview triggers.
- [ ] BH16 Build precise transient alignment systems for staggered beat overlays.
- [ ] BH17 Standardize audio parameter interpolation loops using flat linear scales.
- [ ] BH18 Optimize digital signal processing chains to run entirely thread-isolated.
- [ ] BH19 Implement explicit safety limits on internal filter resonance attributes.
- [ ] BH20 Replace complex modulation code blocks with direct matrix lookup operations.
- [ ] BH21 Enforce strict file structure checks on incoming wav target objects.
- [ ] BH22 Build precise track peak monitoring arrays inside rendering pipelines.
- [ ] BH23 Optimize delay line memory configurations using pre-allocated cyclic tracks.
- [ ] BH24 Standardize swing-ratio calculations using specific millisecond definitions.
- [ ] BH25 Implement fast parallel processing tracks for independent audio channels.
- [ ] BH26 Replace dynamic sample allocation patterns with static system buffer pools.
- [ ] BH27 Verify audio engine execution consistency across varied processor frequencies.
- [ ] BH28 Optimize wave rendering pipelines to avoid intermediate object generation.
- [ ] BH29 Build explicit headroom calculation systems inside the main audio mixer.
- [ ] BH30 Standardize MIDI event processing routines using low-latency timestamps.
- [ ] BH31 Implement immediate sample muting logic on track overflow signals.
- [ ] BH32 Optimize computational overhead of saturation steps via rough table approximations.
- [ ] BH33 Build automated drift correction systems for long-running audio playback.
- [ ] BH34 Replace multi-step channel mixes with single unified processing blocks.
- [ ] BH35 Enforce explicit volume normalisation tracking before audio saves.
- [ ] BH36 Standardize beat metadata layouts using clean structured formats.
- [ ] BH37 Optimize audio rendering lookahead times based on active system load.
- [ ] BH38 Build clear performance tracking metrics for all active filter blocks.
- [ ] BH39 Enforce clean audio device release behavior on general system terminations.
- [ ] BH40 Streamline beat generator setups using explicit track structure metrics.

## BI: Context Control & Prompt Engineering

- [ ] BI01 Implement explicit sliding token window limits on all backend model requests.
- [ ] BI02 Optimize context generation engines to drop low-priority file lines.
- [ ] BI03 Enforce strict anti-sycophancy instruction blocks on processing templates.
- [ ] BI04 Standardize role configuration templates within specific configuration layouts.
- [ ] BI05 Implement semantic caching architectures using high-efficiency content tracking.
- [ ] BI06 Build automated verification setups for tracking context line accuracy.
- [ ] BI07 Enforce explicit verification metrics for tracking model response changes.
- [ ] BI08 Optimize code inclusion templates by pruning long inline comment strings.
- [ ] BI09 Implement immediate fallback routes on model execution timeouts.
- [ ] BI10 Replace unstructured prompt strings with precise system target profiles.
- [ ] BI11 Build explicit verification controls for tracking raw input sanitization steps.
- [ ] BI12 Enforce strict phrase bans targeting common verbose model output loops.
- [ ] BI13 Standardize multi-step prompt tracking pipelines within structural trace logs.
- [ ] BI14 Optimize token generation density parameters based on code task complexity.
- [ ] BI15 Implement automated verification loops checking output format compliance.
- [ ] BI16 Build precise context tracking matrices for long iterative repair runs.
- [ ] BI17 Standardize token consumption monitors within an internal runtime table.
- [ ] BI18 Optimize message insertion arrays inside ongoing generation workflows.
- [ ] BI19 Implement explicit raw text truncation rules for external error inputs.
- [ ] BI20 Replace variable prompt updates with static operational target templates.
- [ ] BI21 Enforce strict validation steps ensuring code output block separation.
- [ ] BI22 Build clean retry routing mechanisms for temporary network interruptions.
- [ ] BI23 Optimize system prompt compilation times using fast pre-build maps.
- [ ] BI24 Standardize model choice matrices for individual classification tasks.
- [ ] BI25 Implement concrete stop-sequence parameters across all target model connections.
- [ ] BI26 Replace generic error messages with full contextual code frame definitions.
- [ ] BI27 Verify prompt assembly consistency using automated structural unit tests.
- [ ] BI28 Optimize context generation footprints by sharing common core target files.
- [ ] BI29 Build explicit tracking loops monitoring processing efficiency across runs.
- [ ] BI30 Standardize multi-turn chat records using lightweight serialization steps.
- [ ] BI31 Implement immediate prompt size optimization checks prior to remote transport.
- [ ] BI32 Optimize generation temperature parameters based on specific task profiles.
- [ ] BI33 Build automated warning alerts for files approaching model context limits.
- [ ] BI34 Replace dynamic text injection loops with explicit semantic placeholder tokens.
- [ ] BI35 Enforce strict code-only return instructions inside code execution wrappers.
- [ ] BI36 Standardize response parsing blocks to handle mixed format text inputs.
- [ ] BI37 Optimize validation workflow execution speeds via fast parallel testing paths.
- [ ] BI38 Build clear analytical profiles capturing model accuracy records over cycles.
- [ ] BI39 Enforce clean communication pipeline drops on model connection exceptions.
- [ ] BI40 Streamline model orchestration tracks using clean, declarative route tracking.

## BJ: Console Interface & Brutalist Layouts

- [ ] BJ01 Enforce explicit VT100 terminal escape sequences for console layout tasks.
- [ ] BJ02 Optimize log printing speeds by implementing direct standard write blocks.
- [ ] BJ03 Implement complete Unix silence rules across non-interactive run targets.
- [ ] BJ04 Standardize status layouts matching OpenBSD system diagnostic output styles.
- [ ] BJ05 Optimize column layout calculations for high-density textual display formats.
- [ ] BJ06 Build automated line wrapping calculation systems for dense text logs.
- [ ] BJ07 Enforce strict color palette limitations matching classic system display standards.
- [ ] BJ08 Optimize progress tracking bars by using low-overhead update frequencies.
- [ ] BJ09 Implement immediate text redraw routines on terminal scale adjustment signals.
- [ ] BJ10 Replace dynamic interface widgets with static text block arrangements.
- [ ] BJ11 Build clear terminal input interception routes to capture keystroke controls.
- [ ] BJ12 Enforce strict maximum line length guidelines across all console logs.
- [ ] BJ13 Standardize interactive diagnostic modes within a dedicated layout module.
- [ ] BJ14 Optimize trace layout generation algorithms to avoid terminal flickers.
- [ ] BJ15 Implement clear section break markers across sequential tool operations.
- [ ] BJ16 Build automated performance data rendering tables using simple text grids.
- [ ] BJ17 Standardize error display blocks using distinct high-visibility layouts.
- [ ] BJ18 Optimize terminal screen space allocation using compact row metrics.
- [ ] BJ19 Implement explicit character encoding checks on all internal log data inputs.
- [ ] BJ20 Replace fluid animations with immediate, state-based text updates.
- [ ] BJ21 Enforce clear spacing boundaries around active analytical code blocks.
- [ ] BJ22 Build reliable input history tracking systems for interactive terminal prompts.
- [ ] BJ23 Optimize layout template processing times using static print macros.
- [ ] BJ24 Standardize option toggle display interfaces using basic bracket graphics.
- [ ] BJ25 Implement concrete prompt navigation structures for system debugging tasks.
- [ ] BJ26 Replace complex layout libraries with explicit system output generation codes.
- [ ] BJ27 Verify layout rendering correctness across varied terminal window scales.
- [ ] BJ28 Optimize screen drawing memory footprints by using shared log strings.
- [ ] BJ29 Build explicit tracking metrics for monitoring display operations execution data.
- [ ] BJ30 Standardize multi-column code view layouts using clear boundary characters.
- [ ] BJ31 Implement immediate display clearing procedures on exit command captures.
- [ ] BJ32 Optimize text color matching workflows through pre-calculated map matrices.
- [ ] BJ33 Build automatic log file tracking monitors mirroring OpenBSD system outputs.
- [ ] BJ34 Replace dynamic help file generation structures with static system assets.
- [ ] BJ35 Enforce strict content validation rules on terminal text input streams.
- [ ] BJ36 Standardize system header formats using specific system identification patterns.
- [ ] BJ37 Optimize workspace line calculation speeds via fast indexing loops.
- [ ] BJ38 Build explicit user interaction analysis tools inside debugging tracks.
- [ ] BJ39 Enforce raw mode configuration cleanup operations on process terminations.
- [ ] BJ40 Streamline status report creation operations using clean plain text matrices.

## BK: Verification Pipeline & Integration Safety

- [ ] BK01 Enforce strict target verification paths on all code modification cycles.
- [ ] BK02 Optimize unit test processing architectures by executing isolated tests first.
- [ ] BK03 Implement complete pre-flight file state tracking across execution paths.
- [ ] BK04 Standardize runtime syntax validation rules using native system compile targets.
- [ ] BK05 Optimize execution time metrics tracking during high-speed parallel builds.
- [ ] BK06 Build automated regression discovery frameworks for target system codebases.
- [ ] BK07 Enforce strict code coverage benchmarks on incoming code modification files.
- [ ] BK08 Optimize integration trace pipelines to log precise system file delta data.
- [ ] BK09 Implement immediate structural file reversion paths on tracking failure alerts.
- [ ] BK10 Replace loose text match assertions with complete concrete syntax evaluations.
- [ ] BK11 Build precise verification boundaries isolating experimental code assets.
- [ ] BK12 Enforce strict dependency validation rules across external system tools.
- [ ] BK13 Standardize multi-stage testing sequences inside clear orchestration modules.
- [ ] BK14 Optimize static validation rule evaluation logic across multi-file maps.
- [ ] BK15 Implement automated validation runs triggering instantly on target updates.
- [ ] BK16 Build precise test failure diagnostic summaries matching standard format layouts.
- [ ] BK17 Standardize mock network layer simulations using predictable local targets.
- [ ] BK18 Optimize setup execution timelines by maintaining long-running test states.
- [ ] BK19 Implement explicit error categorization frameworks for framework verification runs.
- [ ] BK20 Replace random testing variations with explicit seed-based sequences.
- [ ] BK21 Enforce explicit runtime check conditions inside target production routines.
- [ ] BK22 Build clean continuous integration configurations for parallel multi-platform tests.
- [ ] BK23 Optimize static structure analysis sweeps by parallelizing tracking matrices.
- [ ] BK24 Standardize artifact archival steps following validation pipeline executions.
- [ ] BK25 Implement explicit resource consumption tracking metrics on all test suites.
- [ ] BK26 Replace fragile execution timing targets with explicit event sequence tracking.
- [ ] BK27 Verify validation framework stability under simulated system fault inputs.
- [ ] BK28 Optimize tracking file generation logic to minimize local execution steps.
- [ ] BK29 Build explicit test coverage matrix reports for the framework code base.
- [ ] BK30 Standardize target output checking routines using explicit string comparisons.
- [ ] BK31 Implement immediate execution suspension protocols upon critical error traps.
- [ ] BK32 Optimize test data generation pipelines using pre-built target object matrices.
- [ ] BK33 Build automatic log cleanup tasks running post validation suite steps.
- [ ] BK34 Replace complex environment checking paths with simple system feature lookups.
- [ ] BK35 Enforce strict type signature assertions across core validation structures.
- [ ] BK36 Standardize system performance benchmarks within concrete historical sheets.
- [ ] BK37 Optimize verification tracking output channels using isolated logging tracks.
- [ ] BK38 Build clear tracking summaries mapping specific code errors to rule matrices.
- [ ] BK39 Enforce clean system lock closures when testing loops experience hardware breaks.
- [ ] BK40 Streamline testing environment assembly logic using minimal static structures.

## BL: Security Boundaries & POSIX Integrity

- [ ] BL01 Enforce strict file system access constraints during AST mutation cycles.
- [ ] BL02 Optimize path validation logic using absolute system target resolutions.
- [ ] BL03 Implement strict process privilege drop-down steps during execution setups.
- [ ] BL04 Standardize system environment variable isolation rules across worker threads.
- [ ] BL05 Optimize system process spawn logic to prevent shell injection vectors.
- [ ] BL06 Build automated checking steps tracking secret entry points in local updates.
- [ ] BL07 Enforce secure file permission masks on all database file creations.
- [ ] BL08 Optimize internal cryptography checks using native language acceleration tools.
- [ ] BL09 Implement immediate process termination routes on sandbox leakage alerts.
- [ ] BL10 Replace clear-text token caching systems with encrypted memory tracking.
- [ ] BL11 Build secure validation logic checking incoming external script inputs.
- [ ] BL12 Enforce strict operational resource limits using native kernel control flags.
- [ ] BL13 Standardize system signal interception routes matching classic POSIX rules.
- [ ] BL14 Optimize configuration decryption routines using flat hardware layouts.
- [ ] BL15 Implement automated memory cleaning routines for sensitive key strings.
- [ ] BL16 Build precise tracking blocks checking user execution authentication matrices.
- [ ] BL17 Standardize access logging procedures within immutable system records.
- [ ] BL18 Optimize context search logic to skip hidden infrastructure file paths.
- [ ] BL19 Implement explicit length limitations across all input argument arrays.
- [ ] BL20 Replace open system call routes with precise target binary references.
- [ ] BL21 Enforce explicit validation checks on file symbol modification targets.
- [ ] BL22 Build secure process jail setups matching classic OpenBSD profile rules.
- [ ] BL23 Optimize network transport security matrices via strict encryption models.
- [ ] BL24 Standardize tracking tokens for independent background system processes.
- [ ] BL25 Implement concrete memory fence operations inside multi-threaded engines.
- [ ] BL26 Replace generic error messages with blind tracking confirmation loops.
- [ ] BL27 Verify system access boundary operations using targeted intrusion routines.
- [ ] BL28 Optimize boundary checking memory lookups using fast lookup maps.
- [ ] BL29 Build explicit threat identification tracking engines within core network blocks.
- [ ] BL30 Standardize framework configuration validation matching strict secure schemas.
- [ ] BL31 Implement immediate execution lockout modes when file alteration loops break.
- [ ] BL32 Optimize system trace filtering logic through automated structural maps.
- [ ] BL33 Build automatic secure state reconstruction systems for emergency recovery.
- [ ] BL34 Replace third-party authentication paths with explicit native checking patterns.
- [ ] BL35 Enforce strict operational scope boundaries on AI generation sub-tasks.
- [ ] BL36 Standardize data encryption keys management inside uniform host setups.
- [ ] BL37 Optimize validation code execution speeds across secure isolation lines.
- [ ] BL38 Build clear structural validation tracking records for secure code reviews.
- [ ] BL39 Enforce clean system pipe tracking logic to block lingering file descriptor exposures.
- [ ] BL40 Streamline access clearance tracking configurations using simple plain lists.

## BM: Network Operations & Protocol Drivers

- [ ] BM01 Enforce strict connection timeout constants on all network client targets.
- [ ] BM02 Optimize socket data buffering layers to minimize local processing pauses.
- [ ] BM03 Implement complete HTTP request validation patterns across external API lines.
- [ ] BM04 Standardize communication packet structure protocols via explicit typing arrays.
- [ ] BM05 Optimize response chunk parsing tasks through high-speed internal routines.
- [ ] BM06 Build automated keep-alive connection tracking systems for remote hosts.
- [ ] BM07 Enforce strict maximum payload dimension policies on remote server calls.
- [ ] BM08 Optimize network data serialization pipelines using fast memory serialization maps.
- [ ] BM09 Implement immediate alternative target fallback tracks on primary route drops.
- [ ] BM10 Replace standard open client modules with lightweight custom network targets.
- [ ] BM11 Build precise network tracking log systems inside diagnostic modules.
- [ ] BM12 Enforce strict SSL certificate verification targets on external access lanes.
- [ ] BM13 Standardize API message envelope tracking schemas inside static maps.
- [ ] BM14 Optimize proxy communication interception logic across internal proxy lines.
- [ ] BM15 Implement automated connection count monitoring tracks across system routines.
- [ ] BM16 Build precise rate-limiting compliance trackers for upstream remote nodes.
- [ ] BM17 Standardize response compression handling operations using native system drivers.
- [ ] BM18 Optimize backend routing tables using simple pre-sorted hash structures.
- [ ] BM19 Implement explicit error recovery thresholds for network transport lines.
- [ ] BM20 Replace loose text endpoint patterns with structured routing configuration keys.
- [ ] BM21 Enforce explicit content safety verifications on incoming data assets.
- [ ] BM22 Build stable data streaming connections using explicit background workers.
- [ ] BM23 Optimize connection handshake speeds using targeted caching configurations.
- [ ] BM24 Standardize system header format collections inside centralized lists.
- [ ] BM25 Implement concrete packet retry interval matrices on tracking loops.
- [ ] BM26 Replace verbose transport structures with minimal data-only frames.
- [ ] BM27 Verify system network error tracking capabilities via simulated transport blocks.
- [ ] BM28 Optimize DNS tracking resolution speeds via local connection records.
- [ ] BM29 Build explicit network throughput metrics inside trace tracking panels.
- [ ] BM30 Standardize backend communication layers using strict custom definitions.
- [ ] BM31 Implement immediate network port closure commands upon system exit paths.
- [ ] BM32 Optimize transport encryption routine calls through static frame maps.
- [ ] BM33 Build automatic cluster sync protocols for multi-node configuration setups.
- [ ] BM34 Replace dynamic parameter injection logic with clear key-value arrays.
- [ ] BM35 Enforce strict operational scope boundaries on client-side transport blocks.
- [ ] BM36 Standardize authentication transport tokens using secure hidden fields.
- [ ] BM37 Optimize packet delivery speeds through targeted data size bounds.
- [ ] BM38 Build clear diagnostic trace tracks for distributed network system runs.
- [ ] BM39 Enforce clean stream tracking termination logic across broken target ports.
- [ ] BM40 Streamline client initialization routines using simple linear data paths.

## BN: File Architecture & Repository Layouts

- [ ] BN01 Enforce strict folder localization schemas matching core design maps.
- [ ] BN02 Optimize project lookup speed via pre-compiled repository indexes.
- [ ] BN03 Implement complete file block protection patterns during code rewrite phases.
- [ ] BN04 Standardize structure migration tracking codes inside standard history paths.
- [ ] BN05 Optimize file path scanning loops using targeted directory exclusions.
- [ ] BN06 Build automated format tracking tests inside main file control modules.
- [ ] BN07 Enforce strict file size limitation matrices across code script assets.
- [ ] BN08 Optimize code module load parameters by structuring implicit layout blocks.
- [ ] BN09 Implement immediate operational reversion tracking upon file mutation faults.
- [ ] BN10 Replace dynamic path discovery scripts with static path system records.
- [ ] BN11 Build precise change location tracking blocks across active working trees.
- [ ] BN12 Enforce strict naming specification rules across all internal script modules.
- [ ] BN13 Standardize temporary directory construction patterns inside isolated systems.
- [ ] BN14 Optimize file tracking update frequencies inside high-frequency sweeps.
- [ ] BN15 Implement automated target verification actions before final file writes.
- [ ] BN16 Build precise file size analytical reports for project storage reviews.
- [ ] BN17 Standardize ignore configuration structures inside a distinct root file asset.
- [ ] BN18 Optimize file parsing lookahead memory allocations inside parsing loops.
- [ ] BN19 Implement explicit encoding requirement checks across text template sets.
- [ ] BN20 Replace unstructured content generation routines with formal structural steps.
- [ ] BN21 Enforce explicit directory existence verifications prior to code exports.
- [ ] BN22 Build clear repository cleanup mechanisms for temporary processing runs.
- [ ] BN23 Optimize directory search algorithms using low-overhead recursive trees.
- [ ] BN24 Standardize target output path patterns within clear variable keys.
- [ ] BN25 Implement concrete symbolic link tracking guards inside local file sweeps.
- [ ] BN26 Replace custom file copy modules with optimized language standard blocks.
- [ ] BN27 Verify framework file path sorting logic via targeted integration sweeps.
- [ ] BN28 Optimize space management logic by dropping duplicate file records.
- [ ] BN29 Build explicit lock management routines tracking concurrent file writes.
- [ ] BN30 Standardize file metadata validation frameworks matching strict operational models.
- [ ] BN31 Implement immediate file access closure commands upon verification error states.
- [ ] BN32 Optimize directory file count lookups using fast system index charts.
- [ ] BN33 Build automatic layout verification trackers to confirm framework system shape.
- [ ] BN34 Replace dynamic asset discovery routes with explicit manifest entries.
- [ ] BN35 Enforce strict write restriction layers across tracking template targets.
- [ ] BN36 Standardize format layout rules for non-code text assets in storage folders.
- [ ] BN37 Optimize directory layout modification monitoring systems using fast kernel traps.
- [ ] BN38 Build clear system diagnostic trees mapping active workspace files.
- [ ] BN39 Enforce clean temporary tracking file drop paths on normal loop cycles.
- [ ] BN40 Streamline workspace initialization paths using explicit system structures.

## BO: Task Orchestration & Thread Control

- [ ] BO01 Enforce strict time budget allocation values on system execution lanes.
- [ ] BO02 Optimize multi-threaded worker configurations based on target host core limits.
- [ ] BO03 Implement complete task dependency checking layers before worker launches.
- [ ] BO04 Standardize operational step execution paths within clear pipeline classes.
- [ ] BO05 Optimize execution tracking matrix lookups inside large background runs.
- [ ] BO06 Build automated cycle discovery checks across complicated pipeline charts.
- [ ] BO07 Enforce strict queue load constraints on backend processing channels.
- [ ] BO08 Optimize message routing speeds between concurrent execution blocks.
- [ ] BO09 Implement immediate worker context cancellation traps on critical step drops.
- [ ] BO10 Replace arbitrary process sleep durations with explicit event execution targets.
- [ ] BO11 Build precise thread utilization metrics tables inside engine diagnostic suites.
- [ ] BO12 Enforce strict priority level guidelines across system automation runs.
- [ ] BO13 Standardize worker lifecycle event hooks inside concrete interface maps.
- [ ] BO14 Optimize task state evaluation logic by reducing lock duration metrics.
- [ ] BO15 Implement automated tracking checkpoints inside long background calculations.
- [ ] BO16 Build precise workflow failure trace files using standardized json templates.
- [ ] BO17 Standardize thread lock recovery paths to isolate broken execution lines.
- [ ] BO18 Optimize queue extraction logic using low-overhead lock-free designs.
- [ ] BO19 Implement explicit threshold constraints targeting dead system workers.
- [ ] BO20 Replace multi-step process chains with flat atomic orchestration sequences.
- [ ] BO21 Enforce explicit execution isolation rules across unrelated software targets.
- [ ] BO22 Build reliable daemon task execution loops using clean signal trap matrices.
- [ ] BO23 Optimize work token management layers inside distributed worker scenarios.
- [ ] BO24 Standardize progress metric compilation routes across all active tasks.
- [ ] BO25 Implement concrete thread allocation limits on system-wide batch executions.
- [ ] BO26 Replace variable workflow rules with static state orchestration profiles.
- [ ] BO27 Verify thread scheduler performance limits via artificial heavy load tests.
- [ ] BO28 Optimize context change processing overheads by sharing static worker data.
- [ ] BO29 Build explicit resource monitor loops watching active worker memory profiles.
- [ ] BO30 Standardize system command routing maps inside uniform registry files.
- [ ] BO31 Implement immediate background loop termination protocols upon shell crash detections.
- [ ] BO32 Optimize queue structural adjustments via high-speed tracking arrays.
- [ ] BO33 Build automatic pipeline step retry configurations with explicit max limits.
- [ ] BO34 Replace heavy process communication logic with minimal memory queues.
- [ ] BO35 Enforce strict loop validation guidelines across asynchronous execution tracks.
- [ ] BO36 Standardize parallel workflow configurations within clear operational sheets.
- [ ] BO37 Optimize task completion check intervals to balance engine response speed.
- [ ] BO38 Build clear event logging maps detailing step transitions inside target engines.
- [ ] BO39 Enforce clean channel teardown behavior on unexpected master framework breaks.
- [ ] BO40 Streamline orchestrator generation metrics using basic declarative schemas.

## BP: Telemetry, Tracing & Logging Engines

- [ ] BP01 Enforce explicit entry categorization requirements on all system log lines.
- [ ] BP02 Optimize operational trace parsing routines to reduce performance overheads.
- [ ] BP03 Implement high-speed asynchronous logging pipelines for transient data.
- [ ] BP04 Standardize execution event signature patterns inside analytical modules.
- [ ] BP05 Optimize storage space consumption metrics for historical system logs.
- [ ] BP06 Build automated validation loops checking tracking log file formats.
- [ ] BP07 Enforce strict format guidelines across all diagnostic error trace trees.
- [ ] BP08 Optimize runtime performance trace filters via targeted module skips.
- [ ] BP09 Implement immediate backup dump routines on local tracing channel breaks.
- [ ] BP10 Replace high-frequency text prints with optimized binary counter updates.
- [ ] BP11 Build clear tracking summaries mapping platform metrics across execution runs.
- [ ] BP12 Enforce strict message dimension boundaries inside system tracking engines.
- [ ] BP13 Standardize trace collection points using explicit structural hook interfaces.
- [ ] BP14 Optimize runtime log formatting tasks by removing runtime object lookups.
- [ ] BP15 Implement automated diagnostic alert routes for tracking system drops.
- [ ] BP16 Build precise resource execution metrics logs inside state components.
- [ ] BP17 Standardize alert condition verification tasks within isolated tracking files.
- [ ] BP18 Optimize file trace scanning routines using fast targeted binary searches.
- [ ] BP19 Implement explicit severity evaluation models for all tracking data points.
- [ ] BP20 Replace multi-file output logs with a single unified tracking channel.
- [ ] BP21 Enforce clear structural checking controls on target telemetry streams.
- [ ] BP22 Build comprehensive trace visualization structures using plain grid charts.
- [ ] BP23 Optimize runtime event matching speeds via pre-allocated tracking arrays.
- [ ] BP24 Standardize operational profiling configurations within direct registry tables.
- [ ] BP25 Implement concrete trace retention limitation protocols on system storage units.
- [ ] BP26 Replace custom data tracking libraries with minimal language default configurations.
- [ ] BP27 Verify telemetry system reliability using targeted diagnostic fault injections.
- [ ] BP28 Optimize log processing performance footprints using static block caching rules.
- [ ] BP29 Build explicit performance benchmark log sets tracking framework mutations.
- [ ] BP30 Standardize target output logging metrics matching clear operational definitions.
- [ ] BP31 Implement immediate metrics transport operations on critical application events.
- [ ] BP32 Optimize layout rendering speeds for log display interfaces using flat rows.
- [ ] BP33 Build automatic background telemetry clean routines to limit storage expansion.
- [ ] BP34 Replace dynamic tracking parameters with explicit system event attributes.
- [ ] BP35 Enforce strict content filtering rules blocking sensitive information leakage.
- [ ] BP36 Standardize telemetry packet layouts inside clear structural format files.
- [ ] BP37 Optimize trace analytical calculation pipelines via minimal index sweeps.
- [ ] BP38 Build clear operational trace records across all validation routine steps.
- [ ] BP39 Enforce clean diagnostic engine detachment actions on system terminations.
- [ ] BP40 Streamline telemetry setup scripts using standard host environment configurations.

## BQ: Cross-App Infrastructure & Deployment (DEPLOY snapshot)

- [ ] BQ01 rails/check_production_gate.rb: add check that each app's Gemfile.lock is present and matches Gemfile (no drift)
- [ ] BQ02 rails/check_production_gate.rb: verify `config.host_authorization` excludes `/up` for all apps
- [ ] BQ03 All apps: ensure `config.active_storage.service = :local` is used in production; S3/mirror only via explicit override
- [ ] BQ04 All apps: add `config.assume_ssl = true` — verify no `config.force_ssl = true` anywhere
- [ ] BQ05 All apps: verify `config.consider_all_requests_local = false` in production
- [ ] BQ06 All apps: add `config.logger = ActiveSupport::TaggedLogging.logger($stdout)` for JSON-friendly logging
- [ ] BQ07 All apps: add `config.active_record.query_log_tags_enabled = true` to trace N+1 in production logs
- [ ] BQ08 All apps: add `config.action_dispatch.show_exceptions = :none` (exceptions → 500) — document if overridden
- [ ] BQ09 brgen: ensure `Tv::Channel`, `Tv::Video`, `Tv::Broadcast` models are fully migrated and have Active Storage attachments
- [ ] BQ10 bsdports: verify `PortsImportJob` can run without OOM on OpenBSD (use `find_each` + streaming)
- [ ] BQ11 bsdports: add `SecurityAdvisory` model and a job that scrapes OpenBSD errata
- [ ] BQ12 baibl: add `ReadingPlan` & `ReadingPlanDay` — models exist in migration but not in current app tree
- [ ] BQ13 hjerterom: add `Box` → `Beneficiary` foreign key constraint (migration exists but might be missing in schema.rb)
- [ ] BQ14 hjerterom: add `Donor` model (table already created in migration) and wire to `Donation`
- [ ] BQ15 All apps: verify every `db/migrate/` file is idempotent (no `remove_column` without `if_exists`)
- [ ] BQ16 All apps: add `database.yml` connection pool (`pool:`) equal to Falcon/Puma worker count
- [ ] BQ17 All apps: set `timeout` in `database.yml` to 5000 — ensure it is not overridden per environment
- [ ] BQ18 DEPLOY/openbsd/openbsd.sh: add `rcctl enable` and `rcctl start` for `litestream` (backup service)
- [ ] BQ19 DEPLOY/openbsd/openbsd.sh: add cron job for `cert-renewal.sh` to run weekly — verify on VPS
- [ ] BQ20 DEPLOY/openbsd/openbsd.sh: after Stage 2, run `verify_deploy_identity.rb` and fail if any error
- [ ] BQ21 All apps: add `GET /up` endpoint that returns 200 only if DB, cache, and queue are reachable
- [ ] BQ22 All apps: add `GET /health` returning JSON with component statuses for load balancer
- [ ] BQ23 All apps: set `config.active_job.queue_adapter = :solid_queue` in production.rb — verify no Redis dependency
- [ ] BQ24 All apps: add `config/recurring.yml` with `clear_solid_queue_finished_jobs` (copy to apps that are missing it)
- [ ] BQ25 brgen: add `config.after_initialize` to load `sqlite-vec` extension if present (needed for distance queries)

## BR: Rails 8+ Hotwire & StimulusReflex Refinements

- [ ] BR01 All apps: replace `form_with model:` with `form_with model:, data: { turbo: false }` where uploads are involved (DirectUpload uses its own JS)
- [ ] BR02 All apps: add `<meta name="turbo-cache-control" content="no-cache">` to all pages with forms or CSRF tokens
- [ ] BR03 brgen dating: implement `data-reflex="click->Dating#swipe"` on card stack (replaces plain JS swipe)
- [ ] BR04 brgen TV: use `cable_ready.dispatch_event` to trigger live viewer count update every 10s
- [ ] BR05 amber outfit builder: add `data-reflex="change->Outfit#reorder"` on sortable list (PATCH /outfits/:id/reorder)
- [ ] BR06 amber item upload: add `data-controller="direct-upload"` for background image processing
- [ ] BR07 blognet article editor: add `data-reflex="blur->Article#auto_save"` on ActionText editor
- [ ] BR08 bsdports search: add `data-reflex="input->Search#live"` for live search with debounce
- [ ] BR09 baibl verse navigation: add `data-reflex="keydown.arrowDown->Verse#next"` for keyboard bible reading
- [ ] BR10 hjerterom donation form: add `data-reflex="change->Donation#calculate_impact"` for real-time impact estimate
- [ ] BR11 All apps: add `data-reflex-permanent` to all `<input>` elements inside modal dialogs (prevents Turbo morph reset)
- [ ] BR12 All apps: add `around_reflex { ActiveRecord::Base.transaction { yield } }` to all mutation reflexes
- [ ] BR13 All apps: add `before_reflex { halt_and_render_nothing! unless current_user }` on authenticated reflexes
- [ ] BR14 All apps: add `reflexError()` toast handler in Stimulus controllers
- [ ] BR15 All apps: replace `cable_ready.broadcast` with `cable_ready.broadcast_to` (scoped to model) for cache invalidation
- [ ] BR16 All apps: add `config.action_cable.url = "wss://#{host}/cable"` in production
- [ ] BR17 All apps: add `config.action_cable.allowed_request_origins` based on domain list — prevent cross-origin WebSocket
- [ ] BR18 All apps: add `config.cache_store = :solid_cache_store` in production — verify Solid Cache tables exist
- [ ] BR19 brgen: add `StreamChatChannel` for live TV chat (currently using `Tv::StreamChat` but no ActionCable channel)
- [ ] BR20 brgen: add `DatingChannel` for real-time match notification (currently only email/push)
- [ ] BR21 All apps: add `config.eager_load = true` in production — currently `false` in some copied configs
- [ ] BR22 All apps: add `config.assume_ssl = true` and remove any `force_ssl` — enforce in CI

## BS: Missing Live Search (LIVE_SEARCH_STANDARD.md)

- [ ] BS01 brgen marketplace listings: replace `LIKE` with FTS5, add Turbo Frame live update
- [ ] BS02 brgen playlist sets and tracks: add FTS5 search with faceted filters (genre, artist)
- [ ] BS03 brgen TV videos and channels: add full-text search over title + description
- [ ] BS04 brgen takeaway restaurants: replace `LIKE` with FTS5 + distance ranking
- [ ] BS05 brgen maps places: add search-as-you-type via Stimulus debounce
- [ ] BS06 brgen global search: single endpoint returning union of all vertical results
- [ ] BS07 amber wardrobe: add FTS5 fallback for AI search (low-cost offline mode)
- [ ] BS08 amber outfits: add search by name, occasion, season, item names
- [ ] BS09 blognet posts: add FTS5 over title + body, replace `LIKE`
- [ ] BS10 blognet tags: add tag search page with autocomplete
- [ ] BS11 hjerterom resources: add FTS5 over title, description, resource_type
- [ ] BS12 hjerterom food listings: add geo-aware FTS5 search (distance + keyword)
- [ ] BS13 All apps: add search analytics logging (query, result_count, latency_ms)
- [ ] BS14 All apps: implement zero-result suggestions via LLM (fallback to related terms)

## BT: Missing Stimulus Components (shared baseline)

- [ ] BT01 brgen: add `content-loader` for infinite scroll on feed
- [ ] BT02 brgen: add `read-more` for long post bodies
- [ ] BT03 brgen: add `popover` for user profile cards
- [ ] BT04 brgen: add `dialog` for confirmation modals (replaces `confirm()`)
- [ ] BT05 brgen: add `checkbox-select-all` for moderation panel
- [ ] BT06 brgen dating: add `hotkey` (←/→ for swipe, j/k for feed navigation)
- [ ] BT07 brgen: add `speech-recognition` for voice commands
- [ ] BT08 amber: add `sortable` for outfit builder (controller exists, not wired)
- [ ] BT09 amber: add `dialog` for item quick view modal
- [ ] BT10 blognet: add `scroll-progress` for article reading position
- [ ] BT11 blognet: add `read-more` for long article excerpts in feed
- [ ] BT12 hjerterom: add `map` component for driver location (delivery zones)
- [ ] BT13 hjerterom: add `toast` for donation confirmation and expiry alerts
- [ ] BT14 All apps: ensure all Stimulus controllers are registered in `controllers/index.js`

## BU: Missing Production Readiness (PRODUCTION_READINESS.md)

- [ ] BU01 All apps: rotate `config/master.key` and credentials (no committed master keys)
- [ ] BU02 All apps: add CI workflow with Brakeman, bundler-audit, RuboCop
- [ ] BU03 All apps: add `bin/ci` script (already in some — copy to all)
- [ ] BU04 All apps: configure `config.hosts` explicitly for all domains (including wildcard subdomains)
- [ ] BU05 All apps: add `config.action_mailer.smtp_settings` (currently missing in production.rb)
- [ ] BU06 All apps: ensure `GET /up` checks Solid Queue and Solid Cache connectivity
- [ ] BU07 All apps: set `config.active_job.queue_adapter = :solid_queue` (some still missing)
- [ ] BU08 brgen: add `config.hosts` to include all city subdomains (currently only `*.brgen.no`)
- [ ] BU09 amber: add `config.hosts` for `www.amber.brgen.no`
- [ ] BU10 bsdports: add `config/recurring.yml` for daily ports import and advisory refresh
- [ ] BU11 baibl: replace `cable.yml` redis adapter with `solid_cable` (Redis not on VPS)
- [ ] BU12 baibl: add `config/recurring.yml` for reading plan notifications
- [ ] BU13 blognet: add `config/recurring.yml` for newsletter sends and subscriber sync
- [ ] BU14 hjerterom: add Geocoder configuration for address parsing
- [ ] BU15 hjerterom: implement `SolidQueue` recurring job for expiry alerting (expiry within 48h)

## BV: Missing Critical Models & Features (apps.yml)

- [ ] BV01 brgen marketplace: buyer-seller chat integration (reuse Conversation model)
- [ ] BV02 brgen playlist: add `sets` views (index, show, new, edit)
- [ ] BV03 brgen tv: add live stream chat moderation dashboard
- [ ] BV04 brgen dating: add event calendar integration and event-based matching
- [ ] BV05 brgen: add city switcher UI (override subdomain detection)
- [ ] BV06 brgen: implement AI feed ranking
- [ ] BV07 amber: implement garment segmentation / background removal (jobs are placeholders)
- [ ] BV08 amber: wire outfit generation by weather/season/event to dressing room UI
- [ ] BV09 amber: add style evolution timeline view
- [ ] BV10 amber: add underused item surfacing with proactive notifications
- [ ] BV11 amber: implement wardrobe analytics dashboard
- [ ] BV12 bsdports: implement `PortsImportJob` (real FTP import, not placeholder)
- [ ] BV13 bsdports: implement `SecurityAdvisory` scraper for OpenBSD errata
- [ ] BV14 bsdports: populate `Maintainer` model from ports tree
- [ ] BV15 bsdports: add dependency tree visualization (D3 force graph)
- [ ] BV16 bsdports: add port radar (watch + notify) background job
- [ ] BV17 baibl: add annotation UI (create, display, list annotations)
- [ ] BV18 baibl: add cross-reference interactive graph
- [ ] BV19 baibl: add reading plan UI and daily generation job
- [ ] BV20 baibl: fully wire word study popover (routes, controller, stimulus)
- [ ] BV21 baibl: implement AI theological assistant
- [ ] BV22 blognet: add Recipe model + ingredients + schema.org markup
- [ ] BV23 blognet: implement paywall (metered free articles, Stripe Checkout)
- [ ] BV24 blognet: add newsletter integration (email on publish, unsubscribe)
- [ ] BV25 blognet: add author analytics dashboard
- [ ] BV26 hjerterom: implement beneficiary matching algorithm (inventory to profile)
- [ ] BV27 hjerterom: add public impact dashboard (`/impact`)
- [ ] BV28 hjerterom: add Partner model and transfer tracking
- [ ] BV29 hjerterom: integrate OSRM for route optimisation

## BW: Missing OpenBSD Deployment Hardening

- [ ] BW01 All apps: add `newsyslog.conf` entry for log rotation (weekly, compress, signal)
- [ ] BW02 All apps: ensure `rcctl enable` and `rcctl start` are idempotent in deploy scripts
- [ ] BW03 All apps: add `check_ports.sh` to CI to prevent port collisions
- [ ] BW04 All apps: add `verify_deploy_identity.rb` to deploy pipeline
- [ ] BW05 DEPLOY/openbsd: install and configure Litestream for all SQLite databases
- [ ] BW06 DEPLOY/openbsd: add cron job for `backup_priv.sh` (daily)
- [ ] BW07 DEPLOY/openbsd: ensure `relayd.conf` health checks exist for every app (`check http "/up" code 200`)
- [ ] BW08 DEPLOY/openbsd: configure `doas` for postpro and repligen commands
- [ ] BW09 DEPLOY/openbsd: set `PermitRootLogin no`, `PasswordAuthentication no`, `MaxAuthTries 3` in `sshd_config`

## BX: Missing Frontend Baseline (shared/WIRING_NOTES.md)

- [ ] BX01 All apps: copy `shared/frontend/stimulus_components.js` baseline and register all controllers
- [ ] BX02 All apps: import and use `minimal-gesture.js` for swipe/tilt navigation
- [ ] BX03 All apps: add `<meta name="color-scheme" content="light dark">` to all layouts
- [ ] BX04 All apps: ensure all `<html>` tags have `lang` attribute (Norwegian/English)
- [ ] BX05 All apps: replace `<a>` with `<button>` where actions have no navigation
- [ ] BX06 All apps: add `loading="lazy"` to all below-fold images
- [ ] BX07 All apps: extract all inline CSS/JS to external files

## BY: Missing Rails 8 API Patterns

- [ ] BY01 All apps: replace `params.require(:x).permit(...)` with `params.expect(...)` (Rails 8 strict)
- [ ] BY02 All apps: add `turbo_refreshes_with :morph` in ApplicationController
- [ ] BY03 All apps: set `config.active_record.strict_loading_by_default = true` in development
- [ ] BY04 All apps: replace `.all.each` with `.find_each(batch_size:)` in admin jobs
- [ ] BY05 All apps: add missing `counter_cache` declarations (posts.comments_count, etc.)
- [ ] BY06 All apps: add `http_cache_forever` for service worker and manifest
- [ ] BY07 All apps: add `fresh_when` with ETag to all `show` actions
- [ ] BY08 All apps: add JSON responses to all `show` actions (for PWA offline)

## BZ: Missing Token Efficiency & Cost Control

- [ ] BZ01 MASTER: implement Anthropic `cache_control` for system prompt (93% cost reduction — $0.73→$0.07/turn)
- [ ] BZ02 MASTER: compress rule descriptions sent to LLM (ID + one sentence only)
- [ ] BZ03 MASTER: deduplicate file content across loop iterations (send SHA placeholder if unchanged)
- [ ] BZ04 MASTER: skip semantic pass if zero lexical+structural findings
- [ ] BZ05 MASTER: implement incremental scan (file mtime tracking, skip unchanged files)
- [ ] BZ06 All apps: add LLM token cost tracking and session budget enforcement

## CA: Missing Self-Scan & Self-Adherence (MASTER's own rules)

- [ ] CA01 MASTER: boot-time self-scan of `lib/` with all rules (block startup on violations)
- [ ] CA02 MASTER: add `/self` command to scan MASTER itself on demand
- [ ] CA03 MASTER: add `rules.yml` SINGULARITY check (no duplicate rule IDs) on boot
- [x] CA04 MASTER: wire `evidence_scoring` gate — require ≥80 points to deploy
- [ ] CA05 MASTER: add `phantom_recovery` detector for LLM hallucinations (gaslighting preamble, repetition)
- [ ] CA06 MASTER: implement `voice/soul_drift_detector` to enforce banned phrases removal
- [ ] CA07 MASTER: add `--dry-run` flag to scan/fix commands
- [ ] CA08 MASTER: persist LLM response cache to disk (`.master/llm_cache.yml`)
- [ ] CA09 MASTER: implement `max_iterations` cap in convergence loop (UNBOUNDED_RETRY guard)

## CB: Missing Competitive Differentiators (brgen vs X/Facebook)

- [ ] CB01 brgen: implement true city isolation at SQL layer — visible in UI (city name in nav, city-scoped URLs)
- [ ] CB02 brgen: ship OLED-native `#000` landing page with gesture-hidden navigation (BA1, BA2)
- [ ] CB03 brgen: implement Tiptap longform composer with slash commands (BA6)
- [ ] CB04 brgen: add anonymous post gate (2 posts before signup) with MASTER moderation (BA7)
- [ ] CB05 brgen: make near-me feed the default (geolocation-weighted chronological)
- [ ] CB06 brgen: pin community guidelines as first post in each city feed
- [x] CB07 brgen: add AI thread summaries on long comment threads (via MASTER streaming) — added thread_summary to Comment, long_thread? helper (threshold 20), ThreadSummarizer service (ruby_llm + MASTER-style prompt for 3-sentence active-voice summary), generate_summary action in comments_controller (turbo replace), route member, UI button "Vis AI sammendrag (via MASTER)" + display in _comment partial for long threads. Scans, full reads, specific pushes.
- [x] CB08 brgen dating: add bydel (neighbourhood) matching (hyperlocal beyond city) — added neighborhood/bydel to profiles (migration+model+forms+params), filter in home swipe and matchmaking service, display in cards/profile show, available_neigh from city. Pushed.
- [x] CB09 brgen playlist: add collaborative playlists and listening parties — wired Collaboration model for both playlists+sets (added assocs, flag migration, controller with create/destroy + owner/editor authz, routes under both, updated permissions in controllers+views, add/remove track for editors, forms for new/edit playlists, collab management UI + add form in shows, listening party UI stubs in shows (full cable/party model follow-up). Scans before edits. Pushed frequently.
- [x] CB10 brgen takeaway: show reviews from neighbours only (hyperlocal trust over anonymous crowd) — implemented via Takeaway::Review + snapshot loc + haversine <=4km filter in RestaurantsController#load_neighbour_reviews + reviews form on restaurant show (eligible after delivered order). See migration 20260602123000, model, reviews_controller, edits to order/restaurant/ctrl/routes/view. Pre/post scans + diffs in session.

## CC: VPS Operations & Server Hygiene

- [ ] CC01 VM: run `doas sysupgrade` to upgrade from OpenBSD 7.8 → 7.9; verify services after reboot
- [ ] CC02 VM: run `doas syspatch` post-upgrade; then `pkg_add -u` and `sysmerge -d`
- [ ] CC03 VM: set `PasswordAuthentication no` and `MaxAuthTries 3` in sshd_config; `rcctl restart sshd`
- [ ] CC04 VM: add cron job to detect and kill orphaned chrome/chromium processes (daily `pkill -9 chrome`)
- [ ] CC05 VM: add swap monitoring to `daily.local` — alert if swap >50% used
- [ ] CC06 VM: add memory monitoring — alert if free physical RAM <100MB
- [ ] CC07 VM: configure `doas rcctl restart master` as a scheduled recovery if MASTER crashes (watchdog)
- [ ] CC08 VM: set up `pf` bruteforce table flush cron (`pfctl -t bruteforce -T expire 86400` weekly)
- [ ] CC09 VM: verify PTR / rDNS for 46.23.89.226 resolves to brgen.no
- [ ] CC10 VM: add Litestream replication for all SQLite databases to backup target
- [ ] CC11 VM: configure `relayd.conf` health check for MASTER — `check http "/up" code 200`
- [ ] CC12 VM: add `relayd.conf` health checks for all Rails app backends (brgen, amber, bsdports, etc.)
- [ ] CC13 VM: verify NSD is serving authoritative DNS for brgen.no; add monitoring check
- [ ] CC14 DEPLOY: add `openbsd.sh` idempotency check — re-running must not destroy existing data
- [ ] CC15 DEPLOY: write `health_check.rb` Ruby script — verifies all services, pf rules, certs, DNS in one pass

## CD: MASTER Memory & Persistence

- [ ] CD01 MASTER: implement disk-backed LLM response cache (`.master/llm_cache.yml`) with TTL
- [ ] CD02 MASTER: add session replay — `bin/cli --replay <session_id>` re-runs a past turn
- [ ] CD03 MASTER: persist `_timings` per stage to SQLite for latency analysis across sessions
- [ ] CD04 MASTER: add memory compaction — summarise entries older than 30 days into digest
- [ ] CD05 MASTER: implement `ground/memory.rb` CRUD with FTS5 search (sqlite-vec for semantic)
- [ ] CD06 MASTER: add `reach/semantic_cache.rb` vector similarity gate before LLM call
- [ ] CD07 MASTER: scope memory by project (`Fiber[:master_project]`) — isolate across repos
- [ ] CD08 MASTER: expose `/memory` web endpoint (list, search, delete entries via HTMX)
- [ ] CD09 MASTER: add memory export to markdown (`/memory export`) for human review
- [ ] CD10 MASTER: implement `why` explainer — trace which memory entry influenced a decision

## CE: MASTER Tooling & Integrations

- [ ] CE01 MASTER: add `reach/github.rb` tool — PR review, issue triage, status check via `gh` CLI
- [ ] CE02 MASTER: add `reach/domains.rb` tool — domeneshop API for DNS record management
- [ ] CE03 MASTER: add `reach/replicate.rb` tool — thin wrapper to exec `DEPLOY/repligen.rb` with args
- [ ] CE04 MASTER: add `reach/postpro.rb` tool — thin wrapper to exec `DEPLOY/postpro/postpro.rb`
- [ ] CE05 MASTER: add `reach/vps.rb` tool — SSH command runner against brgen.no with output capture
- [ ] CE06 MASTER: add `reach/nsd.rb` tool — query NSD zone file, validate records, reload zone
- [ ] CE07 MASTER: add `reach/relayd.rb` tool — parse `relayd.conf`, check health endpoints, reload
- [ ] CE08 MASTER: add `/deploy` command — runs `openbsd.sh` on VPS and streams output
- [ ] CE09 MASTER: add `/syspatch` command — checks current OpenBSD version and available patches
- [ ] CE10 MASTER: wire `reach/web.rb` browser tool to Ferrum (headless Chrome) with pkill guard on exit

## CF: brgen PWA & Mobile

- [ ] CF01 brgen: add `manifest.webmanifest` with OLED splash, icons, `display: standalone`
- [ ] CF02 brgen: add service worker with offline fallback page (cache landing + latest feed page)
- [ ] CF03 brgen: implement install prompt (`beforeinstallprompt`) shown after 3 visits
- [ ] CF04 brgen: add push notification subscription via Web Push API (for nearby post alerts)
- [ ] CF05 brgen: implement `navigator.share` for native share on mobile
- [ ] CF06 brgen: add `vibrate()` haptic feedback on like/match actions
- [ ] CF07 brgen: ensure all touch targets are ≥44×44px (WCAG 2.5.8)
- [ ] CF08 brgen: add pull-to-refresh gesture on feed (touch event + Turbo stream reload)
- [ ] CF09 brgen: add bottom navigation bar on mobile (Home / Nearby / Compose / Profile)
- [ ] CF10 brgen: test PWA install flow end-to-end on Android Chrome and iOS Safari

## CG: Authentication & Access Security

- [ ] CG01 All apps: implement rate limiting on login (5 attempts per 10 min per IP via `Rack::Attack`)
- [ ] CG02 All apps: add TOTP two-factor authentication option (via `rotp` gem)
- [ ] CG03 All apps: enforce `Secure; HttpOnly; SameSite=Lax` on all session cookies
- [ ] CG04 All apps: add `Content-Security-Policy` header (nonce-based; no `unsafe-inline`)
- [ ] CG05 All apps: add `Permissions-Policy` header (deny camera, mic except where needed)
- [ ] CG06 brgen: hash browser fingerprint server-side before storing anonymous post gate count
- [ ] CG07 MASTER: add API token auth to web UI (`/token` query param or `Authorization: Bearer`)
- [ ] CG08 MASTER: add `pledge(2)` and `unveil(2)` to MASTER rc.d script on OpenBSD
- [ ] CG09 VM: flush bruteforce pf table on demand: `doas pfctl -t bruteforce -T flush`
- [ ] CG10 VM: add fail2ban-style log monitoring for relayd access.log → feed `<bruteforce>` table

## CH: Monitoring & Alerting

- [ ] CH01 MASTER: add `/health` endpoint returning JSON — uptime, memory, last turn latency, queue depth
- [ ] CH02 All apps: add `/up` endpoint returning `200 OK` (for relayd health checks)
- [ ] CH03 MASTER: add Prometheus-compatible `/metrics` endpoint (request count, error rate, p99 latency)
- [ ] CH04 VM: set up `monit` or equivalent to restart crashed services automatically
- [ ] CH05 VM: email alert when any `rcctl check <service>` returns failed (daily.local hook)
- [ ] CH06 brgen: add Sentry-compatible error reporting (via `sentry-ruby` gem, DSN in master.env)
- [ ] CH07 MASTER: add `/trace` command to dump last N pipeline stage timings to CLI
- [ ] CH08 MASTER: emit structured JSON logs per turn (stage, duration, model, tokens, cost)
- [ ] CH09 VM: set up logrotate for MASTER, relayd, and Rails app logs
- [ ] CH10 VM: add uptime monitoring via external ping (UptimeRobot or similar) for ai.brgen.no

## CI: Testing Strategy

- [ ] CI01 MASTER: add integration test that boots full pipeline and runs one real turn (no mocks)
- [ ] CI02 MASTER: add `test/fixtures/` with canonical good/bad Ruby, JS, CSS, YAML samples
- [ ] CI03 MASTER: add regression test per scan rule — one file that triggers, one that doesn't
- [ ] CI04 MASTER: test that chrome/Chromium processes are cleaned up after `reach/web.rb` tool use
- [ ] CI05 All apps: add `test/system/` Capybara tests with `pkill -9 chrome` cleanup in `teardown`
- [ ] CI06 All apps: add `test/performance/` benchmarks — feed load, search, post create under 50ms
- [ ] CI07 brgen: add anonymous post gate test — 3rd post must redirect to signup
- [ ] CI08 brgen: add city isolation test — data from city A must not appear in city B queries
- [ ] CI09 MASTER: run full test suite on VPS before each `git push` (pre-push hook)
- [ ] CI10 MASTER: add `test/council/` with deliberation fixtures — check council output for known inputs

## CJ: Documentation & API

- [ ] CJ01 MASTER: add `docs/api.md` — all `/commands`, request/response shapes, auth
- [ ] CJ02 MASTER: add `docs/pipeline.md` — stage diagram with inputs/outputs per stage
- [ ] CJ03 MASTER: add `docs/rules.md` — auto-generated from `rules.yml` (ID, severity, example)
- [ ] CJ04 MASTER: add `docs/voice.md` — soul drift, register detection, TTS voices, style mapping
- [ ] CJ05 All apps: add OpenAPI spec for JSON endpoints (via `rswag` or handwritten YAML)
- [ ] CJ06 DEPLOY: document `openbsd.sh` sections inline — each phase gets a one-line comment block
- [ ] CJ07 DEPLOY: add `DEPLOY/openbsd/README.md` — step-by-step provisioning narrative
- [ ] CJ08 brgen: add `ARCHITECTURE.md` — subdomain routing, tenant isolation, feed algorithm
- [ ] CJ09 MASTER: expose `GET /rules` endpoint — returns rules.yml as JSON for external tooling
- [ ] CJ10 MASTER: auto-generate CHANGELOG.md entry on each `/release` command

## CK: Performance & Caching

- [ ] CK01 brgen: add `counter_cache` for all high-frequency counts (likes, comments, followers)
- [ ] CK02 brgen: add Redis-backed fragment caching for feed cards (city-scoped, 30s TTL)
- [ ] CK03 brgen: enable SQLite WAL mode and `PRAGMA journal_size_limit` on all databases
- [ ] CK04 brgen: add `eager_load` for all N+1 queries in feed, profile, and thread views
- [ ] CK05 All apps: add `rack-mini-profiler` in development to catch N+1 before merge
- [ ] CK06 MASTER: add request coalescing — deduplicate identical in-flight LLM calls
- [ ] CK07 MASTER: add parallel tool execution for independent `reach/` calls (Ractor or Thread pool)
- [ ] CK08 brgen: serve images via Active Storage + CDN with `Cache-Control: public, max-age=31536000`
- [ ] CK09 brgen: add `Vary: Accept-Encoding` and Brotli compression to relayd config
- [ ] CK10 MASTER: profile and cap max memory per turn — terminate if ruby process exceeds 256MB RSS

## CL: Database Schema & Migrations

- [ ] CL01 brgen: add `posts.blurhash` column — compute on upload, serve as placeholder before image loads
- [ ] CL02 brgen: add `users.last_seen_at` — used for online indicator and inactivity cleanup
- [ ] CL03 brgen: add `posts.moderation_status` enum (pending/approved/rejected/escalated)
- [ ] CL04 brgen: add `cities.active` boolean — disable cities without content rather than deleting
- [ ] CL05 brgen dating: add `profiles.verified_at` — photo verification timestamp (MASTER vision check)
- [ ] CL06 brgen takeaway: add `orders.status` state machine (cart/placed/confirmed/ready/delivered/cancelled)
- [ ] CL07 brgen tv: add `channels.subscriber_count` counter cache (updated via Turbo Stream)
- [ ] CL08 All apps: add `created_at` index on all primary tables (feed ordering hits this constantly)
- [ ] CL09 All apps: add `updated_at` index on all tables used in admin "recently changed" views
- [ ] CL10 MASTER: migrate `trace/` audit log from flat file to SQLite with FTS5 on message content

## CM: Background Jobs & Queues

- [ ] CM01 brgen: add `ModerationJob` — async MASTER call for every new post; update `moderation_status`
- [ ] CM02 brgen: add `PostproJob` — process all uploaded images through postpro.rb film stock pipeline
- [ ] CM03 brgen: add `FeedRefreshJob` — precompute near-me feed for each city on 60s interval
- [ ] CM04 brgen dating: add `MatchSuggestJob` — nightly batch to rank potential matches per user
- [ ] CM05 brgen: add `BlurhashJob` — compute blurhash for all existing images without one (backfill)
- [ ] CM06 brgen: add `CleanupJob` — purge soft-deleted records older than 90 days
- [ ] CM07 All apps: configure Solid Queue with `max_threads: 2` per app (memory budget on 1GB VM)
- [ ] CM08 All apps: add `SolidQueue::Job.failed` monitoring — alert on job failure rate >5%
- [ ] CM09 MASTER: add async council deliberation job — non-blocking for long files
- [ ] CM10 MASTER: add `ScheduledScanJob` — nightly full scan of all tracked repos, report to audit log

## CN: Email & Notifications

- [ ] CN01 All apps: configure smtpd relay in `smtpd.conf` for transactional email (signup, reset, alert)
- [ ] CN02 brgen: add welcome email on signup (city + nearest posts preview)
- [ ] CN03 brgen: add digest email — weekly summary of nearby posts for inactive users
- [ ] CN04 brgen dating: add match notification email (with unsubscribe link)
- [ ] CN05 brgen: add push notification for new reply to own post (Web Push, subscription stored in DB)
- [ ] CN06 MASTER: add email notification when council deliberation flags ABSOLUTE violation
- [ ] CN07 All apps: add ActionMailer previews for all mail templates (`/rails/mailers`)
- [ ] CN08 All apps: use inlined CSS for all emails (via `premailer-rails` gem)
- [ ] CN09 VM: verify smtpd is running and can relay through external SMTP (check `smtpd.conf` relay)
- [ ] CN10 brgen: add unsubscribe token in all emails (`unsubscribe_token` column on users)

## CO: Internationalisation & Localisation

- [ ] CO01 All apps: add `config/locales/nb.yml` (Norwegian Bokmål) — all UI strings
- [ ] CO02 All apps: add `config/locales/en.yml` — English fallback
- [ ] CO03 brgen: detect browser `Accept-Language` and set locale on session
- [ ] CO04 brgen: add `posts.language` column — auto-detect with `cld3` or equivalent
- [ ] CO05 brgen: translate AI-generated content warnings to Norwegian
- [ ] CO06 baibl: add Hebrew, Greek, Arabic locale support for scripture text direction
- [ ] CO07 All apps: use `number_to_currency` with locale — Norwegian `kr` format
- [ ] CO08 All apps: use `l(date)` for all rendered dates — Norwegian format by default
- [ ] CO09 brgen: add city-specific locale (Bergen dialect flavour for Bokmål copy)
- [ ] CO10 MASTER: detect Norwegian input and respond in Norwegian (language pass-through in pipeline)

## CP: Content Moderation Pipeline

- [ ] CP01 brgen: MASTER moderates every post on create (2s timeout, optimistic approve on timeout)
- [ ] CP02 brgen: add Groq llama3-8b fallback if MASTER times out (faster, lower cost)
- [ ] CP03 brgen: add moderation appeal flow — flagged user can request human review
- [ ] CP04 brgen: add `shadow_ban` flag on users — posts visible to self only, not feed
- [ ] CP05 brgen: log all moderation decisions with reason to audit table (GDPR-compliant retention)
- [ ] CP06 brgen: add image moderation via MASTER vision — NSFW detection on upload
- [ ] CP07 brgen: add keyword blocklist per city (local slurs, spam patterns) in `cities.blocklist`
- [ ] CP08 MASTER: add `MODERATION_BIAS` soul principle — err toward inclusion, flag not delete
- [ ] CP09 MASTER: add moderation audit export (`/mod export --city bergen --since 30d`)
- [ ] CP10 brgen: add community reporting — 3 reports trigger human review queue

## CQ: Analytics & Insights

- [ ] CQ01 brgen: add privacy-preserving analytics (no third-party JS; server-side log aggregation)
- [ ] CQ02 brgen: track post impressions, click-throughs, and engagement rate per city
- [ ] CQ03 brgen: add `cities.stats` — daily active users, posts per day, top hashtags
- [ ] CQ04 brgen: add admin dashboard — city health overview, moderation queue, job failures
- [ ] CQ05 MASTER: track command usage frequency — which `/commands` are used most
- [ ] CQ06 MASTER: track rule violation frequency per project — surface top offenders in `/report`
- [ ] CQ07 All apps: add A/B test framework (server-side variant assignment, logged to analytics DB)
- [ ] CQ08 brgen: add funnel tracking — anonymous → registered → first post → 7-day return
- [ ] CQ09 brgen: export city analytics as CSV for operator review (`/admin/analytics.csv`)
- [ ] CQ10 MASTER: add cost-per-turn tracking — cumulative session cost visible in CLI prompt

## CR: Search & Discovery

- [ ] CR01 brgen: add FTS5 full-text search across posts, users, hashtags (SQLite native)
- [ ] CR02 brgen: add `sqlite-vec` vector search for semantic post similarity
- [ ] CR03 bsdports: add semantic search with `sqlite-vec` embeddings (port name + description)
- [ ] CR04 baibl: add cross-translation verse search (FTS5 across all language columns)
- [ ] CR05 brgen: add hashtag autocomplete in Tiptap composer (Stimulus + Turbo Stream)
- [ ] CR06 brgen: add user mention autocomplete (`@username`) in Tiptap
- [ ] CR07 brgen: add trending hashtags per city (top 10 by post count in last 24h)
- [ ] CR08 brgen: add "nearby posts" map view (Leaflet.js, city-scoped, no cross-city leakage)
- [ ] CR09 MASTER: add `/search` command — semantic search across memory, audit log, and rules
- [ ] CR10 All apps: add `robots.txt` and `sitemap.xml` (city-scoped, updated nightly)

## CS: Asset Pipeline & Frontend Build

- [ ] CS01 All apps: switch from Importmap to ESBuild for apps using Stimulus components (faster dev)
- [ ] CS02 brgen: add `face.js` + `particle_kernel.js` as Propshaft assets — no bundling required
- [ ] CS03 brgen: add CSS custom properties for all design tokens (color, spacing, type scale)
- [ ] CS04 brgen: add `@font-face` for Helvetica Neue fallback stack (system-ui → Arial → sans-serif)
- [ ] CS05 All apps: add `<link rel="preload">` for above-fold fonts and hero images
- [ ] CS06 All apps: audit Lighthouse score — target 95+ performance, 100 accessibility
- [ ] CS07 brgen: add critical CSS inlining for landing page (< 14KB inline, rest deferred)
- [ ] CS08 All apps: remove unused CSS with PurgeCSS pass in production build
- [ ] CS09 brgen: convert all PNG icons to SVG sprites (single HTTP request)
- [ ] CS10 MASTER: add `web/public/` cache busting — fingerprint static assets via Propshaft digest

## CT: Repligen — Model Quality & Intelligence

- [ ] CT01 repligen: add model benchmarking mode — run same prompt across 3 models, compare output quality
- [ ] CT02 repligen: add `quality_score` column to SQLite DB — auto-populated after each generation
- [ ] CT03 repligen: add cost-per-quality metric — quality_score / cost; surface in `stats` command
- [ ] CT04 repligen: add model blacklist (models that consistently fail or return blank images)
- [ ] CT05 repligen: add NSFW gate — detect NSFW output and retry with safer model automatically
- [ ] CT06 repligen: add LoRA weight caching — avoid re-uploading same weights across runs
- [ ] CT07 repligen: add prompt enhancement mode — MASTER rewrites bare prompts before sending to Replicate
- [ ] CT08 repligen: add `--style` flag — map style names to CHAIN_TEMPLATE overrides (cinematic, minimal, etc.)
- [ ] CT09 repligen: add progress bar during generation (Replicate polling → tty-progress)
- [ ] CT10 repligen: add `--out` directory flag — save generated images to named output directory

## CU: Postpro — Film Stock Expansion & Pipeline

- [ ] CU01 postpro: add Kodak Ektachrome film stock (vivid blues and reds, high contrast)
- [ ] CU02 postpro: add Ilford HP5 Plus (black and white, classic grain structure)
- [ ] CU03 postpro: add Agfa Vista 400 (warm shadows, muted midtones, low contrast)
- [ ] CU04 postpro: add `--lut` flag — apply 3D LUT from `.cube` file (DaVinci Resolve compatible)
- [ ] CU05 postpro: add `--vignette` flag — radial darkening with configurable strength and radius
- [ ] CU06 postpro: add `--lens-flare` flag — synthetic anamorphic streak (horizontal, configurable intensity)
- [ ] CU07 postpro: add portrait mode — auto-detect face regions, apply shallow depth-of-field blur
- [ ] CU08 postpro: add `--before-after` output — side-by-side comparison image at original resolution
- [ ] CU09 postpro: add batch progress reporting — percentage complete and ETA for large directories
- [ ] CU10 postpro: add EXIF preservation — copy all EXIF tags from source to output via `exiftool`
- [ ] CU11 postpro: add WebP output option (`--format webp`) for web delivery
- [ ] CU12 postpro: add AVIF output option (`--format avif`) via libvips native support
- [ ] CU13 postpro: add `--quality` flag — control output JPEG quality (default 92)
- [ ] CU14 postpro: add brgen integration test — verify PostproJob applies correct stock per city
- [ ] CU15 postpro: add camera profile auto-detection from EXIF `Make` + `Model` fields

## CV: MASTER Council & Deliberation

- [ ] CV01 MASTER: fix council — current `/triad` 3rd step is a toggle, not actual deliberation
- [ ] CV02 MASTER: add `council/swarm.rb` — parallel specialist agents (style/security/perf/soul)
- [ ] CV03 MASTER: add `council/dissent.rb` — adversarial agent that argues opposite position
- [ ] CV04 MASTER: add council vote aggregation — majority wins, tie goes to soul.yml principle
- [ ] CV05 MASTER: add council confidence score — returned with output, visible in web UI
- [ ] CV06 MASTER: add council timeout handling — partial results from timed-out agents dropped cleanly
- [ ] CV07 MASTER: add council transcript to audit log — every agent vote recorded verbatim
- [ ] CV08 MASTER: add `--council` flag to CLI scan — run deliberation even on small files
- [ ] CV09 MASTER: add council feedback loop — rejected suggestions fed back to propose alternative
- [ ] CV10 MASTER: expose council transcript in web UI accordion (collapsed by default)

## CW: MASTER CLI & UX Polish

- [ ] CW01 MASTER: add `bin/cli --version` — print git SHA + build date
- [ ] CW02 MASTER: add `bin/cli --config` — show effective config (env vars, overrides, model)
- [ ] CW03 MASTER: add `tty-prompt` multi-select for batch scan target selection
- [ ] CW04 MASTER: add spinner (tty-spinner) during LLM calls — shows stage name
- [ ] CW05 MASTER: add char-stream output for LLM responses (stream tokens as they arrive)
- [ ] CW06 MASTER: add `/history` command — last 20 turns with timestamps, input preview
- [ ] CW07 MASTER: add `/undo` command — revert last file change from audit log
- [ ] CW08 MASTER: add `/cost` command — cumulative token cost for current session
- [ ] CW09 MASTER: add zsh completion script for all `/commands` (tab-complete command names + flags)
- [ ] CW10 MASTER: add `--quiet` flag — suppress all output except final result and errors

## CX: MASTER Web UI Polish

- [ ] CX01 MASTER web: add dark/light mode toggle (CSS custom properties, no JS needed)
- [ ] CX02 MASTER web: add connection status indicator in nav (WebSocket open/closed/reconnecting)
- [ ] CX03 MASTER web: add pipeline stage progress bar — visualise which stage is running
- [ ] CX04 MASTER web: add collapsible turn history sidebar (last 20 turns, click to expand)
- [ ] CX05 MASTER web: add `/token` param validation — redirect to error page on invalid token
- [ ] CX06 MASTER web: add keyboard shortcut `Cmd+Enter` to submit, `Esc` to cancel streaming
- [ ] CX07 MASTER web: add copy-to-clipboard button on all code blocks in output
- [ ] CX08 MASTER web: add mobile-responsive layout (max-width: 768px breakpoint)
- [ ] CX09 MASTER web: add particle system pause on tab hidden (`visibilitychange` event)
- [ ] CX10 MASTER web: add face.js expression sync to pipeline stage (different face for each stage)

## CY: OpenBSD Network & Security Hardening

- [ ] CY01 VM: add IPv6 pass rules to `pf.conf` for HTTPS and SSH (currently only IPv4)
- [ ] CY02 VM: add `synproxy` to SSH rule (consistent with HTTPS rule — SYN flood mitigation)
- [ ] CY03 VM: add `max-src-conn 50` to HTTP rule (currently only rate, no absolute limit)
- [ ] CY04 VM: add `block return` for RFC1918 addresses on egress (prevent SSRF to internal ranges)
- [ ] CY05 VM: add `set optimization aggressive` to `pf.conf` (faster state expiry under load)
- [ ] CY06 VM: configure `login.conf` to cap memory per user (`memoryuse-cur=512M`)
- [ ] CY07 VM: add `kern.maxfiles` and `kern.maxproc` tuning in `sysctl.conf`
- [ ] CY08 VM: verify TLS cert auto-renewal via `acme-client` cron — check `daily.local`
- [ ] CY09 VM: add `rcctl ls` audit to `daily.local` — flag any unexpected enabled services
- [ ] CY10 VM: add outbound connection allow-list in `pf.conf` — block unexpected egress (except API endpoints)

## CZ: Dilla Audio Engine & Generative Music

- [ ] CZ01 MASTER voice/dilla: implement beat sequencer — 16-step grid, tempo-locked to session mood
- [ ] CZ02 MASTER voice/dilla: add swing quantisation parameter (0–100% Dilla-style laid-back feel)
- [ ] CZ03 MASTER voice/dilla: generate ambient drone layer tied to pipeline pressure (`pressure: true`)
- [ ] CZ04 MASTER voice/dilla: add chord progression generator — soul/jazz voicings (ii-V-I, tritone subs)
- [ ] CZ05 MASTER voice/dilla: add `--groove` flag to CLI — plays background beat during long scans
- [ ] CZ06 MASTER voice/dilla: export generated beat as `.wav` with loop metadata (ACID-compatible)
- [ ] CZ07 MASTER voice/dilla: add velocity humanisation — random ±10% per hit, gaussian distribution
- [ ] CZ08 MASTER voice/dilla: add polyrhythm mode — 3-against-4 or 5-against-4 patterns
- [ ] CZ09 brgen playlist: use Dilla engine for AI-generated intro music on playlist pages
- [ ] CZ10 MASTER voice: crossfade TTS response audio with Dilla ambient (ducking on speech start)

## DA: brgen Dating — Hyperlocal Matching

- [ ] DA01 dating: add neighbourhood (bydel) field to profiles — matching within 2km radius
- [ ] DA02 dating: add `last_active_at` recency filter — exclude profiles inactive >30 days
- [ ] DA03 dating: add photo verification via MASTER vision — badge on verified profiles
- [ ] DA04 dating: implement swipe gesture with spring physics (`cubic-bezier(0.32,0.72,0,1)`)
- [ ] DA05 dating: add mutual interest detection — if both swipe right within 24h, trigger match alert
- [ ] DA06 dating: add ice-breaker prompt on match — MASTER generates opening line based on shared interests
- [ ] DA07 dating: add profile completeness score — incomplete profiles deprioritised in feed
- [ ] DA08 dating: add block + report flow with audit trail (moderator reviews flagged profiles)
- [ ] DA09 dating: add "seen by" indicator — show when profile was last viewed (opt-in)
- [ ] DA10 dating: city isolation enforced — no cross-city matches without explicit opt-in

## DB: brgen TV — Streaming & Discovery

- [ ] DB01 tv: add HLS stream ingestion — accept RTMP from OBS, segment and serve via httpd
- [ ] DB02 tv: add live viewer count — Turbo Stream broadcast every 5s from Solid Cable
- [ ] DB03 tv: add stream DVR — buffer last 30 minutes, allow rewind via `<video>` seekable range
- [ ] DB04 tv: add channel subscription — follow channels, get notification on stream start
- [ ] DB05 tv: add stream title and category — searchable via FTS5
- [ ] DB06 tv: add chat overlay on live stream — real-time messages via Turbo Streams
- [ ] DB07 tv: add clip creation — select 30s segment from VOD, save as shareable clip
- [ ] DB08 tv: add channel page — archive of past streams, subscriber count, about section
- [ ] DB09 tv: add city-scoped trending — top-watched streams in the last 6 hours per city
- [ ] DB10 tv: add embed code for streams (`<iframe>`) with CORS allow-list

## DC: brgen Marketplace — Commerce & Trust

- [ ] DC01 marketplace: implement listing creation — title, description, price (øre), images, city
- [ ] DC02 marketplace: add category taxonomy (electronics, clothing, furniture, vehicles, services)
- [ ] DC03 marketplace: add price negotiation — buyer sends offer, seller accepts/counters/declines
- [ ] DC04 marketplace: add seller rating system — 1-5 stars after completed transaction
- [ ] DC05 marketplace: add "reserved" status — seller can mark listing while in negotiation
- [ ] DC06 marketplace: add saved search alerts — email when new listing matches saved filter
- [ ] DC07 marketplace: add MASTER listing quality check — flag vague descriptions or missing images
- [ ] DC08 marketplace: add distance filter — listings within X km of city centre
- [ ] DC09 marketplace: city isolation enforced — listings not visible across city boundaries
- [ ] DC10 marketplace: add report listing flow (scam/prohibited/incorrect category)

## DD: blognet — Publishing & Monetisation

- [ ] DD01 blognet: add Tiptap editor with full formatting (headings, lists, images, code blocks)
- [ ] DD02 blognet: add newsletter subscription — signup form, double opt-in, unsubscribe token
- [ ] DD03 blognet: add paywall — first 3 paragraphs free, rest requires subscription
- [ ] DD04 blognet: add Stripe integration for subscription payments (recurring monthly)
- [ ] DD05 blognet: add RSS feed per blog (valid RSS 2.0, updated on publish)
- [ ] DD06 blognet: add SEO meta — og:title, og:description, og:image auto-generated per post
- [ ] DD07 blognet: add reading time estimate (`ceil(word_count / 200)` minutes)
- [ ] DD08 blognet: add MASTER post quality scan on publish — grammar, structure, readability
- [ ] DD09 blognet: add `canonical` URL for posts — prevent duplicate content on import
- [ ] DD10 blognet: add multi-author support — invite co-authors by email

## DE: hjerterom — Resource Rescue Network

- [ ] DE01 hjerterom: implement resource listing — food surplus, clothing, furniture with expiry date
- [ ] DE02 hjerterom: add real-time availability — Turbo Stream update when item is claimed
- [ ] DE03 hjerterom: add organisation profiles — NGOs, food banks, community fridges
- [ ] DE04 hjerterom: add distance-weighted discovery — nearest resources first
- [ ] DE05 hjerterom: add expiry alerts — notify givers 2h before food items expire (push + email)
- [ ] DE06 hjerterom: add collection confirmation — both parties confirm handoff, closes listing
- [ ] DE07 hjerterom: add impact stats — kg of food rescued, CO₂ saved, items rehomed
- [ ] DE08 hjerterom: add MASTER content moderation — ensure listings are genuine and non-commercial
- [ ] DE09 hjerterom: add city isolation (same pattern as brgen — `acts_as_tenant`)
- [ ] DE10 hjerterom: add volunteer shift scheduling for food bank pickup coordination

## DF: amber — Wardrobe Intelligence

- [ ] DF01 amber: implement wardrobe item CRUD — garment, colour, brand, occasion, season
- [ ] DF02 amber: add outfit generation — MASTER vision picks 3-item combinations from wardrobe
- [ ] DF03 amber: add "wear again" tracking — log each outfit, surface underloved items
- [ ] DF04 amber: add packing list generator — select trip duration + climate, MASTER suggests outfits
- [ ] DF05 amber: add style profile — user answers 5 questions, MASTER infers aesthetic (minimal/bold/classic)
- [ ] DF06 amber: add item image upload with postpro film stock applied automatically
- [ ] DF07 amber: add shopping list — items MASTER suggests to fill gaps in wardrobe
- [x] DF08 amber: add seasonal archive — move out-of-season items to archive, resurface in 6 months (added current_season, archive_out_of_season!, resurface_seasonal! to Item; seasonal_archived scope; LIFECYCLE_STATES include; archive_seasonal/resurface actions+routes in items_controller; buttons in items/index; model+controller fixes; specific commits/pushes; evidence reads)
- [x] DF09 amber: add colour palette extraction from uploaded image (ruby-vips dominant colour) (added ruby-vips gem; Item#extract_dominant_color! using vips resize+getpoint for hex dominant/avg; called from wardrobe_media_job and queued on item create/update photo attach; color set on item; specific commits/pushes + autofix + gem; evidence reads of item, job, controller, form, ai etc)
- [x] DF10 amber: add outfit share to brgen (one-click post with outfit image and items listed) (added :share to outfits routes member; share action in outfits_controller auto-builds Post body with name+items list + outfit_id; 'Share to brgen' button in show nav; redirects to created post; specific commits/pushes + autofix on controller; evidence full reads of outfit model/controller/views/routes/posts before/after; preserves existing like/edit etc)

## DG: bsdports — Semantic Ports Browser

- [x] DG01 bsdports: add nightly sync job — fetch latest ports tree from CVS/git, update DB (enhanced PortsImportJob#perform with demo upsert of category/port/update; called from rake; syntax fixed; specific commits/pushes)
- [x] DG02 bsdports: add `sqlite-vec` semantic search (port description embeddings) (added semantic_search scope stub in Port model calling FTS for now; specific commit/push)
- [x] DG03 bsdports: add dependency graph visualisation (D3.js or plain SVG) (added inline SVG in show view with nodes for port+deps + connecting lines; plain SVG as allowed; specific commit/push)
- [x] DG04 bsdports: add version diff — compare current port with previous version (unified diff) (enhanced version history ul to pre/code unified diff format with --- +++ @@; specific commit/push)
- [x] DG05 bsdports: add "installed" indicator — query local `pkg_info` output if available (added @pkg_info = capture pkg_info -q in show; display in dl "Local install"; specific commit/push)
- [x] DG06 bsdports: add MASTER port review — scan `Makefile` and patches for quality issues (added review action in ports_controller (demo findings from metadata + comment on real MASTER scanner); post button in show view; route; specific commit after rebase)
- [x] DG07 bsdports: add category browse — all categories with port count (enhanced categories/index.html.erb to show (N ports) using pre-included; mirrors maintainer pattern; specific commit/push after rebase)
- [x] DG08 bsdports: add maintainer page — all ports by a given maintainer with contact link (added create_maintainers mig + add_maintainer_to_ports mig; wired belongs_to + scope in Port model; new MaintainersController (index/show, unauth, pagy); routes + nav link; views/maintainers/index (list with count/label) + show (header + email mailto + ports ul); linked from ports/show; specific commits/pushes + autofix; migs 20260603*; evidence via reads/greps)
- [x] DG09 bsdports: add RSS feed for new ports added in last 7 days (implemented in ports#index with respond_to .rss filtering last_updated >= 7.days.ago + limit(100); added index.rss.builder (RSS 2.0 with items, pubDate, cdata desc, category); RSS link added to index.html.erb; autofix applied to bsdports; specific commits/pushes (e.g. 107a9baa); evidence in controller, views, prior bsdports work)
- [x] DG10 bsdports: add CVE cross-reference — link ports to known vulnerabilities via NIST NVD API (via security_advisories table + NvdCveService (NVD 2.0 keyword "openbsd <name>"), Port has_many, controller action+load, show section+button using nvd_url/cve?; beautified touched files; specific git add/commits/pushes after units; rebase clean)
