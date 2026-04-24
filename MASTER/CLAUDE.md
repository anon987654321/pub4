# MASTER — Claude Code Project Instructions

## Build & Run

```sh
cd /home/dev/pub4/MASTER
bundle install
bundle exec ruby exe/master          # CLI REPL (TTY mode)
echo "hello" | bundle exec ruby exe/master  # pipe mode
```

## Web UI

```sh
cd web && bundle exec falcon serve -b http://127.0.0.1:10002
# Or via rc.d:
doas rcctl restart master
```

## Test

```sh
bundle exec ruby -Ilib:test test/test_web_http.rb   # HTTP smoke tests (5 tests)
bundle exec ruby -Ilib:test test/test_browser.rb     # Browser tests (needs Chrome + 250MB free RAM)
```

## Lint

```sh
bundle exec rubocop lib/
bundle exec reek lib/
```

## Architecture

- 10-stage pipeline: Intake → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render
- Result monad: `Result.ok(value)` / `Result.err(msg, category:)` — all stages return Result
- Entry point: `exe/master` → `Master.boot` (lib/master.rb)
- Config: `.master/config.yml`, data files in `data/*.yml`
- Web UI: Rails 8 app in `web/`, Falcon on port 10002

## Key Conventions

- `frozen_string_literal: true` on every .rb file
- No bare rescue — always specify exception class
- Methods <= 20 lines, classes <= 300 lines
- Result monad everywhere — check with `respond_to?(:ok?)`, not `is_a?`
- OpenBSD: `doas` not `sudo`, `rcctl` not `systemctl`, `pkg_add` not `apt`
- Zeitwerk autoloading — inflectors: `"cli" => "CLI"`, `"mcp_server" => "MCPServer"`

## SSH Access

```sh
sshpass -p 'PASSWORD' ssh -o StrictHostKeyChecking=no dev@brgen.no
```
