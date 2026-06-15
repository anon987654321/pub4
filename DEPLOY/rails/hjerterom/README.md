# hjerterom

Food rescue and redistribution — donations, boxes, volunteers, shifts, beneficiaries.

## Stack

Rails 8.1 · SQLite · Falcon · Hotwire · OpenBSD relayd

## Deploy

```zsh
doas zsh DEPLOY/rails/hjerterom/hjerterom.sh
curl -fsS http://127.0.0.1:38891/up
```

## Integration

Shared concerns and activity emission per `DEPLOY/rails/shared/WIRING_NOTES.md`.

## Status

Feature matrix: `apps.yml` → `hjerterom`.