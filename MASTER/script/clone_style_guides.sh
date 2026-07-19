#!/bin/sh
# Clone upstream style guides for local study (knowledge/ is gitignored).
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/knowledge/style_guides"
mkdir -p "$DIR"
cd "$DIR"

clone_or_pull() {
  url="$1"
  name="$2"
  if [ -d "$name/.git" ]; then
    git -C "$name" pull --ff-only
  else
    git clone --depth 1 "$url" "$name"
  fi,
}

clone_or_pull https://github.com/rubocop/ruby-style-guide.git ruby-style-guide
clone_or_pull https://github.com/rubocop/rails-style-guide.git rails-style-guide
clone_or_pull https://github.com/airbnb/javascript.git javascript
clone_or_pull https://github.com/airbnb/css.git css
clone_or_pull https://github.com/thoughtbot/guides.git guides
clone_or_pull https://github.com/necolas/normalize.css.git normalize.css

echo "style guides ready under $DIR"
