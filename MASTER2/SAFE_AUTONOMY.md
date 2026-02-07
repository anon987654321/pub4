# Safe Autonomy Architecture

This document describes the minimal safe autonomy architecture implemented in MASTER2.

## Overview

The safe autonomy architecture adds four key components to provide principled boundaries for autonomous behavior:

1. **PlannerHelper** - Lightweight plan generation without execution
2. **Constitution** - Immutable safety policies and permissions
3. **Permission Gates** - Enforce allow-lists for dangerous operations
4. **Staging** - Validated self-refactor workflow with rollback

## Components

### 1. PlannerHelper (`lib/planner_helper.rb`)

A standalone, reusable helper that generates numbered step plans from goals without executing them.

```ruby
planner = MASTER::PlannerHelper.new
result = planner.generate_plan("Deploy the application")
# => Result.ok(steps: ["1. Build the app", "2. Run tests", ...])
```

**Features:**
- Generates up to 20 steps from a goal
- Parses numbered lists (1., 2), 3:, etc.)
- No execution - just planning
- Complements the existing Planner class

### 2. Constitution (`data/constitution.yml`)

A read-only configuration file defining core safety constraints that cannot be self-modified.

**Key sections:**
- **Principles** - Core safety rules (no self-modification, no environment control, staged refactoring)
- **Tool Permissions** - Allow-lists and block-lists for dangerous operations
- **Self-Refactor Safety** - Requirements for code self-modification
- **Budget Limits** - Cost constraints
- **Logging** - Observability requirements

**Protection:** The constitution file itself is protected from writes by the tool execution system.

### 3. Permission Gates (`lib/executor.rb`)

The Executor now enforces permission checks before executing dangerous tools:

**Protected operations:**
- `shell_command` - Blocks dangerous commands (rm -rf /, DROP TABLE, etc.), allows safe commands (ls, git status, etc.)
- `code_execution` - Blocks system calls (system(), exec(), backticks), allows safe Ruby code
- `file_write` - Blocks writes to protected paths (constitution.yml, /etc/, /usr/, etc.)

**Example:**
```ruby
executor = MASTER::Executor.new
executor.send(:shell_command, "rm -rf /")
# => "BLOCKED: Matches blocked pattern"

executor.send(:shell_command, "ls -la")
# => "file1.rb\nfile2.rb\n..."
```

### 4. Staging (`lib/staging.rb`)

A helper for staged self-refactoring with validation gates and rollback capability.

**Workflow:**
1. **Stage** - Copy file to staging directory
2. **Modify** - Make changes to staged file
3. **Validate** - Run validation command (e.g., `ruby -c {file}`)
4. **Promote** - Copy to original (with backup)
5. **Cleanup** - Remove staging files

**Example:**
```ruby
result = MASTER::Staging.staged_workflow(
  "lib/myfile.rb",
  validation_command: "ruby -c {file}"
) do |staged_path|
  # Modify the staged file
  File.write(staged_path, new_content)
end

# If validation fails, original file is unchanged
# If validation succeeds, file is promoted with backup
```

**Integration with Evolve:**
```ruby
# Default behavior (unchanged)
evolve = MASTER::Evolve.new
evolve.run(dry_run: false)

# With staging (opt-in)
evolve = MASTER::Evolve.new(staged: true, validation_command: "ruby -c {file}")
evolve.run(dry_run: false)
```

## Architecture Principles

1. **Minimal and Additive** - New features don't change existing behavior unless explicitly opted-in
2. **Defense in Depth** - Multiple layers of protection (patterns, allow-lists, path guards)
3. **Fail Safe** - Invalid operations are blocked, not executed
4. **Observability** - All blocks and dangerous operations are loggable
5. **Immutability** - Core safety rules cannot be modified by tool execution

## Testing

Comprehensive test coverage:
- `test/test_planner_helper.rb` - 11 tests for plan generation
- `test/test_permission_guard.rb` - 25 tests for permission enforcement
- `test/test_staging.rb` - 23 tests for staging workflow
- `test/test_safe_autonomy_integration.rb` - 11 integration tests

Run tests:
```bash
cd MASTER2
export GEM_HOME=$(ruby -e'puts Gem.user_dir')
export PATH="$GEM_HOME/bin:$PATH"

ruby -I lib test/test_planner_helper.rb
ruby -I lib test/test_permission_guard.rb
ruby -I lib test/test_staging.rb
ruby -I lib test/test_safe_autonomy_integration.rb
```

## Compatibility

- **Existing CLI/REPL behavior** - Unchanged
- **Executor patterns** - All patterns (react, pre_act, rewoo, reflexion) work with permission gates
- **Evolve default** - Default behavior unchanged (staged: false)
- **Language axioms PR** - Avoids conflicts with language_axioms.rb, enforcement.rb, auto_fixer.rb

## Future Enhancements

Potential additions (not in scope for Option 1):
- Constitution versioning and migration
- Runtime permission overrides with approval flow
- Detailed audit logging to file
- Permission analytics and reporting
- Gradual permission relaxation based on trust
