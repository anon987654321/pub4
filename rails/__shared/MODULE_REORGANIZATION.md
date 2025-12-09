# __shared Module Reorganization Plan
## Converting from domain-focused to feature-focused naming

## Current State (18 files, 163 KB total)

### Duplicates Found:
- `@chat_features.sh` (19.1 KB) == `@messaging_features.sh` (19.1 KB) - IDENTICAL content
- `@social_features.sh` (14.5 KB) == `@reddit_features.sh` (14.5 KB) - IDENTICAL content  
- `@ai_features.sh` (6.3 KB) == `@langchain_features.sh` (6.3 KB) - IDENTICAL content

### Domain-Focused (Vague):
- @social_features.sh - What does this actually do?
- @marketplace_features.sh - Too broad
- @airbnb_features.sh - Domain-specific, not reusable

### Feature-Focused (Clear):
- ✅ @live_chat.sh - NEW! Clear what it does
- @pwa_setup.sh - Clear
- @stimulus_controllers.sh - Clear
- @view_generators.sh - Clear

## Reorganization Map

### Delete (Duplicates):
```
@chat_features.sh → DELETE (duplicate of @messaging_features.sh)
@social_features.sh → DELETE (duplicate of @reddit_features.sh)
@langchain_features.sh → DELETE (duplicate of @ai_features.sh)
```

### Rename (Feature-Based):
```
@messaging_features.sh → @live_chat.sh (DONE!)
@reddit_features.sh → @posts_and_comments.sh + @voting_and_karma.sh
@marketplace_features.sh → @shopping_cart.sh + @payment_processing.sh  
@airbnb_features.sh → @bookings_and_reservations.sh
@ai_features.sh → @ai_text_generation.sh
```

### Split (Too Large):
```
@common.sh (21.5 KB) → Keep as is (core utilities)
@airbnb_features.sh (19.1 KB) → Split to @bookings_and_reservations.sh + @reviews_and_ratings.sh
```

### Keep As-Is (Already Clear):
```
@core_setup.sh ✓
@pwa_setup.sh ✓  
@rails8_stack.sh ✓
@reflex_patterns.sh ✓
@route_helpers.sh ✓
@stimulus_controllers.sh ✓
@view_generators.sh ✓
load_modules.sh ✓
```

## New Module Structure (14 files, clean & clear)

### Core (4 files):
- @common.sh - Shared utilities
- @core_setup.sh - Rails app initialization
- @rails8_stack.sh - Solid Queue/Cache/Cable
- load_modules.sh - Module loader

### UI/Frontend (4 files):
- @pwa_setup.sh - Progressive Web App
- @stimulus_controllers.sh - Stimulus JS controllers
- @reflex_patterns.sh - StimulusReflex patterns
- @view_generators.sh - CRUD view templates

### Features (10 files):
- @live_chat.sh - Real-time messaging (DONE!)
- @posts_and_comments.sh - Reddit-style posts/comments
- @voting_and_karma.sh - Upvote/downvote system
- @shopping_cart.sh - E-commerce cart
- @payment_processing.sh - Stripe/Vipps/PayPal
- @bookings_and_reservations.sh - Airbnb-style bookings
- @reviews_and_ratings.sh - 5-star reviews
- @ai_text_generation.sh - LangChain/LLM integration
- @file_uploads.sh - ActiveStorage + image processing
- @location_services.sh - Mapbox integration

### Utilities (2 files):
- @route_helpers.sh - RESTful routing helpers
- @test_helpers.sh - RSpec/testing utilities (NEW)

## Execution Order

1. ✅ Create @live_chat.sh (DONE!)
2. Delete duplicates (@chat_features.sh, @social_features.sh, @langchain_features.sh)
3. Rename single modules
4. Split large modules
5. Test each change
6. Update references in main .sh files
7. Commit incrementally

## Benefits

**Before:**
- "What's in @social_features.sh?" → Have to open and read
- "@marketplace_features.sh" → Too vague, what does it include?
- Duplicates waste space and cause confusion

**After:**
- "@live_chat.sh" → Instant clarity: real-time messaging
- "@shopping_cart.sh" → Clear: cart functionality
- "@voting_and_karma.sh" → Clear: Reddit-style voting
- No duplicates, each file has one clear purpose

## Success Criteria

✅ No duplicate files  
✅ All names describe what the module does (not domain)  
✅ Each module has single responsibility  
✅ Under 15KB per file (split if larger)  
✅ All references updated in main generators  
✅ Tests pass after each change  

## Implementation Time

- Deletions: 5 min
- Renames: 15 min
- Splits: 30 min
- Testing: 20 min
- **Total: ~70 minutes**

## Next Actions

1. Delete duplicate files now
2. Rename modules systematically
3. Update load_modules.sh
4. Test one generator to verify imports work
5. Commit with detailed changelog
