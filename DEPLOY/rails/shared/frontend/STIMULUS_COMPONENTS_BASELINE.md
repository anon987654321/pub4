# Shared Stimulus Components baseline

This baseline is for Rails apps under `DEPLOY/rails`.

It is intentionally app-neutral. Each app should copy only the controllers it needs and keep the UI progressive: plain HTML must still work without JavaScript.

## Actual Stimulus Components to standardize

Use the standalone packages from `stimulus-components.com` where they fit product UI:

- `@stimulus-components/auto-submit`
- `@stimulus-components/character-counter`
- `@stimulus-components/checkbox-select-all`
- `@stimulus-components/clipboard`
- `@stimulus-components/content-loader`
- `@stimulus-components/dialog`
- `@stimulus-components/dropdown`
- `@stimulus-components/hotkey`
- `@stimulus-components/lightbox`
- `@stimulus-components/notification`
- `@stimulus-components/popover`
- `@stimulus-components/read-more`
- `@stimulus-components/reveal`
- `@stimulus-components/scroll-to`
- `@stimulus-components/sortable`
- `@stimulus-components/sound`
- `@stimulus-components/speech-recognition`
- `@stimulus-components/textarea-autogrow`
- `@stimulus-components/timeago`

## Rails 8 defaults

Every app should prefer:

- Turbo Frames for replaceable panels.
- Turbo Streams for live updates.
- Solid Queue for expensive work.
- Solid Cable for real-time status.
- Solid Cache for index/feed/card/search fragments.
- Active Storage for media attachments.
- Signed IDs or signed messages for user-facing action tokens.
- Structured events for product telemetry.
- Local CI for repeatable app verification.

## Shared install shape

For importmap apps:

```ruby
# config/importmap.rb
pin "@hotwired/stimulus", to: "https://esm.sh/@hotwired/stimulus@3.2.2"
pin "@stimulus-components/clipboard", to: "https://esm.sh/@stimulus-components/clipboard"
pin "@stimulus-components/notification", to: "https://esm.sh/@stimulus-components/notification"
pin "@stimulus-components/reveal", to: "https://esm.sh/@stimulus-components/reveal"
pin "@stimulus-components/dropdown", to: "https://esm.sh/@stimulus-components/dropdown"
pin "@stimulus-components/dialog", to: "https://esm.sh/@stimulus-components/dialog"
pin "@stimulus-components/lightbox", to: "https://esm.sh/@stimulus-components/lightbox"
pin "@stimulus-components/timeago", to: "https://esm.sh/@stimulus-components/timeago"
pin "@stimulus-components/content-loader", to: "https://esm.sh/@stimulus-components/content-loader"
pin "@stimulus-components/auto-submit", to: "https://esm.sh/@stimulus-components/auto-submit"
pin "@stimulus-components/sortable", to: "https://esm.sh/@stimulus-components/sortable"
```

For direct module apps, use the ESM bootstrap in `stimulus_components.js`.

## Shared component mapping

| Product need | Component |
|---|---|
| Copy URLs, commands, excerpts | Clipboard |
| Toasts for save/upload/job status | Notification |
| Hide/show advanced or raw data | Reveal |
| Filters, model/preset/category menus | Dropdown |
| Confirmation/preview/edit overlays | Dialog |
| Galleries | Lightbox |
| Relative timestamps | Timeago |
| Live search/result panels | Content Loader + Auto Submit |
| Reorder photos/items/tracks/panels | Sortable |
| Long descriptions | Read More |
| Keyboard actions | Hotkey |
| Upload/processing beeps | Sound |
| Voice search/prompt | Speech Recognition |
| Multiline authoring | Textarea Autogrow |
| Limits and feedback | Character Counter |

## Required progressive states

Every live search and async interaction must include:

- initial server-rendered content
- loading state
- empty state
- no-results state
- error state
- keyboard-friendly controls
- structured event emission

## Rollout order

1. Amber media baseline.
2. bsdports live search baseline.
3. Brgen social interactions.
4. Blognet editorial workflow.
5. Baibl scripture navigation/search.
6. Hjerterom domain skeleton.
