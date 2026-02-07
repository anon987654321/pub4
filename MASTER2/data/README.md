# MASTER2 Data Files

This directory contains the four core data files that define system behavior:

## Files

### axioms.yml
Timeless engineering, communication, and meta principles from authoritative sources.
Each axiom has a protection level that determines enforcement:

- **ABSOLUTE**: Violation halts the pipeline immediately (Result.err)
- **PROTECTED**: Warning logged, pipeline continues
- **NEGOTIABLE**: Context-dependent, can be overridden with justification
- **FLEXIBLE**: Informational only, no enforcement

### council.yml
The adversarial council of 12 personas that evaluate proposals.
Structured as `config:` (consensus threshold, iteration limits) and `personas:` (individual members).
Weights represent relative influence, not probabilities. Sum ≠ 1.0 is intentional.

### config.yml
System configuration: model rates, budget limits, circuit breaker thresholds, daemon settings.
Values are seeded into the SQLite `config` table at boot.

### shell.yml
OpenBSD command catalog with safety levels and requirements.

## Data Flow

1. **Boot**: YAML files → SQLite seed → In-memory structures
2. **Query**: Stages query DB for axioms/council/config as needed
3. **Enforcement**: Protection levels determine pipeline behavior
