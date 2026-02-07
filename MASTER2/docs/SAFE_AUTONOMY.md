# Safe Autonomy Architecture

This document describes the minimal safe autonomy architecture added to MASTER2.

## Overview

The safe autonomy architecture provides:

1. **Read-only Constitution** - Immutable policy defaults that cannot be modified by tools
2. **Permission Gates** - Protection against dangerous tool operations  
3. **Staged Self-Refactor** - Validation-first approach to self-modification
4. **Planner** - Systematic task breakdown and execution (already existed)

## Components

### 1. Constitution (`data/constitution.yml`)

The constitution defines immutable safety policies including:

- **Self-modification policies** - Disables uncontrolled self-modification
- **Protected files** - Lists files that cannot be modified (including itself)
- **Tool permissions** - Defines allowed/restricted operations for each tool
- **Resource limits** - Sets boundaries on cost, tokens, and execution time

**Key Features:**
- Read-only by design - tool execution blocks writes to `data/constitution.yml`
- Contains sensible defaults for safe operation
- Defines restricted patterns for dangerous operations

### 2. Permission Gates (in `lib/executor.rb`)

Enhanced the Executor with permission checks:

```ruby
# Protected paths that tools cannot write to
PROTECTED_WRITE_PATHS = [
  /data\/constitution\.yml$/,  # Constitution itself
  /^\/etc\//,                  # System configuration
  /^\/sys\//,                  # System files
  /^\/proc\//,                 # Process information
  /^\/dev\//,                  # Devices
].freeze
```

**Features:**
- Blocks writes to constitution file (both relative and absolute paths)
- Blocks writes to system directories
- Maintains existing dangerous pattern detection
- Still enforces working directory constraint

### 3. Staging Helper (`lib/staging.rb`)

A new module for staged file operations with validation:

```ruby
# Basic usage
staging = MASTER::Staging.new

# Stage files
staging.stage("lib/my_file.rb")

# Validate with command
staging.validate(command: "ruby -c lib/my_file.rb")

# Or validate with block
staging.validate do |staging_dir, files|
  # Your validation logic
  "OK"
end

# Promote on success
staging.promote
```

**Features:**
- Copy files to staging directory
- Run validation before applying changes
- Automatic rollback on validation failure
- Support for both command-based and block-based validation

### 4. Evolve Integration

The `Evolve` class now supports optional staged mode:

```ruby
# Traditional mode (default)
evolve = MASTER::Evolve.new
evolve.run(path: MASTER.root, dry_run: true)

# Staged mode with validation
evolve = MASTER::Evolve.new(staged: true)
evolve.run(
  path: MASTER.root, 
  dry_run: false,
  validation_command: "ruby -c"  # Optional
)
```

**Features:**
- Opt-in staged mode via `staged: true` parameter
- Default behavior unchanged (backward compatible)
- Automatic syntax validation for Ruby files
- Custom validation command support
- Promotes only after successful validation

## Testing

Comprehensive test coverage includes:

- `test/test_permission_gate.rb` - Permission checks and blocking
- `test/test_staging.rb` - Staging operations and validation
- `test/test_planner_basic.rb` - Planner functionality
- `test/test_integration_safe_autonomy.rb` - End-to-end scenarios

Run tests:
```bash
cd MASTER2
ruby -I lib test/test_permission_gate.rb
ruby -I lib test/test_staging.rb
ruby -I lib test/test_planner_basic.rb
ruby -I lib test/test_integration_safe_autonomy.rb
```

## Design Principles

1. **Minimal and Additive** - Changes are small and don't break existing functionality
2. **Opt-in by Default** - New safety features are available but don't change default behavior
3. **Defense in Depth** - Multiple layers of protection (path checks, pattern matching, validation)
4. **Fail Safe** - Errors in validation lead to rollback, not application
5. **Complementary** - Works alongside language-axioms PR without conflicts

## Future Enhancements

Potential extensions (not in scope for Option 1):

- Dynamic permission adjustment based on context
- Audit logging of all permission checks
- Constitution versioning and migration
- More granular tool-level permissions
- Integration with external policy engines

## Files Modified

- `MASTER2/lib/executor.rb` - Added PROTECTED_WRITE_PATHS and permission checks
- `MASTER2/lib/evolve.rb` - Added staged mode support
- `MASTER2/lib/master.rb` - Added require for staging module

## Files Added

- `MASTER2/data/constitution.yml` - Immutable policy configuration
- `MASTER2/lib/staging.rb` - Staging helper for validated operations
- `MASTER2/test/test_permission_gate.rb` - Permission gate tests
- `MASTER2/test/test_staging.rb` - Staging functionality tests
- `MASTER2/test/test_planner_basic.rb` - Planner tests
- `MASTER2/test/test_integration_safe_autonomy.rb` - Integration tests
- `MASTER2/docs/SAFE_AUTONOMY.md` - This documentation

## Constraints Observed

Per the problem statement:

✅ Keep changes minimal and additive
✅ Avoid touching language-axioms files (`lib/language_axioms.rb`, `data/language_axioms.yml`, `lib/enforcement.rb`, `lib/auto_fixer.rb`)
✅ Maintain existing CLI/REPL behavior
✅ New behavior is opt-in (staged mode requires explicit parameter)
✅ Planner already existed and is working
✅ Constitution is read-only by tool execution
✅ Permission gates block dangerous tools
✅ Staged flow available but doesn't affect default Evolve behavior
✅ Tests cover all new functionality
