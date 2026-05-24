# Brgen Stimulus / Rails 8 rollout

Brgen already has social core models and Hotwire refreshes marked done in `apps.yml`. Use the shared baseline to port the missing social/product interactions without adding dashboards.

## Core social

1. Notification component for likes, replies, follows, mentions, direct messages.
2. Clipboard for post/community/share links.
3. Reveal for post details, moderation reasons, raw permalink metadata.
4. Dropdown for feed sort: hot, fresh, top, local.
5. Auto Submit + Content Loader for live feed/search filters.
6. Timeago on posts, comments, notifications, messages.
7. Confirmation for moderation actions.

## Subapps

### tv

- Lightbox/Dialog for videos.
- Content Loader for episode/video lists.
- Notification for live broadcast start.
- Timeago for publish/scheduled timestamps.

### dating

- Hotkey/swipe actions for like/dislike.
- Dialog for profile detail.
- Lightbox for profile photos.
- Notification for match.
- Turbo Streams for match-to-message handoff.

### marketplace

- Lightbox + Sortable for product photos.
- Dropdown + Auto Submit for category/price/geo filters.
- Notification for saved search match.
- Confirmation for sold/delete actions.

### playlist

- Sortable for tracks.
- Sound for preview.
- Clipboard for playlist share.
- Notification for track added.

### takeaway

- Dialog for item customization.
- Notification for basket/order state.
- Reveal for allergens.
- Turbo Streams for order status.

## Rails 8 work

- Solid Queue: media variants, search indexing, notifications.
- Solid Cable: direct messages, reactions, order/live status.
- Solid Cache: feeds, community cards, search result fragments.
- SQLite FTS5: posts, communities, marketplace, takeaway, tv, playlist.
- Signed IDs: moderation links, listing edit links, order tracking links.

## Acceptance

- Search has empty/loading/no-results/error states.
- Feed and subapps remain usable without JavaScript.
- Notifications are progressive enhancement over server-rendered lists.
- Moderation actions require confirmation and authorization.
