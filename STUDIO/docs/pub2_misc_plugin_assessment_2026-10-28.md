# pub2 misc restoration and ThinkRail assessment — 2026-10-28

Scope: inventory of current `anon987654321/pub2/misc/**`, focused review of its utility implementations and paired READMEs, comparison with the live `pub4/MASTER` plugin/tool surface, and a design assessment of JetBrains ThinkRail. This is a research and disposition record, not authorization to edit MASTER. The repository owner's full-read precondition for MASTER remains mandatory.

## Legacy inventory and disposition

| Legacy item | Observed purpose / condition | Disposition |
|---|---|---|
| `misc/default2.theme` | Irssi neutral/monochrome theme file; no executable tool contract. | Do not make a plugin. Preserve as a standalone theme only if Irssi configuration is still wanted. |
| `misc/nmap/nmap.sh` and its README files | OpenBSD-oriented active network scanner with DNS fallbacks, privileged scanning and phased output. The README advertises TCP SYN, UDP, service/version, OS and vulnerability scanning. The cognitive-load counters are presentation counters, not validated measurements. | Do not copy wholesale. The live `pub4/MASTER/lib/io/nmap.rb` already provides a bounded Nmap adapter with explicit authorization, governor admission, target validation, a single selected address, timeouts and constrained profiles. Consolidate any genuinely missing requirements into that implementation only after MASTER's full-read gate and its tests; avoid a duplicate scanner. |
| `misc/pouncekeys/pouncekeys.rb` | Termux setup script for an APK described in its comments as keylogging; it instructs accessibility-based keystroke capture and emailing logs. Its expected SHA-256 is a placeholder, so integrity verification is not real. | Reject. Do not restore or package as a plugin. |
| `misc/r-vx/r-vx.md` | Proposed Rust threat-simulation write-up, not a completed repository tool. It includes simulated sensitive-data/keylogging concepts, host scanning, file writes and a suggested Rails endpoint invoking a binary through backticks. | Do not restore as executable code. If a training need is approved, design a separate fixture-only simulator with no real credential capture, host scanning, persistence or shell execution. |
| `misc/vulcheck/vulcheck.rb` and README | Host-checking prototype for macOS/iOS/Android. It requires root, installs/updates packages, invokes shell commands and uses unreliable platform/rootkit/intrusion heuristics (for example, `ps aux | grep suspicious`). The claims exceed demonstrated capability. | Concept only, not a drop-in plugin. First inventory existing security/audit functions; if material gaps remain, build a read-only, platform-specific checker with argv-safe subprocesses, strict timeouts, evidence provenance, documented false positives and explicit partial-result states. |
 
The legacy inventory contains nine leaf files under `misc/**`, including duplicate HTML/Markdown Nmap documentation. No bulk copy is appropriate. The current Nmap adapter is already a better owner for the overlapping function; there is no rationale for adding another `MASTER/plugins/nmap` plugin.

## ThinkRail assessment

Reference: [JetBrains/thinkrail](https://github.com/JetBrains/thinkrail), its [README](https://github.com/JetBrains/thinkrail/blob/main/README.md), and the [0.2.0 turn-receipt design note](https://thinkrail.ai/blog/thinkrail-0-2-0-review-the-turn/) (published 2026-10-18). ThinkRail is a TypeScript agentic IDE around pi, with isolated git-worktree workspaces, living `SPEC.md` files, portable skills, review UI, tool/MCP authorization and host-captured per-turn change receipts.

### Adopt the principles, not a second framework

1. **Host-captured change receipts — highest value.** Snapshot repository state before a writing turn and after it settles, then derive changed paths and a consolidated diff from the repository itself. Do not trust the agent's tool-call narrative as evidence. Preserve stdout/stderr, exit status, relevant test results and rollback/checkpoint identity as distinct evidence fields. Never silently include unrelated pre-existing operator changes in the turn's receipt.
2. **Make review a single operation.** Present all changes caused by one turn together, including shell-side rewrites, formatter effects, additions, deletions and renames. The equivalent in MASTER should be a readable reviewable artifact and deterministic receipt—not a React IDE or another state store.
3. **Maintain linked specifications.** Keep one authoritative source for each contract. MASTER already has `soul.yml`, `laws.yml`, executable enforcement, path contracts and tests. Improve mechanical links from declarations to implementation, detector, production caller and regression test; never create a parallel specs source that can disagree with those authorities.
4. **Show exact tool intent at the approval boundary.** For non-read-only operations, expose the resolved tool, normalized arguments, target, permissions and expected side effects before approval. Project-provided MCP servers must remain disabled until explicitly trusted. A repository may not grant itself trust or bypass the constitutional law handshake.
5. **Use structured human decisions sparingly.** Surface genuinely divergent alternatives and their consequences instead of silently choosing. Preserve MASTER's existing human-decision state; do not turn routine implementation details into interrupting questionnaires.
6. **Treat workspaces as an optional technique, not a new mandate.** ThinkRail isolates work in git worktrees. pub4's current operator contract says the shared checkout writes directly to `main`, uses path-scoped commits and forbids branches/worktrees for routine work. Keep that project-specific contract unless the operator explicitly changes it; receipt semantics do not require worktrees.

### Existing implementation overlap and gaps observed

- `MASTER/lib/io/nmap.rb` already implements a constrained active assessment. Do not import the legacy scanner. The current recursive tree did not contain a dedicated `MASTER/test/test_io_nmap.rb`; that is a test inventory gap to address only after the MASTER full-read precondition.
- Existing source and test paths include `MASTER/lib/ground/boot_receipt.rb` / `MASTER/test/test_boot_receipt.rb`, `MASTER/lib/trace/worker_receipt.rb` / `MASTER/test/test_worker_receipt.rb`, `MASTER/lib/fix/execution_snapshot.rb` / `MASTER/test/test_execution_trace_snapshot.rb`, and convergence/effect-observer receipt tests. Their purposes differ: worker receipts record background-job start/end, execution snapshots detect source changes during preflight, and convergence receipts record repository inventory. None of those roles, as reviewed, proves a per-writing-turn before/after diff that isolates changes caused by that turn. Inspect the complete existing call paths before deciding whether a dedicated turn receipt is missing; avoid adding duplicate generic receipt abstractions.
- The current tree includes coverage-reconciliation tooling and tests, but that does not establish 100% runtime line and branch coverage. File existence and registered tests are not execution evidence.

## Verification contract for follow-up implementation

For any new or modified executable behavior, "100% test coverage" means 100% measured **line and branch coverage for every changed production file**, with no excluded lines hidden to make the threshold green. The change is not ready to land unless:
- tests cover success, invalid input, policy denial, dependency absence, exceptions/timeouts, partial results and cleanup for every applicable branch;
- at least one known-bad input proves each security guard actually rejects the bad case, and a known-good case proves the guard does not reject valid work;
- the focused suite and relevant full suite run in the pinned supported runtime, with raw command output and per-file exit codes retained;
- the report states both line and branch percentages and identifies any unreachable branch explicitly; any non-100% measurement is a failure, not a pass.

No runtime test command was executed as part of this review, so no test coverage percentage or passing-suite claim is made. The current connector editing surface cannot execute the repository's pinned Ruby/Bundler test commands. Do not use a third-party deployment service as a substitute for local/runtime evidence.

## Repository constraints

MASTER must be read in full before editing or planning edits to it. Then follow its authority order (`soul.yml`, `laws.yml`, executable enforcement, tree contracts, Git history). Keep the four permitted root directories unchanged: `MASTER/`, `RAILS/`, `OPENBSD/`, `STUDIO/`. Do not introduce a fifth root directory. Any eventual code change must include tests, preserve existing behavior, and be reviewed against the actual current tree rather than this document alone.

## Evidence and limits

- Legacy inventory source: `anon987654321/pub2/misc/**` on `main`; focused code reading covered the theme, Nmap script/docs, PounceKeys installer/README, r-vx proposal, and VulCheck implementation/README.
- ThinkRail source reviewed: current public README, package manifest, project spec and release information available on 2026-10-28.
- Not claimed: a byte-by-byte semantic review of every legacy file, execution against a live host, an audit of the upstream APK, successful MASTER test execution, 100% test coverage, or production deployment.
