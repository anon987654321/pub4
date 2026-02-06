export MASTER_HOME="${MASTER_HOME:-$(cd "$(dirname "$0")" && pwd)}"

# Source .env if present
[ -f "$MASTER_HOME/.env" ] && source "$MASTER_HOME/.env"

alias m="ruby $MASTER_HOME/bin/master"
alias m-ask='f() { echo "{\"text\":\"$*\"}" | ruby "$MASTER_HOME/bin/master" --pipe; }; f'
alias m-evolve='f() { echo "{\"file\":\"$1\",\"test_command\":\"$2\"}" | ruby "$MASTER_HOME/bin/master" --pipe --evolve; }; f'
