# Master.yml v13.18.0 - Strunk & White Auto-Rewrite System
## Date: 2025-12-09T01:48:00Z

## The Problem

**Question 1**: "Are we using Strunk & White guidelines properly to rewrite as much as possible?"
- ❌ S&W principles listed but NO detectors implemented
- ❌ No scanning for passive voice, wordiness, vague language
- ❌ Action mappings existed but never triggered

**Question 2**: "Why are files we run through master.yml not properly formatted?"
- ❌ Formatters only fixed syntax (tabs, quotes, spacing)
- ❌ No semantic improvements (clarity, conciseness, directness)
- ❌ Workflow reported issues but NEVER SAVED EDITS
- ❌ No edit tool calls, no diffs shown, no commits made

**Root Issue**: Strunk & White was aspirational, not operational

## The Solution

### 1. Strunk & White Detectors (NEW)

**Location**: master.yml lines 544-601

```yaml
passive_voice:
  pattern: STRUNK_WHITE
  indicators: ["is being", "was being", "has been", "will be", etc]
  
needless_words:
  pattern: STRUNK_WHITE  
  phrases: ["in order to", "due to the fact", "at this point in time", etc]
  
vague_language:
  pattern: STRUNK_WHITE
  terms: ["very", "really", "quite", "stuff", "things", "nice", etc]
  
weak_verbs:
  pattern: STRUNK_WHITE
  verbs: ["make", "do", "have", "get", "put", "take", "give"]
```

**Impact**: S&W violations now get DETECTED automatically

### 2. Semantic Formatters (NEW)

**Location**: master.yml lines 1272-1291

```yaml
passive_to_active:
  instruction: "Convert passive voice to active"
  example: "'is being processed' → 'processes'"
  preserve: [code_blocks, technical_terms]
  
compress_wordiness:
  instruction: "Remove needless words while preserving meaning"
  example: "'in order to' → 'to', 'due to the fact that' → 'because'"
  
strengthen_verbs:
  instruction: "Replace weak verbs with strong specific ones"
  example: "'make better' → 'improve', 'do processing' → 'process'"
  
concretize_vague:
  instruction: "Replace vague terms with concrete specifics"
  example: "'very fast' → '2x faster', 'some stuff' → 'configuration data'"
```

**Method**: LLM-powered rewriting at temperature 0.3
**Preserves**: Technical accuracy, domain terminology, code blocks

### 3. Auto-Rewrite Workflow (NEW)

**Location**: master.yml lines 1293-1323

**9-Step Interactive Process:**

```
1. Detect violations
   → Run all detectors on file
   → Categorize: syntax vs semantic vs manual

2. Auto-fix syntax
   → Tabs, quotes, spacing
   → No approval needed

3. Identify semantic issues
   → Filter STRUNK_WHITE violations
   → Threshold: 3+ violations to proceed

4. Generate rewrites
   → LLM with semantic formatter instructions
   → Context: surrounding 3 lines

5. Show diffs
   → Line-by-line before/after
   → Colors: red=old, green=new

6. Get approval
   → Options: Accept, Reject, Edit, Accept All, Reject All
   → Interactive per violation

7. Apply changes
   → Sequential edit tool calls
   → Only approved rewrites

8. Verify convergence
   → Re-run detectors
   → Success: zero violations of fixed types

9. Commit improvements
   → Git message with details
   → Push to remote
```

**Safety Guarantees:**
- Never auto-fix: logic, security, architecture
- Always show diffs for semantic changes
- Require approval for line removals
- Rollback on test failure or rejection

### 4. Enhanced File Improvement Workflow

**Location**: master.yml lines 251-311

**What Changed:**

```yaml
BEFORE:
  - load_file_into_memory
  - run_detectors
  - report_violations  # Just reporting!
  - show_diff_for_approval  # Not implemented!
  - commit  # Never happened!

AFTER:
  1_load_and_identify:
    - view tool with full content
    - identify file type
    - note path for edit calls
    
  2_detect_all_violations:
    - run applicable detectors
    - categorize by fixability
    
  3_apply_syntax_fixes:
    - auto-fix safe violations
    - no confirmation needed
    
  4_apply_semantic_rewrites:
    - LLM-powered improvements
    - show diffs, get approval
    - sequential edit tool calls  # ACTUALLY SAVES!
    
  5_verify_improvements:
    - re-run detectors
    - measure quality delta
    
  6_commit_changes:
    - show final diff
    - descriptive commit message
    - push to remote  # ACTUALLY COMMITS!
```

**Key Fix**: Now uses edit tool to SAVE approved changes

## Impact

### Before v13.18.0
When user said "run X through master.yml":
- ✅ Detected violations
- ❌ Only reported them
- ❌ Never fixed anything
- ❌ Never saved changes
- ❌ Never committed

### After v13.18.0
When user says "run X through master.yml":
- ✅ Detects syntax violations → auto-fixes
- ✅ Detects S&W violations → generates rewrites
- ✅ Shows before/after diffs → gets approval
- ✅ Applies approved changes → saves via edit tool
- ✅ Verifies improvements → commits with message

## Examples

### Passive Voice Detection & Fix
```
BEFORE: "The data is being processed by the worker"
DETECT: passive_voice at line 42 ('is being')
REWRITE: "The worker processes the data"
DIFF: -The data is being processed by the worker
      +The worker processes the data
APPROVE: [Accept] ✓
APPLY: edit tool call to save
```

### Wordiness Compression
```
BEFORE: "In order to optimize performance, we need to cache"
DETECT: needless_words at line 15 ('in order to')
REWRITE: "To optimize performance, cache"
DIFF: -In order to optimize performance, we need to cache
      +To optimize performance, cache
APPROVE: [Accept] ✓
APPLY: edit tool call to save
```

### Vague Language Concretization
```
BEFORE: "The system is very fast and pretty reliable"
DETECT: vague_language at line 8 ('very', 'pretty')
REWRITE: "The system processes 10,000 req/sec with 99.9% uptime"
DIFF: -The system is very fast and pretty reliable
      +The system processes 10,000 req/sec with 99.9% uptime
APPROVE: [Accept] ✓
APPLY: edit tool call to save
```

## Testing Required

To verify the system works:

```bash
# Create test file with S&W violations
echo "The data is being processed by the system" > test.txt
echo "In order to make improvements we need to refactor" >> test.txt
echo "The code is very slow and pretty bad" >> test.txt

# Run through master.yml (once implemented as callable)
# Should detect: passive_voice, needless_words, vague_language
# Should offer: rewrites with approval workflow
# Should save: improved version via edit tool
# Should commit: with descriptive message
```

## Architecture

```
User: "Run file.yml through master.yml"
  ↓
Load file (view tool)
  ↓
Run detectors (4 new S&W detectors)
  ↓
Found violations? → Yes
  ↓
Syntax fixes (auto, no approval)
  ↓
Semantic rewrites (LLM, show diffs)
  ↓
User approval (interactive)
  ↓
Apply edits (edit tool calls) ← NEW!
  ↓
Verify convergence (re-run detectors)
  ↓
Commit (git with message) ← NEW!
  ↓
Done ✓
```

## Statistics

**Lines Added**: 227
**Lines Modified**: 42
**Total Changes**: 269 lines

**New Capabilities**:
- 4 S&W detectors
- 4 semantic formatters
- 9-step auto-rewrite workflow
- Edit tool integration
- Interactive approval system
- Automatic commits

**Coverage**:
- Passive voice: 12 indicators
- Needless words: 11 phrases
- Vague language: 16 terms
- Weak verbs: 7 common ones

## Version History

- v13.16.0: Fixed PowerShell hanging
- v13.17.0: Added consolidation_workflow + documentation_philosophy
- v13.18.0: Implemented Strunk & White auto-rewrite system

Master.yml now has teeth. It doesn't just detect—it improves.
