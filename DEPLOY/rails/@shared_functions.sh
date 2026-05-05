#!/usr/bin/env zsh
# @shared_functions.sh — shared helpers for DEPLOY/rails/* scripts
# Source this file; do not execute directly.
# Requires: zsh, ruby34, bundle, rails, doas
set -euo pipefail

PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}"

if command -v doas >/dev/null 2>&1; then
  _PRIV=doas
else
  _PRIV=sudo
fi

: "${APP_PORT:=3000}"

log()      { print -P "%F{cyan}==>%f $*"; }
log_ok()   { print -P "%F{green}ok%f $*"; }
log_warn() { print -P "%F{yellow}WARN%f $*" >&2; }
log_err()  { print -P "%F{red}ERR%f $*" >&2; }

need_cmd() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || { log_err "Required: $cmd"; exit 1; }
    log_ok "$cmd found"
  done
}

already_done() {
  local sentinel=$1
  [[ -f $sentinel ]] && { log_warn "Already set up ($sentinel exists). Skipping."; return 0; }
  return 1
}

create_rails_app() {
  local app_dir=$1
  local app_name=${app_dir:t:h}
  mkdir -p "${app_dir:h}"
  if [[ ! -f "${app_dir}/config/application.rb" ]]; then
    log "Creating Rails 8 app at $app_dir"
    rails new "$app_dir" \
      --database=sqlite3 \
      --asset-pipeline=propshaft \
      --javascript=importmap \
      --skip-git \
      --skip-test \
      --skip-bundle
    # Bootstrap gems from amber to avoid OOM on fresh bundle install
    local bundle_home="/home/${app_dir:h:t}/.bundle"
    if [[ ! -d "${bundle_home}/gems" ]]; then
      log "Bootstrapping gems from amber"
      mkdir -p "${bundle_home}"
      cp -r /home/amber/.bundle/gems "${bundle_home}/"
      cp -r /home/amber/.bundle/cache "${bundle_home}/" 2>/dev/null || true
    fi
    mkdir -p "${app_dir}/.bundle"
    print "---\nBUNDLE_PATH: \"${bundle_home}/gems\"" > "${app_dir}/.bundle/config"
    cp /home/amber/app/Gemfile.lock "${app_dir}/Gemfile.lock"
  fi
  cd "$app_dir"
  log_ok "Working in: $app_dir"
}

add_gem() {
  local gem=$1 ver=${2:-}
  if ! grep -q "\"${gem}\"" Gemfile 2>/dev/null; then
    if [[ -n $ver ]]; then
      print "gem \"${gem}\", \"${ver}\"" >> Gemfile
    else
      print "gem \"${gem}\"" >> Gemfile
    fi
    log_ok "gem ${gem} added"
  else
    log_ok "gem ${gem} already present"
  fi
}

bundle_install() {
  bundle check 2>/dev/null && { log_ok "bundle ok (no install needed)"; return 0; }
  log "bundle install"
  bundle install --jobs=2 2>&1 | tail -5
  log_ok "bundle install done"
}

add_gem_group() {
  local groups=$1; shift
  local -a gems=("$@")
  if ! grep -q "gem \"${gems[1]}\"" Gemfile 2>/dev/null; then
    {
      print "group :${groups//,/, :} do"
      for g in "${gems[@]}"; do print "  gem \"$g\""; done
      print "end"
    } >> Gemfile
  fi
}

install_solid_stack() {
  log "Installing Solid Cache / Queue / Cable"
  add_gem solid_cache
  add_gem solid_queue
  add_gem solid_cable
  bin/rails solid_cache:install 2>/dev/null || true
  bin/rails solid_queue:install 2>/dev/null || true
  bin/rails solid_cable:install 2>/dev/null || true
  log_ok "Solid stack installed"
}

install_auth() {
  if [[ ! -f app/models/session.rb ]]; then
    log "Generating Rails 8 authentication"
    bin/rails generate authentication
    bin/rails db:migrate
  else
    log_ok "Authentication already generated"
  fi
}

install_active_storage() {
  if [[ -z $(print db/migrate/*create_active_storage*(N)) ]]; then
    log "Installing Active Storage"
    bin/rails active_storage:install
    bin/rails db:migrate
  else
    log_ok "Active Storage already installed"
  fi
}

install_action_text() {
  if [[ -z $(print db/migrate/*create_action_text*(N)) ]]; then
    log "Installing Action Text"
    bin/rails action_text:install
    bin/rails db:migrate
  else
    log_ok "Action Text already installed"
  fi
}

db_setup() {
  log "Setting up database"
  RAILS_ENV=production bin/rails db:create db:migrate
  log_ok "Database ready"
}

db_migrate() {
  RAILS_ENV=${RAILS_ENV:-production} bin/rails db:migrate
  log_ok "Migrations complete"
}

configure_production() {
  local cfg=config/environments/production.rb
  grep -q 'force_ssl' "$cfg" || print '  config.force_ssl = true' >> "$cfg"
  grep -q 'solid_cache' "$cfg" || print '  config.cache_store = :solid_cache_store' >> "$cfg"
  log_ok "Production config updated"
}

install_security_tools() {
  add_gem_group "development,test" brakeman rubocop-rails-omakase
  log_ok "Security tools added"
}

install_dartsass() {
  add_gem dartsass-rails
  bin/rails dartsass:install 2>/dev/null || true
  log_ok "Dart Sass installed"
}

write_base_scss() {
  mkdir -p app/assets/stylesheets
  rm -f app/assets/stylesheets/application.css
  cat > app/assets/stylesheets/application.scss << 'SCSS'
// ==================== VARIABLES ====================
:root {
  // Colors
  --color-black: #000;
  --color-white: #fff;
  --color-extra-light-grey: #f0f0f0;

  // Spacing
  --space-xs: 0.25rem;
  --space-sm: 0.5rem;
  --space-md: 1rem;
  --space-lg: 1.5rem;
  --space-xl: 2rem;

  // Typography
  --font-size-base: 14px;
  --line-height-base: 1.5;
}

// ==================== RESET & BASE ====================
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

html,
body {
  height: 100%;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
  font-size: var(--font-size-base);
  line-height: var(--line-height-base);
  color: var(--color-black);
  background-color: var(--color-white);
  display: flex;
  flex-direction: column;
}

img { max-width: 100%; display: block; }

a {
  color: #4285f4;
  text-decoration: none;
  cursor: pointer;

  &:hover { text-decoration: underline; }
  &:focus { outline: 2px solid #4285f4; outline-offset: 2px; }
}

// ==================== NAV ====================
nav {
  display: flex;
  align-items: center;
  gap: var(--space-md);
  padding: var(--space-sm) var(--space-md);
  border-bottom: 1px solid var(--color-extra-light-grey);

  a { color: inherit; }
  a:hover { text-decoration: underline; }
  .brand { font-weight: 700; margin-right: auto; }
}

// ==================== MAIN ====================
main {
  flex: 1;
  display: grid;
  grid-template-columns: 1fr;
  gap: var(--space-md);
  padding: var(--space-md);
}

// ==================== FLASH ====================
.flash {
  padding: var(--space-sm) var(--space-md);
  border-bottom: 1px solid var(--color-extra-light-grey);

  &--error, &--alert { color: #c00; }
  &--notice { color: #060; }
}

// ==================== RESPONSIVE ====================
@media (max-width: 768px) {
  .header {
    flex-direction: column;
    gap: var(--space-md);
    padding: var(--space-sm);

    &__tabs {
      gap: var(--space-sm);
      flex-wrap: wrap;
      justify-content: center;
    }
  }
}

@media (max-width: 480px) {
  html, body { font-size: 12px; }

  .header__tabs { gap: var(--space-xs); }
  .header__tab { padding: var(--space-xs) var(--space-sm); font-size: 0.9em; }
}
SCSS
  log_ok "application.scss written"
}

write_base_css() { write_base_scss; }
write_layout()     { write_full_layout "$@"; }

install_rcd() {
  local svc=$1 app_dir=$2 port=$3 user=$4
  local rcd="/etc/rc.d/${svc}"
  [[ -f $rcd ]] && { log_ok "rc.d/${svc} already exists"; return 0; }
  local secret
  secret=$(ruby34 -e 'require "securerandom"; print SecureRandom.hex(64)')
  $_PRIV tee "$rcd" > /dev/null << EOS
#!/bin/ksh
daemon="/usr/local/bin/bundle"
daemon_flags="exec env RAILS_ENV=production SECRET_KEY_BASE=${secret} HOME=/home/${user} falcon serve --bind http://127.0.0.1:${port}"
daemon_user="${user}"
daemon_execdir="${app_dir}"
daemon_timeout="60"
. /etc/rc.d/rc.subr
pexp="ruby.*${port}"
rc_bg=YES
rc_reload=NO
rc_cmd \$1
EOS
  $_PRIV chmod 755 "$rcd"
  $_PRIV rcctl enable "$svc"
  # App must be owned by the service user so it can write storage/log/tmp
  $_PRIV chown -R "${user}:${user}" "${app_dir}"
  log_ok "rc.d/${svc} installed (falcon on :${port})"
}

relayd_add_relay() {
  local host=$1 port=$2
  local table="${host%%.*}"
  local conf=/etc/relayd.conf
  grep -q "table <${table}>" "$conf" 2>/dev/null && { log_ok "relayd <${table}> exists"; return 0; }
  $_PRIV tee -a "$conf" > /dev/null << EOS

table <${table}> { 127.0.0.1 }
relay "${table}_http" {
  listen on 0.0.0.0 port 80
  forward to <${table}> port ${port} check tcp
}
EOS
  log_ok "relayd table <${table}> -> :${port} added"
}

write_falcon_config() {
  local port=${1:-3000}
  add_gem falcon
  cat > config/falcon.rb << FALCON
#!/usr/bin/env -S falcon host
# frozen_string_literal: true

load :rack, :supervisor

hostname = File.basename(__dir__)
port = ENV.fetch("PORT", ${port}).to_i

rack hostname do
  endpoint Async::HTTP::Endpoint.parse("http://0.0.0.0:\#{port}")
end
FALCON
  log_ok "Falcon config written (:${port})"
}

install_thruster() {
  add_gem thruster
  log_ok "Thruster added"
}

# ── Stimulus + Importmap ────────────────────────────────────────────────────

setup_stimulus() {
  log "Setting up Stimulus"
  bin/importmap pin @hotwired/stimulus --download 2>/dev/null || true
  mkdir -p app/javascript/controllers
  cat > app/javascript/controllers/application.js << 'JS'
import { Application } from "@hotwired/stimulus"
const application = Application.start()
application.debug = false
window.Stimulus = application
export { application }
JS
  cat > app/javascript/controllers/index.js << 'JS'
import { application } from "./application"
// controllers are auto-imported via eagerLoadControllersFrom in application.js
// or listed here explicitly:
JS
  cat >> app/javascript/application.js << 'JS'

import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)
JS
  log_ok "Stimulus ready"
}

write_stimulus_controller() {
  local name=$1
  mkdir -p app/javascript/controllers
  cat > "app/javascript/controllers/${name}_controller.js"
  log_ok "Stimulus ${name}_controller.js written"
}

# ── Pagy ───────────────────────────────────────────────────────────────────

setup_pagy() {
  add_gem pagy
  # Pagy 9+ (v43+): no initializer needed; Backend is now Pagy::Method
  ruby34 -e "
    src = File.read('app/controllers/application_controller.rb')
    unless src.include?('Pagy::Method')
      src.sub!(/class ApplicationController.*\n/, \"\\\\0  include Pagy::Method\n\")
      File.write('app/controllers/application_controller.rb', src)
    end
  "
  log_ok "Pagy configured"
}

# ── Shared partials ─────────────────────────────────────────────────────────

write_shared_partials() {
  mkdir -p app/views/shared
  cat > app/views/shared/_flash.html.erb << 'ERB'
<% flash.each do |type, msg| %>
  <div class="flash flash--<%= type %>"><%= msg %></div>
<% end %>
ERB

  cat > app/views/shared/_errors.html.erb << 'ERB'
<% if object.errors.any? %>
  <div class="errors">
    <% object.errors.full_messages.each do |msg| %>
      <p class="error-msg"><%= msg %></p>
    <% end %>
  </div>
<% end %>
ERB

  cat > app/views/shared/_pagination.html.erb << 'ERB'
<%= pagy.series_nav if pagy.pages > 1 %>
ERB
  log_ok "Shared partials written"
}

# ── Auth views ──────────────────────────────────────────────────────────────

write_auth_views() {
  mkdir -p app/views/sessions app/views/passwords
  cat > app/views/sessions/new.html.erb << 'ERB'
<div class="auth-form">
  <h1>Sign in</h1>
  <%= form_with url: session_path do |f| %>
    <%= render "shared/errors", object: f.object if f.object.respond_to?(:errors) %>
    <div class="field">
      <%= f.label :email_address, "Email" %>
      <%= f.email_field :email_address, autofocus: true, autocomplete: "email" %>
    </div>
    <div class="field">
      <%= f.label :password %>
      <%= f.password_field :password, autocomplete: "current-password" %>
    </div>
    <div class="actions">
      <%= f.submit "Sign in", class: "btn btn--primary" %>
    </div>
    <p><%= link_to "Forgot password?", new_password_path %></p>
  <% end %>
</div>
ERB

  cat > app/views/passwords/new.html.erb << 'ERB'
<div class="auth-form">
  <h1>Reset password</h1>
  <%= form_with url: passwords_path do |f| %>
    <div class="field">
      <%= f.label :email_address, "Email" %>
      <%= f.email_field :email_address, autofocus: true, autocomplete: "email" %>
    </div>
    <div class="actions">
      <%= f.submit "Send reset link", class: "btn btn--primary" %>
    </div>
  <% end %>
</div>
ERB

  cat > app/views/passwords/edit.html.erb << 'ERB'
<div class="auth-form">
  <h1>New password</h1>
  <%= form_with model: @user, url: password_path(params[:token]), method: :put do |f| %>
    <div class="field">
      <%= f.label :password, "New password" %>
      <%= f.password_field :password, autocomplete: "new-password" %>
    </div>
    <div class="field">
      <%= f.label :password_confirmation, "Confirm password" %>
      <%= f.password_field :password_confirmation, autocomplete: "new-password" %>
    </div>
    <div class="actions">
      <%= f.submit "Set password", class: "btn btn--primary" %>
    </div>
  <% end %>
</div>
ERB
  log_ok "Auth views written"
}

# ── Registration (sign-up) ───────────────────────────────────────────────────

write_registration() {
  mkdir -p app/views/registrations
  cat > app/controllers/registrations_controller.rb << 'RUBY'
class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]

  def new = render

  def create
    user = User.new(registration_params)
    if user.save
      start_new_session_for user
      redirect_to root_path, notice: "Welcome!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:user).permit(:email_address, :password, :password_confirmation)
  end
end
RUBY
  cat > app/views/registrations/new.html.erb << 'ERB'
<div class="auth-form">
  <h1>Create account</h1>
  <%= form_with model: User.new, url: registration_path do |f| %>
    <%= render "shared/errors", object: f.object %>
    <div class="field">
      <%= f.label :email_address, "Email" %>
      <%= f.email_field :email_address, autofocus: true, autocomplete: "email" %>
    </div>
    <div class="field">
      <%= f.label :password %>
      <%= f.password_field :password, autocomplete: "new-password" %>
    </div>
    <div class="field">
      <%= f.label :password_confirmation, "Confirm password" %>
      <%= f.password_field :password_confirmation, autocomplete: "new-password" %>
    </div>
    <div class="actions">
      <%= f.submit "Create account", class: "btn btn--primary" %>
    </div>
    <p><%= link_to "Sign in instead", new_session_path %></p>
  <% end %>
</div>
ERB
  log_ok "Registration written"
}

# ── Enhanced layout ─────────────────────────────────────────────────────────

write_full_layout() {
  local app_title=${1:-App}
  local nav_links=${2:-}
  mkdir -p app/views/layouts
  cat > app/views/layouts/application.html.erb << LAYOUT
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="turbo-cache-control" content="no-preview">
  <title><%= content_for?(:title) ? yield(:title) + " – ${app_title}" : "${app_title}" %></title>
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>
  <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
  <%= javascript_importmap_tags %>
</head>
<body>
<nav>
  <%= link_to "${app_title}", root_path, class: "brand" %>
  ${nav_links}
  <% if authenticated? %>
    <%= link_to "Sign out", session_path, data: { turbo_method: :delete } %>
  <% else %>
    <%= link_to "Sign in", new_session_path %>
  <% end %>
</nav>
<%= render "shared/flash" %>
<main><%= yield %></main>
</body>
</html>
LAYOUT
  log_ok "Full layout written"
}

# ── Social: votes + threaded comments ───────────────────────────────────────
# Restored from pub3/@reddit_features.sh. Call after db:migrate.

setup_votes_and_comments() {
  bin/rails generate model Vote value:integer user:references \
    votable:references{polymorphic}:index --no-test-framework
  bin/rails generate model Comment content:text user:references \
    commentable:references{polymorphic}:index parent_id:integer \
    likes_count:integer --no-test-framework
  bin/rails db:migrate

  mkdir -p app/models/concerns

  cat > app/models/concerns/votable.rb << 'RUBY'
module Votable
  extend ActiveSupport::Concern
  included do
    has_many :votes, as: :votable, dependent: :destroy
  end
  def score          = votes.sum(:value)
  def upvotes        = votes.where(value: 1).count
  def downvotes      = votes.where(value: -1).count
  def voted_by?(u)   = votes.find_by(user: u)&.value
  def upvoted_by?(u) = voted_by?(u) == 1
end
RUBY

  cat > app/models/concerns/commentable.rb << 'RUBY'
module Commentable
  extend ActiveSupport::Concern
  included do
    has_many :comments, as: :commentable, dependent: :destroy
  end
  def root_comments  = comments.where(parent_id: nil)
  def comment_count  = comments.count
end
RUBY

  cat > app/models/vote.rb << 'RUBY'
class Vote < ApplicationRecord
  belongs_to :user
  belongs_to :votable, polymorphic: true
  validates :value, inclusion: { in: [-1, 1] }
  validates :user_id, uniqueness: { scope: %i[votable_type votable_id] }
end
RUBY

  cat > app/models/comment.rb << 'RUBY'
class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :commentable, polymorphic: true
  belongs_to :parent, class_name: "Comment", optional: true
  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy
  has_many :votes, as: :votable, dependent: :destroy
  validates :content, presence: true, length: { maximum: 10_000 }
  scope :roots,        -> { where(parent_id: nil) }
  scope :best,         -> { left_joins(:votes).group(:id).order("SUM(COALESCE(votes.value,0)) DESC") }
  scope :recent,       -> { order(created_at: :desc) }
  def score = votes.sum(:value)
  def depth = parent ? parent.depth + 1 : 0
end
RUBY

  cat > app/controllers/comments_controller.rb << 'RUBY'
class CommentsController < ApplicationController
  def create
    @commentable = find_commentable
    @comment = @commentable.comments.build(comment_params)
    @comment.user = Current.user
    @comment.save ? redirect_back(fallback_location: root_path) : redirect_back(fallback_location: root_path, alert: @comment.errors.full_messages.to_sentence)
  end

  def destroy
    @comment = Comment.find(params[:id])
    redirect_back(fallback_location: root_path, alert: "Unauthorized") and return unless @comment.user == Current.user
    @comment.destroy
    redirect_back fallback_location: root_path
  end

  private

  def find_commentable
    if params[:post_id]
      Post.find(params[:post_id])
    elsif params[:video_id]
      Video.find(params[:video_id])
    end
  end

  def comment_params = params.require(:comment).permit(:content, :parent_id)
end
RUBY

  cat > app/controllers/votes_controller.rb << 'RUBY'
class VotesController < ApplicationController
  def create
    @votable = find_votable
    vote = @votable.votes.find_or_initialize_by(user: Current.user)
    vote.value = params[:value].to_i.clamp(-1, 1)
    vote.save
    redirect_back fallback_location: root_path
  end

  private

  def find_votable
    if params[:post_id]
      Post.find(params[:post_id])
    elsif params[:comment_id]
      Comment.find(params[:comment_id])
    elsif params[:video_id]
      Video.find(params[:video_id])
    end
  end
end
RUBY

  log_ok "Votes + threaded comments set up"
}

# ── Social: hashtags ─────────────────────────────────────────────────────────
# Restored from pub3/@twitter_features.sh.

setup_hashtags() {
  bin/rails generate model Hashtag name:string:uniq usage_count:integer --no-test-framework
  bin/rails generate model Tagging taggable:references{polymorphic}:index \
    hashtag:references --no-test-framework
  bin/rails db:migrate

  cat > app/models/hashtag.rb << 'RUBY'
class Hashtag < ApplicationRecord
  has_many :taggings, dependent: :destroy
  validates :name, presence: true, uniqueness: true,
            format: { with: /\A[a-zA-Z0-9_]+\z/ }
  before_validation { self.name = name.to_s.downcase.gsub(/[^a-z0-9_]/, "") }
  scope :trending, -> { where("updated_at > ?", 24.hours.ago).order(usage_count: :desc).limit(10) }
  def to_param = name
end
RUBY

  cat > app/models/tagging.rb << 'RUBY'
class Tagging < ApplicationRecord
  belongs_to :taggable, polymorphic: true
  belongs_to :hashtag
  validates :hashtag_id, uniqueness: { scope: %i[taggable_type taggable_id] }
  after_create  { hashtag.increment!(:usage_count) }
  after_destroy { hashtag.decrement!(:usage_count) if hashtag.usage_count&.positive? }
end
RUBY

  mkdir -p app/models/concerns
  cat > app/models/concerns/taggable.rb << 'RUBY'
module Taggable
  extend ActiveSupport::Concern
  included do
    has_many :taggings, as: :taggable, dependent: :destroy
    has_many :hashtags, through: :taggings
  end

  def tag_with(text)
    text.to_s.scan(/#([a-zA-Z0-9_]+)/).flatten.uniq.each do |name|
      tag = Hashtag.find_or_create_by!(name: name.downcase)
      taggings.find_or_create_by!(hashtag: tag)
    end
  end
end
RUBY

  log_ok "Hashtags set up"
}

# ── Social: direct messaging ─────────────────────────────────────────────────
# Restored from pub2/@instant_messaging.sh, adapted for Rails 8 auth.

setup_messaging() {
  bin/rails generate model Conversation --no-test-framework
  bin/rails generate model ConversationParticipant conversation:references \
    user:references last_read_at:datetime --no-test-framework
  bin/rails generate model Message conversation:references user:references \
    content:text read:boolean --no-test-framework
  bin/rails db:migrate

  cat > app/models/conversation.rb << 'RUBY'
class Conversation < ApplicationRecord
  has_many :conversation_participants, dependent: :destroy
  has_many :participants, through: :conversation_participants, source: :user
  has_many :messages, dependent: :destroy

  scope :for_user, ->(u) { joins(:conversation_participants).where(conversation_participants: { user: u }) }

  def self.between(u1, u2)
    joins(:conversation_participants)
      .where(conversation_participants: { user_id: [u1.id, u2.id] })
      .group("conversations.id")
      .having("COUNT(DISTINCT conversation_participants.user_id) = 2")
      .first
  end

  def unread_count_for(user)
    participant = conversation_participants.find_by(user: user)
    messages.where("created_at > ?", participant&.last_read_at || Time.at(0)).count
  end

  def mark_read!(user)
    conversation_participants.find_by(user: user)&.update(last_read_at: Time.current)
  end
end
RUBY

  cat > app/models/message.rb << 'RUBY'
class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :user
  validates :content, presence: true
  scope :recent, -> { order(created_at: :asc) }
  after_create_commit { broadcast_append_to conversation }
end
RUBY

  cat > app/controllers/conversations_controller.rb << 'RUBY'
class ConversationsController < ApplicationController
  def index
    @conversations = Conversation.for_user(Current.user).includes(:participants, :messages)
  end

  def show
    @conversation = Conversation.find(params[:id])
    @conversation.mark_read!(Current.user)
    @messages = @conversation.messages.recent
    @message = Message.new
  end

  def create
    other = User.find(params[:user_id])
    @conversation = Conversation.between(Current.user, other) ||
      Conversation.create!.tap { |c| c.participants << [Current.user, other] }
    redirect_to @conversation
  end
end
RUBY

  cat > app/controllers/messages_controller.rb << 'RUBY'
class MessagesController < ApplicationController
  def create
    @conversation = Conversation.find(params[:conversation_id])
    @message = @conversation.messages.build(content: params.dig(:message, :content), user: Current.user)
    @message.save ? redirect_to(@conversation) : redirect_back(fallback_location: @conversation)
  end
end
RUBY

  log_ok "Direct messaging set up"
}
