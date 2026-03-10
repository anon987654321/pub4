```zsh
#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob

APP_NAME="bsdports"
BASE_DIR="${BASE_DIR:-/home/dev/rails}"
SERVER_IP="${SERVER_IP:-185.52.176.18}"
SCRIPT_DIR="${0:a:h}"

# Source shared functions with error checking
if ! source "${SCRIPT_DIR}/@shared_functions.sh"; then
    echo "Error: Failed to source ${SCRIPT_DIR}/@shared_functions.sh" >&2
    exit 1
fi

# Choose a free port with retry limit
local max_retries=10 retry_count=0
while (( retry_count++ < max_retries )); do
    local candidate_port=$((10000 + RANDOM % 45536))
    if validate_port_available $candidate_port; then
        APP_PORT=$candidate_port
        echo "Selected port: $APP_PORT"
        break
    fi
    if (( retry_count == max_retries )); then
        echo "Error: Failed to find available port after $max_retries attempts" >&2
        exit 1
    fi
done

if ! bin/rails db:migrate; then
    echo "Error: Rails migration failed." >&2
    exit 1
fi
```
