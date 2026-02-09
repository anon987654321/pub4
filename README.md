# MASTER2 - Autonomous Code Refactoring Engine

## Setup
export GEM_HOME=\$(ruby -e'puts Gem.user_dir')
export PATH="\$GEM_HOME/bin:\$PATH"
gem install --user-install parser unparser diffy minitest dotenv sqlite3

export OPENROUTER_API_KEY=your_key

## Commands
- refactor <file> : Auto-refactor low-risk changes
- analyze <file> : Get suggestions
- self_refactor : Refactor lib/ files
- auto_iterate : Iterative self-improvement (converges on no changes)
- stats : Show monitoring stats
- repl : Interactive REPL with ? help and !! repeat
- version : Show version
- help : Show help

### Command Options
- `--offline` or `-o` : Offline mode
- `--converge` or `-c` : Auto-iterate until convergence
- `--dry-run` or `-d` : Show what would change without writing
- `--preview` or `-p` : Show before/after diff with confirmation

### Smart Features (Phase 1 Quick Wins)
- **Auto-detection**: Run `./bin/master file.rb` to auto-suggest refactor/analyze
- **Progress indicators**: Spinner with elapsed time for long operations
- **Color output**: Green for success, red for errors, yellow for warnings
- **Smart errors**: Command typos suggest closest match, missing files suggest similar
- **Interactive REPL**: Type `?` for help, `!!` to repeat last command
- **Performance metrics**: Shows tokens used, cost estimate, and execution time
- **Smart defaults**: No args enters REPL, directory input prompts for batch analysis

## Features
- Ruby AST (parser/unparser)
- JS/Python regex stubs
- LLM analysis (Grok-4-fast)
- Autonomy decisions
- Persistence (SQLite)
- Monitoring (tokens/cost)
- Tools (shell/web search)

## Tests
ruby -I lib test/full_test.rb

Ready.
