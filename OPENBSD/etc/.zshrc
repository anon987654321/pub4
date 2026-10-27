# Provider credentials are host-local and must never be committed.
typeset -g PUB4_OPERATOR_ENV="${HOME}/.config/pub4/operator.env"
if [[ -r "$PUB4_OPERATOR_ENV" ]]; then
  if [[ ! -O "$PUB4_OPERATOR_ENV" ]]; then
    print -u2 -r -- "operator0: refusing $PUB4_OPERATOR_ENV; file must be owned by the current user"
  else
    # A readable file is not necessarily private. On OpenBSD and macOS, %Lp
    # reports the group/other permission bits as part of the numeric mode.
    # Unknown modes fail closed: credentials are never sourced on uncertainty.
    typeset -g PUB4_OPERATOR_ENV_MODE
    PUB4_OPERATOR_ENV_MODE="$(stat -f '%Lp' "$PUB4_OPERATOR_ENV" 2>/dev/null)" || PUB4_OPERATOR_ENV_MODE=""
    case "$PUB4_OPERATOR_ENV_MODE" in
      [0-7]00|0[0-7]00)
        source "$PUB4_OPERATOR_ENV"
        ;;
      *)
        print -u2 -r -- "operator0: refusing $PUB4_OPERATOR_ENV; permissions must be owner-only (chmod 600)"
        ;;
    esac
  fi
fi

path=(/home/dev/.local/share/gem/ruby/*/bin(N) $path)

export MASTER_AESTHETIC="${MASTER_AESTHETIC:-wscons}"
export MASTER_BRUTALIST=1
export MASTER_STARSHIP=0

typeset -g PUB4_ROOT="${HOME}/pub4"
source "${PUB4_ROOT}/OPENBSD/lib/zshrc.shared"

# Non-interactive shells (SSH `cmd`, scp): env only, no auto-launch.
[[ -o interactive && -t 0 && -t 1 ]] || return

# Escape hatch: `MASTER_NOAUTOSTART=1 zsh` boots a shell without auto-MASTER.
[[ -n $MASTER_NOAUTOSTART ]] && return

(cd ~/pub4 && RUBYOPT=-W0 git pull -q 2>/dev/null)
source "${PUB4_ROOT}/OPENBSD/lib/ruby_select.sh"
cd ~/pub4/MASTER && exec "$BUNDLE" exec "$RUBY" bin/master