# Fresh Perspective Pattern

**Pattern**: Periodically simulate context reset to generate radical alternatives and prevent bloat.

## When to Apply

- When file grows >2x original size
- Every N iterations (e.g., every 10 commits)
- When user requests "step back and rethink"
- When hitting diminishing returns on incremental improvements

## Process

### Step 1: Compare with Git History
```bash
# Find historical minimalism peaks
git log --all --oneline -- master.json | head -30

# Compare current vs historical
git diff --stat <historical_commit> HEAD -- master.json

# Identify bloat direction
git show <minimal_version>:master.json | wc -l
wc -l master.json
```

### Step 2: Simulate Context Reset

**Mental Exercise**: Pretend you're seeing the file for the first time with fresh eyes.

**Questions to Ask**:
1. If I started from scratch, would I build this?
2. What would I delete if forced to cut 80%?
3. What's duplication vs. actual enforcement?
4. What can be referenced instead of duplicated?
5. What's JSON-enforceable vs. should-be-documentation?

### Step 3: Generate 15 Radical Alternatives

**Template**:
```
Alternative 1: [Name]
- Approach: [One sentence]
- Rationale: [Why this might be better]
- Tradeoffs: [What you lose]

Alternative 2: [Name]
...

Alternative 15: [Name]
```

**Categories to Explore**:
1. **Extreme Minimalism**: 50 lines or less
2. **External References**: URLs to industry standards
3. **Different Format**: YAML, TOML, executable code
4. **Separation**: Split into multiple files
5. **Hybrid**: Minimal JSON + extensive docs
6. **Auto-generation**: Generate on demand
7. **Schema-only**: JSON Schema without narrative
8. **Metric-based**: Objectives not rules
9. **Event-driven**: Hooks not data
10. **Pattern language**: Composable patterns
11. **Test-driven**: Tests as spec
12. **Natural language**: Prose instead of JSON
13. **Git hooks**: Enforce in git not LLM
14. **Constraint solver**: Logic programming
15. **URL-based**: Extend remote configs

### Step 4: Select Best Hybrid

Usually the answer is combining multiple alternatives:
- Keep CRITICAL enforcement in JSON
- Extract documentation to Markdown
- Reference industry standards (Rubocop, ESLint)
- Split large sections into separate files

### Step 5: Implement Consolidation

**Checklist**:
- [ ] Backup current version
- [ ] Create minimal enforcement-only version
- [ ] Extract detailed docs to Markdown
- [ ] Add references to external standards
- [ ] Verify all enforcement preserved
- [ ] Measure reduction (should be 50%+ smaller)
- [ ] Commit with clear rationale

## Codifying This Pattern

Add to `master.json`:
```json
"meta_patterns": {
  "fresh_perspective_trigger": {
    "when": ["file_size_2x_original", "every_10_commits", "user_requests"],
    "process": [
      "Compare with git history to find bloat direction",
      "Simulate context reset - view file with fresh eyes",
      "Generate 15 radical alternatives across different paradigms",
      "Select hybrid approach (usually: minimal JSON + external docs)",
      "Implement consolidation with verification"
    ],
    "goal": "Prevent creeping complexity, maintain intelligent minimalism",
    "details": "docs/FRESH_PERSPECTIVE.md"
  }
}
```

## Example: v42.4.0 → v43.0.0

**Problem**: Grew from 179 lines (v55.0) to 1075 lines (v42.4.0) = +500% bloat

**Fresh Perspective Analysis**:
- **Alternative 15 chosen**: Hybrid (minimal JSON + external docs + industry refs)
- **Result**: 1075 → 206 lines = 81% reduction
- **Preserved**: All CRITICAL enforcement, operational convergence, prediction engine
- **Extracted**: Principles to docs/principles.md, style guides to docs/style_guides/
- **Referenced**: Rubocop, ESLint, StandardJS instead of duplicating

**Verification**:
```bash
# Before
wc -l master.json  # 1075 lines

# After
wc -l master.json  # 206 lines
wc -l docs/principles.md  # ~200 lines (documentation, not enforcement)

# Total: Same information, better organization
```

## Anti-Patterns to Avoid

❌ **Don't**: Add every best practice you learn to the config
✅ **Do**: Add only what you can automatically enforce

❌ **Don't**: Duplicate industry standards (Rubocop, ESLint)
✅ **Do**: Reference them with minimal overrides

❌ **Don't**: Mix enforcement with education
✅ **Do**: JSON for enforcement, Markdown for education

❌ **Don't**: Repeat information that's in code comments
✅ **Do**: Single source of truth (prefer code comments for local context)

## Metrics

**Healthy Signals**:
- Config size stable or shrinking over time
- >80% of content is machine-enforceable
- New principles require deleting old ones (conservation of complexity)
- References to external standards increasing

**Unhealthy Signals**:
- Config growing faster than codebase
- Mostly narrative explanation, little enforcement
- Duplicating content from official docs
- No references to industry standards

## Tools

```bash
# Measure bloat over time
git log --format="%h %s" --stat -- master.json | grep 'insertion'

# Find historical minimal versions
git log --all --format="%h %s" -- master.json | grep -i 'minimal\|consolidat\|simplif'

# Compare sizes
git show <commit>:master.json | wc -l
```
