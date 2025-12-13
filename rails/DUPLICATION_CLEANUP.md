# Duplication Cleanup - Rails Generators

**Status:** Ready to execute  
**Impact:** Removes ~2,010 lines of duplicate code  
**Time:** <1 minute  

## Files to Delete

Close Chrome first to free up memory, then run:

```powershell
cd G:\pub\rails\__shared

# Delete duplicates (keep the semantic names)
Remove-Item @langchain_features.sh  # Keep @ai_features.sh
Remove-Item @airbnb_features.sh     # Keep @marketplace_features.sh
Remove-Item @messaging_features.sh  # Keep @chat_features.sh
Remove-Item @reddit_features.sh     # Keep @social_features.sh
```

## Verification

After deletion, you should have 15 shared modules (down from 19):

```powershell
Get-ChildItem @*.sh | Measure-Object
# Expected: Count = 15
```

## Files Kept (Semantic Names)

- ✅ `@ai_features.sh` - Future-proof for non-LangChain AI
- ✅ `@marketplace_features.sh` - Comprehensive marketplace features  
- ✅ `@chat_features.sh` - Shorter, clearer name
- ✅ `@social_features.sh` - More generic than "reddit"

## Next Step

After duplication cleanup, integrate Rails 8 Solid Stack by updating `@common.sh`:

```zsh
# Line 11 (after existing sources), add:
source "${SCRIPT_DIR}/@rails8_stack.sh"
```

---

**Generated:** 2025-12-13 03:31 UTC  
**Per:** ANALYSIS_COMPLETE_2025-12-13.md Priority 1
