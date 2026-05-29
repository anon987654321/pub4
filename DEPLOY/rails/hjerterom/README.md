# hjerterom — food and reuse network

Runs local resource redistribution like a food bank, not a social network. Receive, sort, pack, distribute, track.

## Features

- Food rescue and weekly box coordination
- Clothing, toy, and book reuse tracking
- Volunteer shift scheduling and notifications
- Donor and beneficiary matching
- Distribution route optimization

## Stack

Rails 8 · SQLite · Falcon · Hotwire · OpenBSD

## Current Integration Status (2026)

- **Visual system**: Target Brgen cinema palette + NNG tokens (see family `WIRING_NOTES.md`).
- **Activity Graph**: Should emit donation, distribution, and volunteer events to the shared graph.
- **Photo / Multimodal**: Can leverage public photo upload for donation photos.
- **Shared patterns**: Use shared social concerns (Reactable, Followable, Notification) and EventEmitter where relevant.
- Deploy follows the thin tracked-tree model.

See `DEPLOY/rails/ARCHITECTURE_NOTES.md`, `WIRING_NOTES.md`, and `LEGACY_FEATURE_SCRIPTS.md`.

## Deploy

```zsh
doas zsh DEPLOY/rails/hjerterom/hjerterom.sh
```
