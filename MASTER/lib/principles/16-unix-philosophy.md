# Unix Philosophy

> Do one thing well. Write programs that work together.

tier: architecture
priority: 16
auto_fixable: false

## Anti-patterns (violations)

### monolithic_design
- **Smell**: Single app does everything
- **Example**: 500k LOC Rails monolith with no boundaries
- **Fix**: Extract services, use clear module boundaries

### tight_coupling
- **Smell**: Components can't be used independently
- **Example**: CLI that only works with specific database
- **Fix**: Use stdin/stdout, compose with pipes
