# pub4 - Multi-Technology Projects Repository

This repository contains various example projects and utilities for different technologies and platforms.

## Projects

### 1. Ruby Project (`ruby_project/`)
A simple Ruby application demonstrating basic Ruby features including:
- Hello World program
- Calculator class with basic operations
- Gemfile for dependency management

**Quick Start:**
```bash
cd ruby_project
ruby hello.rb
ruby calculator.rb
```

### 2. Ruby on Rails Project (`rails_project/`)
A minimal Ruby on Rails application structure showcasing:
- MVC architecture
- Models, Controllers, and routing
- Database configuration
- Rails best practices

**Quick Start:**
```bash
cd rails_project
bundle install
rails db:create && rails db:migrate
rails server
```

### 3. Zsh Scripts (`zsh_scripts/`)
Collection of zsh configuration files and utilities:
- Custom `.zshrc` configuration
- Useful aliases for development
- Helper functions for common tasks
- Automated setup script

**Quick Start:**
```bash
cd zsh_scripts
./setup.sh
source ~/.zshrc
```

### 4. OpenBSD Utilities (`openbsd_utils/`)
Scripts and configurations for OpenBSD systems:
- PF firewall configuration
- System hardening script
- Backup utilities
- Installation guide

**Quick Start:**
```bash
cd openbsd_utils
chmod +x *.sh
# Review scripts before running with doas
```

### 5. Rust Project (`rust_project/`)
A Rust application demonstrating Rust fundamentals:
- Calculator library with error handling
- String utilities
- Unit tests
- Cargo project structure

**Quick Start:**
```bash
cd rust_project
cargo build
cargo run
cargo test
```

## Repository Structure

```
pub4/
├── ruby_project/       # Ruby examples and utilities
├── rails_project/      # Ruby on Rails application
├── zsh_scripts/        # Zsh configuration and scripts
├── openbsd_utils/      # OpenBSD utilities and docs
└── rust_project/       # Rust application
```

## Requirements

- **Ruby**: Ruby 2.7+ and Bundler
- **Rails**: Ruby 3.0+ and Rails 7.0+
- **Zsh**: Zsh shell (5.0+)
- **OpenBSD**: OpenBSD 7.0+ (for OpenBSD utilities)
- **Rust**: Rust 1.70+ and Cargo

## Contributing

Each project directory contains its own README with specific instructions and details.

## License

This is a collection of example projects for educational and reference purposes.
