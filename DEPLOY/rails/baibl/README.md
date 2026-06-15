# baibl

Scripture study — semantic search, annotations, cross-references, collaborative commentary.

**New (Wave 1):** Improved multi-tradition comparisons & visualizations for Bible, Quran, Bhagavad Gita and more. Parallel side-by-side views, thematic cross-references, interactive concept thread visualizations (Stimulus powered), and "compare this passage" links from chapter views. Seed data now includes samples from multiple traditions + curated links.

## Stack

Rails 8.1 · SQLite · Falcon · Hotwire · OpenBSD relayd

## Deploy

```zsh
doas zsh DEPLOY/rails/baibl/baibl.sh
```

After deploy/migrate: `bin/rails db:seed` for fresh comparison data.

## Usage

- `/compare?theme=creation` (or love, duty, etc.)
- From any chapter: "Compare this passage" button.
- Interactive viz: click/hover concept threads to highlight parallels.

## Status

Feature matrix: `apps.yml` → `baibl`. See scriptures#compare + comparison_viz_controller.