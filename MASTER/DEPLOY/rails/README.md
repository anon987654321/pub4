rails/
├─ amber/               # Amber‑related deployment scripts
│   └─ amber.sh
├─ baibl/               # Baibl service scripts
│   └─ baibl.sh
├─ blognet/             # Blognet deployment utilities
│   └─ blognet.sh
├─ brgen/               # Brgen family of scripts (brgen*.sh)
│   └─ brgen*.sh
├─ bsdports/            # BSD‑Ports integration scripts
│   └─ bsdports.sh
├─ hjerterom/           # Hjerterom service scripts
│   └─ hjerterom.sh
├─ privcam/             # PrivCam deployment helpers
│   └─ privcam.sh
├─ __shared/            # Shared resources used by all scripts
│   ├─ @common.sh                # Core utilities (e.g., `get_app_port`, feature loading)
│   ├─ @*_features.sh            # Feature modules (messaging, reddit, airbnb, …)
│   ├─ layouts/*                 # Reusable partials & static assets
│   └─ @shared_functions.sh      # Logging, environment handling, common helpers
├─ __common_patterns.css        # Global CSS patterns shared across deployments
├─ check_ports.sh                # Validate service ports against `master.json`
├─ modernize_zsh.sh              # Migrate legacy Zsh patterns to the new style
├─ voting_system.sh              # Scripts for deploying the voting subsystem
└─ rich_editor_system.sh         # Tools for installing and configuring the rich‑text editor
