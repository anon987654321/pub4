# Refactor Command UX Upgrade

This document describes the enhancements made to the `refactor` command.

## Overview

The `refactor` command has been upgraded with three distinct operational modes, integrated governance through lint/render stages, council summary reporting, and full Undo support.

## Features

### 1. Three Operational Modes

#### Preview Mode (Default: `--preview`)
Shows a unified diff of the proposed changes without modifying the file.

```bash
refactor path/to/file.rb
# or explicitly
refactor path/to/file.rb --preview
```

**Output:**
```
  Proposals: 2
  Cost: $0.0123
  Council: APPROVED (85% consensus)

--- a/file.rb
+++ b/file.rb
@@ -1,5 +1,5 @@
 class Example
-  def old_method
+  def new_method
     # ...
   end
 end

  Use --apply to write changes, --raw to see full output
```

#### Raw Mode (`--raw`)
Displays the complete proposed file content after refactoring.

```bash
refactor path/to/file.rb --raw
```

**Output:**
```
  Proposals: 2
  Cost: $0.0123
  Council: APPROVED (85% consensus)

# frozen_string_literal: true

class Example
  def new_method
    # improved implementation
  end
end
```

#### Apply Mode (`--apply`)
Applies the changes after user confirmation with full Undo support.

```bash
refactor path/to/file.rb --apply
```

**Output:**
```
  Proposals: 2
  Cost: $0.0123
  Council: APPROVED (85% consensus)

--- a/file.rb
+++ b/file.rb
...

  Apply these changes? [y/N] y
  ✓ Changes applied to /path/to/file.rb
  (Use 'undo' command to revert)
```

### 2. Governance Integration

All refactor output is passed through the lint and render stages:
- **Lint Stage**: Enforces axiom compliance
- **Render Stage**: Applies typography improvements (smart quotes, em dashes, etc.)

This ensures that refactor output matches the same quality standards as other pipeline outputs.

### 3. Council Summary

When council review data is available, a summary line is included in the output:

- **Approved**: `Council: APPROVED (85% consensus)`
- **Rejected**: `Council: REJECTED (45% consensus)`
- **Vetoed**: `Council: VETOED by Security Guard, Style Guide`

### 4. Undo Support

When using `--apply` mode:
1. Original file content is registered in the Undo stack before modification
2. Changes are written to disk only after user confirmation
3. Use the `undo` command to restore the original file

```bash
# Apply changes
refactor path/to/file.rb --apply
# (confirm with 'y')

# Restore original if needed
undo
```

## Implementation Details

### DiffView Module

A new `MASTER2/lib/diff_view.rb` module provides unified diff generation:

```ruby
MASTER::DiffView.unified_diff(original, modified, 
                              filename: "file.rb", 
                              context_lines: 3)
```

### Backward Compatibility

The `--raw` mode matches the previous behavior of the refactor command, ensuring backward compatibility for existing scripts and workflows.

### Commands Integration

The refactor command integrates seamlessly with the existing `Commands.dispatch` system and doesn't break other commands.

## Tests

Comprehensive test coverage in `MASTER2/test/test_refactor.rb`:

- ✅ Missing file error handling
- ✅ Mode extraction (--preview, --raw, --apply)
- ✅ Preview output (unified diff format)
- ✅ Raw output (full proposed content)
- ✅ Apply workflow with confirmation
- ✅ Undo restoration
- ✅ Council summary formatting
- ✅ Lint and render integration

Additional tests in `MASTER2/test/test_diff_view.rb`:

- ✅ Unified diff generation
- ✅ Line changes, additions, deletions
- ✅ Context line handling
- ✅ Multiple changes in one file

## Usage Examples

### Preview before applying
```bash
# See what changes would be made
refactor app/models/user.rb

# Review and decide
refactor app/models/user.rb --apply
```

### Get raw output for piping
```bash
# Output full proposed code
refactor lib/helper.rb --raw > proposed_helper.rb
```

### Safe refactoring workflow
```bash
# 1. Preview
refactor critical_file.rb

# 2. Apply with backup
refactor critical_file.rb --apply
# (type 'y' to confirm)

# 3. Test the changes
ruby test/critical_test.rb

# 4. Undo if needed
undo
```

## Demo

Run the demo script to see the modes in action:

```bash
ruby examples/demo_refactor_modes.rb
```
