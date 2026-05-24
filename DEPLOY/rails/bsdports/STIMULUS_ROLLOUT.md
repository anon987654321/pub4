# bsdports Stimulus / Rails 8 rollout

bsdports should become the production-readiness and accessibility reference app.

## Implement first

1. Auto Submit + Content Loader for port search across name, summary, description.
2. Clipboard for install commands and port URLs.
3. Reveal for dependencies, build flags, maintainer details, raw metadata.
4. Timeago for import/build/security advisory timestamps.
5. Notification for import completion, advisory updates, build failures.
6. Popover for license, platform, security, maintainer hints.
7. Read More for long descriptions.
8. Checkbox Select All for compare/export sets.

## Rails 8 work

- SQLite FTS5 index for ports.
- Solid Queue scheduled ports-tree import.
- Solid Cache for search result fragments and dependency expansions.
- Turbo Streams for import status and build/security updates.
- Structured events:
  - `bsdports.search.performed`
  - `bsdports.port.viewed`
  - `bsdports.install_command.copied`
  - `bsdports.import.started`
  - `bsdports.import.finished`
  - `bsdports.advisory.published`

## Missing foundations to add

- Dependency model.
- SecurityAdvisory model.
- Maintainer model.
- Dependency tree visualization endpoint.
- WCAG AAA pass.

## Acceptance

- Search is keyboard-friendly and server-rendered by default.
- Install command copy has visible success state.
- Dependency/details reveal panels work without losing page navigation.
- Import job progress is observable without a dashboard.
