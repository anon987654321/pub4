#!/usr/bin/env zsh
set -euo pipefail

# Blognet setup: AI-powered blogging platform with LangChain, OpenAI, Weaviate, Replicate
APP_NAME="blognet"

BASE_DIR="/home/dev/rails"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

BRGEN_IP="46.23.95.45"

source "${SCRIPT_DIR}/__shared/@common.sh"

log "Starting Blognet setup"
setup_full_app "$APP_NAME"
command_exists "ruby"

command_exists "node"

command_exists "psql"

command_exists "redis-server"

install_gem "faker"
install_gem "ruby-openai"
install_gem "langchainrb"
install_gem "weaviate-ruby"

bundle_output=$(bundle list 2>/dev/null || true)
if [[ "$bundle_output" != *"replicate-ruby"* ]]; then
  log "Installing replicate-ruby from GitHub"
  bundle config set --local github.https true

  bundle add replicate-ruby --git https://github.com/replicate/replicate-ruby.git
fi
bin/rails generate scaffold Blog title:string description:text user:references published:boolean
bin/rails generate scaffold BlogPost blog:references title:string content:text user:references published:boolean
bin/rails generate model BlogComment blog_post:references user:references content:text
bin/rails db:migrate

generate_turbo_views "blogs" "blog"
generate_turbo_views "blog_posts" "blog_post"
commit "Blognet setup complete: AI-powered blogging platform with LangChain, OpenAI, Weaviate, and Replicate"
log "Blognet setup complete. Run bin/falcon-host with PORT set to start on OpenBSD."

