# Session Recovery and Checkpoints

The MASTER system includes a robust checkpoint and recovery mechanism for handling long-running operations, session persistence, and graceful recovery from interruptions.

## Table of Contents

- [Overview](#overview)
- [Checkpoint System](#checkpoint-system)
- [Queue Checkpoints](#queue-checkpoints)
- [Recovery Instructions](#recovery-instructions)
- [Usage Examples](#usage-examples)
- [Best Practices](#best-practices)

## Overview

Session recovery enables:
- **Automatic checkpointing**: Save progress during long operations
- **Graceful interruption**: Pause and resume work
- **State persistence**: Continue where you left off after crashes
- **Cost tracking**: Maintain budget and spending across sessions
- **Progress recovery**: Never lose work from failed operations

## Checkpoint System

### What Gets Saved

Checkpoints capture:
- Queue state (pending, completed, failed items)
- Current item being processed
- Budget and spending information
- Timestamps for all operations
- Error information for failed items
- Pause state

### When Checkpoints Are Created

Checkpoints are automatically saved:
- After completing an item
- After an item fails
- When pausing the queue
- At regular intervals during processing

### Checkpoint Location

Checkpoints are stored in:
```
~/.copilot/session-state/queue_checkpoint.json
```

The checkpoint file is JSON-formatted for easy inspection and debugging.

## Queue Checkpoints

The queue system (`lib/queue.rb`) provides the primary checkpoint mechanism for batch operations.

### Queue State Structure

```ruby
{
  items: [
    {
      item: "file.rb",
      priority: 0,
      added_at: "2024-02-05T10:00:00Z"
    }
  ],
  completed: [
    {
      item: "processed.rb",
      priority: 0,
      added_at: "2024-02-05T10:00:00Z",
      completed_at: "2024-02-05T10:01:30Z",
      cost: 0.002
    }
  ],
  failed: [
    {
      item: "broken.rb",
      priority: 0,
      added_at: "2024-02-05T10:00:00Z",
      failed_at: "2024-02-05T10:02:00Z",
      error: "SyntaxError: unexpected end"
    }
  ],
  current: {
    item: "inprogress.rb",
    priority: 0,
    added_at: "2024-02-05T10:00:00Z"
  },
  paused: false,
  budget: 1.00,
  spent: 0.045
}
```

### Creating Checkpoints

Checkpoints are created automatically, but you can trigger them manually:

```ruby
queue = MASTER::Queue.new
queue.add("file1.rb")
queue.add("file2.rb")
queue.add("file3.rb")

# Process with automatic checkpointing
while item = queue.next
  begin
    result = process(item)
    queue.complete(cost: result.cost)  # Checkpoint saved here
  rescue => error
    queue.fail(error)  # Checkpoint saved here
  end
end
```

### Pausing Operations

Pause processing and save state:

```ruby
queue.pause  # Saves checkpoint immediately
```

Resume later:

```ruby
queue.resume
```

### Budget Tracking

Set a budget to prevent overspending:

```ruby
queue = MASTER::Queue.new
queue.set_budget(5.00)  # $5 maximum

queue.add_directory("lib/", recursive: true)

while item = queue.next
  # Automatically stops when spent >= budget
  result = process(item)
  queue.complete(cost: result.cost)
end
```

### Progress Monitoring

Check progress at any time:

```ruby
progress = queue.progress

# Returns:
# {
#   total: 100,
#   done: 45,
#   failed: 2,
#   remaining: 53,
#   percent: 45.0,
#   spent: 0.23,
#   budget: 1.00
# }

puts queue.status
# => "Progress: 45/100 (45.0%) | Failed: 2 | $0.23 / $1.00 budget"
```

## Recovery Instructions

### Recovering From Interruption

If the system crashes or is interrupted during processing:

1. **Restart the system**: Run `bin/cli` as normal

2. **Load checkpoint**: The queue automatically loads the last checkpoint:

```ruby
queue = MASTER::Queue.new
if queue.load_checkpoint
  puts "Recovered from checkpoint"
  puts "Already completed: #{queue.completed.size}"
  puts "Remaining: #{queue.items.size}"
  puts "Failed: #{queue.failed.size}"
  puts "Spent so far: $#{queue.progress[:spent]}"
  
  # Resume processing
  queue.resume
  while item = queue.next
    # Continue where you left off
  end
else
  puts "No checkpoint found, starting fresh"
end
```

### Inspecting Checkpoint Files

View checkpoint state directly:

```bash
cat ~/.copilot/session-state/queue_checkpoint.json | jq .
```

Check what failed:

```bash
cat ~/.copilot/session-state/queue_checkpoint.json | jq '.failed'
```

See remaining items:

```bash
cat ~/.copilot/session-state/queue_checkpoint.json | jq '.items'
```

### Manual Recovery

If automatic recovery fails, manually reconstruct state:

```ruby
require 'json'

checkpoint_path = File.join(
  ENV['HOME'], 
  '.copilot', 
  'session-state', 
  'queue_checkpoint.json'
)

if File.exist?(checkpoint_path)
  data = JSON.parse(File.read(checkpoint_path), symbolize_names: true)
  
  # Check what was completed
  data[:completed].each do |item|
    puts "✓ #{item[:item]} (cost: $#{item[:cost]})"
  end
  
  # Check what failed
  data[:failed].each do |item|
    puts "✗ #{item[:item]}: #{item[:error]}"
  end
  
  # Retry failed items
  queue = MASTER::Queue.new
  data[:failed].each do |item|
    queue.add(item[:item])
  end
  
  # Continue with remaining items
  data[:items].each do |item|
    queue.add(item[:item], priority: item[:priority])
  end
end
```

### Clearing Checkpoints

Remove checkpoint to start fresh:

```ruby
File.delete(checkpoint_path) if File.exist?(checkpoint_path)
```

Or from shell:

```bash
rm ~/.copilot/session-state/queue_checkpoint.json
```

## Usage Examples

### Example 1: Process Directory with Recovery

```ruby
# Start processing
queue = MASTER::Queue.new
queue.set_budget(10.00)
queue.add_directory("lib/", extensions: [".rb"])

# Process with automatic checkpointing
queue.each_item do |file|
  # Your processing logic
  analyze_code(file)
end

# If interrupted, later:
queue = MASTER::Queue.new
queue.load_checkpoint
queue.resume
queue.each_item do |file|
  # Continues from where it left off
  analyze_code(file)
end
```

### Example 2: Prioritized Processing

```ruby
queue = MASTER::Queue.new

# Add high priority items first
queue.add("critical.rb", priority: 10)
queue.add("important.rb", priority: 5)
queue.add("normal.rb", priority: 0)

# Items are processed by priority (highest first)
while item = queue.next
  process(item)
  queue.complete
end

# Checkpoint automatically maintains priority order
```

### Example 3: Error Handling with Recovery

```ruby
queue = MASTER::Queue.new
queue.add_files("*.rb")

while item = queue.next
  begin
    result = risky_operation(item)
    queue.complete(cost: result.cost)
  rescue StandardError => error
    puts "Failed: #{item} - #{error.message}"
    queue.fail(error)  # Saves error in checkpoint
    # Continue with next item
  end
end

# Later, review failures
checkpoint = JSON.parse(File.read(checkpoint_path), symbolize_names: true)
checkpoint[:failed].each do |item|
  puts "#{item[:item]}: #{item[:error]}"
  # Decide whether to retry
end
```

### Example 4: Manual Pause and Resume

```ruby
# Setup
queue = MASTER::Queue.new
queue.add_directory("lib/")

# Process with manual control
items_processed = 0

while item = queue.next
  process(item)
  queue.complete
  
  items_processed += 1
  
  # Pause after 10 items
  if items_processed >= 10
    puts "Pausing after 10 items..."
    queue.pause
    break
  end
end

# Later session
queue = MASTER::Queue.new
queue.load_checkpoint
queue.resume

# Continue processing remaining items
while item = queue.next
  process(item)
  queue.complete
end
```

## Best Practices

### DO

- **Always set budgets**: Prevent runaway costs
- **Check progress regularly**: Monitor during long operations
- **Handle failures gracefully**: Use `queue.fail(error)` to track what went wrong
- **Inspect checkpoints**: Review state files to understand what happened
- **Use priorities**: Process critical items first
- **Load checkpoints on startup**: Always check for saved state

### DON'T

- **Don't skip error handling**: Always wrap processing in begin/rescue
- **Don't ignore failed items**: Review and retry as needed
- **Don't delete checkpoints carelessly**: They contain valuable state
- **Don't process without budgets**: Long operations can get expensive
- **Don't assume recovery is automatic**: Check load_checkpoint return value
- **Don't mix checkpoint versions**: Clear old checkpoints when making breaking changes

### Performance Tips

1. **Batch operations**: Group small items to reduce checkpoint frequency
2. **Monitor costs**: Track spending to optimize budget allocation
3. **Retry strategically**: Not all failures are worth retrying
4. **Clean up old checkpoints**: Remove stale state files periodically

### Debugging

Enable verbose logging:

```ruby
queue = MASTER::Queue.new
queue.add_files("*.rb")

while item = queue.next
  puts "Processing: #{item}"
  result = process(item)
  puts "Result: #{result.inspect}"
  queue.complete(cost: result.cost)
  
  progress = queue.progress
  puts "Progress: #{progress[:percent]}% | Spent: $#{progress[:spent]}"
end
```

Check checkpoint integrity:

```bash
# Validate JSON syntax
cat ~/.copilot/session-state/queue_checkpoint.json | jq empty

# Pretty print
cat ~/.copilot/session-state/queue_checkpoint.json | jq . | less
```

---

For more information on the queue system, see `lib/queue.rb`.
For checkpoint file format details, see the JSON structure in this document.
