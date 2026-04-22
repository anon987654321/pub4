# Clone the repository
git clone https://github.com/Shubhamsaboo/awesome-llm-apps.git
cd awesome-llm-apps/advanced_llm_apps/cursor_ai_experiments/local_chatgpt_clone

# Install Ruby dependencies (OpenBSD‑first)
# • Enforce a pure‑Ruby bundle so OpenBSD’s libffi and OpenSSL are used.
# • Omit development and test groups to avoid heavy native extensions.
bundle config set force_ruby_platform true
bundle install --without development test

# Export LLM credentials (never hard‑code them)
# • `OPENROUTER_API_KEY` – API key for the OpenRouter gateway.
# • `OPENROUTER_MODEL`   – Model identifier (default: `deepseek-ai/deepseek-v3`).
# • Optional: `LOG_LEVEL=debug` for verbose logging.
export OPENROUTER_API_KEY=your_key_here
export OPENROUTER_MODEL=deepseek-ai/deepseek-v3

# Run the service
# • The Master process listens on 0.0.0.0:3000.
# • On OpenBSD the preferred front‑end is `relayd`, which proxies port 10002 → 3000.
# • Enable `relayd` in `/etc/rc.conf.d/relay.conf` if you use the default setup.
bin/master server

# Verify it works
curl -fsS http://localhost:3000/health || echo "❌ Service not responding"

# Stop the server gracefully
# • Sends SIGINT to the master process; it shuts down cleanly.
pkill -f '^bin/master'

# Optional: run the built‑in test suite
# • Requires development gems; install them with `bundle install --with development`.
bundle exec rake test

# Security notice
# • Never commit your API key. Store it in a protected file (e.g. ~/.profile or
#   /etc/login.conf) with mode 600.
# • The service runs without root privileges; use `setuser` or a dedicated
#   unprivileged user in production.