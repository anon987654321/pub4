# Secrets — exported before any auto-launch.
export OPENROUTER_API_KEY=__REDACTED__
export REPLICATE_API_KEY=__REDACTED__
export WEAVIATE_API_KEY=__REDACTED__
export GEMINI_API_KEY=__REDACTED__
export DEEPSEEK_API_KEY=__REDACTED__

export PATH="/home/dev/.local/share/gem/ruby/3.4/bin:$PATH"

# Modern dev terminal (Nerd Fonts, Starship, Neovim, good aliases)
# Installed via DEPLOY/openbsd pkg_add + this tracked .zshrc
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

export EDITOR=nvim
export VISUAL=nvim

# Quality of life (from operator's blessed local stack)
alias v='nvim'
alias ll='ls -lah'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias brgen='tmux-ssh dev@brgen.no'  # if remote helper needed inside VPS

# tmux-ssh: persistent named tmux over ssh (synced from live dev stack for consistency)
tmux-ssh() {
  typeset host=$1
  typeset session=${2:-main}
  [[ -z $host ]] && { print "Usage: tmux-ssh user@host [session]"; return 1 }
  ssh -t "$host" "tmux new -A -s $session"
}

# Non-interactive shells (SSH `cmd`, scp): env only, no auto-launch.
[[ -o interactive && -t 0 && -t 1 ]] || return

# Escape hatch: `MASTER_NOAUTOSTART=1 zsh` boots a shell without auto-MASTER.
[[ -n $MASTER_NOAUTOSTART ]] && return

(cd ~/pub4 && RUBYOPT=-W0 git pull -q 2>/dev/null)
cd ~/pub4/MASTER && exec bundle34 exec ruby34 bin/cli
