# MASTER Zsh Frontend
# Pure Zsh — no bashisms

zmodload zsh/mapfile
zmodload zsh/stat  
zmodload zsh/datetime
zmodload zsh/system

export MASTER_ROOT="${${(%):-%x}:A:h}"
export MASTER_DB="${MASTER_ROOT}/master.db"
export PATH="${MASTER_ROOT}/bin:${PATH}"

# Lazy-load functions
fpath=("${MASTER_ROOT}/lib/zsh" $fpath)
autoload -Uz m-start m-ask m-evolve m-quality m-status m-cost m-remember

# Shell functions for common operations
m-start() { "${MASTER_ROOT}/bin/start" "$@" }
m-ask()   { print -r -- "{\"text\":\"$*\"}" | ruby "${MASTER_ROOT}/bin/intake" | ruby "${MASTER_ROOT}/bin/guard" | ruby "${MASTER_ROOT}/bin/route" | ruby "${MASTER_ROOT}/bin/ask" | ruby "${MASTER_ROOT}/bin/critique" | ruby "${MASTER_ROOT}/bin/render" }
m-evolve(){ print -r -- "{\"text\":\"$*\"}" | ruby "${MASTER_ROOT}/bin/intake" | ruby "${MASTER_ROOT}/bin/guard" | ruby "${MASTER_ROOT}/bin/route" | ruby "${MASTER_ROOT}/bin/ask" | ruby "${MASTER_ROOT}/bin/critique" | ruby "${MASTER_ROOT}/bin/execute" | ruby "${MASTER_ROOT}/bin/evolve" | ruby "${MASTER_ROOT}/bin/render" }
m-quality() { print -r -- "{\"files\":\"${*:-.}\"}" | ruby "${MASTER_ROOT}/bin/quality" | ruby "${MASTER_ROOT}/bin/render" }
m-status() { ruby "${MASTER_ROOT}/bin/seed" --status 2>/dev/null || print "master0: no status data" }
m-cost()  { sqlite3 "${MASTER_DB}" "SELECT date(created_at,'unixepoch','localtime'), ROUND(SUM(cost_usd),4) FROM costs GROUP BY 1 ORDER BY 1 DESC LIMIT 7" }

# Tab completion
_master_commands() {
  local -a commands=(
    'start:interactive REPL'
    'ask:one-shot query'
    'evolve:self-modify with rollback'
    'quality:run quality gates'
    'status:system status'
    'cost:spending summary'
  )
  _describe 'command' commands
}
compdef _master_commands m-start m-ask m-evolve m-quality m-status m-cost

# File operations using pure Zsh
m-files() {
  local -a files=( ${MASTER_ROOT}/lib/**/*.rb(.N) )
  local total_lines=0
  for f in $files; do
    local -a lines=( "${(f)mapfile[$f]}" )
    total_lines+=${#lines}
  done
  print "master0: ${#files} files, ${total_lines} lines"
}

PROMPT="dev@sonnet-4.5$ "
