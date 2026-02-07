# MASTER2 - Autonomous Code Refactoring Engine

## Setup
export GEM_HOME=\$(ruby -e'puts Gem.user_dir')
export PATH="\$GEM_HOME/bin:\$PATH"
gem install --user-install parser unparser diffy minitest dotenv

Set OPENROUTER_API_KEY in .env

## Commands
- refactor <file> : Analyze and apply low-risk changes
- analyze <file> : Get suggestions
- self_refactor : Refactor MASTER2 itself
- repl : Interactive mode

## Examples
See examples/

## Multi-Language
Ruby (AST), JS/Python (regex stubs)

Ready for production.
