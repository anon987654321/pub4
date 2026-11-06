# POSIX sh — sourced by sh, ksh and zsh callers alike.
#
# The one place the deploy path decides which Ruby it runs. OpenBSD ships Ruby
# only as packages named by version, so the interpreter on a box is whatever
# the package manager installed, and nothing may name one. The order is the
# one MASTER/bin/ruby and MASTER/lib/operator/ruby_runner.rb already use.
#
# Sets RUBY (absolute path), RUBY_SUFFIX (what follows "ruby": 40, 34, 3.4 or
# empty), BUNDLE and GEM (the same suffix, else the plain tool) and
# RUBY_CACHE_KEY (ruby plus major and minor, e.g. ruby34), which keys per-Ruby
# caches so the builds of different Rubies never mix. RUBY=/path/to/ruby in the
# environment wins. With no Ruby installed it says so and exits the caller.

_rs_find() {
  _rs_name=$1
  _rs_path=$(command -v "$_rs_name" 2>/dev/null) || _rs_path=
  case $_rs_path in
    /*) printf '%s\n' "$_rs_path"; return 0 ;;
  esac
  # Cron and rc.d start with a PATH that omits the package prefix.
  [ -x "/usr/local/bin/$_rs_name" ] && { printf '%s\n' "/usr/local/bin/$_rs_name"; return 0; }
  return 1
}

if [ -z "${RUBY:-}" ]; then
  for _rs_candidate in ruby4.0 ruby40 ruby3.4 ruby34 ruby3.3 ruby33 ruby; do
    RUBY=$(_rs_find "$_rs_candidate") && break
    RUBY=
  done
fi

if [ -z "${RUBY:-}" ]; then
  echo "ruby_select: no Ruby found (tried ruby4.0 ruby40 ruby3.4 ruby34 ruby3.3 ruby33 ruby)" >&2
  return 1 2>/dev/null || exit 1
fi

_rs_base=${RUBY##*/}
case $_rs_base in
  ruby*) RUBY_SUFFIX=${_rs_base#ruby} ;;
  *) RUBY_SUFFIX= ;;
esac

BUNDLE=$(_rs_find "bundle$RUBY_SUFFIX") || BUNDLE=$(_rs_find bundle) || BUNDLE=bundle
GEM=$(_rs_find "gem$RUBY_SUFFIX") || GEM=$(_rs_find gem) || GEM=gem
RUBY_CACHE_KEY=ruby$("$RUBY" -e 'print RUBY_VERSION.split(".").first(2).join' 2>/dev/null || printf '%s' "$RUBY_SUFFIX")

# The Bundler the box has is the Bundler to use. A lockfile written by another
# Bundler would otherwise make this one fetch and switch to it, and that install
# targets the system gem directory, which the deploy user cannot write.
BUNDLE_VERSION=${BUNDLE_VERSION:-system}

export RUBY RUBY_SUFFIX BUNDLE GEM RUBY_CACHE_KEY BUNDLE_VERSION
unset _rs_name _rs_path _rs_candidate _rs_base
unset -f _rs_find 2>/dev/null || true
