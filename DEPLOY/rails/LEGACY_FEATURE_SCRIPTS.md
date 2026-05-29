# Legacy Feature Scripts (@*.sh)

These files are extracted patterns from earlier generator work (see also `github_repos/rails-style-guide/`).

**Current status (2026):** They are **reference material only**. The active production model uses tracked Rails app trees + thin, app-specific deploy scripts (see `README.md` and `ARCHITECTURE_NOTES.md`).

Do not run these blindly against existing production trees.

## Inventory & Duplication Notes

### Core / Shared Helpers
- `@core.sh`, `@shared_functions.sh` (and copies inside some scripts): Logging, `need_cmd`, `already_done`, `create_rails_app`, gem helpers, Solid stack, auth, rc.d, relayd helpers.
  - High duplication of the same helper functions across files.
  - Recommendation: Keep as historical reference. Current thin deploy scripts (e.g. `brgen/brgen.sh`) implement only what they need directly.

### Frontend & Assets
- `@frontend.sh`, `@assets.sh`, `@pwa.sh`, `@yarn.sh`
- Patterns for Stimulus + Importmap, PostCSS, PWA scaffolding.
- Partially absorbed into `shared/frontend/` and `shared/install_frontend_baseline.sh`.

### Social / Interaction
- `@social.sh`, `@reddit_features.sh`, `@twitter_features.sh`, `@airbnb_features.sh`, `@messenger_features.sh`
- Votes, comments, reactions, follows, notifications, direct messages.
- Much of this logic has moved into `shared/app/models/concerns/shared/{reactable,followable}.rb` and `shared/app/services/shared/`.

### Server / Deployment
- `@server.sh`, `@postgresql.sh`, `@redis.sh`, `@rails_new.sh`
- rc.d + relayd installation, DB setup.
- Current model prefers the lighter patterns in individual app `*.sh` scripts + `shared/` helpers.

### Specialized Verticals
- `@posts.sh`, `@instant_messaging.sh`, `@live_streaming.sh`, `@live_cam_streaming.sh`, `@ai.sh`
- These are useful as checklists when adding new verticals (TV, messaging, AI features, etc.).

### Other
- `@devise.sh`, `@active_storage_and_imageprocessing.sh`, `@views.sh`, `@features_base.sh`

## Recommended Approach Going Forward

1. When bootstrapping a new app or vertical, consult these for ideas but implement directly in the tracked `app/` tree + a thin deploy script.
2. Common patterns that have proven useful have been (or should be) extracted into `shared/` (see `WIRING_NOTES.md`).
3. If a pattern here is still heavily used, consider moving the best version into `shared/` and updating the thin deploy scripts to source it.
4. These files may be pruned in a future cleanup once the family has fully converged on the tracked-tree model.

## Related
- `README.md` → "Legacy feature scripts"
- `ARCHITECTURE_NOTES.md`
- `shared/WIRING_NOTES.md`
- Individual app deploy scripts (e.g. `brgen/brgen.sh`)

Last reviewed: 2026 during DEPLOY/rails convergence waves.