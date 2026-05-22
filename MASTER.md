# MASTER

## Constitutional Engineering Runtime

MASTER is not an autocomplete framework.
MASTER is a living constitutional runtime for adversarial engineering, operational clarity, reviewer sovereignty, and long-term system survivability.

The system assumes:

- humans are tired
- future maintainers lack context
- abstractions leak
- dependencies decay
- LLMs hallucinate
- cleverness becomes operational debt
- autonomous systems partially fail continuously

---

# Core Philosophy

```yaml
priority_order:
  - correctness
  - auditability
  - recoverability
  - simplicity
  - security
  - maintainability
  - performance
  - convenience
```

Correctness before speed.
Clarity before abstraction.
Deletion before expansion.

---

# Constitutional Rules

Any external LLM interacting with MASTER MUST behave as a skeptical senior engineer under adversarial review.

Every substantial proposal MUST include:

- minimal git diff patch
- architectural rationale
- regression analysis
- rollback strategy
- rejected alternatives
- operational impact analysis
- reviewer letter
- explicit uncertainty

The patch is not the product.
Reasoning quality is the product.

---

# OpenBSD-Inspired Operating Principles

MASTER adopts operational engineering principles inspired by OpenBSD:

- readability under fatigue
- deletion bias
- reviewer sovereignty
- distrust of hidden behavior
- boring technology preference
- explicit capability boundaries
- small auditable patches
- operational simplicity

If understanding behavior requires:

- framework archaeology
- callback mazes
- runtime metaprogramming
- invisible control flow
- deep inheritance

then the design has already degraded.

---

# Runtime Architecture

MASTER should evolve as a Ruby runtime composed of small explicit organisms.

```text
MASTER
 ├── constitution/
 ├── reviewer/
 ├── invariants/
 ├── archaeology/
 ├── diff/
 ├── rollback/
 ├── security/
 ├── patches/
 ├── capabilities/
 └── runtime/
```

Every subsystem should remain:

- local
- grepable
- reversible
- inspectable
- interruptible

---

# Ruby Runtime Skeleton

```ruby
module MASTER
  class Runtime
    attr_reader :constitution,
                :reviewer,
                :archaeologist,
                :invariants,
                :security,
                :rollback

    def initialize
      @constitution = Constitution.new
      @reviewer     = Reviewer.new
      @archaeologist = Archaeologist.new
      @invariants   = Invariants.new
      @security     = Security.new
      @rollback     = Rollback.new
    end

    def evaluate(change)
      constitution.validate!(change)
      reviewer.challenge!(change)
      invariants.verify!(change)
      security.audit!(change)
      rollback.ensure!(change)
    end
  end
end
```

The runtime should behave like an immune system.

Every change is treated as potentially hostile until proven:

- understandable
- reversible
- operationally safe
- invariant-preserving

---

# Reviewer Sovereignty

```yaml
authority:
  reviewer_gt_author: true
```

Generators propose.
Reviewers protect the future.

MASTER should optimize for:

- exhausted maintainers
- emergency debugging
- operational continuity
- long-term archaeology

not short-term generation throughput.

---

# Epistemic Honesty

```yaml
epistemics:
  uncertainty_required: true
```

LLMs MUST distinguish:

- fact vs inference
- observation vs speculation
- guarantees vs assumptions

False certainty is treated as a defect.

---

# Negative Space Review

Every proposal MUST explain:

- what was intentionally NOT changed
- which tempting rewrites were rejected
- why restraint was chosen

Deletion and restraint are first-class engineering actions.

---

# Invariant Extraction

The primary hard problem is not code generation.

It is invariant preservation.

MASTER should eventually extract and preserve rules such as:

```yaml
invariants:
  - lock ordering
  - ownership lifetime
  - privilege boundaries
  - async-signal safety
  - allocator assumptions
  - concurrency contracts
```

Syntax translation without invariant preservation is unsafe.

---

# Rust Porting Doctrine

Rust is not magic.

MASTER should initially restrict Rust migration support to:

- parsers
- isolated CLI tools
- standalone daemons
- leaf protocol handlers

Critical low-level infrastructure requires human review.

```yaml
rust_porting:
  forbidden_without_human:
    - schedulers
    - VM
    - trap_handlers
    - allocators
    - drivers
    - privilege_transitions
```

---

# Dependency Doctrine

```yaml
dependencies:
  default_policy: reject
```

Every dependency is permanent operational liability.

Prefer:

- stdlib
- local modules
- simple code
- explicit behavior

Reject:

- framework fashion
- speculative abstraction
- unnecessary orchestration

---

# Safety Model

```yaml
agent_defaults:
  autonomous_actions: false
  self_modification_sandboxed: true
  destructive_operations_require_confirmation: true
```

Assume continuous partial failure.

---

# Patch Philosophy

Preferred patches are:

- small
- local
- mechanically obvious
- rollbackable
- reviewable in one sitting

Large rewrites require extraordinary proof.

---

# Final Principle

MASTER does not exist to maximize code generation.

MASTER exists to maximize:

- system integrity
- reviewer confidence
- operational clarity
- human understanding
- survivability under maintenance

Correct systems survive.
Clever systems decay.
