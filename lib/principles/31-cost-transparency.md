# Cost Transparency

> Show LLM costs in real-time. Users must know spend.

tier: llm
priority: 31
auto_fixable: true

## Anti-patterns (violations)

### hidden_costs
- **Smell**: API calls without showing token/cost count
- **Example**: LLM query completes, no cost shown
- **Fix**: Display `[$0.0023, 847 tokens]` after each call

### surprise_bills
- **Smell**: Users discover costs only at billing
- **Example**: Month-end $500 invoice, no prior warning
- **Fix**: Running total, alerts at thresholds
