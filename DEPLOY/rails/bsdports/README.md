# bsdports — OpenBSD ports index

Semantic search and AI-assisted exploration of the OpenBSD ports tree.

## Features

- Full-text and semantic package search
- Dependency graph visualization
- Security advisory cross-reference
- Infrastructure and toolchain recommendations
- AI exploration assistant

## Stack

Rails 8 · SQLite · Falcon · Hotwire · OpenBSD

## Deploy

```zsh
doas zsh DEPLOY/rails/bsdports/bsdports.sh
```

## Stimulus / Rails 8 Rollout (condensed from STIMULUS_ROLLOUT.md)
Prioritize: Auto Submit + Content Loader for search, Clipboard for commands, Reveal for details, Timeago, Notification, Popover, Read More, Checkbox Select All.

Rails 8: SQLite FTS5, Solid Queue for scheduled import, Solid Cache for fragments.
