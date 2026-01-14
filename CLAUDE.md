# AI Coding Assistant Instructions

**Version:** 67.2.0 (2026-01-06)
**Source of Truth:** `master.yml` (this file is a reference implementation)
**For:** GitHub Copilot CLI, Claude Code CLI, and compatible AI coding assistants
**Model:** Both GitHub Copilot CLI and Claude Code CLI use Claude Sonnet 4.5
**GitHub Copilot Users:** Can place this in `.github/copilot-instructions.md` for automatic loading

---

## ⚠️ IMPORTANT: Single Source of Truth

**This file references `master.yml` - the comprehensive Universal Project Completion Framework.**

- **master.yml** = Complete specification (1224 lines, all principles, workflow, patterns)
- **CLAUDE.md** = Practical quick reference (this file)

If content conflicts, **master.yml wins**. This file extracts the most actionable patterns for daily use.

---

## Quick Start

### Core Principles (See master.yml lines 69-112)

1. **Evidence over intuition** - No future tense. Show proof (diffs, tests, benchmarks).
2. **Simplicity ultimate** - Delete until it hurts. Explain to junior in 30 seconds.
3. **Fail fast, recover gracefully** - Loud errors, reversible changes.
4. **Security by default** - Validate inputs, minimize permissions, encrypt secrets.
5. **Explicit over implicit** - No magic, no hidden dependencies.

### Implementation Patterns (See master.yml lines 101-112)

- **boy_scout_rule** - Leave code better than found
- **idempotent_by_default** - Check state before acting
- **backup_before_modify** - Never destructive in-place
- **test_driven_development** - Write tests first
- **validate_before_done** - Tests pass, metrics collected, proof shown

---

## Output Format (See master.yml lines 114-129)

**Pattern:** `component at phase: status (detail) [metric]`

**Examples:**
```
parser at init: ok (42 rules loaded) [0.023s]
tests at verify: ok (184 passed, 0 failed) [2.341s]
git at commit: ok (3 files changed, 47 insertions, 12 deletions) [abc123f]
```

**Forbidden:** Future tense, promises without proof, ASCII art, truncation

---

## Decision Trees (See master.yml lines 132-154)

### Bug Fix
```
1. Reproduce → Write failing test
2. Diagnose → Root cause (use diagnostic_escalation)
3. Fix → Minimal change
4. Verify → ALL tests pass
5. Show → Diff + test output
```

### Low Confidence (<70%)
```
STOP → Ask human:
  "I understand you want X.
   I'm uncertain about Y (confidence: 0.65).
   Options: A) ... B) ...
   Should I proceed with A or B?"
```

---

## Diagnostic Escalation (See master.yml lines 829-863)

**When debugging, escalate systematically:**

1. **Syntax** - `zsh -n`, `eslint`, `rubocop` (saves 2-3 hours)
2. **Logic** - Unit tests, type checkers (saves 1-2 hours)
3. **History** - `git bisect`, `git log --patch` (saves hours)
4. **Binary** - Hex editor for control chars (saves DAYS on "impossible" bugs)
5. **Reference** - Sister repos, upstream (prevents rebuilding)

**Level 4 detection (binary corruption):**
```powershell
# PowerShell
[System.IO.File]::ReadAllBytes('file') | Where { $_ -lt 0x20 -and $_ -notin @(0x09,0x0A,0x0D) }
```
```bash
# Bash
od -An -tx1 file.sh | grep -E ' 0[0-8bcef] | 1[0-9a-f]'
```

---

## File Safety (See master.yml lines 27-32)

### NEVER Batch Delete
```bash
# ❌ FORBIDDEN
rm *.txt

# ✅ REQUIRED - One at a time
for file in *.txt; do
  [[ -f "$file" ]] || continue
  read content < "$file"
  process "$content" > new.txt
  [[ -s new.txt ]] || exit 1
  rm "$file"
done
```

---

## Git Workflow (See master.yml lines 293-336)

### Commit Format
```
type(scope): brief description

Detailed explanation of WHAT changed and WHY.

Examples:
fix(auth): prevent race condition in token refresh
feat(api): add rate limiting to public endpoints
security(db): parameterize all SQL queries
```

**Types:** `fix`, `feat`, `refactor`, `test`, `docs`, `chore`, `perf`, `security`

---

## Security Checklist (See master.yml lines 354-364, 650-652)

Before declaring work complete:
- [ ] Injection - All inputs validated, queries parameterized
- [ ] Broken Auth - Sessions secure, passwords hashed (bcrypt/argon2)
- [ ] Sensitive Data - Secrets in env vars, TLS for transport
- [ ] XSS - All user input escaped in HTML
- [ ] CSRF - State-changing operations protected
- [ ] Deserialization - Validated, safe formats (JSON not pickle)

Reference: https://owasp.org/www-project-top-ten/

---

## When To Ask Human (See master.yml lines 444-464)

**ALWAYS ask when:**
- Security concern detected
- Confidence <70% on important decision
- Scope expanding beyond request
- No progress after 3 attempts
- Requirements unclear

---

## Language-Specific Quick Reference

### Ruby
```ruby
# frozen_string_literal: true  # REQUIRED

config[:database]  # ✅ symbols
user&.profile&.email  # ✅ safe navigation
```

### JavaScript/TypeScript
```typescript
"use strict";
const config = {...};  // ✅ const over var
```

### Shell (Bash/Zsh)
```bash
#!/usr/bin/env bash
set -euo pipefail  # ✅ REQUIRED

# Prefer Zsh builtins (10-100x faster)
${(L)var}  # lowercase instead of tr
${var//pattern/replacement}  # instead of sed
```

### SQL
```sql
-- ✅ Parameterized
SELECT * FROM users WHERE email = $1;

-- ❌ NEVER interpolate
SELECT * FROM users WHERE email = '#{input}';
```

---

## Proactive Features (See master.yml lines 489-539)

The framework can suggest features when appropriate:

- **parallel_operations** - Read 5 files in ONE response
- **persona_voting** - Run 10 expert reviewers for consensus
- **evidence_scoring** - Generate metrics (complexity, duplication %)
- **semantic_entropy** - Detect hallucinations via consistency
- **diagnostic_escalation** - 5-level systematic debugging

Ask: "What framework features could help with this task?"

---

## Workflow Lessons (See master.yml lines 1010-1084)

**Hard-won operational knowledge:**

- **async_deadlock_risk** - Use sync mode in multi-process environments
- **script_creation_antipattern** - Execute directly, don't create intermediary scripts
- **cross_platform_shell** - Use zsh wrapper: `C:\cygwin64\bin\zsh.exe -c 'commands'`
- **vps_connection_paralysis** - Execute immediately after SSH, don't pause
- **scientific_documentation** - Cite research papers in code (9.5/10 quality)
- **binary_corruption** - Check hex editor when "impossible" bugs occur

---

## Quality Gates (See master.yml lines 339-369)

### BLOCK (Hard Stop)
- ❌ Any test fails
- ❌ Unvalidated user input
- ❌ Plaintext secrets
- ❌ SQL/XSS/Command injection possible
- ❌ Future tense in output

### WARN (Fix If Possible)
- ⚠️ Function >20 lines
- ⚠️ Cyclomatic complexity >10
- ⚠️ Nesting depth >3
- ⚠️ Test coverage <70%
- ⚠️ Duplicate code (70% similar, 3+ times)

---

## Common Anti-Patterns to Avoid

### ❌ Theater (Simulation)
```
❌ "I will add tests"
✅ [Shows diff] "tests at auth: ok (12 passed, 0 failed)"
```

### ❌ Magic Numbers
```ruby
❌ if user.age > 18
✅ LEGAL_AGE = 18
   if user.age > LEGAL_AGE
```

### ❌ Silent Failures
```ruby
❌ rescue => e; nil; end
✅ rescue PaymentError => e
     logger.error("Payment failed: #{e.message}")
     raise
   end
```

---

## Cost Awareness (See master.yml lines 703-727)

- **Simple ops** (<20 lines) → Haiku/GPT-3.5
- **Medium tasks** (20-200 lines) → Sonnet/GPT-4
- **Complex planning** (>200 lines) → Opus/o1
- **Budget limit** → Pause at $1.50, stop at $2.00

---

## Glossary (See master.yml lines 956-994)

**Key terms explained at 3 levels:**

- **cyclomatic_complexity** - "How many routes through the maze?"
- **evidence_score** - "Like school grades: more proof = higher score"
- **persona_consensus** - "If most parents say yes, you can go"
- **veto** - "Parent says no → can't argue your way out"

---

## Full Reference

**For complete details, see:**
- `master.yml` - Full framework (1224 lines)
- Lines 69-112: Core principles
- Lines 157-277: 10-phase workflow
- Lines 280-337: 10 adversarial personas
- Lines 339-369: Gates & guardrails
- Lines 541-607: Evidence system
- Lines 664-693: Cognitive biases
- Lines 829-863: Diagnostic escalation (5 levels)
- Lines 956-994: Glossary (tri-level explanations)
- Lines 1010-1084: Workflow lessons (real session learnings)

---

## Meta

**This document:**
- Version: 67.2.0
- Last Updated: 2026-01-06
- Source: master.yml (single source of truth)
- Purpose: Quick reference for daily AI assistant use
- Validation: References line numbers in master.yml v67.2.0 for verification
- Compatibility: Tested with GitHub Copilot CLI and Claude Code CLI (both using Claude Sonnet 4.5)

**Key principle:** When in doubt, read `master.yml`. This file is a practical extraction, not a replacement.

**Remember:** Execute, don't describe. Show diffs, not intentions. Proof over promises.
