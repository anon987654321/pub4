# The 45 Principles of Clean Systems

> A comprehensive guide to building maintainable, elegant, and cost-aware software.

## Table of Contents

- [Core Principles](#core-principles) (3 principles)
- [SOLID Principles](#solid-principles) (5 principles)  
- [Design Patterns](#design-patterns) (5 principles)
- [Reliability](#reliability-principles) (4 principles)
- [Functional Programming](#functional-programming) (3 principles)
- [Code Quality](#code-quality) (5 principles)
- [Clarity](#clarity-principles) (2 principles)
- [Architecture](#architecture-principles) (2 principles)
- [User Experience](#user-experience-principles) (2 principles)
- [Performance](#performance-principles) (3 principles)
- [LLM-Specific](#llm-specific-principles) (2 principles)
- [Safety & UX](#safety-and-ux-principles) (2 principles)
- [Aesthetic & Creative](#aesthetic-and-creative-principles) (3 principles)
- [Communication](#communication-principles) (2 principles)
- [Verification](#verification-principles) (1 principle)
- [Meta-Principles](#meta-principles) (1 principle)

---

## Core Principles

### 01. KISS (Keep It Simple, Stupid)
**Tier:** Core | **Priority:** 1 | **Auto-Fixable:** No

Complexity is the enemy. Simple solutions are easier to understand, debug, and maintain.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Over Engineering** | Building for hypothetical future requirements; abstract factory for single implementation | Delete abstractions until it hurts |
| **Unnecessary Complexity** | Nested conditionals, convoluted logic, 5-level deep if/else chains | Extract methods, use early returns |
| **Premature Abstraction** | Creating `IUserRepository` with only `UserRepository` | Wait for duplication, then abstract |

---

### 02. DRY (Don't Repeat Yourself)
**Tier:** Core | **Priority:** 2 | **Auto-Fixable:** Yes

Every piece of knowledge must have a single, authoritative representation.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Duplicate Code** | Same logic in multiple places (validation in 3 controllers) | Extract to shared method/module |
| **Copy-Paste Programming** | Cloning a function and changing variable names | Parameterize original, reuse it |

---

### 03. YAGNI (You Aren't Gonna Need It)
**Tier:** Core | **Priority:** 3 | **Auto-Fixable:** Yes

Implement things when you need them, never when you foresee needing them.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Speculative Generality** | Building plugin system for app with one plugin | Delete until actually needed |
| **Unused Code** | Methods/classes never called (e.g., `def legacy_handler`) | Delete it |
| **Dead Code** | Unreachable code paths (code after unconditional return) | Delete it |

---

### 04. Separation of Concerns
**Tier:** Core | **Priority:** 4 | **Auto-Fixable:** No

Divide program into distinct sections, each addressing a separate concern.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Mixed Concerns** | User class handles auth, email, and billing | Split into UserAuth, UserMailer, UserBilling |
| **UI Logic in Models** | `User#to_html` or formatting in ActiveRecord | Use presenters/decorators for display logic |
| **Business Logic in Views** | Templates with `<% if user.age > 18 && user.verified? %>` | Move logic to model/presenter, expose simple flags |

---

## SOLID Principles

### 05. Single Responsibility (SOLID S)
**Tier:** SOLID | **Priority:** 5 | **Auto-Fixable:** Yes

A module should have one, and only one, reason to change.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **God Class** | Class over 300 lines or 10+ public methods (e.g., ApplicationController with 50 methods) | Extract concerns into focused classes |
| **Feature Envy** | Method uses another class more than its own (`order.customer.address.city.upcase`) | Move method to the class it envies |
| **Long Method** | Method over 20 lines or 5 nesting levels (100-line `process_order` with 8 if/else branches) | Extract into smaller named methods |

---

### 06. Open-Closed (SOLID O)
**Tier:** SOLID | **Priority:** 6 | **Auto-Fixable:** No

Open for extension, closed for modification.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Shotgun Surgery** | One change requires edits in many files (adding payment type = 12 file changes) | Use strategy pattern, dependency injection |
| **Rigid Design** | Giant switch statement for each type that can't be extended | Use polymorphism, plugins, or hooks |

---

### 07. Liskov Substitution (SOLID L)
**Tier:** SOLID | **Priority:** 7 | **Auto-Fixable:** No

Subtypes must be substitutable for their base types.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Refused Bequest** | `Square < Rectangle` that ignores `height=` | Use composition, or don't inherit |
| **Type Checking** | `if obj.is_a?(Dog) then bark else meow` | Define common interface, let each type implement |

---

### 08. Interface Segregation (SOLID I)
**Tier:** SOLID | **Priority:** 8 | **Auto-Fixable:** No

Clients should not depend on interfaces they don't use.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Fat Interface** | `IRepository` with 30 methods, most unused | Split into smaller role-based interfaces |
| **Forced Implementation** | `def unused_method; raise NotImplementedError; end` | Remove method from interface, use mixins |

---

### 09. Dependency Inversion (SOLID D)
**Tier:** SOLID | **Priority:** 9 | **Auto-Fixable:** No

Depend on abstractions, not concretions.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Tight Coupling** | Class directly instantiates dependencies (`def initialize; @db = PostgreSQL.new; end`) | Inject dependencies through constructor |
| **Hard-Coded Dependencies** | `HTTPClient.get(url)` called in 20 places | Inject abstraction, swap implementations easily |

---

## Design Patterns

### 10. Law of Demeter
**Tier:** Design | **Priority:** 10 | **Auto-Fixable:** Yes

Only talk to your immediate friends. Avoid train wrecks.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Message Chains** | Long chains like `a.b.c.d.e` | Add delegate method: `order.customer_city` |
| **Inappropriate Intimacy** | Accessing private fields via reflection | Use public interface, hide implementation |
| **Feature Envy** | Method with 10 calls to `other.field` | Move method to the class it envies |

---

### 11. Composition Over Inheritance
**Tier:** Design | **Priority:** 11 | **Auto-Fixable:** No

Favor object composition over class inheritance. GoF wisdom.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Deep Hierarchy** | Inheritance chain deeper than 3 levels (`Widget < Control < View < Base < Object`) | Flatten with mixins or composition |
| **Refused Bequest** | `EmptyList < List` that disables `add`, `remove` | Use composition: `has_a` not `is_a` |
| **Inheritance Abuse** | `Stack < ArrayList` just to reuse methods | Compose: `Stack` contains `ArrayList` |

---

### 12. Fail Fast
**Tier:** Reliability | **Priority:** 12 | **Auto-Fixable:** Yes

Errors should be reported as soon as they are detected.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Silent Failure** | Errors caught and ignored (`rescue => e; end`) | Log, re-raise, or handle explicitly |
| **Swallowed Exceptions** | `rescue Exception` that returns nil | Catch specific exceptions, let others bubble |
| **Defensive Nulls** | `find_user \|\| nil` hiding "not found" | Raise exception or use Result monad |

---

### 13. Principle of Least Astonishment
**Tier:** UX | **Priority:** 13 | **Auto-Fixable:** No

Systems should behave as users expect. No surprises.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Surprising Behavior** | `save()` that also sends email notification | Rename or split: `save_and_notify()` |
| **Inconsistent API** | `find` returns nil, `get` raises exception | Establish conventions, document behavior |
| **Hidden Side Effects** | `get_value()` that increments counter | Separate query from command |

---

### 14. Command-Query Separation
**Tier:** Design | **Priority:** 14 | **Auto-Fixable:** Yes

Methods should either change state OR return data, never both.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Side Effects in Queries** | `stack.pop()` returns value AND removes it | Split: `stack.top()` + `stack.remove()` |
| **Mixed Responsibilities** | `calculate_total()` that also saves to DB | `total = calculate(); save(total)` |

---

## Reliability Principles

### 15. Boy Scout Rule
**Tier:** Practice | **Priority:** 15 | **Auto-Fixable:** Yes

Leave the code cleaner than you found it.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Technical Debt Ignored** | `# FIXME: this is broken` from 2019 | Fix it now or delete the comment |
| **Broken Windows** | Dead imports, unused variables, lint warnings | Clean up on each commit, no exceptions |

---

### 16. Unix Philosophy
**Tier:** Architecture | **Priority:** 16 | **Auto-Fixable:** No

Do one thing well. Write programs that work together.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Monolithic Design** | 500k LOC Rails monolith with no boundaries | Extract services, use clear module boundaries |
| **Tight Coupling** | CLI that only works with specific database | Use stdin/stdout, compose with pipes |

---

### 17. Functional Core, Imperative Shell
**Tier:** Architecture | **Priority:** 17 | **Auto-Fixable:** No

Pure logic in the core, side effects at the edges.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Scattered Side Effects** | `calculate_price()` that logs to file | Return data from core, let shell handle IO |
| **Impure Core** | Business logic reading ENV variables | Inject configuration, keep core deterministic |

---

### 18. Idempotent Operations
**Tier:** Reliability | **Priority:** 18 | **Auto-Fixable:** No

Same operation, same result. Critical for distributed systems.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Non-Idempotent Mutations** | `increment_counter()` called twice = +2 | Use `set_counter(value)` instead |
| **Unsafe Retries** | Payment API retried without dedup | Add idempotency key, check before processing |

---

### 19. Defensive Programming
**Tier:** Reliability | **Priority:** 19 | **Auto-Fixable:** Yes

Never trust input. Validate at boundaries.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Missing Validation** | `File.read(params[:path])` - path traversal vulnerability | Whitelist, sanitize, validate all input |
| **Trust Boundary Violation** | API response parsed without schema validation | Validate at boundaries, fail on invalid data |

---

### 20. Graceful Degradation
**Tier:** Reliability | **Priority:** 20 | **Auto-Fixable:** No

Partial functionality beats total failure.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Missing Fallback** | Cache miss = entire page 500 error | Fallback to database, show stale data |
| **Cascade Failures** | Auth service down = all services dead | Circuit breakers, timeouts, bulkheads |

---

## Code Quality

### 21. Explicit Over Implicit
**Tier:** Clarity | **Priority:** 21 | **Auto-Fixable:** Yes

Zen of Python. Clarity over magic.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Magic Values** | `if status == 7` - what is 7? | Use constants: `STATUS_APPROVED = 7` |
| **Hidden Behavior** | Rails `before_save` modifying data silently | Make transformations explicit in code path |
| **Implicit Conversions** | `"5" + 3` behavior varies by language | Explicit: `int("5") + 3` |

---

### 22. Convention Over Configuration
**Tier:** Productivity | **Priority:** 22 | **Auto-Fixable:** No

Sensible defaults reduce boilerplate. Rails fame.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Excessive Configuration** | 200-line XML to configure ORM | Provide sensible defaults, override only when needed |
| **Missing Defaults** | `connect(host, port, timeout, retry, ...)` all required | Default to localhost:5432, timeout 30s, etc. |

---

### 23. Progressive Disclosure
**Tier:** UX | **Priority:** 23 | **Auto-Fixable:** No

Show basics first, details on demand.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Information Overload** | 50-field form on first page | Wizard flow, show advanced only when clicked |
| **No Hierarchy** | Error message same size as help text | Primary action prominent, secondary subdued |

---

### 24. Real-Time Feedback
**Tier:** UX | **Priority:** 24 | **Auto-Fixable:** Yes

Keep users informed of system status.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Silent Operations** | Click button, nothing for 10 seconds | Spinner, progress bar, status message |
| **Missing Progress** | "Installing..." for 5 minutes, no detail | Show step: "Installing 3/7: database..." |

---

### 25. Meaningful Names
**Tier:** Clarity | **Priority:** 25 | **Auto-Fixable:** Yes

Names reveal intent. Clean Code principle.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Cryptic Names** | `def p(x, y, z)` - what do these mean? | `def process_payment(amount, currency, user)` |
| **Abbreviated Names** | `usrAcctMgr` instead of `user_account_manager` | Spell it out, IDE has autocomplete |
| **Generic Names** | `data`, `info`, `temp`, `handler` | Be specific: `user_profile`, `error_message` |

---

### 26. Small Functions
**Tier:** Clean Code | **Priority:** 26 | **Auto-Fixable:** Yes

Functions should do one thing, do it well.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Long Method** | 150-line `process_order()` method | Extract: `validate()`, `calculate()`, `persist()` |
| **Multiple Responsibilities** | `save_and_email_and_log()` | Split into `save()`, `email()`, `log()` |

---

### 27. Few Arguments
**Tier:** Clean Code | **Priority:** 27 | **Auto-Fixable:** Yes

Ideal is zero to two arguments. Three is suspicious.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Long Parameter List** | `create(a, b, c, d, e, f, g)` - 7 args | Group into parameter object or builder |
| **Parameter Objects Needed** | `(host, port, user, pass)` in 10 methods | Create `ConnectionConfig` object |

---

## Functional Programming

### 28. No Side Effects
**Tier:** Functional | **Priority:** 28 | **Auto-Fixable:** No

Functions shouldn't change state they don't own.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Hidden Side Effects** | `get_user()` that also updates last_accessed | Make explicit: `get_user()` + `touch_user()` |
| **Global Mutation** | `calculate()` that sets `$result` | Return value instead of mutating global |

---

### 29. Immutability
**Tier:** Functional | **Priority:** 29 | **Auto-Fixable:** No

Prefer immutable data. Fewer bugs, easier reasoning.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Mutable Shared State** | Global config hash modified at runtime | Freeze objects, use thread-local copies |
| **Defensive Copies Needed** | `arr.dup` everywhere to avoid mutation | Use frozen/immutable data structures by default |

---

### 30. Pure Functions
**Tier:** Functional | **Priority:** 30 | **Auto-Fixable:** Yes

Same input, same output. No side effects.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Impure Functions** | `calculate()` returns different values based on time | Pass all dependencies as parameters |
| **Hidden Dependencies** | `process()` reads `ENV["MODE"]` internally | Accept mode as parameter: `process(mode)` |

---

## Performance & LLM

### 31. Cost Transparency
**Tier:** LLM | **Priority:** 31 | **Auto-Fixable:** Yes

Show LLM costs in real-time. Users must know spend.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Hidden Costs** | LLM query completes, no cost shown | Display `[$0.0023, 847 tokens]` after each call |
| **Surprise Bills** | Month-end $500 invoice, no prior warning | Running total, alerts at thresholds |

---

### 32. Cache Aggressively
**Tier:** LLM | **Priority:** 32 | **Auto-Fixable:** Yes

Cache LLM responses. Same prompt = same result.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Redundant API Calls** | Identical question costs tokens each time | Hash prompt, cache response for 24h |
| **Wasted Tokens** | System prompt rebuilt on every call | Precompute, cache, reuse |

---

### 33. Squint Test (Visual Rhythm)
**Tier:** Aesthetic | **Priority:** 33 | **Auto-Fixable:** Yes

Code and documents should look pleasing from afar. Visual structure reveals balance before readability.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Wall of Text** | Dense blocks with no visual breaks (50-line method, no blank lines) | Add breathing room between logical sections |
| **Ragged Indentation** | Mix of 2-space and 4-space indents | Enforce consistent indentation |
| **Orphan Lines** | One-line method lost in 500-line file | Group related code together |
| **Asymmetric Structure** | 10 methods then 1 giant method | Balance method sizes or extract class |
| **No Paragraph Breaks** | README as single wall of text | Break into digestible paragraphs |

---

## Aesthetic & Creative

### 34. Prose Over Lists
**Tier:** Communication | **Priority:** 34 | **Auto-Fixable:** No

Flowing prose is easier to read than bullets, numbered lists, or tables. Prose carries momentum.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Bullet Point Thinking** | "Features: - Fast - Secure - Simple" | Write a sentence connecting ideas |
| **Numbered Steps** | "1. Open file 2. Edit 3. Save" | Describe workflow as continuous prose |
| **Table Abuse** | Tables for key-value pairs instead of data | Write prose or use simple inline format |

---

### 35. Mass Generation with Curation
**Tier:** Creative | **Priority:** 35 | **Auto-Fixable:** No

When quality matters, generate many variations and curate ruthlessly. Create 60-70 alternatives, keep the best 8.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **First Draft Syndrome** | Accepting first output without alternatives | Generate a swarm and curate |
| **Incremental Refinement** | Tweaking same design for hours | Explore breadth before depth |
| **False Scarcity** | Limiting to 3 variations to save time | Generate abundantly when stakes are high |

---

### 36. Analog Warmth Over Digital Perfection
**Tier:** Aesthetic | **Priority:** 36 | **Auto-Fixable:** Yes

Perfect is sterile. Imperfection is human. Apply tasteful analog artifacts to generated media.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Clinical Output** | AI portrait with plastic skin and uniform lighting | Apply film stock emulation and subtle grain |
| **Over-Sharpening** | Edges with halos from aggressive unsharp mask | Embrace natural softness of vintage lenses |
| **Uniform Color** | Mathematically perfect color with no drift | Add lift to shadows and subtle color cast |

---

### 37. Guard Expensive Operations
**Tier:** Safety | **Priority:** 37 | **Auto-Fixable:** Yes

Before running costly operations, estimate cost and confirm intent. Display estimate clearly. Never surprise the user.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Silent Spending** | Video generation without showing estimated cost | Display cost estimate before execution |
| **Accidental Production** | Database drop without explicit confirmation | Require explicit opt-in for dangerous actions |
| **Runaway Loops** | Retry loop on paid API without limit | Set hard limits and circuit breakers |

---

## Verification & Interface

### 38. Dual Detection (Literal and Conceptual)
**Tier:** Verification | **Priority:** 38 | **Auto-Fixable:** No

Run both literal (regex/AST) and conceptual (LLM) searches. Neither alone catches everything.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Regex Only** | Checking for long methods but missing conceptual bloat | Add LLM-based semantic analysis |
| **LLM Only** | Missing obvious syntactic violations | Add deterministic pattern matching first |
| **Single Pass** | One linter run before commit | Layer multiple detection strategies |

---

## Communication

### 39. Accessible Then Technical
**Tier:** Communication | **Priority:** 39 | **Auto-Fixable:** No

Documentation should welcome newcomers first, then gradually increase technical depth. Never lead with jargon.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Jargon First** | README starting with API signatures | Lead with plain English explanation |
| **Buried Vision** | Why explained after How | State the vision in the first paragraph |
| **Uniform Depth** | Expert-only documentation | Gradient from accessible to technical |

---

### 40. No Abbreviations
**Tier:** Communication | **Priority:** 40 | **Auto-Fixable:** Yes

Write full words. Abbreviations save keystrokes but cost clarity. They exclude newcomers and create ambiguity.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Jargon Soup** | "Config the repos env vars for the apps API" | Expand all abbreviations to full words |
| **Inconsistent Abbreviation** | "config" and "cfg" in same file | Pick full word and use it everywhere |
| **Ambiguous Shorthand** | "auth" meaning authentication or authorization | Write the full word to remove ambiguity |

---

## Performance & Aesthetics

### 41. Graceful Degradation Under Load
**Tier:** Performance | **Priority:** 41 | **Auto-Fixable:** Yes

When performance degrades, reduce quality incrementally rather than crashing. Use EWMA to detect frame drift.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **All-or-Nothing Quality** | No frame rate detection or quality adjustment | Add EWMA frame timing and dynamic resolution scaling |
| **Hidden Tab Burn** | Animation loop ignores visibility state | Check `document.hidden` and throttle or pause |
| **No Emergency Brake** | Quality degrades forever without hard limit | Set minimum quality floor and emergency reset |

---

### 42. Precompute Expensive Math
**Tier:** Performance | **Priority:** 42 | **Auto-Fixable:** Yes

Trig, noise lookups, and complex formulas should be precomputed and stored in lookup tables.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Hot Path Trig** | `Math.sin()` and `Math.cos()` called every frame per object | Precompute trig tables indexed by angle step |
| **Repeated Noise** | Simplex noise recalculated for static texture | Generate noise texture once and sample from it |
| **Redundant Sqrt** | Distance calculated multiple times for same points | Cache distance or use squared distance comparison |

---

### 43. Audio-Reactive Smoothing
**Tier:** Aesthetic | **Priority:** 43 | **Auto-Fixable:** No

Apply exponential smoothing to frequency bands. Use separate accumulators for bass, beat, and energy.

#### Anti-Patterns

| Smell | Example | Fix |
|-------|---------|-----|
| **Raw Audio Jitter** | Direct mapping of FFT bin to size | Apply exponential smoothing accumulator |
| **Uniform Reactivity** | Everything reacts the same way to audio | Separate accumulators with different decay rates |
| **Instant Attack Decay** | Beat triggers instant full brightness | Use attack-decay envelope for beat pulse |

---

### 44. Typography Discipline
**Tier:** Aesthetic | **Priority:** 44 | **Auto-Fixable:** No

Structure through contrast, whitespace, and restraint—not decoration. Hierarchy via weight and brightness.

#### Key Guidelines
- Hierarchy via weight/brightness, never ASCII art
- One color per semantic meaning
- Whitespace is the primary layout tool
- Proximity groups related items
- Success whispers, errors speak loudly
- Five icons maximum, single meaning each

#### Anti-Patterns
- ASCII separators (`---`, `===`) add noise
- Box drawing (`╭╮╰╯│─`) clutters
- Overuse of bold defeats hierarchy

---

### 45. Silence by Default
**Tier:** Interface | **Priority:** 45 | **Auto-Fixable:** No

Successful operations produce minimal output; verbosity is opt-in. Errors always get full context.

#### Key Guidelines
- Default to silence on success
- One line for routine completions
- Verbose output only via explicit flag
- Errors always get full context
- Never bury the outcome in noise

#### Anti-Patterns
- Multi-line success messages
- Verbose routine completions
- Burying outcomes in decorative noise

---

## Meta-Principles

### Meta-Principles
**Tier:** Meta | **Priority:** 0 | **Auto-Fixable:** No

Principles about principles. Self-reference for the system.

---

## Summary by Tier

### Core (3 principles)
- KISS, DRY, YAGNI
- Foundation for all other work

### SOLID (5 principles)
- Single Responsibility, Open-Closed, Liskov Substitution, Interface Segregation, Dependency Inversion
- Enterprise-grade OOP patterns

### Design (5 principles)
- Law of Demeter, Composition Over Inheritance, Command-Query Separation, plus 2 more from reliability tier

### Reliability (4 principles)
- Fail Fast, Idempotent Operations, Defensive Programming, Graceful Degradation
- Critical for production systems

### Functional (3 principles)
- No Side Effects, Immutability, Pure Functions
- Composability and reasoning

### Code Quality (5 principles)
- Explicit Over Implicit, Meaningful Names, Small Functions, Few Arguments, plus Convention Over Configuration

### Performance (3 principles)
- Cache Aggressively, Precompute Math, Graceful Degradation Under Load

### UX & Communication (6 principles)
- Progressive Disclosure, Real-Time Feedback, Accessible Then Technical, No Abbreviations, Typography, Silence by Default

### Aesthetic & Creative (3 principles)
- Squint Test, Analog Warmth, Audio-Reactive Smoothing

### LLM-Specific (2 principles)
- Cost Transparency, Cache Aggressively

### Safety (1 principle)
- Guard Expensive Operations

### Verification (1 principle)
- Dual Detection

---

## Using These Principles

**Prioritization:** Start with Core principles (1-3), then SOLID (5-9), then reliability.

**Conflict Resolution:** Core > SOLID > Design > Everything else.

**Team Adoption:** Post principles 1-15 in your team space. Once habits form, introduce tiers progressively.

**Automated Checking:** Combine regex patterns from "smell" definitions with LLM analysis (Dual Detection).

---

**Version**: MASTER v52.0 REFLEXION  
**Last Updated**: 2024-02-05  
**Total Principles**: 45 + 1 meta  
**Auto-Fixable**: ~25 principles  
**Anti-Patterns Documented**: 107
