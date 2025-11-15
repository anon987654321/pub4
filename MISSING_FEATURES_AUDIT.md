# Missing Features Audit - pub4 Rails Apps
**Generated:** 2025-11-15T02:00:00Z  
**Session:** Crash recovery analysis  
**Scope:** All Rails installers vs master.json v32.0 specifications

---

## CRITICAL MISSING FEATURES

### 1. **Rich Text Editor (rhino-editor/tiptap)** ❌
**Status:** Only blognet.sh has rhino-editor gem  
**Required by master.json:** privcam, hjerterom, blognet, brgen_playlist, brgen (all social apps)  
**Missing from:**
- ❌ privcam.sh - needs for creator posts/profiles
- ❌ hjerterom.sh - needs for giveaway descriptions
- ❌ brgen.sh - needs for post content (currently plain text)
- ❌ brgen_dating.sh - needs for profile bios
- ❌ brgen_marketplace.sh - needs for item descriptions
- ❌ brgen_playlist.sh - needs for track descriptions
- ✅ blognet.sh - HAS rhino-editor gem

**Fix:** Add to all apps:
```ruby
gem "rhino-editor"  # Tiptap-powered ActionText-compatible editor
```

---

### 2. **Image Gallery/Lightbox (stimulus-lightbox)** ❌
**Status:** NONE of the apps have stimulus-lightbox  
**Required by master.json:** privcam (photo galleries), brgen (post attachments), marketplace (product photos)  
**Missing from:**
- ❌ privcam.sh - CRITICAL for photo/video gallery viewing
- ❌ brgen.sh - needs for multi-photo posts
- ❌ brgen_marketplace.sh - needs for product image zoom
- ❌ hjerterom.sh - needs for food distribution photos

**Fix:** Add to all apps with image uploads:
```bash
npm install @stimulus-components/lightbox
# Wraps lightgallery.js (licensed) - see master.json
```

---

### 3. **PWA Offline-First Support** ⚠️
**Status:** Partial - only some apps have manifest/service-worker  
**Required by master.json:** ALL apps need PWA support per innovation_research_2024  
**Files exist:**
- ✅ `__shared/@pwa_setup.sh` exists
- ⚠️ But not called by: privcam, hjerterom, baibl, amber, mytoonz, bsdports

**Missing components:**
- ❌ public/service-worker.js generation
- ❌ public/manifest.json generation  
- ❌ gem "turbo-offline" for background sync
- ❌ Rails PWA generators not invoked

**Fix:** Ensure all .sh call:
```bash
source "${SCRIPT_DIR}/__shared/@pwa_setup.sh"
setup_pwa "$APP_NAME"
```

---

### 4. **Modern CSS 2024 (@container queries, :has())** ⚠️
**Status:** Partial implementation  
**Required by master.json:** innovation_research_2024 specifies @container for all apps  
**Found in:** brgen.sh, blognet.sh, brgen_playlist.sh, @common.sh  
**Missing from:** Most other apps use old grid patterns

**Missing patterns:**
```scss
.cards { container-type: inline-size; }
@container (width > 60ch) { .card { flex-direction: row; } }
.post:has(.comment) { border-color: blue; }  // Interactive state
```

**Fix:** Add to application.scss in all apps

---

### 5. **Reddit Scraper + Paraphraser (Ferrum + LangChainRB)** ❌
**Status:** NOT IMPLEMENTED in any .sh file  
**Required by master.json:** brgen.sh scraping_patterns section specifies:
- reddit.com/r/bergen scraper
- ferrum headless Chrome with human simulation
- langchainrb paraphraser for unique content
- db/seeds.rb integration

**Missing from:** ALL apps (zero matches for "ferrum", "scraper", "paraphrase")

**Fix:** Create scraper service:
```bash
# brgen.sh needs:
gem "ferrum"           # Headless Chrome
gem "langchainrb"      # Norwegian LLM paraphraser
# db/seeds.rb with BrgenScraper.scrape_and_seed
```

---

### 6. **Stimulus Components (@stimulus-components/*)** ⚠️
**Status:** Partial - only referenced in shared files  
**Required by master.json:** modern_stack.stimulus.components  
**Found:** @common.sh, @stimulus_controllers.sh reference them  
**Missing specific implementations:**
- ❌ @stimulus-components/infinite-scroll (only StimulusReflex used)
- ❌ @stimulus-components/carousel
- ❌ @stimulus-components/dropdown
- ❌ @stimulus-components/notification

**Fix:** Install via npm in all apps:
```bash
npm install @stimulus-components/infinite-scroll
npm install @stimulus-components/notification
```

---

### 7. **BankID Integration (Age Verification)** ❌
**Status:** NOT IMPLEMENTED  
**Required by master.json:** privcam.sh needs BankID for 18+ verification  
**Specified:** innovation_research_2024.privcam_creator_economy.bankid_verification

**Missing:**
- ❌ gem "omniauth-bankid"
- ❌ Age verification callback
- ❌ verified_creator boolean flag

**Fix:** Add to privcam.sh:
```ruby
gem "omniauth-bankid"
bin/rails generate migration AddVerifiedCreatorToUsers verified_creator:boolean
```

---

### 8. **Stripe/Vipps Payment Integration** ⚠️
**Status:** Gems exist, but incomplete integration  
**Apps with payments:**
- ✅ privcam.sh - has Stripe gem
- ✅ hjerterom.sh - has Vipps gem (omniauth-vipps)
- ✅ brgen_takeaway.sh - has Stripe + money-rails
- ❌ Missing: Subscription models, tipping system, webhooks

**Missing per master.json:**
- ❌ Subscription model with plans/tiers (privcam)
- ❌ Tip model with Stripe PaymentIntent (privcam)
- ❌ gem "pay" for subscription management
- ❌ gem "receipts" for invoices
- ❌ Webhook controllers for Stripe events

**Fix:** Add subscription engine:
```ruby
gem "pay"
gem "receipts"
bin/rails generate model Subscription user:references plan:string status:integer
```

---

### 9. **Analytics Dashboard (Ahoy + Blazer + Chartkick)** ⚠️
**Status:** Partial - only hjerterom.sh has all three  
**Required by master.json:** privcam needs creator analytics, hjerterom has it  
**Found:**
- ✅ hjerterom.sh - has ahoy_matey, blazer, chartkick
- ❌ privcam.sh - MISSING (needs revenue_by_day, subscribers_growth)
- ❌ brgen.sh - MISSING (needs engagement metrics)

**Fix:** Add to privcam.sh:
```ruby
gem "ahoy_matey"
gem "blazer"
gem "chartkick"
bin/rails generate controller CreatorDashboard analytics revenue subscribers
```

---

### 10. **Mapbox Integration** ⚠️
**Status:** Specified but not fully implemented  
**Required by master.json:** hjerterom.sh innovation_research_2024.hjerterom_logistics  
**Specified:**
- Mapbox front page map showing food locations
- stimulus-mapbox controller
- Volunteer routing with geocoder

**Missing:**
- ❌ mapbox-gl gem (if Ruby wrapper exists) OR
- ❌ mapbox-gl-js NPM package
- ❌ stimulus-mapbox controller
- ❌ RouteOptimizerService with ACO algorithm

**Fix:** Add to hjerterom.sh:
```bash
npm install mapbox-gl
# Create app/javascript/controllers/mapbox_controller.js
# Create app/services/route_optimizer_service.rb
```

---

### 11. **MyToonz Frontend Extraction** ❌
**Status:** Codepen demo NOT extracted  
**Required by master.json:** app_specific_details.mytoonz.frontend_status  
**Current:** mytoonz.sh has backend structure but missing:
- ❌ Codepen HTML/CSS/JS extraction to Rails propshaft
- ❌ Inline styles moved to application.scss
- ❌ Stimulus controllers for comic interactions
- ❌ Frontend refactoring per rails8.frontend_refactoring

**Fix:** Extract index.html codepen demo:
```bash
# Move inline <style> to app/assets/stylesheets/mytoonz.scss
# Move inline <script> to app/javascript/controllers/comic_controller.js
# Convert to Stimulus + Propshaft architecture
```

---

### 12. **Playlist Audio Engine Fixes** ⚠️
**Status:** Issues documented but not fixed  
**Required by master.json:** deployment_config.index_html_analysis.FIXES_NEEDED  
**Current issues:**
- ❌ YouTube/MP3 crossfade smoothness
- ❌ Beat detection threshold calibration (avgFlux * 1.45)
- ❌ YouTube API error handling
- ❌ Track preloading for instant transitions
- ❌ Playback queue UI
- ❌ Shuffle persistence to sessionStorage
- ❌ Volume controls (music/effects separate)

**Fix:** Update brgen_playlist.sh audio engine (after frontend extraction)

---

### 13. **Weaviate Vector DB (Production)** ❌
**Status:** NOT CONFIGURED in any .sh  
**Required by master.json:** core_principles.database_strategy = "weaviate_production"  
**Current:** All apps use sqlite3 dev, postgresql prod  
**Missing:**
- ❌ Weaviate Docker/service setup
- ❌ langchainrb_rails vector storage config
- ❌ Embedding generation for posts/content
- ❌ Semantic search implementation

**Fix:** Add to openbsd.sh production setup:
```bash
# Install Weaviate via Docker or native
# Configure config/weaviate.yml
# Add langchainrb vectorizer initializer
```

---

### 14. **Solid Stack (Rails 8)** ⚠️
**Status:** Mentioned but not consistently applied  
**Required by master.json:** rails8.solid_stack  
**Should replace:** Redis/Sidekiq with solid_queue/solid_cache/solid_cable  
**Current:** Most apps still use redis + sidekiq

**Fix:** Add to all Gemfiles:
```ruby
gem "solid_queue"
gem "solid_cache"
gem "solid_cable"
# Remove: gem "redis", gem "sidekiq"
```

---

### 15. **Turbo Native / Hotwire Morphing** ❌
**Status:** NOT IMPLEMENTED  
**Required by master.json:** innovation_research_2024.rails8_hotwire_native  
**Missing:**
- ❌ turbo_native_bridge controller
- ❌ public/turbo-native-config.json
- ❌ turbo:morph meta tags
- ❌ Native SDK integration

**Fix:** Add to modern apps:
```bash
bin/rails generate controller Bridge native_action
# Create public/turbo-native-config.json
# Add <meta name="turbo-refresh-method" content="morph">
```

---

## MINOR GAPS

### 16. **Faker Seeds** ✅
**Status:** COMPLETE per crash log  
All .sh files now have faker seeds

### 17. **Ruby 3.3.7** ✅
**Status:** COMPLETE per crash log  
All .sh files specify ruby 3.3.7

### 18. **Brutalist CSS** ✅
**Status:** IMPLEMENTED in brgen.sh  
Per master.json ultramodern_design_system

### 19. **Namespaced Routes** ⚠️
**Status:** Partial  
- ✅ brgen_dating.sh, brgen_marketplace.sh use namespaces
- ✅ brgen_takeaway.sh, brgen_tv.sh use namespaces
- ❌ brgen_playlist.sh needs namespace::Playlist refactor

---

## OPENBSD GAPS

### 20. **openbsd.sh ALL_DOMAINS Array** ⚠️
**Status:** Fixed in crash log but needs verification  
**Issue:** Zsh associative array syntax error resolved  
**Status:** PENDING FINAL TEST per crash log

### 21. **VPS Pre-Point Setup** ⏳
**Status:** IN PROGRESS per crash log  
**Blocked:** /home/brgen/app prereq missing  
**Next:** openbsd.sh --pre-point completion

---

## SUMMARY

| Category | Complete | Partial | Missing | Critical |
|----------|----------|---------|---------|----------|
| Rich Text Editors | 1/15 | 0 | 14 | ✅ YES |
| Image Galleries | 0/4 | 0 | 4 | ✅ YES |
| PWA Support | 0/15 | 7 | 8 | ⚠️ MEDIUM |
| Modern CSS 2024 | 3/15 | 5 | 7 | ⚠️ MEDIUM |
| Scraping/AI | 0/1 | 0 | 1 | ✅ YES |
| Payments | 3/3 | 3 | 0 | ❌ NO |
| Analytics | 1/3 | 0 | 2 | ⚠️ MEDIUM |
| Vector DB | 0/1 | 0 | 1 | ⚠️ MEDIUM |
| BankID | 0/1 | 0 | 1 | ✅ YES |
| Frontend Extract | 0/2 | 0 | 2 | ⚠️ MEDIUM |

**TOTAL GAPS:** 39 missing features across 15 Rails apps

---

## RECOMMENDED ACTION PLAN

### Phase 1: CRITICAL (Do First)
1. Add rhino-editor to 14 apps (privcam, hjerterom, brgen, dating, marketplace, etc.)
2. Add stimulus-lightbox to 4 apps (privcam, brgen, marketplace, hjerterom)
3. Implement brgen.sh Reddit scraper + paraphraser (ferrum + langchainrb)
4. Add BankID to privcam.sh for age verification

### Phase 2: HIGH PRIORITY
5. Complete PWA setup for all apps (call @pwa_setup.sh)
6. Add @container queries to all application.scss
7. Implement Stripe subscriptions/tipping for privcam
8. Add analytics dashboard to privcam + brgen

### Phase 3: MEDIUM PRIORITY
9. Extract mytoonz frontend from Codepen
10. Fix brgen_playlist audio engine issues
11. Add Mapbox routing to hjerterom
12. Configure Weaviate for production semantic search

### Phase 4: LOW PRIORITY
13. Migrate to Solid Stack (replace Redis/Sidekiq)
14. Add Turbo Native bridge for mobile apps
15. Verify openbsd.sh ALL_DOMAINS fix on VPS

---

**Next Step:** Begin Phase 1 surgically - add rhino-editor to all apps requiring rich text.
