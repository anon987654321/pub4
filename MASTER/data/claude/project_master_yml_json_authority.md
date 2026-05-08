---
name: master.yml + master.json are the constitutional source of truth
description: Current Ruby MASTER must implement what the predecessor master.json (v43.0.1) and master.yml (v31, v49.75, etc.) describe — close the drift
type: project
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
The user's directive: **"MASTER should do what master.yml and master.json describes."**

The current modular Ruby MASTER has drifted from the constitutional intent of its YAML/JSON predecessors. The predecessors are the authoritative spec for behavior; the Ruby is just the executor.

**Why:** Stated explicitly on 2026-05-05 after we mined the deleted master.json (Nov–Dec 2025, 130 commits) and master.yml (Dec 2025–Feb 2026, 668 commits) histories. The user wants behavior-spec parity, not just rule-set parity.

**Key gaps to close (priority order):**

1. **Six Universal Laws ladder** (ROBUSTNESS→SINGULARITY→LINEARITY→PROXIMITY→ABSTRACTION→DENSITY) — single hierarchical priority system; every rule and persona anchored to one law.
2. **Strunk & White safeguards** — `apply_to: [prose, comments, documentation, strings]`, `never_apply_to: [code_logic, algorithms, data_structures]`, `never_delete_variable_names / never_delete_function_calls / never_simplify_conditional_logic`. Prevents lossy compression.
3. **biases section** — hallucination, simulation, completion_theater, sycophancy, false_confidence + cognitive traps as concrete detectable rules with regex patterns.
4. **structural_ops taxonomy** — merge/semantic_regroup/defrag/decouple/hoist/flatten/delete/expand/reduce_noise, each with risk + verify + supports_law.
5. **8-phase workflow with introspection + learn phase** (discover→analyze→ideate→design→implement→validate→deliver→**learn**), introspect question per phase. Closes the project orchestrator / spec planner gap.
6. **patterns.veto regex detectors** (secrets, sql_injection, unfinished, unsafe_calls, race_conditions) and patterns.high (future_tense, sycophancy, magic_numbers, deep_nesting).
7. **Adversarial: 5 questions per violation; solution generation: 5-15 solutions, early exit on quality** — currently makes 1 fix per file.
8. **Fixed-point convergence: silence in 2 consecutive runs** — currently 1 cycle.
9. **Incremental scanning** — only modified files when not user-triggered; full-scan triggers = new_principle_added / master_yml_modified / user_requests_full_scan. (60-85% faster.)
10. **Prediction engine with confidence thresholds** — per-detector autofix mappings (null_usage 0.95→null_object, abbreviation 0.99→expand, nesting 0.92→extract_method).
11. **12 weighted personas** for council with `w:`, `q:`, `emphasizes: [LAWS]`. Veto rights to [security, attacker, maintainer].
12. **SHA256 evidence logging** — `Read {file} (sha256: {hash}, {lines} lines)` for every read/write.
13. **Beauty section** — Bringhurst typography, Ando architecture, Rams design, Martin code as aesthetic anchors.
14. **preserve: section** — protect boot dmesg, diagnostic output, help text from over-simplification.
15. **OpenBSD per-config validators** — pf.conf, sshd_config, httpd.conf, nsd.conf, smtpd.conf with required_patterns and warnings.
16. **Tech stack constants** — LCP 2.5s, INP 200ms, CLS 0.1, WCAG_AA 4.5 contrast, 24px touch targets, 66ch line length.
17. **Cost guards** — max_per_file: $1, max_per_session: $10, warn_at: $0.50.
18. **Per-language generation templates** — HTML/CSS/Ruby/sh/yml starter templates.

**How to apply:** Treat closing these gaps as the primary backlog. Execute in priority order; each is independently commit-able. The user is an architect — aesthetic items (Six Laws naming, beauty section, zen interface, voice) are first-class, not nice-to-have.
