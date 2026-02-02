# Bug Hunting Protocol Guide

## Overview

The Bug Hunting Protocol is a comprehensive 8-phase methodology integrated into the Universal Code Quality Analysis system. It provides systematic debugging guidance for both human developers and AI agents.

## Activation

The bug hunting protocol activates automatically when violations are detected, or can be explicitly enabled:

### Automatic Activation
```bash
# Bug hunting runs automatically when violations are detected
ruby cli.rb buggy_code.rb
```

### Explicit Activation
```bash
# Force bug hunting even for clean code
BUG_HUNTING=true ruby cli.rb code.rb

# Or using DEBUG mode
DEBUG=true ruby cli.rb code.rb
```

## The 8 Phases

### Phase 1: Lexical Consistency Analysis
**Purpose**: Extract all identifiers and verify semantic consistency

**What it detects**:
- Similar identifiers that may indicate typos
- Case inconsistencies (userId vs user_id)
- Plural/singular confusion (user vs users)
- Naming pattern violations

**Example output**:
```
PHASE 1: LEXICAL ANALYSIS
- Identifiers found: 74
- Consistency violations:
  ✗ Similar identifiers: 'User' vs 'users'
  ✗ Case inconsistency: 'userId' vs 'user_id'
```

### Phase 2: Simulated Execution
**Purpose**: Mentally trace execution from multiple perspectives

**Perspectives analyzed**:
1. **Happy Path**: Nominal execution with valid inputs
2. **Edge Cases**: nil, empty, zero, boundary conditions
3. **Concurrent Execution**: Race conditions, deadlocks
4. **Failure Injection**: Database failures, timeouts, resource exhaustion
5. **Backwards Trace**: From bug manifestation to root cause

**Example output**:
```
PHASE 2: SIMULATED EXECUTION
- Happy Path: Analyzed nominal execution with valid inputs
- Edge Cases: Checked nil, empty, zero, boundary conditions
- Concurrent Execution: Examined potential race conditions
```

### Phase 3: Assumption Interrogation
**Purpose**: Find and document implicit assumptions

**Assumption categories**:
- Data assumptions (exists, correct format, in range)
- Control flow assumptions (expected order, synchronous)
- Environment assumptions (file exists, network available)
- Dependency assumptions (library version, API format)

**Example output**:
```
PHASE 3: ASSUMPTIONS
- File system: File operations assume file exists
  Status: ⚠ Needs validation
- Database operations: Assumes success without error handling
  Status: ⚠ Needs validation
```

### Phase 4: Data Flow Analysis
**Purpose**: Trace data lineage from source to usage

**What it tracks**:
- Variable assignments
- Data transformations
- Source origins
- Usage locations

**Example output**:
```
PHASE 4: DATA FLOW
- user_email: Assigned from params[:email]
- email: Assigned from user.email → database column 'email'
```

### Phase 5: State Inspection
**Purpose**: Reconstruct system state when bug occurred

**State dimensions**:
- Application state (variables, call stack)
- Database state (table contents, locks)
- External state (filesystem, network, cache)
- Temporal state (timezone, event sequence)

**Example output**:
```
PHASE 5: STATE RECONSTRUCTION
- Application state: Analyzed potential variable states
- Potential edge states: nil values, empty collections, zero values
```

### Phase 6: Pattern Recognition
**Purpose**: Match against catalog of common bug patterns

**Patterns detected**:
- Off-by-one errors (loop boundaries)
- Null pointer dereference (missing nil checks)
- Type mismatch (String vs Integer)
- Race condition (check-then-act gap)
- Resource leak (files not closed)
- Stale cache (invalidation missing)
- Encoding issues (UTF-8 vs ASCII)
- Floating point precision (0.1 + 0.2 != 0.3)

**Example output**:
```
PHASE 6: PATTERN MATCHING
- Pattern: Resource leak (file not closed)
  Confidence: High
  Fix strategy: Use block form: File.open('file') do |f| ... end
```

### Phase 7: Proof of Understanding
**Purpose**: Verify complete understanding before attempting fix

**Required artifacts**:
1. Minimal reproduction case (smallest code that triggers bug)
2. Plain English explanation (rubber duck test)
3. Prediction of fix (what will happen)
4. Test case (fails now, passes after fix)

**Red flags**:
- Cannot reproduce consistently
- Cannot explain in simple terms
- Cannot predict specific outcome
- Multiple unrelated fixes attempted
- Fix works but don't know why

**Example output**:
```
PHASE 7: PROOF OF UNDERSTANDING
- Understanding complete: ✓ Yes
  ✓ Lexical analysis completed
  ✓ Execution traces generated
  ✓ Implicit assumptions identified
  ✓ Data flows traced
```

### Phase 8: Verification
**Purpose**: Verify fix is correct, complete, and doesn't break anything

**Verification checklist**:
- Minimal reproduction case passes
- All existing tests pass
- All edge cases handled
- Fix matches prediction
- Fix is localized (minimal change)
- Fix is understandable
- Fix is documented (WHY, not just WHAT)

**Example output**:
```
PHASE 8: VERIFICATION
- All checks passed: ✗ No
  ✗ Bug hunting protocol completed all phases
  ✓ Findings documented for review
  ✓ Pattern matches identified or ruled out
```

## Integration with Problem-Solving Engine

The bug hunting protocol integrates with the problem-solving engine from master.yml:

### Generate 5+ Fix Approaches
When designing a fix (Phase 7), the system considers multiple approaches:
1. Obvious solution (what everyone tries first)
2. Opposite approach (invert the problem)
3. Analogy approach (how is this solved elsewhere?)
4. Minimal approach (simplest thing that could work)
5. Maximal approach (most robust but complex)
6. Lateral approach (reframe the problem itself)

### Ask Hostile Questions
Challenge assumptions with:
- "What am I still missing? (blind spots)"
- "Why didn't previous attempts work? (learn from failure)"
- "What would make this fail in production? (failure modes)"
- "Am I solving the symptom or root cause? (depth check)"

### Cherry-Pick Best Elements
Don't just choose one approach. Synthesize hybrid solution:
- Correctness check from approach 1
- Edge case handling from approach 3
- Simple structure from approach 4
- Error handling from approach 5

## Systematic Protocols (Prerequisites)

Before debugging, follow reconnaissance protocol:

### Always tree.sh before entering codebase
```bash
tree -L 3 -I 'node_modules|vendor'
```
Map directory structure, identify entry points, locate configuration files.

### Always clean.sh before editing
```bash
# Remove build artifacts
rm -rf *.pyc *.class node_modules/
# Clear temporary files
rm -rf /tmp/* .cache/
# Verify git status
git status
```
Dirty state causes false positives and obscures real changes.

### Never skip reconnaissance
Even for "quick fixes":
1. Read surrounding context (50 lines before/after)
2. Search for similar patterns in codebase
3. Check git history of modified files
4. Review related tests
5. Verify assumptions with grep/search

## Example: Complete Bug Hunt

### Input Code (buggy_example.rb)
```ruby
class User
  def save
    # BUGS: No error handling, silent failures
    db.execute("INSERT INTO users (email) VALUES (?)", @email)
  end
  
  def get_data
    # BUGS: Resource leak, generic names
    f = File.open("user_data.txt")
    d = f.read
    f.close  # Never called if exception
    d
  end
end
```

### Output Report
```
===== BUG HUNTING REPORT =====
File: buggy_example.rb

PHASE 1: LEXICAL ANALYSIS
- Identifiers found: 15
- Consistency violations:
  ✗ Similar identifiers: 'f' vs 'file'
  ✗ Single letter variables: f, d

PHASE 2: SIMULATED EXECUTION
- Happy Path: Nominal execution succeeds
- Edge Cases: What if file doesn't exist? (FileNotFoundError)
- Failure Injection: What if read() raises? (file never closed)

PHASE 3: ASSUMPTIONS
- File system: Assumes "user_data.txt" exists
  Status: ⚠ Needs validation
- Database operations: Assumes db connection exists
  Status: ⚠ Needs validation

PHASE 4: DATA FLOW
- f: Assigned from File.open("user_data.txt")
- d: Assigned from f.read

PHASE 5: STATE RECONSTRUCTION
- Application state: f holds file handle
- Potential edge states: File missing, permission denied

PHASE 6: PATTERN MATCHING
- Pattern: Resource leak (file not closed)
  Confidence: High
  Fix strategy: Use block form: File.open('file') do |f| ... end

PHASE 7: PROOF OF UNDERSTANDING
✓ Minimal reproduction: File.open without ensure/block
✓ Plain English: If f.read raises, f.close never called
✓ Predicted fix: Use block form for automatic cleanup
✓ Test case: Inject read error, verify file closed

PHASE 8: FIX APPROACHES (5 alternatives)
Approach 1: Add begin/ensure block
Approach 2: Use File.open with block ⭐ SELECTED
Approach 3: Use File.read (simpler for small files)

Selected: Approach 2 (idiomatic Ruby, automatic cleanup)

Implementation:
```ruby
def retrieve_user_data_from_persistent_storage_file
  File.open("user_data.txt") do |file_handle_for_reading_user_data|
    file_contents_as_string = file_handle_for_reading_user_data.read
    file_contents_as_string
  end  # File automatically closed even on exception
end
```

VERIFICATION:
✓ Minimal reproduction passes (no leak)
✓ All existing tests pass
✓ Exception during read still closes file
✓ Fix matches prediction
✓ Fix is localized (one method)

=== COMPLETE ===
```

## Configuration in master.yml

The bug hunting protocol is fully documented in master.yml v8.0:

### Sections Added
- `systematic_protocols`: Reconnaissance requirements
- `problem_solving_engine`: 5+ approaches methodology
- `bug_hunting_protocol`: All 8 phases with detailed guidance
- `diagnostic_escalation`: When to escalate intensity
- `common_bug_patterns`: Catalog with detection heuristics

### Access Protocol Definition
```ruby
require 'yaml'
config = YAML.load_file('master.yml')
bug_protocol = config['bug_hunting_protocol']
patterns = config['common_bug_patterns']
```

## Best Practices

### When to Use Bug Hunting Protocol
- Complex bugs that resist standard debugging
- Intermittent failures (race conditions, timing issues)
- After multiple failed fix attempts
- Production issues requiring root cause analysis
- Code review identifies potential bugs

### When NOT to Use Bug Hunting Protocol
- Simple syntax errors (use linter)
- Obvious typos (use IDE)
- Well-understood patterns (apply known fix)
- Time-critical hotfixes (fix fast, analyze later)

### Iteration Strategy
1. Run bug hunting protocol
2. Analyze findings from all 8 phases
3. Generate 5+ fix approaches
4. Implement minimal fix
5. Verify all checklist items
6. If verification fails: revert, restart from Phase 1
7. If same failure 3+ times: escalate to human review

## Integration Points

### Command Line Interface
```bash
# Standard analysis (auto-activates on violations)
ruby cli.rb code.rb

# Force bug hunting
BUG_HUNTING=true ruby cli.rb code.rb

# Debug mode (same as BUG_HUNTING)
DEBUG=true ruby cli.rb code.rb
```

### Programmatic API
```ruby
require './cli'

# Load code
code_unit = CodeUnit.new(content: source_code, file_path: "example.rb")

# Run analysis with bug hunting
analysis = UniversalCodeAnalyzer.analyze_single_code_unit_for_all_violation_types(
  code_unit,
  enable_bug_hunting: true
)

# Generate report
if analysis[:bug_hunting_report]
  report = BugHuntingAnalyzer.format_bug_hunting_report(
    analysis[:bug_hunting_report]
  )
  puts report
end
```

### Pipeline Integration
The bug hunting protocol integrates seamlessly into existing Pipeline workflow:

1. **Code Loading**: No changes required
2. **Violation Detection**: Existing analyzers run first
3. **Bug Hunting Activation**: Automatic if violations > 0 OR enable_bug_hunting=true
4. **Report Generation**: Bug hunting report displayed after violations
5. **Fix Application**: Manual confirmation still required

## Troubleshooting

### "Bug hunting not activating"
- Check violations exist OR set `BUG_HUNTING=true`
- Verify master.yml contains `bug_hunting_protocol` section
- Check Ruby version compatibility (2.7+)

### "Report incomplete"
- Phase 8 failing is normal (indicates issues found)
- Phase 7 failing means insufficient understanding → keep analyzing
- Missing phases indicate implementation bug → report issue

### "Too many false positives"
- Lexical analyzer is sensitive to comment text
- Filter results by confidence level (High > Medium > Low)
- Some patterns are heuristic-based → verify manually

## Version History

### v8.0 (2026-02-02)
- Initial bug hunting protocol implementation
- All 8 phases operational
- Integration with existing analyzers
- Problem-solving engine integration
- Common bug patterns catalog
- Systematic protocols documentation

## References

- `master.yml`: Constitutional framework (bug_hunting_protocol section)
- `cli.rb`: Implementation (BugHuntingAnalyzer and 8 phase classes)
- Problem statement: Original specification and requirements

## Contributing

When adding new bug patterns:
1. Add to `common_bug_patterns` in master.yml
2. Add detection logic to `PatternMatcher` class
3. Include example in documentation
4. Add test case demonstrating detection

When enhancing phases:
1. Update phase implementation class (e.g., `LexicalConsistencyAnalyzer`)
2. Update report formatting in `BugHuntingAnalyzer.format_bug_hunting_report`
3. Update documentation with examples
4. Ensure backward compatibility
