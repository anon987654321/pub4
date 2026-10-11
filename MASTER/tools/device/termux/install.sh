#!/data/data/com.termux/files/usr/bin/bash
# Install MASTER in Termux's private home, never shared Android storage.
set -eu

fail() { printf 'master-install0: %s\n' "$*" >&2; exit 1; }
command -v pkg >/dev/null 2>&1 || fail "Run this inside Termux, not Android's shell."
command -v git >/dev/null 2>&1 || {
  pkg update
  pkg install -y git
}
ROOT="${HOME}/pub4"
REPO="https://github.com/anon987654321/pub4.git"

if [ ! -d "${ROOT}/.git" ]; then
  [ ! -e "$ROOT" ] || fail "$ROOT exists but is not a Git checkout; move it aside and retry."
  git clone "$REPO" "$ROOT"
else
  printf 'master-install0: using existing checkout %s (no automatic pull)\n' "$ROOT"
fi

cd "$ROOT/MASTER"
pkg update
pkg install -y ruby clang make cmake pkg-config sqlite openssl libffi termux-api
if ! command -v ruby >/dev/null 2>&1; then
  fail "Ruby installation failed; run pkg install ruby and retry."
fi

ruby -rrubygems -e 'required = Gem::Requirement.new(">= 3.3.0", "< 4.1.0"); actual = Gem::Version.new(RUBY_VERSION); abort "MASTER requires #{required}; found #{actual}" unless required.satisfied_by?(actual)'
printf 'master-install0: installing locked Ruby dependencies\n'
ruby bin/deps install
printf 'master-install0: checking dependency state\n'
ruby bin/deps check

# Termux:API also needs its Android companion app installed and permissions
# granted in Android settings; pkg install alone cannot grant those permissions.
if command -v termux-media-player >/dev/null 2>&1; then
  printf 'master-install0: Termux:API command found; verify the companion app and permissions on-device\n'
else
  printf 'master-install0: optional voice/media support needs the Termux:API app and pkg install termux-api\n'
fi

mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/master" <<'LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash
set -eu
cd "$HOME/pub4/MASTER"
exec ruby bin/cli "$@"
LAUNCHER
chmod 700 "$HOME/.local/bin/master"

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.bashrc" ;;
esac

printf 'master-install0: running boot smoke test\n'
ruby bin/deps boot
printf 'master-install0: installed; restart Termux or run: source ~/.bashrc && master\n'
