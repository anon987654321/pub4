#!/usr/bin/env zsh
set -euo pipefail

readonly VERSION="1.0.0"
readonly APP_NAME="brgen_playlist"

SCRIPT_DIR="${0:a:h}"
APP_DIR="/home/brgen/app"
cd "$APP_DIR"

log() { printf '{"time":"%s","msg":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" }

log "Installing Brgen Playlist - Music streaming per Spotify Blend competitive analysis"

# Use SQLite for development
print > config/database.yml << 'YAML'
default: &default
  adapter: sqlite3
  pool: 5
  timeout: 5000

development:
  <<: *default
  database: db/development.sqlite3

test:
  <<: *default
  database: db/test.sqlite3

production:
  adapter: postgresql
  encoding: unicode
  pool: 5
  database: brgen_production
YAML

# Preserve exact CSS from index.html demo
print > app/assets/stylesheets/playlist.css << 'CSS'
:root{--safe-top:env(safe-area-inset-top,0);--safe-right:env(safe-area-inset-right,0);--safe-bottom:env(safe-area-inset-bottom,0);--safe-left:env(safe-area-inset-left,0)}
*{margin:0;padding:0;box-sizing:border-box}
html,body{height:100%;background:#000;color:#00f;font:16px/1.5 'Courier New',monospace;overflow:hidden}
canvas{position:fixed;inset:0;width:100dvw;height:100dvh;display:block;background:#000;touch-action:none;image-rendering:pixelated;image-rendering:crisp-edges;filter:contrast(1.1)}
h1{position:fixed;top:calc(10px + var(--safe-top));left:calc(10px + var(--safe-left));width:min(92vw,560px);z-index:95;pointer-events:none;user-select:none;font-weight:700;font-size:clamp(14px,3.5vw,24px);letter-spacing:.02em;color:#00f;text-shadow:1px 1px 0 #000}
.ui{position:fixed;right:calc(12px + var(--safe-right));bottom:calc(10px + var(--safe-bottom));color:#00f;font:9px/1.1 'Courier New',monospace;text-transform:uppercase;letter-spacing:.28em;user-select:none;text-align:right;z-index:90;text-shadow:1px 1px 0 #000}
CSS

# Models with collaborative features per Spotify Blend
bin/rails generate model Playlist::Set user:references name:string description:text privacy:integer:default[0] collaborative:boolean:default[false]
bin/rails generate model Playlist::Track set:references name:string artist:string album:string duration:integer position:integer audio_url:string
bin/rails generate model Playlist::Collaboration set:references user:references role:string
bin/rails generate model Playlist::Activity set:references user:references action:string track_id:integer

bin/rails db:migrate

log "Brgen Playlist complete with Spotify-inspired collaboration SQLite dev"