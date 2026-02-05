# Cache Aggressively

> Cache LLM responses. Same prompt = same result.

tier: llm
priority: 32
auto_fixable: true

## Anti-patterns (violations)

### redundant_api_calls
- **Smell**: Same prompt sent multiple times
- **Example**: Identical question costs tokens each time
- **Fix**: Hash prompt, cache response for 24h

### wasted_tokens
- **Smell**: Re-computing what could be cached
- **Example**: System prompt rebuilt on every call
- **Fix**: Precompute, cache, reuse
