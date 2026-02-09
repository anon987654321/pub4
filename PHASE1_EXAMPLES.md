# Phase 1: CLI Quick Wins - Usage Examples

## Command Line Examples

### Smart File Detection
```bash
# Before: Required explicit command
$ ./bin/master refactor complex_file.rb

# After: Auto-detects and suggests
$ ./bin/master complex_file.rb
Auto-detected file type. Suggested command: refactor
Reason: File appears complex and could benefit from refactoring
Proceed with 'refactor'? (y/n): y
```

### Dry Run Mode
```bash
# See changes without applying them
$ ./bin/master refactor my_code.rb --dry-run
Dry-run mode: showing changes without writing
Diff:
- def old_method
+ def new_method
```

### Preview Mode
```bash
# Preview and confirm before applying
$ ./bin/master refactor my_code.rb --preview
Preview of changes:
[diff output]
Apply changes? (y/n): y
✓ Refactored successfully
```

### Helpful Error Messages
```bash
# Command typos
$ ./bin/master refact foo.rb
Error: Unknown command 'refact'
Did you mean 'refactor'?

# Missing files
$ ./bin/master analyze foo.rbb
Error: File not found foo.rbb
Did you mean one of these?
  - foo.rb
  - lib/foo_helper.rb
```

### Smart Defaults
```bash
# No arguments - enters REPL
$ ./bin/master
MASTER 4.0.0 REPL
Type '?' for help, 'exit' to quit, '!!' to repeat last command
master> 

# Directory - batch analysis
$ ./bin/master analyze lib/
Analyze all files in directory 'lib/'? (y/n): y
Found 8 Ruby files
```

### Performance Metrics
```bash
$ ./bin/master refactor my_code.rb
⠋ Refactoring my_code.rb...
✓ Refactored with diff:
[diff output]

--- Performance Metrics ---
Time: 1.23s
Tokens: 450 in, 320 out
Estimated cost: $0.0023
```

## Interactive REPL Examples

### Starting REPL
```bash
$ ./bin/master
MASTER 4.0.0 REPL
Type '?' for help, 'exit' to quit, '!!' to repeat last command
master> 
```

### Getting Help
```
master> ?
Available commands:
  refactor <code> - Refactor code snippet
  analyze <code>  - Analyze code quality
  ?               - Show this help
  !!              - Repeat last command
  exit            - Exit REPL
```

### Repeating Commands
```
master> analyze def hello; puts 'world'; end
✓ Analysis:
[analysis output]
Time: 450ms

master> !!
Repeating: analyze def hello; puts 'world'; end
✓ Analysis:
[analysis output]
Time: 420ms
```

### Command History
The REPL supports readline, so you can:
- Press ↑/↓ to navigate command history
- Press Ctrl+R to search history
- Use standard readline shortcuts (Ctrl+A, Ctrl+E, etc.)

## Color Output Examples

The CLI uses color-coded output (respects NO_COLOR environment variable):

- **Green** (✓): Success messages, completion indicators
- **Red**: Error messages, file not found
- **Yellow**: Warnings, suggestions, prompts
- **Blue**: Informational messages, tips, metrics

```bash
# With colors
$ ./bin/master refactor foo.rb
✓ Refactored successfully        # Green

# Without colors (NO_COLOR=1)
$ NO_COLOR=1 ./bin/master refactor foo.rb
✓ Refactored successfully        # Plain text
```

## Progress Indicators

Long-running operations show an animated spinner:

```
⠋ Refactoring my_code.rb...
⠙ Refactoring my_code.rb...
⠹ Refactoring my_code.rb...
⠸ Refactoring my_code.rb...
✓ Complete
```

The spinner automatically:
- Only displays on TTY (won't interfere with pipes/redirects)
- Clears itself when operation completes
- Shows elapsed time after completion

## Command-Line Flags

All new flags work with existing commands:

```bash
# Offline mode + dry-run
$ ./bin/master refactor foo.rb --offline --dry-run

# Preview + converge
$ ./bin/master refactor foo.rb --preview --converge

# Short forms
$ ./bin/master refactor foo.rb -o -d -p
```

## File Type Detection

Supports multiple languages:
- Ruby (.rb)
- Python (.py)
- JavaScript (.js, .mjs)
- TypeScript (.ts)
- Java (.java)

Detection analyzes:
- File extension
- Line count
- Method/function count
- Branch/conditional count

Suggests:
- **refactor** for complex files (>200 lines, >10 methods, >20 branches)
- **analyze** for simpler files

## Exit Codes

The CLI maintains proper exit codes:
- `0` - Success
- `1` - Error occurred
- Uses `Ctrl+C` gracefully in REPL

## Environment Variables

- `NO_COLOR` - Disables color output
- `OFFLINE` - Set automatically with `--offline` flag
- `OPENROUTER_API_KEY` - Required for LLM operations
