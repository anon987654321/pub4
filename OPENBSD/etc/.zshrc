# Provider credentials are host-local and must never be committed.
typeset -g PUB4_OPERATOR_ENV="${HOME}/.config/pub4/operator.env"
if [[ -r $PUB4_OPERATOR_ENV ]]; then
  source "$PUB4_OPERATOR_ENV"
fi

path=(/home/dev/.local/share/gem/ruby/*/bin(N) $path)

export MASTER_AESTHETIC="${MASTER_AESTHETIC:-wscons}"
export MASTER_BRUTALIST=1
export MASTER_STARSHIP=0

typeset -g PUB4_ROOT="${HOME}/pub4"
source "${PUB4_ROOT}/FUN/zshrc.shared"

# Non-interactive shells (SSH `cmd`, scp): env only, no auto-launch.
[[ -o interactive && -t 0 && -t 1 ]] || return

# Escape hatch: `MASTER_NOAUTOSTART=1 zsh` boots a shell without auto-MASTER.
[[ -n $MASTER_NOAUTOSTART ]] && return

(cd ~/pub4 && RUBYOPT=-W0 git pull -q 2>/dev/null)
source "${PUB4_ROOT}/OPENBSD/lib/ruby_select.sh"
cd ~/pub4/MASTER && exec "$BUNDLE" exec "$RUBY" bin/cli