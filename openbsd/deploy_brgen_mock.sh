#!/usr/bin/env zsh
# Deploy mock Rails app to brgen.no on OpenBSD 7.7
# Run as: doas zsh deploy_brgen_mock.sh

set -euo pipefail

readonly APP_DIR="/var/rails/brgen"
readonly PORT=11006

log() { print "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

# Verify Ruby 3.3 installed
if ! command -v ruby33 >/dev/null 2>&1; then
  log "ERROR: ruby33 not found. Run: pkg_add ruby%3.3"
  exit 1
fi

# Verify Rails 8 gem installed
if ! ruby33 -e 'require "rails"; exit Rails.version.to_i >= 8' 2>/dev/null; then
  log "Installing Rails 8..."
  gem33 install rails --version '~> 8.1.0'
fi

log "Creating Rails app at $APP_DIR"
mkdir -p "$(dirname "$APP_DIR")"
cd "$(dirname "$APP_DIR")"

# Generate new Rails 8 app with SQLite (Solid Stack)
rails33 new brgen \
  --skip-git \
  --skip-test \
  --skip-system-test \
  --skip-bootsnap \
  --database=sqlite3

cd "$APP_DIR"

log "Adding Falcon to Gemfile"
cat >> Gemfile << 'EOF'

# Async HTTP server
gem 'falcon'
EOF

log "Installing gems"
bundle33 install --without development test

log "Creating HomeController"
cat > app/controllers/home_controller.rb << 'EOF'
class HomeController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:health]
  
  def index
    @info = {
      app: "brgen.no",
      rails: Rails.version,
      ruby: RUBY_VERSION,
      hostname: Socket.gethostname,
      environment: Rails.env,
      timestamp: Time.now.utc.iso8601,
      uptime: %x(uptime).strip
    }
  end
  
  def health
    render json: {
      status: "ok",
      timestamp: Time.now.utc.iso8601,
      rails: Rails.version,
      ruby: RUBY_VERSION
    }, status: 200
  end
end
EOF

log "Configuring routes"
cat > config/routes.rb << 'EOF'
Rails.application.routes.draw do
  root "home#index"
  get "health", to: "home#health"
  
  get "up" => "rails/health#show", as: :rails_health_check
end
EOF

log "Creating view"
mkdir -p app/views/home
cat > app/views/home/index.html.erb << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <title>brgen.no - Rails 8 + OpenBSD</title>
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .container {
      max-width: 800px;
      background: rgba(255,255,255,0.95);
      padding: 60px 40px;
      border-radius: 16px;
      box-shadow: 0 20px 60px rgba(0,0,0,0.3);
      color: #1a202c;
    }
    h1 {
      font-size: 3.5em;
      margin-bottom: 10px;
      background: linear-gradient(135deg, #667eea, #764ba2);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      background-clip: text;
    }
    .status {
      display: inline-block;
      background: #10b981;
      color: white;
      padding: 8px 20px;
      border-radius: 20px;
      font-weight: 600;
      margin-bottom: 40px;
      font-size: 0.9em;
    }
    .info-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: 20px;
      margin: 30px 0;
    }
    .info-card {
      background: #f7fafc;
      padding: 20px;
      border-radius: 8px;
      border-left: 4px solid #667eea;
    }
    .info-card h3 {
      font-size: 0.85em;
      color: #718096;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      margin-bottom: 8px;
    }
    .info-card p {
      font-size: 1.1em;
      font-weight: 600;
      color: #2d3748;
      font-family: 'Monaco', 'Courier New', monospace;
    }
    .footer {
      margin-top: 40px;
      padding-top: 20px;
      border-top: 2px solid #e2e8f0;
      color: #718096;
      font-size: 0.9em;
    }
    .stack {
      margin: 10px 0;
      font-family: 'Monaco', monospace;
      font-size: 0.85em;
    }
    a { color: #667eea; text-decoration: none; font-weight: 600; }
    a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <div class="container">
    <h1>🎉 brgen.no</h1>
    <span class="status">✓ PRODUCTION</span>
    
    <p style="font-size: 1.3em; margin-bottom: 30px; color: #4a5568;">
      Rails 8 application successfully deployed on OpenBSD 7.7 infrastructure.
    </p>
    
    <div class="info-grid">
      <div class="info-card">
        <h3>Application</h3>
        <p><%= @info[:app] %></p>
      </div>
      
      <div class="info-card">
        <h3>Rails Version</h3>
        <p><%= @info[:rails] %></p>
      </div>
      
      <div class="info-card">
        <h3>Ruby Version</h3>
        <p><%= @info[:ruby] %></p>
      </div>
      
      <div class="info-card">
        <h3>Environment</h3>
        <p><%= @info[:environment] %></p>
      </div>
      
      <div class="info-card">
        <h3>Hostname</h3>
        <p><%= @info[:hostname] %></p>
      </div>
      
      <div class="info-card">
        <h3>Timestamp (UTC)</h3>
        <p style="font-size: 0.85em;"><%= @info[:timestamp] %></p>
      </div>
    </div>
    
    <div class="footer">
      <p class="stack">
        <strong>Technology Stack:</strong><br>
        OpenBSD 7.7 → PF Firewall → NSD DNS+DNSSEC → Relayd (TLS) → Falcon → Rails 8 → SQLite (Solid Stack)
      </p>
      
      <p style="margin-top: 20px;">
        <strong>Health Check:</strong> <a href="/health">/health</a><br>
        <strong>Rails Health:</strong> <a href="/up">/up</a>
      </p>
      
      <p style="margin-top: 20px; font-size: 0.85em;">
        Server Uptime: <%= @info[:uptime] %>
      </p>
    </div>
  </div>
</body>
</html>
EOF

log "Configuring production environment"
cat >> config/environments/production.rb << 'EOF'

# Allow all hosts (behind relayd reverse proxy)
config.hosts.clear

# Force SSL is handled by relayd
config.force_ssl = false
EOF

log "Setting up database"
RAILS_ENV=production bin/rails db:create db:migrate

log "Precompiling assets"
RAILS_ENV=production bin/rails assets:precompile

log "Creating rc.d service script"
cat > /etc/rc.d/brgen << 'RCEOF'
#!/bin/ksh
daemon="/usr/local/bin/bundle33"
daemon_flags="exec falcon host --bind http://localhost:11006"
daemon_user="_brgen"

. /etc/rc.d/rc.subr

rc_bg=YES
rc_reload=NO

rc_cmd $1
RCEOF

chmod +x /etc/rc.d/brgen

log "Creating _brgen user"
if ! id -u _brgen >/dev/null 2>&1; then
  useradd -s /sbin/nologin -d "$APP_DIR" -L daemon -c "brgen.no Rails App" _brgen
fi

log "Setting permissions"
chown -R _brgen:_brgen "$APP_DIR"

log "Starting service"
rcctl enable brgen
rcctl start brgen

log "Deployment complete!"
log ""
log "Service: brgen running on localhost:$PORT"
log "Access: https://brgen.no (after relayd configured)"
log "Health: https://brgen.no/health"
log ""
log "Logs: /var/log/messages (via rc.d)"
log "Control: rcctl stop|start|restart brgen"
