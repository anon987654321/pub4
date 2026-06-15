# TODO — MASTER contract backlog

Active contract only. Full historical backlog archived at `docs/archive/TODO-full-2026-06-15.md`.
Research sections (O–AM, BF–PH, etc.) are opinions/backlog — not execution contract.

Work left to right. Mark done with `[x]` only after verified behavior.


## F. Architecture violations in MASTER's own code

MASTER must pass its own rules. Violations found by reading lib/.

- [x] F01 scanner.rb#scan: 35-line method — split into read_file, parse_ast, apply_rules, publish (SRP + SMALL_FUNCTIONS)
- [x] F02 DetectionPipeline: shallow relay class adds no abstraction (DIFFERENT_LAYER_DIFFERENT_ABSTRACTION) — merge into Scanner or delete
- [x] F03 RuleLoop: council_fix and request_fix duplicate prompt-building logic (DRY) — extract build_prompt_for(violation, src, path, style:)
- [x] F04 pipeline.rb#maybe_rollback: git stash logic in Pipeline violates SRP — extract to Loop::Rollback class
- [x] F05 memory.rb: 256 lines (SMALL_FILES) — split into Memory::Store, Memory::Search, Memory::Consolidate modules
- [x] F06 repo_ecology.rb: analyze_file returns 12-key Hash (DATA_CLASS) — introduce FileRecord = Data.define(...)
- [x] F07 ground/constitution.rb: load_yaml called on every invocation — memoize with @constitution_cache (IMMUTABLE)
- [x] F08 master.rb#bootstrap_container: 50+ line method — split into init_ground, init_judge, init_loop, init_reach
- [x] F09 scanner.rb parallel_each: raw Thread.new without error boundary — wrap in rescue and publish thread_error
- [x] F10 rule_loop.rb#preamble: reads soul.yml on every call — memoize (pure function same input = same output)
- [x] F11 pipeline.rb ParallelGroup#merge_results: uses filter_map + reduce on results — simplify (KISS)
- [x] F12 repo_ecology.rb: co_change_graph built twice (once in snapshot, once in scan) — always use memoized accessor
- [x] F13 judge/agent.rb: verify method count ≤10 public methods (NO_GOD_CLASS threshold)
- [x] F14 now/context_window.rb: verify no god class
- [x] F15 loop/rule_loop.rb: CANDIDATE_COUNT=3 magic number — name as semantic constant with comment (NO_MAGIC)
- [x] F16 ground/memory.rb: MAX_INJECT_TOKENS = 2000 used as token limit — verify against actual model context size
- [x] F17 reach/llm.rb: verify no hardcoded API keys (SECRET_PROXIMITY)
- [x] F18 All lib/**/*.rb: verify zero Marshal.load (anti_patterns.forbidden)
- [x] F19 All lib/**/*.rb: verify zero `open(.*#{` shell-through-open (anti_patterns.forbidden)
- [x] F20 All lib/**/*.rb: verify zero `system(.*#{` command injection patterns (UNSAFE_CALLS)
- [x] F21 All lib/**/*.rb: check for mutable constants missing .freeze (IMMUTABLE)
- [x] F22 All lib/**/*.rb: check for long chains a.b.c.d.e not covered by existing rule exclusions (LAW_OF_DEMETER)
- [x] F23 All lib/**/*.rb: check for 3+ positional args needing keyword conversion (FEW_ARGUMENTS)
- [x] F24 loop/fix_helpers.rb: read and verify SRP — only fix-related helpers, no scanning logic
- [x] F25 judge/scan/rule_dsl.rb: verify auto_build? pattern documented (SELF_EXPLAINING)


## G. Voice and personality alignment

rules.yml voice section must govern MASTER's own outputs.

- [x] G01 Anti-simulation: add forbidden word filter (will, would, could, might) to prompts MASTER sends to LLM
- [x] G02 Strunk preambles: strip "In summary,", "Consequently,", "Therefore," from MASTER's own output generation
- [x] G03 Strunk hedges: strip "I think that", "I believe", "seems", "appears" from MASTER output
- [x] G04 Strunk endings: strip "as a result.", "for this reason.", "thus." from MASTER output
- [x] G05 Banned output: enforce no headlines/bullet_lists_without_content/filler_phrases in voice/personality.rb
- [x] G06 Inverted pyramid: MASTER's scan reports lead with outcome, then evidence, then detail
- [x] G07 Boot message: verify 5-line dmesg style; never collapse to 1 line, never expand beyond 5
- [x] G08 Silence on success: verify routine completions emit one line max
- [x] G09 Diagnostic output: multi-line structured output is intentional — verify personality.rb preserve: section enforced
- [x] G10 require_evidence: modification claims must show diff, completion claims must show command output


## H. Testing coverage

RuleCoverageRule: every Rule subclass needs a test file.

- [x] H01 Test for SmallFilesRule (B01)
- [x] H02 Test for SmallFunctionsRule (B02)
- [x] H03 Test for GodClassRule (B03)
- [x] H04 Test for CqsRule (B04)
- [x] H05 Test for SECRET_PROXIMITY rule (A01)
- [x] H06 Test for MAGIC_COLOR rule (A02)
- [x] H07 Test for UNBOUNDED_RETRY rule (A03)
- [x] H08 Test for STRICT_MODE_ZSH rule (A13)
- [x] H09 Test for KEYWORD_ARGS rule (A04)
- [x] H10 Test for DEAD_CODE rule (A08)
- [x] H11 Test for TRAILING_COMMAS rule (A09)
- [x] H12 Test for AstFixer: collapse blank lines transform (C01)
- [x] H13 Test for AstFixer: trailing whitespace strip (C02)
- [x] H14 Test for AstFixer: .freeze append on mutable constant (C03)
- [x] H15 Self-scan test: MASTER scans its own lib/, expects zero violations
- [x] H16 Idempotency test: scan + fix + scan produces same result as scan + fix + fix + scan
- [x] H17 Test for evidence_scoring gate (scan_clean:25 weight, pass_threshold: 80)
- [x] H18 Test for failure_taxonomy: transient errors retry ≤3, permanent errors fail immediately
- [x] H19 Test for SINGULARITY: rules.yml has no duplicate IDs
- [x] H20 Test for phantom_recovery: gaslighting preamble discards response and retries


## I. Data quality and config

- [x] I01 rules.yml SINGULARITY boot assertion: verify all 173 IDs unique on load (no duplicates)
- [x] I02 rules.yml schema validator: every rule has required fields (id, name, tier, severity, autofix)
- [x] I03 rules.yml: fix any NO_COLUMN_ALIGN violations (multi-space alignment in YAML values)
- [x] I04 data/soul.yml ↔ rules.yml cross-reference: ensure golden_rule in soul.yml matches rules.yml kernel tier
- [x] I05 data/patterns.yml: audit for rules referenced here that are not in rules.yml
- [x] I06 data/standing_orders.yml: verify voice directives match rules.yml voice section
- [x] I07 MASTER/Gemfile: add `reek` if not present (ReekRule depends on it)
- [x] I08 MASTER/Gemfile: verify `prism` version matches rules.yml language support claims


## J. Pipeline and convergence integrity

- [x] J01 FixLoop: add cycle detector — if same violation appears N≥3 times across passes, stop and escalate
- [x] J02 Pipeline: wire evidence_scoring — scan_clean(25) + test_pass(35) ≥80 gates the :deploy stage
- [x] J03 Pipeline: tier1_critical rules → halt with rollback on violation, not just :err status
- [x] J04 RuleLoop: genetic_fix must reject candidates that increase violation count vs original (not just differ)
- [x] J05 Loop::Governor: verify pressure detection accounts for OpenBSD vmm memory (no swap, 1GB RAM)
- [x] J06 scan_since: extend to include MASTER lib/ alongside user code (self-scan on git diff)
- [x] J07 Heartbeat: emit `heartbeat:scan_clean` or `heartbeat:violations N` with self-scan result
- [x] J08 Convergence loop: add max_iterations cap (UNBOUNDED_RETRY applies to MASTER itself)


## K. Missing behaviors

- [x] K01 COST_TRANSPARENCY: after each LLM call, MASTER emits `[$N.NNNN, NNN tokens]` on event bus
- [x] K02 CACHE_LLM: hash prompt + model → cache response with 5-min TTL; serve from cache on repeat calls
- [x] K03 ERROR_CONTEXT: every Result.err includes {file:, method:, attempted:} context hash
- [x] K04 USER_CONTROL: add --dry-run flag to scan/sweep — show findings without applying fixes
- [x] K05 SYSTEM_STATUS: scan progress stream shows `scan: path/file.rb N violations` per file (already in stream_progress — verify wired)
- [x] K06 IDEMPOTENT: verify scan+fix is idempotent — apply twice, second pass produces no changes
- [x] K07 CACHE_LLM: LLM response cache should survive process restart (persist to .master/llm_cache.yml)
- [x] K08 PROGRESSIVE_DISCLOSURE: /help shows one-liner per command; detail on /help <command>
- [x] K09 FEEDBACK_LOOPS: scan_dir streams per-file progress; verify FixLoop does same
- [x] K10 DESIGN_BY_CONTRACT: document preconditions on Scanner#scan (path must exist, depth must be :deep)


## L. Web surface (MASTER/web/)

- [x] L01 All .erb views: scan with HTML_LANG, META_CHARSET, IMG_ALT, BUTTON_OVER_ANCHOR — fix violations
- [x] L02 All .css/.scss: scan with MOBILE_FIRST, NO_IMPORTANT, NO_IMPORT_SCSS — fix violations
- [x] L03 All .css: scan with MAGIC_COLOR — extract raw hex values to CSS custom properties
- [x] L04 All .js/.ts: scan with NO_VAR, FOR_OF, TEMPLATE_LITERALS, CONST_BY_DEFAULT — fix violations
- [x] L05 All .js: scan with JS_MODULE_SIZE — split files >300 lines
- [x] L06 web/app/controllers: scan with RATE_LIMITING_MISSING — verify all auth routes throttled
- [x] L07 web/app/models: scan with STRICT_LOADING_MISSING — add strict_loading_by_default true
- [x] L08 web/db/migrate/: scan with MIGRATION_ADD_REFERENCE_NO_FK — verify all references have foreign_key: true


## N. Documentation alignment

- [ ] N01 MASTER/QUICKSTART.md: verify every command in quickstart runs on OpenBSD 7.9 with ruby34
- [x] N02 AGENTS.md: update to reflect current 7-module structure (now/loop/judge/voice/ground/reach/trace)
- [x] N03 README.md: verify tagline matches project_master_mission.md ("Constitutional AI for any text artifact")
- [x] N04 rules.yml comments: remove any remaining TODO/FIXME markers (self-adherence to TODO_FIXME rule)
- [x] N05 All deferred comments in lib/: rewrite to S&W active voice per STRUNK rule

---

