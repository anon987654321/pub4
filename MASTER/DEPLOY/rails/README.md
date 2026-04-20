# RailsDEPLOY Installers (Rails 8.2+, Mobile‑first PWA)

This directory holds zsh installers that bootstrap and deploy Rails 8.2+ applications using a shared baseline.

## Goals
- Rails 8.2+ with Hotwire and modern authentication.
- Mobile‑first UI and PWA‑ready scaffolds (manifest, service worker).
- Installer‑centric workflow: each app is generated and configured via `.sh` scripts.
- OpenBSD‑compatible deployment (`MASTER/DEPLOY/openbsd/openbsd.sh`).

## Structure
- **App installers**: subdirectories with app‑specific scripts and READMEs (`amber/amber.sh`, `baibl/baibl.sh`, `blognet/blognet.sh`, `brgen/brgen*.sh`, `bsdports/bsdports.sh`, `hjerterom/hjerterom.sh`, `privcam/privcam.sh`).
- **Shared building blocks**:
  - `@shared_functions.sh` – common setup and logging helpers.
  - `__shared/@common.sh` – utilities (`get_app_port`, feature loading).
  - `__shared/@*_features.sh` – feature modules (messaging, reddit, airbnb, etc.).
  - `__shared/layouts/*` – reusable layout partials and assets.
  - `__common_patterns.css` – shared styling patterns.
- **Utility scripts**:
  - `check_ports.sh` – validates app/port consistency from `master.json`.
  - `modernize_zsh.sh` – migrates zsh script patterns.
  - `voting_system.sh`, `rich_editor_system.sh` – installable feature systems.

## Execution model
- Executable scripts have shebangs and can be run directly.
- Modules under `__shared/` are sourced, not executed directly.
- Use `#!/usr/bin/env zsh` for all installers and shared modules.

## Compatibility matrix
| Component | Requirement |
|---|---|
| Ruby | 3.3+ (3.4 preferred) |
| Rails | 8.2+ |
| Database | PostgreSQL 16+ (or SQLite for lightweight) |
| Node package manager | `yarn` (preferred) or `npm` |
| OS | OpenBSD 7.8+ / Linux dev machines |
| CLI tools | `zsh`, `git`, `ruby`, `bundle`, `rails`, `jq` |

## Example usage```zsh
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
Before committing changes to `MASTER/DEPLOY/rails`:
1. Run syntax checks: `zsh -n <script.sh>`.
2. Ensure no markdown code fences remain in `.sh` files.
3. Execute `check_ports.sh` when `master.json` is present.
4. Keep installer output idempotent.