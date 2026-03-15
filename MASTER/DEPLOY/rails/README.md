# Rails DEPLOY Installers (Rails 8.2+, Mobile-first PWA)

This directory contains zsh-driven Rails installer scripts used to bootstrap and deploy multiple apps with a shared Rails 8.2+ baseline.

## Goals
- **Rails 8.2+ defaults** with Hotwire and modern auth patterns.
- **Mobile-first UI** in generated CSS/layout templates.
- **PWA-ready** app scaffolds (manifest/service worker compatible structure).
- **Installer-centric workflow**: each app is generated/configured by `.sh` installers.
- **OpenBSD-friendly deployment** (works with `MASTER/DEPLOY/openbsd/openbsd.sh`).

## Structure

### App installers
Each subdirectory contains an app-specific installer and README:
- `amber/amber.sh`
- `baibl/baibl.sh`
- `blognet/blognet.sh`
- `brgen/brgen*.sh`
- `bsdports/bsdports.sh`
- `hjerterom/hjerterom.sh`
- `privcam/privcam.sh`

### Shared building blocks
- `@shared_functions.sh` — common setup/logging helpers used by installers.
- `__shared/@common.sh` — utility helpers (`get_app_port`, optional feature loading).
- `__shared/@*_features.sh` — feature modules (messaging/reddit/airbnb/etc).
- `__shared/layouts/*` — reusable Rails layout partials and assets.
- `__common_patterns.css` — shared styling patterns for generated UIs.

### Utility scripts
- `check_ports.sh` — validates app/port consistency from `master.json`.
- `modernize_zsh.sh` — migration helper for zsh-oriented script patterns.
- `voting_system.sh`, `rich_editor_system.sh` — installable feature systems.

## Execution model
- **Directly executable**: top-level installers and utility scripts with shebangs.
- **Source-only modules**: scripts under `__shared/` unless explicitly run as executables.
- **Shell standard**: use `#!/usr/bin/env zsh` for installers and shared shell modules.

## Compatibility matrix
| Component | Expected |
|---|---|
| Ruby | 3.3+ (3.4 preferred) |
| Rails | 8.2+ |
| DB | PostgreSQL 16+ (or SQLite for lightweight setups) |
| Node package manager | `yarn` (preferred) or `npm` |
| OS target | OpenBSD 7.8+ / Linux dev machines |
| Required CLI | `zsh`, `git`, `ruby`, `bundle`, `rails`, `jq` |

## Example usage
```zsh
#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="${0:a:h}"
source "${SCRIPT_DIR}/@shared_functions.sh"

APP_DIR="/home/dev/rails/myapp"
APP_PORT=41000

setup_full_app "$APP_DIR"
generate_default_css
```

## Validation checklist
Before committing changes under `MASTER/DEPLOY/rails`:
1. Run syntax checks on updated scripts: `zsh -n <script.sh>`.
2. Ensure no markdown code-fences are left inside executable `.sh` files.
3. Run `check_ports.sh` when `master.json` is present.
4. Keep installer output idempotent (safe to re-run where possible).
