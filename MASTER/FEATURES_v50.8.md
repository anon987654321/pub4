# MASTER v50.8 - New Features Documentation

## Overview

MASTER v50.8 introduces 8 advanced features that enhance code quality analysis with long-term memory, automation, and AI-powered refactoring capabilities.

---

## 1. Git-Backed Memory System 🧠

**Long-term context persistence using git history**

The memory system stores every decision, fix, and violation in `.master_memory/` directory with git commit tracking.

### Features
- Persistent storage of all violations and decisions
- Search similar past violations
- Pattern detection: "User always fixes N+1, ignores style issues"
- Team collaboration via remote sync

### Usage

```bash
# Search for similar past violations
$ memory search "N+1 queries"

# Show user decision patterns
$ memory patterns

# Sync memory with remote repository
$ memory sync
```

### Memory Entry Structure
```json
{
  "timestamp": "2026-02-04T10:30:00Z",
  "event_type": "violation_found",
  "file": "lib/auth.rb",
  "violation": {
    "principle": "SOLID_SRP",
    "line": 45,
    "description": "God class with 23 methods"
  },
  "decision": "fixed",
  "cost": 0.002
}
```

### API

```ruby
memory = Master::Memory::GitBacked.new

# Record a decision
memory.record_decision(
  "lib/auth.rb",
  { principle: "SOLID_SRP", line: 45, description: "..." },
  { type: "fix_applied", action: "fixed", cost: 0.002 }
)

# Search similar violations
results = memory.search_similar_violations(principle: "SOLID_SRP")

# Get user patterns
patterns = memory.get_user_patterns
# => { "SOLID_SRP" => { fixed: 10, ignored: 2, deferred: 1 } }

# Get file history
history = memory.get_file_history("lib/auth.rb")
```

---

## 2. Smart Pre-Commit Git Hooks ⚡

**Fast, cached analysis for commits (sub-100ms for typical commits)**

Automatically analyze only changed files before committing with intelligent caching.

### Features
- Installs git pre-commit hook
- Analyzes only staged Ruby files
- Caches results by file content hash
- Sub-100ms for cached files

### Usage

```bash
# Install pre-commit hook
$ hooks install

# Test hook on current staged files
$ hooks test

# Uninstall hook
$ hooks uninstall
```

### Cache Structure
```json
{
  "lib/auth.rb": {
    "sha256": "abc123...",
    "last_scan": "2026-02-04T10:30:00Z",
    "violations": [...],
    "score": 95
  }
}
```

### API

```ruby
hooks = Master::Git::SmartHooks.new

# Install hook
result = hooks.install

# Test on staged files
result = hooks.test

# Analyze file with caching
result = hooks.analyze_with_cache("lib/auth.rb")
```

---

## 3. Voice-to-Code Interface 🎤

**Analyze and explain code using voice commands**

Voice interface for hands-free code analysis (requires audio dependencies for full functionality).

### Features
- Voice command parsing
- Transcription via Whisper API
- Natural language to CLI command conversion
- Text-to-speech responses (stub implementation)

### Usage

```bash
# Start interactive voice session
$ voice

# Transcribe an audio file
$ voice --transcribe recording.wav
```

### Example Flow
```
User: "Analyze authentication module and explain security issues"
  ↓ [Transcribe with Whisper]
  ↓ "analyze lib/auth.rb --focus security"
  ↓ [Execute analysis]
  ↓ [Display results]
```

### API

```ruby
interface = Master::Voice::Interface.new

# Start interactive session
interface.start_session

# Transcribe audio file
result = interface.transcribe_audio("recording.wav")

# Parse natural language command
command = interface.parse_intent("analyze authentication module")
```

---

## 4. Automatic Test Generation 🧪

**Generate RSpec tests from violations**

Automatically generate failing tests for code quality violations.

### Features
- Generate RSpec tests from violations
- Tests fail until violation is fixed
- Track test coverage by principle
- Support for RSpec and Minitest

### Usage

```bash
# Generate tests during analysis (future implementation)
$ analyze lib/ --generate-tests

# Show test coverage
$ test-coverage
```

### Example Generated Test

```ruby
# MASTER Auto-generated test
# Violation: PRINCIPLE_VALIDATION - Missing email presence validation
# Generated: 2026-02-04 10:30:00
# Fix this by adding: validates :email, presence: true

RSpec.describe User do
  it 'validates email presence' do
    user = User.new(email: nil)
    expect(user).to_not be_valid
    expect(user.errors[:email]).to include("can't be blank")
  end
end
```

### API

```ruby
generator = Master::TestGen::RSpecGenerator.new

# Generate test for a violation
result = generator.generate_test_for_violation(
  "lib/user.rb",
  { principle: "PRINCIPLE_VALIDATION", line: 45, description: "..." }
)

# Get test coverage
coverage = generator.test_coverage
```

---

## 5. Codebase Knowledge Graph 📊

**Visualize violations, principles, and relationships**

Generate interactive graph visualizations of code quality metrics.

### Features
- Aggregate violations, files, principles
- Generate JSON graph structure
- Calculate metrics (centrality, clusters)
- D3.js compatible format

### Usage

```bash
# Generate graph (display metrics)
$ graph

# Save to file
$ graph --output var/graph.json
```

### Graph Structure

```json
{
  "nodes": [
    {
      "id": "file:lib/auth.rb",
      "type": "file",
      "violations": 5,
      "score": 78
    },
    {
      "id": "principle:SOLID_SRP",
      "type": "principle",
      "violation_count": 12
    }
  ],
  "edges": [
    {
      "from": "file:lib/auth.rb",
      "to": "principle:SOLID_SRP",
      "type": "violates",
      "severity": "high"
    }
  ]
}
```

### API

```ruby
graph = Master::Graph::Knowledge.new

# Add nodes
graph.add_file_node("lib/auth.rb", violations: 5, score: 78)
graph.add_principle_node("SOLID_SRP")

# Add edges
graph.add_edge("file:lib/auth.rb", "principle:SOLID_SRP", type: "violates")

# Calculate metrics
metrics = graph.calculate_metrics

# Export
json = graph.to_json
```

---

## 6. Principle Conflict Resolution Engine ⚖️

**Smart handling when principles contradict**

Detect and resolve conflicts when multiple principles give contradictory advice.

### Features
- Detect principle conflicts
- LLM arbitration for resolution
- Interactive confirmation
- Pattern learning from decisions

### Known Conflicts
- DRY vs WET
- YAGNI vs Extensibility
- SRP vs Cohesion
- Performance vs Readability

### Usage

```bash
# Analyze with conflict resolution (future implementation)
$ analyze lib/ --resolve-conflicts
```

### Example Resolution

```
Conflict detected:
  Location: lib/auth.rb:45
  Principles: PRINCIPLE_DRY, PRINCIPLE_WET

Recommendation: Keep separate (WET wins)
Reason: Different domain concerns

Accept? [y/n/explain]
```

### API

```ruby
resolver = Master::Conflicts::Resolver.new

# Detect conflicts
conflicts = resolver.detect_conflicts(violations)

# Resolve conflict
result = resolver.resolve(conflict, interactive: true)
```

---

## 7. Principle-Driven Refactoring Agents 🤖

**Specialized agents for specific principles**

Each agent focuses on a single principle with specialized detection and fixing.

### Available Agents
- **DRY Agent** - Extract duplicate code
- **SOLID SRP Agent** - Split god classes
- **KISS Agent** - Simplify complex methods
- **Performance Agent** - Fix N+1 queries

### Usage

```bash
# List available agents
$ agent list

# Run specific agent
$ agent dry lib/

# Run all agents
$ agent --all lib/
```

### Example Output

```
DRYAgent: Found 3 violations
[1/3] lib/auth.rb:45
  Duplicate code found (3 occurrences)
  
Proposed fix for lib/auth.rb:
────────────────────────────────────────────────────────
Extract to method: validate_user_credentials
────────────────────────────────────────────────────────

Apply this fix? [y/n]
```

### API

```ruby
# Create agent
agent = Master::Agents::PrincipleAgents::DRYAgent.new

# Scan files
violations = agent.scan(["lib/auth.rb"])

# Run with auto-fix
result = agent.run(files, auto_fix: true)
```

---

## 8. Meta-Evolution Engine 🔄

**MASTER analyzes and improves its own code**

Self-improvement: MASTER runs on its own codebase and generates fixes.

### Features
- Self-analysis of MASTER's code
- Automatic fix generation
- Test execution before merge
- Evolution tracking

### Usage

```bash
# Run meta-evolution
$ meta-evolve

# Run with auto-merge (requires tests to pass)
$ meta-evolve --auto-merge
```

### Evolution Tracking

```yaml
# var/evolution.yml
self_improvements:
  - date: "2026-02-04"
    commit: "abc123"
    violations_fixed: 3
    principles: ["SOLID_SRP", "KISS"]
    success: true
```

### API

```ruby
meta = Master::Evolution::Meta.new

# Analyze own code
result = meta.self_analyze

# Generate fixes
result = meta.generate_self_fixes(auto_apply: true)

# Full evolution cycle
result = meta.evolve(auto_merge: false)
```

---

## Dependencies

### Required
- `parser` (~> 3.3) - Ruby AST parsing for test generation

### Optional
- `ruby-audio` (~> 1.6) - Audio recording for voice interface (commented out)
- `rugged` (~> 1.7) - Git library (optional, can use system git)

### Installation

```bash
cd MASTER
bundle install
```

---

## Integration with Existing Features

All new features integrate seamlessly with MASTER's existing:
- 4-tier LLM pipeline (fast → code → strong → validation)
- Cost tracking and limits
- 33 coding principles
- Session memory and compression

---

## Future Enhancements

- Full Whisper integration for voice interface
- Interactive conflict resolution UI
- Real-time knowledge graph visualization in web UI
- Automated PR creation for meta-evolution
- Team collaboration features for shared memory
- Integration with CI/CD pipelines

---

## Security Notes

- Memory files stored in `.master_memory/` (add to .gitignore if sensitive)
- Git memory uses separate branch to avoid polluting history
- Voice transcription requires API keys (OpenAI or OpenRouter)
- Hook installation modifies `.git/hooks/pre-commit`

---

## Support

For issues or questions:
- Check existing violations with `scan` or `analyze`
- Use `help` to see all available commands
- Memory patterns to understand decision history
- Agent-specific help with `agent list`
