# Phase 4 Usage Examples

## Getting Started with Phase 4

### Initial Setup

Run the setup wizard to configure your preferences:

```bash
MASTER> phase4-setup
━━━ Phase 4 Autonomy Setup ━━━

Let's configure your autonomy preferences.

Verbosity level? (low/medium/high)
> medium

Show proactive suggestions? (yes/no)
> yes

Enable automatic error recovery? (yes/no)
> yes

Use colors in output? (yes/no)
> yes

✓ Preferences saved!
```

## Example Workflows

### 1. Code Analysis with Suggestions

```bash
# Scan a codebase
MASTER> scan lib/
Found 5 issues in 12 files
→ Suggestion: Try `refactor lib/` next

# Follow the suggestion
MASTER> refactor lib/
Refactoring lib/...
✓ Applied 3 improvements

→ Suggestion: Try `test` next

# Or use the suggest command
MASTER> suggest
Suggestion: commit
```

### 2. Self-Healing in Action

```bash
# Command fails due to rate limit
MASTER> ask "Complex question requiring many tokens"
✗ Rate limit exceeded
⟳ Retrying in 60s... (attempt 1/3)
✓ Success after 2 attempts

# Automatic rollback on syntax error
MASTER> refactor broken.rb
✗ Syntax error detected
⟲ Rolling back changes...
✓ Repository restored to clean state
```

### 3. Adaptive Verbosity

```bash
# Initially verbose
MASTER> status
━━━ STATUS [12:34:56] ━━━
Session: silent-tide
Commands: 15
Cost: $0.03
Streak: 5
━━━━━━━━━━━━━━━━━━━━━━

# After learning you prefer minimal output
MASTER> status
✓  # Just the essentials

# Unless you need details (debug mode)
MASTER> debug status
━━━ DEBUG STATUS [12:35:10] ━━━
[Full detailed output...]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 4. Metrics Tracking

```bash
# View real-time dashboard
MASTER> metrics
Dashboard:
  Uptime: 2h 15m 34s
  Events/min: 2.3
  Success Rate: 94.2%
  Learning Rate: 0.15
  Autonomy Score: 0.72 (high)
  Health: 0.89 (healthy)

Performance Summary:
  scan: 8 calls, avg 1.2s, 100% success
  refactor: 5 calls, avg 3.4s, 80% success
  ask: 12 calls, avg 2.1s, 91.7% success

Recent Learning:
  - Pattern: scan → refactor → test (×3)
  - Pattern: edit → edit → lint (×2)

# Export detailed report
MASTER> phase4-report markdown
Report exported to: ~/.master/var/reports/autonomy_report_20260206_124530.md
```

### 5. Feedback Loop

```bash
# Rate your satisfaction
MASTER> satisfaction 9
Thank you! Your satisfaction: 9/10. Average: 8.2/10

# System learns from negative feedback
MASTER> satisfaction 4
Thank you! Your satisfaction: 4/10. Average: 7.8/10
# System automatically adjusts to be more concise

# View trends
MASTER> metrics
Feedback Insights:
  Total Feedback: 47
  Average Score: 7.8/10
  Trend: improving ↗
  Corrections Applied: 3
```

### 6. System Diagnostics

```bash
# Run comprehensive diagnostics
MASTER> diagnostics
Running Phase 4 diagnostics...

System Health:
  ✓ file_system: healthy (all required dirs present)
  ✓ git_status: repo present, clean working directory
  ✓ dependencies: all gems installed
  ✓ environment: OPENROUTER_API_KEY set
  ✓ memory: 45.2% usage (healthy)

Metrics Dashboard:
  · uptime: 7823s
  · events_per_minute: 2.3
  · success_rate: 94.2%
  · learning_rate: 0.15
  · autonomy_score: 0.72
  · health_score: 0.89

Feedback Insights:
  · total_feedback: 47
  · average_score: 7.8
  · trend: improving
  · correction_count: 12

Learned Patterns: 8
  · scan → refactor → test (×5)
  · ask → ask → refine (×3)
  · edit → edit → lint (×4)
  · refactor → test → commit (×2)
  · evolve → test → commit (×1)
```

### 7. Auto-Tuning

```bash
# Let the system optimize itself
MASTER> tune
Auto-tuning system based on feedback...
  · Satisfaction stable - maintaining current settings
  · Optimizing slow operations: chamber, evolve
  · Applying 3 recent corrections
  · Adjusting verbosity: medium → low (based on usage)
  · Enabling smart suggestions (high success rate)
Auto-tuning complete!
```

## Advanced Usage

### Using Phase 4 in Scripts

```ruby
require_relative 'lib/master'
require_relative 'lib/autonomy/phase4'

# Initialize components
components = MASTER::Autonomy::Phase4.initialize_components(llm)

# Execute with full Phase 4 enhancements
result = MASTER::Autonomy::Phase4.execute_enhanced(
  'scan',
  { path: 'lib/' },
  components: components
) do |args|
  # Your scan implementation
  scan_directory(args[:path])
end

if result[:success]
  puts "✓ Success after #{result[:attempts]} attempt(s)"
else
  puts "✗ Failed: #{result[:error]}"
end
```

### Custom Recovery Strategies

```ruby
# Add custom recovery strategy
healing = components[:healing]

# Override recovery for specific error
def custom_recovery(error)
  case error.message
  when /custom pattern/
    { action: :heal, healing_action: :custom_fix }
  else
    super
  end
end
```

### Pattern Learning API

```ruby
suggestions = components[:suggestions]

# Record successful command sequence
suggestions.record_command('scan', success: true, context: { files: 12 })
suggestions.record_command('refactor', success: true, context: { files: 12 })
suggestions.record_command('test', success: true, context: { files: 12 })

# Get suggestion based on learned patterns
next_cmd = suggestions.suggest_next(current_command: 'test')
# => "commit"
```

### Metrics Export Formats

```bash
# Export as Markdown
MASTER> phase4-report markdown
Report exported to: ~/.master/var/reports/autonomy_report_20260206_124530.md

# Export as JSON
MASTER> phase4-report json
Report exported to: ~/.master/var/reports/autonomy_report_20260206_124530.json

# Export as YAML
MASTER> phase4-report yaml
Report exported to: ~/.master/var/reports/autonomy_report_20260206_124530.yaml
```

## Tips and Tricks

### 1. Quick Satisfaction Feedback

After any command, quickly rate it:
```bash
MASTER> refactor lib/
...
MASTER> satisfaction 8
```

### 2. Check Before Expensive Operations

```bash
MASTER> evolve
⚠ Warnings detected:
  - Budget very low - may not converge
  - No git repo - can't revert failures
Continue anyway? (y/n)
> n

MASTER> git init
MASTER> evolve  # Now safer
```

### 3. Use Diagnostics for Debugging

```bash
# Something not working right?
MASTER> diagnostics
# Check health metrics to identify issues
```

### 4. Learn Preferences Over Time

The system learns your preferences automatically:
- Verbosity level (based on interaction duration)
- Suggestion helpfulness (based on usage)
- Error tolerance (based on reactions)
- Output formatting (based on feedback)

### 5. Export Reports for Analysis

```bash
# Weekly review
MASTER> phase4-report markdown
# Review the markdown file to see improvements
```

## Troubleshooting

### Suggestions Not Appearing

```bash
# Check if suggestions are enabled
MASTER> phase4-setup
# Select "yes" for suggestions

# Or check preferences directly
cat ~/.master/var/ui_preferences.yml
```

### High Memory Usage

```bash
# Run diagnostics
MASTER> diagnostics
# Check memory usage

# If high, system will auto-trigger GC
# Or manually reset metrics
rm ~/.master/var/metrics.jsonl
```

### Incorrect Patterns Learned

```bash
# Clear learned patterns
rm ~/.master/var/suggestions_learned.yml

# Provide corrective feedback
MASTER> satisfaction 3
# System will adjust
```

## Next Steps

1. Run `phase4-setup` to configure preferences
2. Use commands normally - Phase 4 works automatically
3. Provide satisfaction ratings to help improve
4. Check `diagnostics` periodically
5. Review exported reports for insights

See `docs/PHASE4.md` for complete documentation.
