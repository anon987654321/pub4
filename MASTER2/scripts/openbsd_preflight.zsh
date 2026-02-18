#!/bin/zsh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "master2 preflight (openbsd/zsh)"
echo "root: $ROOT_DIR"

if [[ "${SHELL:t}" != "zsh" ]]; then
  echo "warn: shell is '${SHELL:t}', expected 'zsh'"
else
  echo "ok: zsh shell detected"
fi

if ! command -v ruby >/dev/null 2>&1; then
  echo "fail: ruby not found"
  exit 1
fi
echo "ok: ruby $(ruby -v | awk '{print $1, $2}')"

if ! command -v bundle >/dev/null 2>&1; then
  echo "fail: bundler not found"
  exit 1
fi
echo "ok: bundler available"

if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
  echo "warn: OPENROUTER_API_KEY not set (LLM features unavailable)"
else
  echo "ok: OPENROUTER_API_KEY set"
fi

echo "check: ruby syntax"
ruby -c bin/master >/dev/null
echo "ok: bin/master syntax"

echo "check: app health"
timeout 20s bin/master health || true

echo "ready: run 'bin/master'"
