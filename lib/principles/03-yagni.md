# YAGNI (You Aren't Gonna Need It)

> Implement things when you need them, never when you foresee needing them.

tier: core
priority: 3
auto_fixable: true

## Anti-patterns (violations)

### speculative_generality
- **Smell**: Building for imagined future requirements
- **Example**: Plugin system for an app with one plugin
- **Fix**: Delete until actually needed

### unused_code
- **Smell**: Methods/classes never called
- **Example**: `def legacy_handler` with zero references
- **Fix**: Delete it

### dead_code
- **Smell**: Unreachable code paths
- **Example**: Code after unconditional return
- **Fix**: Delete it
