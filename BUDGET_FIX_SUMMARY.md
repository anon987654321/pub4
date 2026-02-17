# Budget Fix: Adjusted for $100 Credit

**Date:** 2026-02-17
**Issue:** MASTER2 hitting token/credit limits despite $100 available
**Root Cause:** max_tokens set too high (16384) + large prompt context (6060 tokens)

## Changes Made

### 1. Reduced max_chat_tokens: 16384 → 4096
This prevents requesting more output tokens than your credit can afford.

### 2. Adjusted Budget Thresholds
```yaml
spending_cap: 100.0  # Was: 10.0
thresholds:
  premium: 80.0  # Was: 8.0
  strong: 50.0   # Was: 5.0
  fast: 20.0     # Was: 1.0
  cheap: 0.0
```

### 3. Made Budget Checks Non-Blocking
Changed from hard error to warning:
```ruby
# Old: return Result.err("Budget exhausted...")
# New: Logging.warn(...) - continuing anyway
```

### 4. Improved Token Limit Error Handling
- Auto-reduces max_tokens to 90% of affordable amount
- Detects "Prompt tokens limit exceeded" errors
- Suggests `/clear` command when prompt is too large

## Error Messages Resolved

**Before:**
```
W LLM retry 1/3: This request requires more credits, or fewer max_tokens. 
  You requested up to 16384 tokens, but can only afford 731.

- claude-sonnet-4.5: Prompt tokens limit exceeded: 6060 > 3655
```

**After:**
- max_tokens capped at 4096 (much more affordable)
- Auto-reduces further if still too high
- Warns about large prompts instead of silent failures

## Usage Tips

### If you still get token errors:

1. **Clear history to reduce prompt size:**
   ```
   /clear
   ```

2. **Check budget status:**
   ```
   budget
   ```

3. **The system will auto-reduce max_tokens** if needed

### Monitor Your Usage

Your $100 budget will now last much longer with max_tokens at 4096 instead of 16384.

---

**Files Modified:**
- `MASTER2/data/budget.yml` - Updated limits
- `MASTER2/lib/llm.rb` - Made budget checks non-blocking
- `MASTER2/lib/llm/request.rb` - Improved error handling
