# Safe Autonomy Architecture

This document describes the minimal safe autonomy architecture implemented in MASTER2, complementing the language-axioms PR.

## Components

### 1. Constitution (`data/constitution.yml`)

A read-only policy file defining immutable safety rules and operational defaults:

**Safety Policies:**
- `self_modification`: Requires staging and validation for any self-modification
- `environment_control`: Prevents direct environment control without explicit permission
- `dangerous_operations`: Blocks inherently dangerous operations (rm -rf /, disk writes, etc.)

**Permissions:**
- `shell_command`: Restricted by default, requires explicit permission
- `code_execution`: Sandboxed by default, requires explicit permission
- `file_write`: Repo-only by default, blocks writes to sensitive paths including constitution.yml itself
- `file_read`: Unrestricted by default, blocks SSH keys and sensitive system files
- `network_access`: Restricted by default

**Staging Configuration:**
- Defines staging directory, validation commands, and rollback policies
- Enables safe self-refactor with automated validation

**Protected Files:**
- Lists critical files that cannot be modified without staging
- Includes `lib/evolve.rb`, `lib/master.rb`, `lib/executor.rb`, `data/constitution.yml`

### 2. Permission Gates in Executor (`lib/executor.rb`)

The Executor now enforces constitution-based permissions:

**Features:**
- `.constitution`: Class method to load and cache constitution
- `.tool_permitted?(tool_name, context)`: Check if tool is allowed based on permissions
- Permission checking integrated into `execute_tool` method
- Dangerous tools (shell_command, code_execution, file_write) require explicit permission

**Usage:**
```ruby
# Create executor with explicit permissions
executor = MASTER::Executor.new(permissions: { explicit_permission: true })

# Or pass permissions when calling
executor.call("some task", permissions: { explicit_permission: true })

# Without permissions, dangerous tools are blocked
executor = MASTER::Executor.new  # No permissions
executor.send(:execute_tool, "shell_command 'ls'")  
# => "BLOCKED: Tool 'shell_command' requires explicit permission (constitution)"
```

**Constitution Protection:**
- `file_write` checks constitution's blocked_paths
- Automatically blocks writes to `data/constitution.yml`
- Enforces working directory boundaries

### 3. Staging Module (`lib/staging.rb`)

Provides safe self-refactor with validation and rollback:

**Core Methods:**
- `stage_file(path)`: Copy file to staging area with automatic backup
- `validate(staged_path)`: Run validation commands from constitution
- `promote(staged_path, original_path)`: Move validated changes to production
- `rollback(original_path)`: Restore from backup on failure
- `staged_modify(path, &block)`: Complete workflow with automatic rollback

**Features:**
- Automatic backup creation
- Ruby syntax validation by default
- Custom validation commands from constitution
- Atomic operations with rollback on any failure
- Cleanup of staging directory

**Usage:**
```ruby
staging = MASTER::Staging.new

# Full workflow with automatic validation and rollback
result = staging.staged_modify("lib/example.rb") do |staged_path|
  # Modify the staged file
  content = File.read(staged_path)
  File.write(staged_path, modified_content)
end

if result.ok?
  puts "Changes validated and promoted"
else
  puts "Changes rolled back: #{result.error}"
end
```

### 4. Staged Evolve Integration (`lib/evolve.rb`)

Evolve now supports opt-in staged self-refactor:

**New Parameters:**
- `staged: false` - Default behavior unchanged (direct writes)
- `staged: true` - Uses staging workflow with validation

**Features:**
- Maintains backward compatibility
- Optional staging parameter for safe self-modification
- Automatic validation before promoting changes
- Rollback on validation failure

**Usage:**
```ruby
evolve = MASTER::Evolve.new

# Default behavior (unchanged)
evolve.run(path: MASTER.root, dry_run: false)

# Staged behavior (new)
evolve.run(path: MASTER.root, dry_run: false, staged: true)
```

## Testing

Four new test files validate the implementation:

1. **test_constitution.rb**: Verifies constitution file structure and protection
2. **test_permission_gate.rb**: Tests executor permission enforcement
3. **test_staging.rb**: Validates staging workflow, validation, and rollback
4. **test_evolve_staged.rb**: Confirms staged parameter integration

Run tests:
```bash
cd MASTER2
ruby -I lib test/test_constitution.rb
ruby -I lib test/test_permission_gate.rb
ruby -I lib test/test_staging.rb
ruby -I lib test/test_evolve_staged.rb
```

## Design Principles

1. **Minimal and Additive**: No breaking changes to existing functionality
2. **Opt-in**: New safety features are optional (staged parameter)
3. **Defense in Depth**: Multiple layers of protection (patterns, permissions, constitution)
4. **Self-Protection**: Constitution protects itself from modification
5. **Fail-Safe**: Automatic rollback on any validation failure

## Integration with Language-Axioms PR

This architecture complements the language-axioms PR by:

- Not touching `lib/language_axioms.rb`, `data/language_axioms.yml`, `lib/enforcement.rb`, or `lib/auto_fixer.rb`
- Using existing Result monad pattern
- Following existing file structure and naming conventions
- Maintaining CLI/REPL behavior unchanged by default

## Future Enhancements

Possible extensions (not implemented in this minimal version):

- Audit logging for all tool calls
- Permission escalation workflows
- Multi-level staging (dev → staging → production)
- Automated constitution compliance checking
- Integration with existing Guard stages for unified protection

## Security Considerations

The architecture provides defense against:

- Accidental self-modification without validation
- Dangerous operations (filesystem destruction, data loss)
- Unauthorized access to sensitive files
- Environment manipulation without permission
- Constitution tampering

Note: This is defense in depth, not a security boundary. The system assumes the Ruby process itself is trusted.
