# Shared Modules Rename Plan - Universal Features Only

**Analysis Date:** 2025-12-13 04:08 UTC  
**Scope:** 14 shared modules → Rename to descriptive, universal names

---

## Current → Proposed Renames

### Keep As-Is (Clear Names)
- ✅ `@core_setup.sh` - Ruby, PostgreSQL, Redis, Rails setup
- ✅ `@rails8_stack.sh` - Solid Queue/Cache/Cable
- ✅ `@pwa_setup.sh` - Progressive Web App features
- ✅ `@route_helpers.sh` - Route manipulation
- ✅ `@view_generators.sh` - CRUD view templates
- ✅ `@stimulus_controllers.sh` - 12 Stimulus controllers
- ✅ `@reflex_patterns.sh` - StimulusReflex patterns
- ✅ `load_modules.sh` - Module loader

### Rename for Clarity (6 files)

**1. @social_features.sh → @votable_commentable.sh**
```
Functions: Reddit-style voting, threaded comments, karma
Universal?: YES - Used in brgen, amber, blognet, bsdports
Why rename: "social" is vague, "votable_commentable" describes what it does
```

**2. @chat_features.sh → @realtime_messaging.sh**
```
Functions: Conversations, messages, typing indicators, ActionCable
Universal?: PARTIAL - Only brgen, privcam, amber use it
Why rename: "chat" → "realtime_messaging" clarifies ActionCable-based
```

**3. @marketplace_features.sh → @booking_payments.sh**
```
Functions: Bookings, reviews, availability, host profiles, payments
Universal?: PARTIAL - Only marketplace, takeaway, hjerterom use it
Why rename: "marketplace" → "booking_payments" clarifies Airbnb-style features
```

**4. @ai_features.sh → @langchain_completion.sh**
```
Functions: LangChain, RAG, semantic search, content generation
Universal?: RARE - Only amber, baibl might use it
Why rename: "ai" is vague, "langchain_completion" is specific
```

**5. @live_chat.sh → @actioncable_chat.sh**
```
Functions: ActionCable live chat channels
Universal?: YES - All apps have real-time features
Why rename: Distinguish from @realtime_messaging (which is Messenger-style)
```

**6. @live_search.sh → @debounced_search.sh**
```
Functions: Debounced search with StimulusReflex
Universal?: YES - All apps have search
Why rename: "live" is vague, "debounced" describes the pattern
```

**7. @common.sh → @shared_functions.sh**
```
Functions: Central loader + 30+ setup/generate functions
Universal?: YES - Required by all apps
Why rename: "common" doesn't indicate it's the MAIN loader
Alternative: Keep as @common.sh (convention)
```

---

## Truly Universal Features (Used by 90%+ of apps)

Based on analysis:

✅ **Voting + Comments** (@votable_commentable.sh)
- Used by: brgen, amber, blognet, bsdports, hjerterom, pub_attorney
- 6/15 apps = 40% (not universal, but social apps need it)

✅ **Real-time Updates** (@actioncable_chat.sh + @debounced_search.sh)
- Used by: ALL apps need real-time features
- 15/15 apps = 100% (UNIVERSAL)

✅ **CRUD Views** (@view_generators.sh)
- Used by: ALL apps
- 15/15 apps = 100% (UNIVERSAL)

✅ **Stimulus Controllers** (@stimulus_controllers.sh)
- Used by: ALL apps
- 15/15 apps = 100% (UNIVERSAL)

❌ **Booking/Payments** (@booking_payments.sh)
- Used by: marketplace, takeaway, hjerterom only
- 3/15 apps = 20% (NOT universal - rename anyway for clarity)

❌ **AI/LangChain** (@langchain_completion.sh)
- Used by: amber, baibl maybe
- 2/15 apps = 13% (NOT universal - consider removing or separate repo)

---

## Final Recommendation

### Rename These 4 (Universal + Clarity)
```bash
mv @social_features.sh @votable_commentable.sh
mv @live_chat.sh @actioncable_chat.sh
mv @live_search.sh @debounced_search.sh
mv @common.sh @shared_functions.sh  # Or keep as @common.sh
```

### Rename These 2 (Non-universal but clarify)
```bash
mv @chat_features.sh @messenger_conversations.sh
mv @marketplace_features.sh @booking_reviews_payments.sh
```

### Consider Separating (Rare use)
```bash
# Move to separate optional repo or delete if unused
@ai_features.sh → Move to @optional/ or delete
```

---

## Impact Assessment

**Before:**
- Vague names: social, chat, marketplace, ai, live_*
- Hard to know what each provides
- Duplicates deleted but names still unclear

**After:**
- Descriptive: votable_commentable, actioncable_chat, debounced_search
- Clear what Rails patterns each implements
- Follows Rails naming conventions (Concern-style)

**Breaking Changes:**
- All app generators source these modules
- Must update `source` statements in all .sh files
- Estimated impact: 15 apps × 4 renames = 60 source statements

**Alternative: Keep @common.sh, only rename the 5 feature modules**

---

## Your Decision

**Option A: Rename all 6 (including @common.sh)**
- Most descriptive
- Breaking change to core loader

**Option B: Rename 5 feature modules only (keep @common.sh)**
- Less breaking
- @common.sh is conventional

**Option C: Rename 4 universal + 2 non-universal (all 6)**
- Balanced approach
- Clear distinction between universal and domain-specific

**What's your preference?**

---

**Generated:** 2025-12-13 04:08 UTC  
**Awaiting:** Your naming decision before executing renames
