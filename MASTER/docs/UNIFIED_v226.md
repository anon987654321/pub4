# MASTER v226 - Unified Deep Debug Framework

Complete documentation for the unified framework combining Constitutional AI, Bug Hunting Protocol, Resilience Engine, and Systematic Protocols.

## Overview

MASTER v226 "Unified Deep Debug" merges three powerful frameworks:

- **v38 Constitutional AI**: 7 personas, 12 biases, 7 depth techniques
- **v38 Bug Hunting Protocol**: 8-phase systematic debugging
- **v226 Resilience Engine**: Never give up, act-react loop
- **MASTER's 43 Principles**: Core design and implementation rules

## Quick Start

### Interactive Mode

```bash
cd MASTER
ruby lib/cli_v226.rb
```

Launches a conversational REPL with:
- Visual mood indicators
- Persona switching
- Status reporting
- Interactive debugging tools

### Batch Analysis Mode

```bash
# Basic analysis
ruby lib/cli_v226.rb lib/postpro.rb

# With bug hunting
ruby lib/cli_v226.rb lib/postpro.rb --debug

# JSON output
ruby lib/cli_v226.rb lib/postpro.rb --json
```

## CLI Options

```
-d, --debug          Enable 8-phase bug hunting protocol
-j, --json           Output results in JSON format
-p, --persona=MODE   Set persona mode (ronin, verbose, hacker, poet, detective)
-i, --interactive    Force interactive mode
-h, --help           Show help
```

## Architecture

### Components

```
MASTER/
├── lib/
│   ├── cli_v226.rb          # Unified CLI (interactive + batch)
│   ├── postpro.rb           # Enhanced with new stocks/presets
│   └── unified/             # Unified framework components
│       ├── mood_indicator.rb    # Visual feedback
│       ├── personas.rb          # Character modes
│       ├── bug_hunting.rb       # 8-phase analyzer
│       ├── resilience.rb        # Never give up engine
│       └── systematic.rb        # Required workflows
├── config/
│   └── master_v226.yml      # Unified configuration
└── docs/
    └── UNIFIED_v226.md      # This file
```

## Features

### 1. Enhanced Postpro

New film stocks with metadata:
- **Ilford HP5**: Classic B&W, versatile, forgiving latitude (1931)
- **Portra 400**: Natural skin tones, wedding favorite (1998)
- **Portra 800**: Low light versatility, warm palette (1998)
- **CineStill 50D**: Daylight tungsten-balanced, clean highlights (2012)

New presets:
- **cyberpunk**: Neon dystopia, blade runner aesthetics
- **vintage_home_video**: VHS nostalgia, family memories
- **lomography**: Happy accidents, toy camera aesthetic
- **documentary**: Unvarnished truth, photojournalism

Performance improvements:
- Caching for repeated transformations
- Graceful fallback when libvips unavailable
- Returns CSS filters as alternative

Usage:
```ruby
require_relative 'lib/master'

# List all presets
puts MASTER::Postpro.list_presets

# Apply preset
result = MASTER::Postpro.apply_preset('image.jpg', preset: :cyberpunk)
```

### 2. Constitutional AI

Multi-perspective analysis with 7 personas:
- **Pragmatist** (20%): Fastest path to working code
- **Perfectionist** (15%): Quality, edge cases, robustness
- **Minimalist** (20%): Simplicity, deletion, KISS
- **User Advocate** (15%): UX, clarity, documentation
- **Security Expert** (15%): Vulnerabilities, safety
- **Performance Engineer** (10%): Speed, memory, scalability
- **Maintainer** (5%): Future readability, technical debt

12 cognitive biases actively countered:
- Confirmation bias
- Anchoring bias
- Availability heuristic
- Sunk cost fallacy
- Dunning-Kruger effect
- Not invented here syndrome
- Bikeshedding
- Recency bias
- Optimism bias
- Planning fallacy
- Fundamental attribution error
- Hindsight bias

7 depth-forcing techniques:
- Five Whys
- Inversion
- Rubber Duck
- Binary Search
- Minimal Reproduction
- Constraint Inversion
- Time Travel Debug

### 3. Bug Hunting Protocol

8-phase systematic analysis:

#### Phase 1: Lexical Consistency
- Variable naming
- Typos, case sensitivity
- Scope issues

#### Phase 2: Simulated Execution
- Trace control flow
- State at each step
- Branch conditions

#### Phase 3: Assumption Interrogation
- Challenge every assumption
- Input validation
- Environment checks

#### Phase 4: Data Flow Analysis
- Track data from source to sink
- Type coercions
- Unexpected mutations

#### Phase 5: State Archaeology
- Git history analysis
- Recent changes
- Configuration drift

#### Phase 6: Pattern Recognition
- Off-by-one errors
- Race conditions
- Resource leaks
- Unhandled edge cases

#### Phase 7: Proof of Understanding
- Write failing test
- Explain bug to others
- Predict fix behavior

#### Phase 8: Verification
- Run tests
- Manual testing
- Monitor in production

Usage:
```ruby
require_relative 'lib/unified/bug_hunting'

analyzer = MASTER::Unified::BugHunting.new('lib/file.rb')
results = analyzer.analyze

# Or use class method
results = MASTER::Unified::BugHunting.analyze_file('lib/file.rb')

puts results[:total_issues]
puts results[:severity]
```

### 4. Resilience Engine

Never give up approach with act-react loop:

```ruby
require_relative 'lib/unified/resilience'

engine = MASTER::Unified::Resilience.new

# Solve problem with automatic iteration
result = engine.solve("Find bug in authentication") do |action|
  # Your attempt here
  test_hypothesis(action)
end

# View status
puts engine.report

# Get debugging techniques
five_whys = engine.five_whys("Authentication fails")
rubber_duck = engine.rubber_duck(code)
binary_search = engine.binary_search_debug(problem_space)
minimal_repro = engine.minimal_reproduction(context)
```

Features:
- Automatic iteration (up to 100 attempts)
- Reset protocol after 10 failed attempts
- Creative problem solving strategies
- Analogy application
- Constraint thinking
- Extreme case analysis

### 5. Systematic Protocols

Required workflows before operations:

```ruby
require_relative 'lib/unified/systematic'

# Before entering directory
MASTER::Unified::Systematic.before_directory('./lib')

# Before editing file
MASTER::Unified::Systematic.before_edit('lib/file.rb')

# Before committing
MASTER::Unified::Systematic.before_commit

# After error
MASTER::Unified::Systematic.after_error(context)
```

Patterns:
- **tree**: Understand structure before diving deep
- **clean**: Read entire file before editing
- **diff**: Review changes before commit
- **logs**: Check full context after error

### 6. Mood Indicator

Visual feedback for terminal UI:

```ruby
require_relative 'lib/unified/mood_indicator'

mood = MASTER::Unified::MoodIndicator.new

mood.set(:idle)      # ○ White - Waiting
mood.set(:thinking)  # ◐ Cyan - Thinking
mood.set(:working)   # ◑ Yellow - Working
mood.set(:success)   # ● Green - Success
mood.set(:error)     # ✗ Red - Error

mood.display("Processing...")
mood.pulse(:working, "Building...", duration: 0.5)
mood.clear
```

### 7. Persona Modes

Character-based output formatting:

```ruby
require_relative 'lib/unified/personas'

persona = MASTER::Unified::PersonaMode.new(mode: :verbose)

# Available modes
persona.switch(:ronin)      # Terse, 10 words max
persona.switch(:verbose)    # Explanatory, 500 words
persona.switch(:hacker)     # Security-focused, paranoid
persona.switch(:poet)       # Beautiful, metaphorical
persona.switch(:detective)  # Analytical, methodical

# Format output
output = persona.format_output("Your text here")
puts output
```

## Configuration

Edit `config/master_v226.yml` to customize:

```yaml
features:
  enable_constitutional_ai: true
  enable_bug_hunting: false      # Opt-in
  enable_resilience: false       # Opt-in
  enable_systematic_protocols: true
  enable_caching: true
  enable_metrics: true
```

## Examples

### Example 1: Analyze File with Bug Hunting

```bash
ruby lib/cli_v226.rb lib/postpro.rb --debug
```

Output:
```
╔══════════════════════════════════════════╗
║  Analysis Results                      ║
╚══════════════════════════════════════════╝
File: lib/postpro.rb
Time: 2026-02-06T00:00:00+0000

Basic Metrics:
  Lines: 961
  Methods: 49
  Classes: 0

Bug Hunting Results:
  Total issues: 3
  Severity: low
```

### Example 2: Interactive Mode with Persona

```bash
ruby lib/cli_v226.rb --interactive
```

```
╔══════════════════════════════════════════╗
║  MASTER v226 - Unified Deep Debug    ║
╚══════════════════════════════════════════╝

Type 'help' for commands, 'exit' to quit
Current persona: verbose

○ master › persona ronin
✓ Switched to persona: ronin

○ master › status

System Status:
  Mode: interactive
  Persona: ronin
  Current mood: idle
```

### Example 3: JSON Output for CI/CD

```bash
ruby lib/cli_v226.rb lib/file.rb --json | jq '.analysis.bug_hunting.total_issues'
```

### Example 4: Using Resilience Engine

```ruby
require_relative 'lib/unified/resilience'

engine = MASTER::Unified::Resilience.new

result = engine.solve("Fix authentication bug") do |action|
  # Try different approaches
  if action[:iteration] < 5
    approach_a
  else
    approach_b
  end
end

if result.ok?
  puts "Solved: #{result.value}"
else
  puts "Failed: #{result.error}"
end
```

## Testing

Test postpro enhancements:
```bash
ruby -r ./MASTER/lib/master.rb -e "puts MASTER::Postpro.list_presets"
```

Test CLI modes:
```bash
# Interactive
ruby MASTER/lib/cli_v226.rb --interactive

# Batch
ruby MASTER/lib/cli_v226.rb MASTER/lib/postpro.rb

# Bug hunting
ruby MASTER/lib/cli_v226.rb MASTER/lib/postpro.rb --debug

# JSON
ruby MASTER/lib/cli_v226.rb MASTER/lib/postpro.rb --json
```

Run MASTER tests:
```bash
cd MASTER
ruby test/test_master.rb
```

## Design Philosophy

### Minimalism
- Keep It Simple, Stupid (KISS)
- You Aren't Gonna Need It (YAGNI)
- Do one thing well

### Constitutional
- 48 total principles (43 MASTER + 5 v38)
- Multi-perspective decision making
- Bias mitigation built-in

### Resilient
- Never give up on problems
- Systematic iteration
- Automatic reset when stuck

### Observable
- Visual feedback (mood indicators)
- Multiple output formats (text, JSON)
- Clear status reporting

## Integration with MASTER

The unified framework extends MASTER without breaking existing functionality:

```ruby
require_relative 'lib/master'

# Use existing MASTER features
llm = MASTER::LLM.new
cli = MASTER::CLI.new

# Use new unified features
bug_hunter = MASTER::Unified::BugHunting.new('file.rb')
mood = MASTER::Unified::MoodIndicator.new
persona = MASTER::Unified::PersonaMode.new
```

## Performance

Optimizations:
- TTY lazy-loading (fast startup)
- Transformation caching (postpro)
- Minimal dependencies
- Pure Ruby implementation

## Contributing

Follow MASTER's 48 constitutional principles:
1. Keep it simple (KISS)
2. Don't repeat yourself (DRY)
3. You aren't gonna need it (YAGNI)
4. Separation of concerns
5. Single responsibility
... (see config/master_v226.yml for complete list)

## License

MIT - Same as MASTER

## Version History

- **v226.0.0** (2026-02-06): Initial unified framework release
  - Enhanced postpro with 4 new stocks, 4 new presets
  - Unified CLI with interactive + batch modes
  - 8-phase bug hunting protocol
  - Resilience engine with act-react loop
  - Systematic protocols enforcement
  - Mood indicators and persona modes

## Resources

- Configuration: `config/master_v226.yml`
- Components: `lib/unified/`
- Examples: This document
- Tests: `test/test_master.rb`

## Support

For issues, questions, or contributions, see MASTER's main README.

---

*MASTER v226 - Unified Deep Debug - Constitutional AI meets Systematic Debugging*
