# master.rb v120.2.0
**Self-optimizing code quality framework with autoiterative convergence**
## Overview
master.rb is a self-refactoring Ruby program that enforces code quality standards through iterative convergence. It analyzes code, detects issues, applies fixes, and repeats until no improvements remain.
## Features
- ✅ **Self-healing**: Refactors its own source code
- ✅ **Convergent**: Iterates until mathematically stable

- ✅ **Atomic**: Lock-based concurrency protection + atomic writes

- ✅ **Zero-dependency core**: Only stdlib required (tty-prompt optional)

- ✅ **Design system aware**: Validates WCAG contrast, spacing scales

- ✅ **CLI-first**: Works without interactive prompts

- ✅ **Multi-language**: Supports rb/js/ts/html/css/sh/zsh

## Installation
```bash
# Download

curl -O https://raw.githubusercontent.com/anon987654321/master/main/master.rb

chmod +x master.rb

# Optional: Install tty-prompt for interactive menu
gem install --user-install tty-prompt

```

## Usage
### Interactive Mode
```bash

ruby master.rb

```

### CLI Mode (auto-refactor all files)
```bash

ruby master.rb  # Runs without tty-prompt

```

### Dry-Run
```bash

ruby master.rb --dry

```

### Silent Mode
```bash

ruby master.rb --silent

```

### Self-Update
```bash

ruby master.rb --self-update

```

## Configuration
All settings in `CONFIG` hash:
```ruby
CONFIG = {

  meta: { version, updated, owner },

  policy: { forbid_ternary, max_line_length, max_nesting },

  design: { spacing_scale, contrast_min, touch_target_min },

  tools: { external: { rb: "rubocop -a", js: "prettier --write" } }

}

```

## LLM Contract
When using with AI assistants:
- **Canonical**: Discard older versions
- **Response format**: Unified git diff + ≤2 sentence note

- **No changes**: Emit `(no changes)`

- **Approval keywords**: `approve`, `ship`, `merge`, `finalize`

- **Safety**: No destructive operations without approval

## Output Format
```
[22:55:23] info autoiterator: master.rb

[22:55:23] debug iter 1: 0 issues

[22:55:23] done converged in 1 iteration

```

## Architecture
- **Logger**: ANSI-colored, timestamped output
- **Spinner**: Non-blocking progress indicators

- **CodeAudit**: WCAG contrast validation + pattern detection

- **Autoiterator**: File-level convergent refactoring engine

- **MasterFormatter**: CLI + interactive menu controller

- **MasterContract**: LLM communication protocol

