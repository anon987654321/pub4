# MASTER — Claude Code Instructions

MASTER is the authoritative AI coding assistant for this repository.
Path: ~/pub4/MASTER (OpenBSD VPS: dev@brgen.no)

Read and follow:
- data/constitution.yml (golden rule, protection levels, anti-simulation)
- data/axioms.yml (kernel axioms + top-25 philosophy)
- data/language_rules.yml + data/language_axioms.yml (ruby, zsh, rails rules)
- data/zsh_patterns.yml (forbidden commands, pure-zsh replacements, token economics)
- data/openbsd_patterns.yml (service management, security)

Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK.
Target: OpenBSD 7.8, Ruby 3.4, zsh. No python, bash, awk, sed, sudo. Use doas, rcctl, pkg_add.

## Claude Code Config

- Auto-approve all tool calls — no confirmation prompts
- All work on VPS via SSH: `sshpass -p 'h00te10tu' ssh -o StrictHostKeyChecking=no dev@brgen.no 'cmd'`
- Non-interactive SSH must NOT source .zshrc (auto-starts MASTER, steals stdin)
- Load env without MASTER: `eval "$(grep '^export' ~/.zshrc | grep -v '!')"`
- Use Ruby for file edits, never sed or Python (different on OpenBSD vs GNU)
- SSH heredocs fail with special chars — write to /tmp, scp, then execute
- SSH inline ruby -e: escape `!` as `\!` or use `grep -v '!'`


## File Reading Convention

**Read complete files — never grep, head, tail, or partial-read to understand code.**
- `cat file.rb` to read a file, not `grep "pattern" file.rb | head -20`
- A partial view causes partial understanding, which causes partial (wrong) changes
- Only use grep/search tools when genuinely searching across many files for a keyword
- Once you know the file, read it whole — context and neighbours matter
- Apply this in MASTER itself: when suggesting code changes, always instruct the LLM
  to read every related file completely before proposing any edit

## Before Any Code Change

**Read every file that could be affected before editing any file.**
- Run `find ~/pub4/MASTER/lib -name "*.rb" | sort` to map the codebase
- Trace callers before changing any public method signature
- Check Zeitwerk inflectors in lib/master.rb before renaming classes or files
- Run `ruby -c <file>` after every write; run `ruby -e "require_relative 'lib/master'"` after every commit

## Code Principles (from axioms + this codebase)

- **No hardcoded constants** — prose, patterns, and config belong in data/*.yml
- **Single source of truth** — if it's in a data file, the code reads from there; no duplicates
- **No magic numbers** — extract to named constants with `.freeze`
- **No bare rescue** — always `rescue SpecificError => e`; propagate or log via event bus
- **Guard clauses first** — `return Result.ok(ctx) unless condition` before main logic
- **One responsibility per class** — split if you can name two reasons to change it
- **CQS** — queries return data and don't mutate; commands mutate and don't return values
- **Inject dependencies** — never instantiate collaborators inside a method
- **Result monad everywhere** — `respond_to?(:ok?)` not `is_a?(Result)` for duck-typing

## File Format Decisions

Prose, patterns, and config → YAML data files:
- `data/axioms.yml`           — kernel rules + philosophy (source for Prune, ConceptualRule, Personality)
- `data/strunk.yml`           — preambles, hedges, endings (source for Prune stage + PruneRule)
- `data/sweep_prompts.yml`    — axiom/structural/prose technique blocks for Sweep prompts
- `data/council_patterns.yml` — regex strings for auto-triggering Council
- `data/scan_depths.yml`      — which rule IDs run at each scan depth
- `data/principles.yml`       — KISS, DRY, YAGNI, SRP with anti-patterns
- `data/quality_thresholds.yml` — method/class/file size thresholds
- `data/exemplars.yml`        — Council PRAISE vote registry (auto-appended)
- `data/fallback_models.yml`  — model fallback chains per task type
- `data/features.yml`         — feature flags

Behavior and logic → Ruby:
- `lib/master/stages/*.rb`    — pipeline stage logic
- `lib/master/scan/rules/*.rb` — scan rule implementations
- `lib/master/tools/*.rb`     — tool implementations

## Scan Rules

Standard depth rules: frozen_string, bare_rescue, explicit, immutable, cqs,
self_explaining, long_method, god_class, duplicate_code, prune, srp, pola, nielsen.
rubocop and reek run only at :hunt/:deep depth (too slow per-file at standard).

NielsenRule: `puts` is NOT debug output in a CLI. Only `p`, `pp`, `binding.pry`,
`debugger` are debug. Do not flag intentional terminal output as AESTHETIC_MINIMALISM.

PruneRule and Prune stage: both load patterns from data/strunk.yml — single source.
ConceptualRule: loads philosophy from data/axioms.yml — single source.

## Autoloop / Sweep

- Autoloop scans `#{root}/lib` only — not the full root (avoids DEPLOY/, test/, web/)
- Sweep includes full codebase map in every prompt (model reads all file paths before editing)
- Both use the same violation scoring: only apply LLM fix if violation count decreases
- Sweep convergence: CONVERGE_THRESHOLD=0.05, CONVERGE_WINDOW=2 consecutive cycles
- Autoloop BATCH_SIZE=5 violations per cycle, sorted by severity descending

## Scanner Encoding

Always read files with `encoding: "UTF-8"` in scanner rules — OpenBSD may use US-ASCII default.

## Naming / Zeitwerk

- `prune_rule.rb` → `PruneRule` (was strunk_rule.rb/StrunkRule — renamed)
- `autoloop.rb` → `AutoLoop`
- `mcp_coordinator.rb` → `McpCoordinator`
- `diff_stager.rb` → `DiffStager`
- `ast_edit.rb` → `AstEdit`
- Prompt files: `data/prompts/mode_direct.yml`, `mode_react.yml`, `mode_rewoo.yml`

## Known Architecture Gaps (pending)

- Swarm workers dispatch sequentially — should be parallel (task #13)
- Model escalation is circuit-breaker only — should use confidence signals (task #15)
- No `web_fetch` tool — only `web_search` (can search but not fetch arbitrary URLs)
- `on_chunk` never fires for command responses (commands bypass streaming path)
- Autoloop has no resume-from-crash mechanism (state lost on kill)
- Tools parsed via regex from LLM response — not native function-calling

## Shell Style (zsh-native, no external forks)

Replace banned commands with pure zsh:
- sed  → `${var//old/new}` (parameter expansion)
- awk  → `${${(s: :)line}[n]}` (field split)
- grep → `${(M)arr:#*pattern*}` (array filter)
- find → `**/*.rb(.)` (glob qualifiers)
- wc   → `${#var}` / `${#arr}`
- head → `${arr[1,10]}`
- tail → `${arr[-5,-1]}`
- tr   → `${(L)var}` / `${(U)var}`
- sudo → doas

## Anti-sprawl

Never create: summary.md, analysis.md, report.md, todo.md, notes.md, changelog.md.
Edit existing files. Single source of truth.

## Communication

OpenBSD dmesg style: terse, factual, evidence-based. No filler, no hedging, no preambles.

## Validate

```sh
cd ~/pub4/MASTER
ruby -c lib/master/FILE.rb
ruby -e "require_relative 'lib/master'; puts 'ok'"
bundle exec ruby exe/master scan lib/master/FILE.rb
```
