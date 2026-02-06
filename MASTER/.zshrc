# MASTER shell environment
# Source this from ~/.zshrc: source /home/dev/pub/MASTER/.zshrc

MASTER_ROOT="${0:A:h}"
export MASTER_ROOT

# Source .env for API keys (NEVER hardcode keys in this file)
[[ -f "${MASTER_ROOT}/.env" ]] && source "${MASTER_ROOT}/.env"

# Aliases
alias m-start="${MASTER_ROOT}/bin/start"
alias m-ask='f() { echo "{\"text\":\"$*\"}" | "${MASTER_ROOT}/bin/intake" | "${MASTER_ROOT}/bin/guard" | "${MASTER_ROOT}/bin/route" | "${MASTER_ROOT}/bin/ask" | "${MASTER_ROOT}/bin/render" }; f'
alias m-evolve="${MASTER_ROOT}/bin/evolve"
alias m-quality="${MASTER_ROOT}/bin/quality"
