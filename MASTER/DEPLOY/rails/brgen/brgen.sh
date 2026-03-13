#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# BRGEN v3.1.0 - Rails 8 Social Network
# Orchestrator — sources per-feature scripts in order

typeset -r VERSION="3.1.0"
typeset -r SCRIPT_DIR="${0:A:h}"

echo "==> BRGEN v${VERSION}"

typeset -a features
features=(
  setup
  auth
  models
  routes
  controllers
  views
  styles
  seeds
  i18n
)

for feature in $features; do
  script="$SCRIPT_DIR/features/${feature}.sh"
  if [[ ! -f "$script" ]]; then
    echo "WARN: missing $script — skipping"
    continue
  fi
  zsh "$script"
done

echo ""
echo "==> BRGEN complete."
echo "    Review config/database.yml, then:"
echo "    bin/rails server -b 0.0.0.0 -p 11006"
echo "    For production: zsh $SCRIPT_DIR/features/deploy.sh"
