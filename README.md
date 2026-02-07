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
- repl : Interactive

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
