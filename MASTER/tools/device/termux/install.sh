#!/data/data/com.termux/files/usr/bin/bash
# Install MASTER in Termux's private home, never shared Android storage.
set -eu

fail() { printf 'master-install0: %s\n' "$*" >&2; exit 1; }
command -v pkg >/dev/null 2>&1 || fail "Run this inside Termux, not Android's shell."

pkg update
command -v git >/dev/null 2>&1 || pkg install -y git

ROOT="${HOME}/pub4"
REPO="https://github.com/anon987654321/pub4.git"

if [ -d "${ROOT}/.git" ]; then
  actual_origin="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
  case "$actual_origin" in
    "$REPO"|https://github.com/anon987654321/pub4|git@github.com:anon987654321/pub4.git|ssh://git@github.com/anon987654321/pub4.git) ;;
    *) fail "Existing checkout origin does not match pub4; refusing to run its installer. Found: ${actual_origin:-<none>}" ;;
  esac
  [ -f "$ROOT/MASTER/bin/deps" ] || fail "Existing checkout has no MASTER/bin/deps; refusing to continue."
  printf 'master-install0: using existing checkout %s (no automatic pull or overwrite)\n' "$ROOT"
else
  [ ! -e "$ROOT" ] || fail "$ROOT exists but is not a Git checkout; move it aside and retry."
  git clone "$REPO" "$ROOT"
fi

cd "$ROOT/MASTER"
pkg install -y ruby clang make cmake pkg-config sqlite openssl libffi termux-api

ruby -rrubygems -e 'required = Gem::Requirement.new(">= 3.3.0", "< 4.1.0"); actual = Gem::Version.new(RUBY_VERSION); abort "MASTER requires #{required}; found #{actual}" unless required.satisfied_by?(actual)'
printf 'master-install0: installing Ruby dependencies\n'
ruby bin/deps install
printf 'master-install0: checking dependency state\n'
ruby bin/deps check

# The Termux:API Android companion app and its permissions are separate from
# the termux-api package installed by pkg.
if command -v termux-media-player >/dev/null 2>&1; then
  printf 'master-install0: Termux:API command found; verify the companion app and permissions on-device\n'
else
  printf 'master-install0: voice/media support needs the Termux:API app and Android permissions\n'
fi

mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/master" <<'LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash
# MASTER_TERMUX_LAUNCHER
set -eu
cd "$HOME/pub4/MASTER"
exec ruby bin/master "$@"
LAUNCHER
chmod 700 "$HOME/.local/bin/master"

# Earlier installer versions escaped the dollar signs, which wrote literal
# $HOME/$PATH into .bashrc and could discard the inherited PATH. Remove only
# that exact generated line before ensuring the correct export is present.
ruby -e 'path = File.join(ENV.fetch("HOME"), ".bashrc"); if File.file?(path); malformed = %q{export PATH="\$HOME/.local/bin:\$PATH"}; lines = File.readlines(path); filtered = lines.reject { |line| line.chomp == malformed }; File.write(path, filtered.join) if filtered.length != lines.length; end'
if ! grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" 2>/dev/null; then
  printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.bashrc"
fi

printf 'master-install0: checking boot path\n'
ruby bin/deps boot
printf 'master-install0: installed; run: source ~/.bashrc && master\n'
