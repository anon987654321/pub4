# Secrets — exported before any auto-launch.
export OPENROUTER_API_KEY=__REDACTED__
export REPLICATE_API_KEY=__REDACTED__
export WEAVIATE_API_KEY=__REDACTED__
export GEMINI_API_KEY=__REDACTED__
export DEEPSEEK_API_KEY=__REDACTED__

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