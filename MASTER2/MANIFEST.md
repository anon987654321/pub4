# MANIFEST: MASTER v4 Philosophical Foundation

## Purpose

MASTER v4 exists to enforce quality through recursive self-application. It is not a tool that *suggests* quality—it is a system that *embodies* quality and refuses to produce output that violates its foundational axioms.

## The Axiom System

### What Are Axioms?

Axioms are timeless, universal truths extracted from authoritative sources: *The Pragmatic Programmer*, *Clean Code*, *The Elements of Style*, *The Elements of Typographic Style*, and proven methodologies like SOLID and the Unix Philosophy.

Axioms are not preferences. They are not trends. They are fundamental laws of information systems that transcend languages, frameworks, and eras.

### Protection Levels

- **ABSOLUTE**: Violations halt the system. These axioms define system integrity itself. Example: "The Tool Applies to Itself" (recursive quality).
- **PROTECTED**: Violations generate warnings but allow continuation. These represent best practices that should guide but not block.

### Why Axioms Matter

Every piece of software embodies decisions. Most decisions are ad-hoc, context-dependent, or expedient. Axioms provide a foundation that outlasts projects, teams, and technologies. They are the signal in the noise.

MASTER v4 uses axioms to:
1. Filter out low-quality patterns before they manifest
2. Guide refactoring toward proven structures
3. Create a shared language for quality across domains

## The Adversarial Council

### Why 12 Personas?

A single perspective, no matter how intelligent, has blind spots. Security specialists miss usability problems. Performance engineers over-optimize. Minimalists delete necessary complexity. Ethicists overlook pragmatic constraints.

The council exists to surface these blind spots through structured conflict.

### The Veto System

Three personas have veto power:
1. **Security Officer**: Protects confidentiality, integrity, availability
2. **The Attacker**: Thinks like a malicious actor, finds exploits
3. **The Maintainer**: Represents the 3 AM on-call engineer

These three can unilaterally block proposals. Why? Because security failures, exploitable vulnerabilities, and operational disasters are *existential risks*. No amount of performance gain or aesthetic elegance justifies them.

### Consensus Threshold (70%)

Weighted consensus prevents both groupthink and gridlock. At 70%, a proposal must convince the majority by weight, not just headcount. High-weight personas (Security Officer: 0.30) have proportional influence.

If consensus falls below 70%, the proposal returns to refinement. The council does not vote on taste—it votes on whether a proposal satisfies its respective concerns.

### Oscillation Detection

If the council debates for 25 iterations without convergence, the system halts. This prevents infinite refinement loops and forces explicit human intervention.

## The Pressure/Depressure Metaphor

### Input Tank (Pressure)

User input is verbose, ambiguous, and context-free. The Pressure Tank compresses it:
- Strunk & White: "Omit needless words"
- Intent identification: question, command, refactor, admin
- Entity extraction: files, services, configurations
- Axiom/council loading: context-specific preparation

The result: a dense, precise prompt optimized for downstream processing.

### Output Tank (Depressure)

LLM output is informationally rich but typographically raw. The Depressure Tank refines it:
- Smart quotes, em dashes, ellipses (Bringhurst typography)
- Zsh-pure validation (no bash-isms)
- Multi-model refinement for iterative polishing
- Cost/token summaries

The result: publication-quality output that respects both content and presentation.

## Self-Application Principle

> "A system that asserts quality must first and foremost achieve its own standards. Its first test is self-application."

MASTER v4 is built using the axioms it enforces:
- **DRY**: Result monad eliminates error-handling duplication
- **KISS**: Each stage has one responsibility
- **SOLID (SRP)**: Stages are independent, composable
- **Scout Rule**: Each iteration improves code health
- **Omit Needless Words**: Documentation is concise, direct

If MASTER v4 cannot pass its own council, it has failed.

## Why This Architecture?

### Functional Core (Result Monad)

Imperative error handling (`if err != nil; return err; end`) proliferates. The Result monad makes error propagation explicit, type-safe, and composable. Stages chain via `flat_map`, short-circuiting on first error.

### Stage Pipeline

Each stage transforms input and passes to the next. Stages are:
- **Pure functions**: `call(input) -> Result`
- **Composable**: Pipeline order is configurable
- **Testable**: Stages mock/stub independently

This is not object-oriented design. This is functional composition with minimal ceremony.

### SQLite Persistence

Axioms and council definitions are canonical seed data. SQLite provides:
- **Schema validation**: Types enforce structure
- **Query power**: Filter axioms by category/protection
- **Transactional safety**: Circuit breaker state is consistent
- **Zero dependencies**: No external DB required

### Circuit Breaker & Budget

LLM APIs fail. Networks partition. Rate limits trigger. The circuit breaker prevents cascading failures. The budget prevents runaway costs. Both are operational necessities, not theoretical safeguards.

## Philosophical Influences

- **The Pragmatic Programmer** (Hunt & Thomas): DRY, YAGNI, Scout Rule, POLA
- **Clean Code** (Martin): SOLID, meaningful names, single responsibility
- **The Elements of Style** (Strunk & White): Omit needless words, active voice
- **The Elements of Typographic Style** (Bringhurst): Hierarchy, rhythm, proportion
- **Unix Philosophy**: Simplicity, composition, text streams
- **OpenBSD**: Security by default, pledge/unveil, minimal surface area
- **Nielsen Heuristics**: Usability, visibility, error prevention, consistency

## Anti-Goals

MASTER v4 does **not** aim to:
- Replace human judgment (it augments, not automates)
- Enforce style preferences (only timeless axioms)
- Optimize for speed (correctness precedes performance)
- Support every language/framework (depth over breadth)
- Be "easy" to use (it demands precision)

## Success Criteria

MASTER v4 succeeds if:
1. Every output respects its axioms
2. The council surfaces real concerns, not theater
3. The system applies to itself without exception
4. Engineers trust its judgment over time

If MASTER v4 becomes a rubber stamp, it has failed.
If MASTER v4 blocks every proposal, it has failed.
If MASTER v4 produces output it would reject, it has failed.

The goal: a system worthy of its own standards.
