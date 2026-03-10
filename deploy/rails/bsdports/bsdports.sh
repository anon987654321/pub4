```
#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob

APP_NAME="bsdports"
BASE_DIR="/home/dev/rails"
SERVER_IP="185.52.176.18"
SCRIPT_DIR="${0:a:h}"
source "${SCRIPT_DIR}/@shared_functions.sh"

# Choose a free port
while ! validate_port_available $((10000 + RANDOM % 55536)); do
  : # retry
done
APP_PORT=$((10000 + RANDOM % 55536))

if ! bin/rails db:migrate; then
  echo "Error: Rails migration failed." >&2
  exit 1
fi
```
