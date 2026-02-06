# Session Recovery System

The MASTER Session Recovery system provides checkpoint/restore capabilities for long-running tasks, allowing graceful interruption and resumption of work.

## Overview

Session Recovery enables:
- **Automatic checkpointing** during long operations
- **State persistence** across process restarts
- **Graceful shutdown** without losing progress
- **Resume from last checkpoint** on restart
- **Budget tracking** and cost control
- **Error recovery** with state rollback

---

## Architecture

### Core Components

1. **SessionRecovery** (`lib/core/session_recovery.rb`)
   - Main checkpoint/restore engine
   - State serialization and deserialization
   - Checkpoint management

2. **SessionPersistence** (`lib/core/session_persistence.rb`)
   - Disk-based state storage
   - Checkpoint file management
   - History tracking

3. **Configuration** (`lib/config/session_recovery.yml`)
   - Recovery behavior settings
   - Checkpoint intervals
   - Retention policies

---

## Configuration

### session_recovery.yml

```yaml
session_recovery:
  # Enable automatic checkpointing
  enabled: true
  
  # Checkpoint frequency
  checkpoint_interval: 300  # seconds (5 minutes)
  checkpoint_on_items: 10   # items processed
  
  # Storage
  checkpoint_dir: ".master_checkpoints"
  max_checkpoints: 10
  
  # Recovery
  auto_resume: true
  resume_on_start: false
  
  # Retention
  keep_failed: true
  keep_successful: 7  # days
  
  # Budget tracking
  track_costs: true
  warn_threshold: 0.8  # 80% of budget
```

### Environment Variables

```bash
# Override checkpoint directory
export MASTER_CHECKPOINT_DIR="/var/lib/master/checkpoints"

# Disable auto-resume
export MASTER_AUTO_RESUME=false

# Set checkpoint interval (seconds)
export MASTER_CHECKPOINT_INTERVAL=600
```

---

## Usage

### Basic Checkpointing

```ruby
require 'master'

# Create recovery session
session = MASTER::SessionRecovery.new(
  task_id: "refactor-users-module",
  budget: 5.0
)

# Process items with automatic checkpointing
items.each_with_index do |item, i|
  begin
    result = process_item(item)
    
    # Manual checkpoint every 10 items
    if (i + 1) % 10 == 0
      session.checkpoint(
        progress: i + 1,
        data: { processed: results }
      )
    end
  rescue => e
    # Save error state
    session.checkpoint_error(e, item)
    raise
  end
end

# Mark complete
session.complete!
```

### Resuming from Checkpoint

```ruby
# Check for existing checkpoint
if session.checkpoint_exists?
  puts "Found checkpoint from #{session.last_checkpoint_time}"
  
  # Restore state
  state = session.restore
  
  # Resume from last position
  items_remaining = items[state[:progress]..-1]
  results = state[:data][:processed]
  
  # Continue processing
  items_remaining.each do |item|
    results << process_item(item)
  end
else
  # Start fresh
  process_all_items(items)
end
```

### Queue with Recovery

The queue system automatically uses session recovery:

```ruby
# Queue tasks with checkpointing
queue = MASTER::Queue.new(budget: 10.0)

queue.add("Refactor users", budget: 2.0)
queue.add("Extract services", budget: 3.0)
queue.add("Update tests", budget: 1.5)

# Process with automatic checkpointing
queue.process do |task|
  # Checkpoint happens automatically every N items
  result = execute_task(task)
  
  # Budget tracking included
  puts "Spent: $#{queue.total_spent} / $#{queue.budget}"
  
  result
end

# Interrupt with Ctrl-C - state saved
# Resume later:
queue.resume  # Picks up where it left off
```

---

## Checkpoint Format

Checkpoints are stored as JSON files:

```json
{
  "task_id": "refactor-users-module",
  "version": "52.0",
  "timestamp": "2024-02-05T23:30:00Z",
  "progress": {
    "items_processed": 45,
    "items_total": 100,
    "percentage": 45.0
  },
  "budget": {
    "allocated": 5.0,
    "spent": 2.13,
    "remaining": 2.87
  },
  "state": {
    "current_file": "app/models/user.rb",
    "processed_files": ["app/models/role.rb", "..."],
    "pending_files": ["app/services/user_service.rb", "..."]
  },
  "metadata": {
    "hostname": "dev-machine",
    "user": "developer",
    "pid": 12345
  }
}
```

### Checkpoint Location

```
.master_checkpoints/
├── refactor-users-module/
│   ├── checkpoint_001.json
│   ├── checkpoint_002.json
│   ├── checkpoint_003.json (latest)
│   └── metadata.json
├── extract-services/
│   └── checkpoint_001.json
└── index.json
```

---

## CLI Commands

### Create Checkpoint

```bash
# Manual checkpoint during operation
bin/cli checkpoint create --task "current-task" --data '{"progress": 50}'
```

### List Checkpoints

```bash
# Show all checkpoints
bin/cli checkpoint list

# Output:
# refactor-users-module
#   Latest: 2024-02-05 23:30:00 (45% complete)
#   Budget: $2.13 / $5.00
#   
# extract-services
#   Latest: 2024-02-05 22:15:00 (completed)
#   Budget: $3.45 / $3.00
```

### Resume from Checkpoint

```bash
# Resume specific task
bin/cli checkpoint resume refactor-users-module

# Resume latest checkpoint
bin/cli checkpoint resume --latest
```

### Clean Checkpoints

```bash
# Remove old checkpoints
bin/cli checkpoint clean --older-than 7d

# Remove specific checkpoint
bin/cli checkpoint remove refactor-users-module

# Remove all completed checkpoints
bin/cli checkpoint clean --completed
```

---

## Advanced Features

### Budget Tracking

Session recovery includes automatic budget tracking:

```ruby
session = MASTER::SessionRecovery.new(
  task_id: "large-refactor",
  budget: 10.0
)

session.track_cost(0.25)  # Log $0.25 spent
session.track_cost(0.50)  # Log $0.50 spent

puts session.budget_remaining  # => 9.25
puts session.budget_used_percent  # => 7.5%

# Budget warnings
if session.over_budget?
  puts "WARNING: Over budget!"
elsif session.near_budget_limit?
  puts "WARNING: Approaching budget limit (#{session.budget_used_percent}%)"
end
```

### Automatic Checkpoint Intervals

Configure automatic checkpointing:

```ruby
session = MASTER::SessionRecovery.new(
  task_id: "process-large-dataset",
  checkpoint_interval: 300,  # 5 minutes
  checkpoint_on_items: 100   # or every 100 items
)

# Automatically checkpoints based on criteria
items.each do |item|
  process_item(item)
  session.tick  # Checks if checkpoint needed
end
```

### Error Recovery

Handle errors gracefully:

```ruby
session = MASTER::SessionRecovery.new(task_id: "risky-task")

begin
  dangerous_operation()
rescue => e
  # Save error state for analysis
  session.checkpoint_error(e, context: {
    item: current_item,
    attempt: retry_count
  })
  
  # Try to recover
  if session.can_retry?
    session.retry_from_checkpoint
  else
    raise
  end
end
```

### Progress Callbacks

Monitor progress with callbacks:

```ruby
session = MASTER::SessionRecovery.new(
  task_id: "long-task",
  on_checkpoint: ->(state) {
    puts "Checkpoint: #{state[:progress]} items"
  },
  on_resume: ->(state) {
    puts "Resuming from: #{state[:progress]} items"
  },
  on_complete: ->(state) {
    puts "Completed: #{state[:items_total]} items"
    puts "Total cost: $#{state[:budget][:spent]}"
  }
)
```

---

## Integration with Queue System

Queue operations automatically use session recovery:

```ruby
# Queue configuration with recovery
queue = MASTER::Queue.new(
  budget: 20.0,
  checkpoint_interval: 300,
  auto_resume: true
)

# Add tasks
queue.add("Task 1", budget: 5.0)
queue.add("Task 2", budget: 3.0)

# Process with automatic checkpointing
queue.process

# Interrupt anytime - state is saved
# Resume from checkpoint:
queue.resume  # Continues from last checkpoint
```

### Graceful Shutdown

Handle shutdown signals:

```ruby
trap('INT') do
  puts "\nGracefully shutting down..."
  queue.checkpoint!
  exit 0
end

trap('TERM') do
  puts "\nTerminating with checkpoint..."
  queue.checkpoint!
  exit 0
end
```

---

## Best Practices

### 1. Checkpoint Frequency

```ruby
# Too frequent: overhead
checkpoint_interval: 30  # Every 30 seconds

# Too infrequent: lost work
checkpoint_interval: 3600  # Every hour

# Recommended: balance
checkpoint_interval: 300  # Every 5 minutes
checkpoint_on_items: 50   # Or every 50 items
```

### 2. Budget Management

```ruby
# Set realistic budgets
session = MASTER::SessionRecovery.new(
  task_id: "refactor",
  budget: 5.0,           # Reasonable estimate
  warn_threshold: 0.8     # Warn at 80%
)

# Monitor during execution
if session.budget_used_percent > 50
  puts "Halfway through budget"
end
```

### 3. Error Handling

```ruby
# Always checkpoint before risky operations
session.checkpoint(message: "Before dangerous operation")

begin
  dangerous_operation()
rescue => e
  # Checkpoint error state
  session.checkpoint_error(e)
  
  # Rollback to last good state if needed
  session.rollback
  raise
end
```

### 4. Cleanup

```ruby
# Regular checkpoint cleanup
MASTER::SessionRecovery.cleanup(
  older_than: 7.days,
  keep_failed: true,
  keep_completed: false
)
```

### 5. Testing

```ruby
# Test recovery scenarios
it "resumes from checkpoint" do
  session = create_session
  session.checkpoint(progress: 50)
  
  # Simulate restart
  new_session = restore_session
  expect(new_session.progress).to eq(50)
end
```

---

## Troubleshooting

### Checkpoint Not Found

```bash
# Verify checkpoint directory
ls -la .master_checkpoints/

# Check permissions
chmod 755 .master_checkpoints/

# Verify checkpoint ID
bin/cli checkpoint list
```

### Corrupt Checkpoint

```ruby
# Validate checkpoint
session = MASTER::SessionRecovery.new(task_id: "my-task")

if session.checkpoint_valid?
  session.restore
else
  puts "Checkpoint corrupt, starting fresh"
  session.reset
end
```

### Disk Space

```bash
# Check checkpoint size
du -sh .master_checkpoints/

# Clean old checkpoints
bin/cli checkpoint clean --older-than 30d
```

### Budget Exceeded

```ruby
# Check budget status
session = MASTER::SessionRecovery.new(task_id: "my-task")
puts "Spent: $#{session.budget_spent}"
puts "Limit: $#{session.budget_limit}"

# Increase budget if needed
session.increase_budget(5.0)
```

---

## Migration from pub2/pub3

Previous session recovery implementations:

```ruby
# Old (pub2)
Session.save_state(data)
Session.load_state

# New (MASTER v52+)
session = MASTER::SessionRecovery.new(task_id: "my-task")
session.checkpoint(data: data)
state = session.restore
```

Config migration:

```yaml
# Old
session:
  checkpoint_dir: ".checkpoints"

# New
session_recovery:
  checkpoint_dir: ".master_checkpoints"
  checkpoint_interval: 300
```

---

## API Reference

### SessionRecovery Class

```ruby
# Constructor
SessionRecovery.new(task_id:, budget: nil, **options)

# Instance methods
#checkpoint(data: {}, message: nil)
#restore -> Hash
#checkpoint_exists? -> Boolean
#complete!
#rollback(to_checkpoint: nil)
#budget_spent -> Float
#budget_remaining -> Float
#over_budget? -> Boolean
#can_retry? -> Boolean
```

### SessionPersistence Class

```ruby
# Class methods
SessionPersistence.save(checkpoint_id, data)
SessionPersistence.load(checkpoint_id) -> Hash
SessionPersistence.list -> Array
SessionPersistence.cleanup(older_than:, **options)
```

---

## Further Reading

- [README.md](README.md) - Main documentation
- [FRAMEWORK_INTEGRATION.md](FRAMEWORK_INTEGRATION.md) - Framework and plugins
- [ENFORCEMENT.md](ENFORCEMENT.md) - Git hooks and validation

---

**Version**: MASTER v52.0 REFLEXION  
**Last Updated**: 2024-02-05  
**Implementation**: `lib/core/session_recovery.rb`, `lib/core/session_persistence.rb`
