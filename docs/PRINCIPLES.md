# MASTER Principles

This document provides a comprehensive guide to all 43 principles that govern the MASTER system. These principles enforce software quality, maintainability, and reliability at every level.

## Table of Contents

- [Overview](#overview)
- [Principle Categories](#principle-categories)
- [Design Principles (1-4)](#design-principles-1-4)
- [SOLID Principles (5-9)](#solid-principles-5-9)
- [Quality Principles (10-24)](#quality-principles-10-24)
- [Code Principles (25-30)](#code-principles-25-30)
- [Architecture Principles (31-43)](#architecture-principles-31-43)
- [Enforcement](#enforcement)

## Overview

Each principle includes:
- **Name**: Clear, memorable identifier
- **Description**: What the principle means
- **Tier**: Category (design, solid, quality, code, architecture)
- **Priority**: Importance level (1-43)
- **Anti-patterns**: Common violations to avoid
- **Auto-fixable**: Whether violations can be automatically corrected

## Principle Categories

### Design Principles
Core design philosophy that applies to all software decisions.

### SOLID Principles
Object-oriented design fundamentals for maintainable systems.

### Quality Principles
Operational excellence, reliability, and user experience.

### Code Principles
Day-to-day coding practices and naming conventions.

### Architecture Principles
System-level design and performance optimization.

---

## Design Principles (1-4)

### 01 - KISS (Keep It Simple, Stupid)

**Description**: Favor simplicity. The simplest solution is usually the best.

**Anti-patterns**:
- Over-engineering: Adding complexity before it's needed
- Premature optimization: Optimizing before profiling
- Clever code: Code that's hard to understand despite working

**Examples**:
```ruby
# Bad: Over-engineered
class DataProcessor
  def process(data)
    @strategy_factory.create_processor(data.type)
                     .with_validator(@validator_chain)
                     .apply_transformers(@transformer_registry)
                     .execute(data)
  end
end

# Good: Simple and clear
class DataProcessor
  def process(data)
    validate(data)
    transform(data)
    save(data)
  end
end
```

**Enforcement**: Complexity metrics, file size limits, method length checks.

---

### 02 - DRY (Don't Repeat Yourself)

**Description**: Every piece of knowledge should have a single, unambiguous representation.

**Anti-patterns**:
- Copy-paste programming: Duplicating code instead of extracting
- Magic numbers: Hardcoded values repeated throughout
- Parallel hierarchies: Matching class structures that change together

**Examples**:
```ruby
# Bad: Repeated logic
def calculate_discount_for_gold(price)
  price * 0.8
end

def calculate_discount_for_silver(price)
  price * 0.9
end

# Good: Single source of truth
DISCOUNT_RATES = { gold: 0.8, silver: 0.9 }

def calculate_discount(price, tier)
  price * DISCOUNT_RATES[tier]
end
```

**Enforcement**: Duplication detection (flay), pattern matching for repeated code.

---

### 03 - YAGNI (You Aren't Gonna Need It)

**Description**: Don't implement features until they are actually needed.

**Anti-patterns**:
- Speculative generality: Creating frameworks for imagined future needs
- Unused features: Code that serves no current purpose
- Infrastructure overkill: Building capabilities before requirements exist

**Examples**:
```ruby
# Bad: Building for unknown future
class User
  def export_to_json; end
  def export_to_xml; end
  def export_to_csv; end
  def export_to_yaml; end  # Nobody asked for this
end

# Good: Build only what's needed now
class User
  def to_json  # Only format currently required
    { id: id, name: name }.to_json
  end
end
```

**Enforcement**: Dead code detection, unused method analysis.

---

### 04 - Separation of Concerns

**Description**: Different concerns should be handled by different modules.

**Anti-patterns**:
- Mixed responsibilities: Business logic in views
- Tangled dependencies: Everything depends on everything
- God objects: Single class doing too much

**Examples**:
```ruby
# Bad: Controller doing too much
class OrdersController
  def create
    order = Order.new(params)
    order.save
    email = "Order #{order.id} confirmed"
    Net::SMTP.start('smtp.example.com') { |smtp| smtp.send(email) }
    render json: order
  end
end

# Good: Separated concerns
class OrdersController
  def create
    order = CreateOrder.call(params)
    OrderMailer.confirmation(order).deliver_later
    render json: order
  end
end
```

**Enforcement**: Layering checks, dependency analysis, concern detection.

---

## SOLID Principles (5-9)

### 05 - Single Responsibility (SOLID S)

**Description**: A module should have one, and only one, reason to change.

**Anti-patterns**:
- God class: Class over 300 lines or 10+ public methods
- Feature envy: Method uses another class more than its own
- Long method: Method over 20 lines or 5 nesting levels

**Enforcement**: Class method count, dependency limits, file size checks.

---

### 06 - Open-Closed (SOLID O)

**Description**: Software entities should be open for extension, closed for modification.

**Anti-patterns**:
- Shotgun surgery: Single change requires editing many files
- Switch statements: Type checking instead of polymorphism
- Modification cascades: Changes ripple through unrelated code

**Enforcement**: Change impact analysis, switch statement detection.

---

### 07 - Liskov Substitution (SOLID L)

**Description**: Subtypes must be substitutable for their base types without breaking functionality.

**Anti-patterns**:
- Refused bequest: Subclass raises errors on parent methods
- Strengthened preconditions: Subclass is more restrictive
- Weakened postconditions: Subclass delivers less than promised

**Enforcement**: Contract violation detection, type checking.

---

### 08 - Interface Segregation (SOLID I)

**Description**: Clients should not depend on interfaces they don't use.

**Anti-patterns**:
- Fat interfaces: Interfaces with dozens of methods
- Interface pollution: Forcing clients to implement unused methods
- Monolithic APIs: Single interface for all use cases

**Enforcement**: Interface method count, implementation coverage analysis.

---

### 09 - Dependency Inversion (SOLID D)

**Description**: Depend on abstractions, not concretions. High-level modules should not depend on low-level modules.

**Anti-patterns**:
- Direct instantiation: `new` called everywhere
- Concrete dependencies: Depending on specific implementations
- Hard-coded collaborators: Cannot test in isolation

**Enforcement**: New operator detection, dependency injection analysis.

---

## Quality Principles (10-24)

### 10 - Law of Demeter

**Description**: Only talk to your immediate friends. Don't reach through objects.

**Anti-patterns**:
- Train wrecks: `user.account.subscription.plan.price`
- Inappropriate intimacy: Reaching into object internals
- Message chains: Multiple dots in a single expression

**Enforcement**: Pattern matching for chained method calls.

---

### 11 - Composition Over Inheritance

**Description**: Favor object composition over class inheritance.

**Anti-patterns**:
- Deep inheritance: More than 3 levels deep
- Implementation inheritance: Inheriting behavior, not interface
- Fragile base class: Changes break all subclasses

**Enforcement**: Inheritance depth checks, hierarchy analysis.

---

### 12 - Fail Fast

**Description**: Detect errors early and fail immediately rather than propagating bad state.

**Anti-patterns**:
- Silent failures: Errors swallowed without handling
- Defensive nulls: Returning nil instead of raising
- Late detection: Problems discovered far from source

**Examples**:
```ruby
# Bad: Silent failure
def divide(a, b)
  return nil if b.zero?
  a / b
end

# Good: Fail fast
def divide(a, b)
  raise ArgumentError, "Cannot divide by zero" if b.zero?
  a / b
end
```

---

### 13 - Principle of Least Astonishment

**Description**: Software should behave in ways that users expect.

**Anti-patterns**:
- Surprising behavior: Methods that don't match their names
- Inconsistent APIs: Similar operations work differently
- Hidden side effects: Methods that do more than they say

---

### 14 - Command-Query Separation

**Description**: Methods should either change state (command) or return data (query), not both.

**Anti-patterns**:
- Query with side effects: `user.name` saves to database
- Unclear intent: Can't tell if method mutates
- Mixed responsibilities: Single method does two jobs

---

### 15 - Boy Scout Rule

**Description**: Leave code cleaner than you found it.

**Anti-patterns**:
- Degrading quality: Each change makes code worse
- Technical debt accumulation: Never paying down debt
- Broken windows: Tolerating small problems

---

### 16 - Unix Philosophy

**Description**: Do one thing well. Write programs that work together.

**Anti-patterns**:
- Monolithic design: Single app does everything
- Tight coupling: Components can't be used independently
- Reinventing wheels: Building instead of composing

---

### 17 - Functional Core, Imperative Shell

**Description**: Pure functions at the core, side effects at the edges.

**Anti-patterns**:
- Mixed paradigms: Side effects throughout codebase
- Untestable core: Business logic depends on I/O
- Stateful computation: Functions that mutate global state

---

### 18 - Idempotent Operations

**Description**: Operations should produce same result regardless of how many times they're executed.

**Anti-patterns**:
- Non-idempotent APIs: Repeated calls cause different outcomes
- Accumulating state: Each call adds more changes
- Race conditions: Concurrent calls produce inconsistent results

---

### 19 - Defensive Programming

**Description**: Validate inputs, check preconditions, handle edge cases.

**Anti-patterns**:
- Trusting input: No validation
- Missing guards: Assumptions not checked
- Error propagation: Letting errors bubble unchecked

---

### 20 - Graceful Degradation

**Description**: System should degrade gracefully when resources are constrained.

**Anti-patterns**:
- Binary failure: Works perfectly or crashes completely
- No fallbacks: Single point of failure
- Resource exhaustion: No limits or throttling

---

### 21 - Explicit Over Implicit

**Description**: Make behavior obvious and visible rather than hidden.

**Anti-patterns**:
- Magic behavior: Actions happen invisibly
- Hidden dependencies: Unclear what's required
- Implicit state: Variables modified behind the scenes

---

### 22 - Convention Over Configuration

**Description**: Provide sensible defaults, allow overrides only when needed.

**Anti-patterns**:
- Configuration explosion: Everything requires setup
- No defaults: Must configure before anything works
- Unclear conventions: Non-standard patterns

---

### 23 - Progressive Disclosure

**Description**: Show complexity gradually, simple first then advanced.

**Anti-patterns**:
- Overwhelming interfaces: Everything visible at once
- No learning path: Beginners must know everything
- Feature dumping: All capabilities exposed equally

---

### 24 - Real-Time Feedback

**Description**: Provide immediate feedback for user actions.

**Anti-patterns**:
- Silent operations: No indication of progress
- Batch feedback: Learn about errors hours later
- Delayed validation: Problems discovered too late

---

## Code Principles (25-30)

### 25 - Meaningful Names

**Description**: Names should reveal intent and be pronounceable.

**Anti-patterns**:
- Single-letter variables: `x`, `tmp`, `data`
- Abbreviations: `usr`, `mgr`, `ctx`
- Misleading names: Names that lie about purpose

**Examples**:
```ruby
# Bad
def proc(u)
  u.n.upcase
end

# Good
def format_username(user)
  user.name.upcase
end
```

---

### 26 - Small Functions

**Description**: Functions should be small and focused on one task.

**Anti-patterns**:
- Long methods: Over 20 lines
- Deep nesting: More than 3 levels
- Multiple concerns: Function does several things

**Enforcement**: Method length checks, nesting level analysis.

---

### 27 - Few Arguments

**Description**: Functions should have few arguments (ideally 0-2, max 3).

**Anti-patterns**:
- Long parameter lists: 5+ arguments
- Flag arguments: Booleans that change behavior
- Out parameters: Arguments modified by function

---

### 28 - No Side Effects

**Description**: Functions should not have hidden side effects.

**Anti-patterns**:
- Hidden mutations: Modifying global state
- File system changes: Writing files unexpectedly
- Network calls: Making requests silently

---

### 29 - Immutability

**Description**: Prefer immutable data structures.

**Anti-patterns**:
- Mutable collections: Lists modified in place
- Shared state: Multiple components mutating same object
- Temporal coupling: Order of calls matters

---

### 30 - Pure Functions

**Description**: Functions with no side effects that always return same output for same input.

**Anti-patterns**:
- Timestamp dependencies: Using current time
- Random behavior: Non-deterministic results
- I/O operations: Reading files, making requests

---

## Architecture Principles (31-43)

### 31 - Cost Transparency

**Description**: Make resource costs visible and trackable.

**Enforcement**: Budget tracking, cost reporting in queue system.

---

### 32 - Cache Aggressively

**Description**: Cache expensive operations, check modification times.

**Examples**: Principle loading uses mtime-based caching, configuration cached until files change.

---

### 33 - Squint Test (Visual Rhythm)

**Description**: Code should look pleasing from afar before reading details.

**Anti-patterns**:
- Visual noise: Inconsistent indentation
- Wall of text: No whitespace or structure
- Irregular patterns: Random formatting

---

### 34 - Prose Over Lists

**Description**: Write in narrative paragraphs, not bullet points.

**Anti-patterns**:
- List explosion: Everything as bullets
- No flow: Disconnected fragments
- Missing context: Lists without explanation

---

### 35 - Mass Generation with Curation

**Description**: Generate many options (64), curate to best (8).

**Implementation**: Swarm generator in creative workflows.

---

### 36 - Analog Warmth Over Digital Perfection

**Description**: Embrace imperfection and organic feel.

**Implementation**: Film emulation, grain, halation effects in postprocessing.

---

### 37 - Guard Expensive Operations

**Description**: Check preconditions before expensive operations.

**Examples**:
```ruby
# Check budget before processing
return nil if @budget && @spent >= @budget
```

---

### 38 - Dual Detection (Literal and Conceptual)

**Description**: Detect violations both by pattern matching and semantic analysis.

**Implementation**: Regex patterns for literal violations, LLM for conceptual violations.

---

### 39 - Accessible Then Technical

**Description**: Start with plain language, layer technical details.

**Anti-patterns**:
- Jargon first: Technical terms without introduction
- No context: Assuming expert knowledge
- Information dump: Everything at once

---

### 40 - No Abbreviations

**Description**: Write full words, avoid abbreviations except well-known ones (API, HTTP, URL).

**Examples**:
```ruby
# Bad
def proc_usr_req(ctx)
  mgr.proc(ctx)
end

# Good
def process_user_request(context)
  manager.process(context)
end
```

---

### 41 - Graceful Degradation Under Load

**Description**: Quality degrades smoothly under high load, never crashes.

**Implementation**: Frame time averaging, emergency brakes in animations.

---

### 42 - Precompute Expensive Math

**Description**: Compute trigonometric functions once, store in lookup tables.

**Implementation**: Sine/cosine tables for audio-reactive animations.

---

### 43 - Audio-Reactive Smoothing

**Description**: Smooth audio data with exponential filtering.

**Implementation**: Separate accumulators for bass, beat, energy with different decay rates.

---

## Enforcement

Principles are enforced through multiple mechanisms:

### Literal Detection
Pattern matching using regular expressions in `lib/violations.rb`. Detects:
- Method chains (Law of Demeter)
- Long methods (Small Functions)
- Magic numbers (DRY)
- Complexity patterns (KISS)

### Conceptual Detection
LLM-based analysis for subtle violations that regex cannot catch.

### Git Hooks
Pre-commit hook at `.git/hooks/pre-commit` validates staged files.

### Validation Tool
`bin/validate_principles` checks files against all principles:
```bash
bin/validate_principles              # Check all lib/ files
bin/validate_principles --verbose    # Show detailed output
bin/validate_principles file.rb      # Check specific file
```

### Port Checker
`bin/check_ports` validates deployment configuration for conflicts.

### CI/CD Integration
Add to your CI pipeline:
```yaml
- name: Validate principles
  run: bin/validate_principles
  
- name: Check ports
  run: bin/check_ports
```

### Severity Levels
- **Critical**: Must fix before commit
- **High**: Should fix before commit
- **Medium**: Warning, can commit
- **Low**: Informational

### Auto-fix Capability
Some principles support automatic fixes. Enable with:
```bash
bin/validate_principles --fix
```

Currently auto-fixable principles: Single Responsibility (extracting methods).

---

For more details on enforcement configuration, see `docs/ENFORCEMENT.md`.
