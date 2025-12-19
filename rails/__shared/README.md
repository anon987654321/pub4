# Rails Shared Modules

This directory contains shared functions and modules used by all Rails generator scripts in the parent directory.

## Purpose

Per `master.yml` v74.2.0, these modules provide reusable functionality for generating Rails 8 applications with:
- Solid Stack (Solid Queue/Cache/Cable - no Redis required)
- PostgreSQL database
- Hotwire (Turbo + Stimulus)
- PWA support
- Modern authentication
- Production-ready Falcon server configuration

## Module Organization

### Core Modules (Consolidated)

These are the main consolidated modules that other generators source:

- **@shared_functions.sh** - Main entry point, loads all modules and provides `setup_full_app()` function
- **@core.sh** - Core Rails setup (Ruby, Yarn, PostgreSQL, Redis, basic structure)
- **@helpers.sh** - Helper functions (gem/package installation, route manipulation, git commits)
- **@features.sh** - Feature modules loader (AI, booking, messaging, voting)
- **@integrations.sh** - Integration modules loader (chat, search)

### Specialized Modules

These modules provide specific functionality:

- **@rails8_stack.sh** - Rails 8 Solid Stack setup (Queue/Cache/Cable)
- **@rails8_propshaft.sh** - Asset pipeline with Propshaft
- **@default_application_css.sh** - Default CSS styles
- **@frontend_pwa.sh** - Progressive Web App features
- **@frontend_stimulus.sh** - Stimulus controllers
- **@frontend_reflex.sh** - StimulusReflex patterns
- **@generators_crud_views.sh** - View template generators

### Feature-Specific Modules

- **@features_ai_langchain.sh** - LangChain.rb AI integration
- **@features_booking_marketplace.sh** - Airbnb-style booking/marketplace
- **@features_messaging_realtime.sh** - Real-time messaging with ActionCable
- **@features_voting_comments.sh** - Voting and comment systems

### Integration Modules

- **@integrations_chat_actioncable.sh** - Live chat with WebSockets
- **@integrations_search.sh** - Live search functionality

### Legacy Files (Pre-Consolidation)

These files existed before consolidation and are kept for reference:

- @core_setup.sh, @core_database.sh, @core_dependencies.sh (now in @core.sh)
- @helpers_installation.sh, @helpers_logging.sh, @helpers_routes.sh (now in @helpers.sh)
- @loader.sh, load_modules.sh, @route_helpers.sh (superseded by @shared_functions.sh)

## Usage

### Basic Usage

All Rails generator scripts should source the main shared functions file:

```zsh
#!/usr/bin/env zsh
set -euo pipefail

APP_NAME="myapp"
BASE_DIR="/home/dev/rails"
SCRIPT_DIR="${0:a:h}"

source "${SCRIPT_DIR}/__shared/@shared_functions.sh"

log "Starting MyApp setup"
setup_full_app "$APP_NAME"

# Add app-specific customizations here
```

### The setup_full_app Function

The `setup_full_app()` function is the main entry point that:

1. Creates the Rails application directory structure
2. Runs `rails new` if needed
3. Sets up PostgreSQL database configuration
4. Installs Rails 8 Solid Stack (Queue/Cache/Cable)
5. Sets up Rails 8 authentication
6. Generates Falcon production server config

Parameters:
- `$1` (required): Application name
- `$2` (optional): Set to "true" to enable Redis alongside Solid Stack (default: "false")

Example:
```zsh
# Standard setup (Solid Stack only, no Redis)
setup_full_app "myapp"

# With Redis explicitly enabled
setup_full_app "myapp" "true"
```

## Key Functions Reference

### From @core.sh
- `log()` - Timestamped logging
- `command_exists()` - Check if command is available
- `setup_ruby()` - Verify Ruby environment
- `setup_yarn()` - Setup Yarn and frontend assets
- `setup_postgresql()` - Configure PostgreSQL database
- `setup_redis()` - Configure Redis (legacy, prefer Solid Stack)
- `setup_rails()` - Install Rails framework components
- `setup_core()` - Setup core application structure
- `migrate_db()` - Run database migrations
- `setup_seeds()` - Create seeds.rb file

### From @helpers.sh
- `install_gem()` - Install Ruby gem if not already present
- `install_yarn_package()` - Install npm package via Yarn
- `install_stimulus_component()` - Install Stimulus component
- `add_routes_block()` - Add routes to config/routes.rb (pure zsh)
- `commit()` - Git commit helper

### From @rails8_stack.sh
- `setup_rails8_solid_stack()` - Setup Solid Queue/Cache/Cable
- `setup_rails8_authentication()` - Setup Rails 8 built-in auth

### From @shared_functions.sh
- `setup_full_app()` - Complete Rails app setup
- `generate_falcon_config()` - Generate production Falcon config
- `setup_devise_guests()` - Setup devise-guests for anonymous access

## Master.yml Compliance

All modules comply with master.yml v74.2.0:
- ✓ Use zsh-native patterns (no sed/awk/tr)
- ✓ Rails 8 + Solid Stack (Redis optional)
- ✓ OpenBSD deployment ready
- ✓ Token efficient, minimal sprawl
- ✓ Preserves working code

## Version History

- **2025-12-19**: Created consolidated modules (@core.sh, @helpers.sh, @features.sh, @integrations.sh)
- **2025-12-12**: Reduced from 22 files to 10 focused modules (55% reduction)
- **2025-10**: Initial shared functions implementation

## See Also

- `/home/runner/work/pub4/pub4/master.yml` - Universal configuration framework
- `/home/runner/work/pub4/pub4/openbsd/openbsd.sh` - OpenBSD infrastructure deployment
- Parent directory - Individual Rails application generators
