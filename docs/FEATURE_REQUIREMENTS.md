# Feature Requirements Update

Date: 2025-12-23
Status: Requirements captured for future implementation

## Brgen Social Features (Reddit Clone)

Current Status: Basic social platform (posts, comments, communities)
Required Additions:
- [ ] Voting system (upvote/downvote on posts and comments)
- [ ] Nested comment threads (already has comments)
- [ ] Subreddit-style communities (has Community model)
- [ ] User karma/reputation system
- [ ] Post sorting (hot, new, top, controversial)
- [ ] Moderation tools
- [ ] Awards/badges system
- [ ] Cross-posting functionality

Assessment: 70% complete for Reddit clone
Missing: Voting, karma, advanced sorting

## X.com (Twitter) Layout

Required Changes:
- [ ] Three-column layout (sidebar, feed, widgets)
- [ ] Fixed left navigation
- [ ] Real-time feed updates (has Solid Cable)
- [ ] Trending topics sidebar
- [ ] Quote tweets/reposts
- [ ] Threading (already has nested comments)
- [ ] Media previews in feed
- [ ] Infinite scroll (mentioned in requirements)

Old CSS Location: __OLD_BACKUPS/**/*
Action: Restore vintage styles from pub repo

## Shared Components (All Apps)

### Social Media Sharing
Required:
- Share to Twitter/X
- Share to Facebook
- Share to LinkedIn
- Copy link button
- QR code generation
- Native share API (mobile)

Implementation:
- Create shared Stimulus controller
- Add to @shared_functions.sh
- Include in all app layouts

### Stimulus Components (stimulus-components.com)
To integrate:
- [ ] Dropdown
- [ ] Modal
- [ ] Tabs
- [ ] Tooltip
- [ ] Notification
- [ ] Autosave
- [ ] Character counter
- [ ] Password visibility
- [ ] Clipboard copy

### LightGallery Lightbox
Features:
- Image zoom
- Video player
- Fullscreen
- Thumbnails
- Sharing
- Download

Integration points:
- Post images
- User uploads
- Gallery views

### Swipe.js
Use cases:
- Image carousels
- Story-style posts
- Mobile navigation
- Card stacks

### Mobile First Enhancements
Priority:
1. Touch-friendly targets (48x48px min)
2. Bottom navigation (thumb zone)
3. Pull to refresh
4. Swipe gestures
5. Offline support (PWA)
6. Fast load times

### PWA Features
Required:
- manifest.json
- Service worker
- Offline fallback
- Install prompt
- Push notifications
- Background sync
- Cache strategy

### StimulusReflex
Already in brgen requirements
Features:
- Real-time updates
- Optimistic UI
- Server-side rendering
- Form validation
- Live search

### Hotwire (Turbo + Stimulus)
Already specified
Ensure:
- Turbo Frames for partial updates
- Turbo Streams for real-time
- Stimulus for interactions
- Turbo Native ready

## Implementation Plan

### Phase 1: Shared Components Library
Create: rails/__shared/
- stimulus_controllers/
  - social_share_controller.js
  - lightgallery_controller.js
  - swipe_controller.js
  - dropdown_controller.js
  - modal_controller.js
- stylesheets/
  - mobile_first.css
  - layout_twitter.css
  - layout_reddit.css
- helpers/
  - social_sharing_helper.rb
  - pwa_helper.rb

### Phase 2: Brgen Enhancements
1. Add voting system
2. Implement karma
3. Create X.com layout variant
4. Restore old CSS from __OLD_BACKUPS
5. Add Reddit-style sorting

### Phase 3: All Apps Integration
1. Update each app generator
2. Include shared components
3. Add PWA manifest
4. Configure service workers
5. Mobile-first CSS

### Phase 4: Testing
1. Mobile responsiveness
2. Offline functionality
3. Performance (Lighthouse)
4. Accessibility (WCAG)

## File Structure

```
rails/
├── __shared/
│   ├── stimulus_controllers/
│   │   ├── social_share_controller.js
│   │   ├── lightgallery_controller.js
│   │   ├── swipe_controller.js
│   │   └── stimulus_components/ (from npm)
│   ├── stylesheets/
│   │   ├── mobile_first.css
│   │   ├── layouts/
│   │   │   ├── twitter.css
│   │   │   └── reddit.css
│   │   └── __OLD_BACKUPS/ (restored)
│   ├── views/
│   │   ├── shared/
│   │   │   ├── _social_share.html.erb
│   │   │   ├── _lightbox.html.erb
│   │   │   └── _pwa_install.html.erb
│   └── javascript/
│       ├── pwa.js
│       └── service_worker.js
├── brgen/
│   ├── app/models/
│   │   ├── vote.rb (NEW)
│   │   └── karma.rb (NEW)
│   └── app/controllers/
│       └── votes_controller.rb (NEW)
└── @shared_functions.sh (enhanced)
```

## Dependencies to Add

Package.json:
```json
{
  "dependencies": {
    "@stimulus-components/dropdown": "^3.0.0",
    "@stimulus-components/modal": "^2.0.0",
    "@stimulus-components/notification": "^3.0.0",
    "lightgallery": "^2.7.0",
    "swiper": "^11.0.0",
    "workbox-webpack-plugin": "^7.0.0"
  }
}
```

Gemfile additions:
```ruby
gem 'acts_as_votable'  # For voting system
gem 'public_activity'  # For activity feeds
gem 'meta-tags'        # For social sharing
```

## Notes for Autonomous Continuation

When implementing:
1. Start with shared components (highest reuse)
2. Add to @shared_functions.sh generators
3. Create templates in __shared/
4. Update each app incrementally
5. Test mobile-first approach
6. Ensure PWA compliance

Priority Order:
1. Social sharing (easy, high value)
2. LightGallery (visual impact)
3. Mobile-first CSS (usability)
4. PWA setup (progressive enhancement)
5. Stimulus components (nice-to-have)
6. Layout variants (brgen-specific)

Estimated Effort:
- Shared components: 4-6 hours
- Brgen enhancements: 6-8 hours
- All apps integration: 8-10 hours
- Testing and polish: 4-6 hours
Total: 22-30 hours

Current Session:
- Continue beautification (priority)
- Document requirements (done)
- Implement features (future session)

All requirements captured for future work.
