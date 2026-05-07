# bsdports

Browseable web index of the OpenBSD ports tree. Rails 8 · PostgreSQL · Falcon.

## How it works

Seeds itself from the OpenBSD FTP mirror: downloads `ports.tar.gz`, untars, walks each `Makefile`, and imports name/summary/url/description into Postgres. One row per port, scoped by category and platform.

## Models

| Model | Purpose |
|---|---|
| `Platform` | OpenBSD release branch (e.g. `7.8`, `-current`) |
| `Category` | Top-level ports category (`net`, `databases`, `lang`, …) belongs_to platform |
| `Port` | Individual port (`name`, `summary`, `url`, `description`) belongs_to category + platform |

## Features

- LangChain-backed semantic search across summaries + descriptions.
- StimulusReflex live filtering by category and platform.
- Periodic re-seed via Solid Queue job to track upstream churn.

## Deploy

```zsh
doas zsh DEPLOY/rails/bsdports/bsdports.sh
```
