#!/usr/bin/env zsh
# bsdports.sh — BSD Ports tracker/browser (Rails 8)
# Usage: zsh bsdports.sh
set -euo pipefail

APP_NAME=bsdports
APP_DIR=/home/${APP_NAME}/app
APP_PORT=47312
SCRIPT_DIR=${0:a:h}

. "${SCRIPT_DIR:h}/@shared_functions.sh"

need_cmd ruby34 bundle rails doas

already_done "${APP_DIR}/app/models/port.rb" && exit 0

log "BSDports — OpenBSD Ports Browser and Tracker"

# ── Create app ─────────────────────────────────────────────────────────────
create_rails_app "$APP_DIR"

# ── Gems ────────────────────────────────────────────────────────────────────
add_gem pagy
add_gem rouge
install_solid_stack
install_security_tools

# ── Auth ───────────────────────────────────────────────────────────────────
install_auth

# ── Models ─────────────────────────────────────────────────────────────────
bin/rails generate model Category \
  name:string slug:string:uniq description:text \
  --no-test-framework

bin/rails generate model Port \
  name:string:uniq version:string category:references \
  maintainer:string comment:text description:text \
  homepage:string pkgpath:string:uniq \
  permit_file_distfiles:boolean:'default[false]' \
  last_updated:date \
  --no-test-framework

bin/rails generate model Dependency \
  port:references depends_on:references{Port} dep_type:string \
  --no-test-framework

bin/rails generate model PortUpdate \
  port:references old_version:string new_version:string \
  commit_id:string commit_message:text committed_at:datetime \
  --no-test-framework

bin/rails generate model Watch \
  user:references port:references \
  notify_on_update:boolean:'default[true]' \
  --no-test-framework

bin/rails generate model Comment \
  user:references port:references parent_id:integer \
  content:text \
  --no-test-framework

bin/rails db:migrate

# ── Model logic ─────────────────────────────────────────────────────────────
cat > app/models/port.rb << 'RUBY'
class Port < ApplicationRecord
  belongs_to :category
  has_many :dependencies, dependent: :destroy
  has_many :depends_on, through: :dependencies, source: :depends_on
  has_many :dependents, class_name: "Dependency", foreign_key: :depends_on_id
  has_many :reverse_deps, through: :dependents, source: :port
  has_many :port_updates, dependent: :destroy
  has_many :watches, dependent: :destroy
  has_many :watchers, through: :watches, source: :user
  has_many :comments, dependent: :destroy

  validates :name, :version, :pkgpath, presence: true
  validates :pkgpath, uniqueness: true

  scope :recent_updates, -> { joins(:port_updates).order("port_updates.committed_at DESC").distinct }
  scope :by_category,    ->(cat) { where(category: cat) }
  scope :search,         ->(q) { where("name LIKE ? OR comment LIKE ?", "%#{q}%", "%#{q}%") }

  def watched_by?(user)
    watches.exists?(user: user)
  end

  def latest_update
    port_updates.order(committed_at: :desc).first
  end
end
RUBY

cat > app/models/comment.rb << 'RUBY'
class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :port
  belongs_to :parent, class_name: "Comment", optional: true
  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy

  validates :content, presence: true, length: { maximum: 5000 }

  scope :roots, -> { where(parent_id: nil).order(created_at: :asc) }

  after_create_commit -> { broadcast_append_to [port, "comments"] }
end
RUBY

# ── Controllers ─────────────────────────────────────────────────────────────
cat > app/controllers/application_controller.rb << 'RUBY'
class ApplicationController < ActionController::Base
  include Pagy::Method
  allow_browser versions: :modern
end
RUBY

cat > app/controllers/ports_controller.rb << 'RUBY'
class PortsController < ApplicationController
  before_action :set_port, only: %i[show watch unwatch]

  def index
    scope = Port.includes(:category)
    scope = scope.search(params[:q])       if params[:q].present?
    scope = scope.by_category(params[:category_id]) if params[:category_id].present?
    scope = scope.order(params[:sort] == "updated" ? "last_updated DESC" : :name)
    @pagy, @ports = pagy(scope)
    @categories   = Category.order(:name)
  end

  def show
    @updates  = @port.port_updates.order(committed_at: :desc).limit(10)
    @deps     = @port.depends_on.includes(:category)
    @rdeps    = @port.reverse_deps.includes(:category).limit(20)
    @comments = @port.comments.roots.includes(:user, replies: :user)
    @comment  = Comment.new
  end

  def watch
    require_authentication
    @port.watches.find_or_create_by!(user: Current.user)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @port }
    end
  end

  def unwatch
    require_authentication
    @port.watches.find_by(user: Current.user)&.destroy!
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @port }
    end
  end

  private

  def set_port = @port = Port.find_by!(pkgpath: params[:id].gsub("-", "/")) rescue Port.find(params[:id])
end
RUBY

cat > app/controllers/categories_controller.rb << 'RUBY'
class CategoriesController < ApplicationController
  def index
    @categories = Category.order(:name).includes(:ports)
  end

  def show
    @category = Category.find_by!(slug: params[:id])
    @pagy, @ports = pagy(@category.ports.order(:name))
  end
end
RUBY

cat > app/controllers/comments_controller.rb << 'RUBY'
class CommentsController < ApplicationController
  before_action :require_authentication
  before_action :set_port

  def create
    @comment = @port.comments.build(comment_params.merge(user: Current.user))
    if @comment.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @port }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @comment = @port.comments.find(params[:id])
    @comment.destroy! if @comment.user == Current.user
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @port }
    end
  end

  private

  def set_port = @port = Port.find(params[:port_id])
  def comment_params = params.require(:comment).permit(:content, :parent_id)
end
RUBY

# ── Routes ─────────────────────────────────────────────────────────────────
cat > config/routes.rb << 'RUBY'
Rails.application.routes.draw do
  resource  :session
  resources :passwords, param: :token

  root "ports#index"

  resources :categories, only: %i[index show]

  resources :ports, only: %i[index show] do
    member do
      post   :watch
      delete :unwatch
    end
    resources :comments, only: %i[create destroy]
  end

  get "up", to: "rails/health#show", as: :rails_health_check
end
RUBY

# ── Assets + Infrastructure ─────────────────────────────────────────────────
mkdir -p app/assets/stylesheets
cat > app/assets/stylesheets/application.css << 'CSS'
:root {
  --bg: #0d1117; --surface: #161b22; --border: #30363d;
  --text: #c9d1d9; --text-dim: #8b949e; --primary: #58a6ff;
  --green: #3fb950; --radius: 6px; --space: 8px;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace; background: var(--bg); color: var(--text); line-height: 1.5; }
main { max-width: 1200px; margin: 0 auto; padding: calc(var(--space)*2); }
a { color: var(--primary); text-decoration: none; }
a:hover { text-decoration: underline; }
.card { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); padding: 1rem; margin-bottom: 1rem; }
.badge { display: inline-block; padding: .1rem .5rem; border-radius: 2em; font-size: .75rem; font-family: system-ui, sans-serif; }
.badge-category { background: #21262d; color: var(--text-dim); border: 1px solid var(--border); }
.badge-version  { background: #388bfd1a; color: #58a6ff; border: 1px solid #388bfd33; }
.port-row { display: flex; align-items: baseline; gap: .75rem; padding: .5rem 0; border-bottom: 1px solid var(--border); }
.port-name { font-weight: 600; color: var(--primary); }
.port-comment { color: var(--text-dim); font-family: system-ui, sans-serif; font-size: .9rem; }
.flash-notice { background: #1a3a1a; color: #81c784; padding: .75rem 1rem; border-radius: var(--radius); margin-bottom: 1rem; font-family: system-ui, sans-serif; }
.flash-alert  { background: #3a1a1a; color: #e57373; padding: .75rem 1rem; border-radius: var(--radius); margin-bottom: 1rem; font-family: system-ui, sans-serif; }
CSS

# ── Views ───────────────────────────────────────────────────────────────────
mkdir -p app/views/ports app/views/categories app/views/comments

write_shared_partials
write_auth_views

cat > app/views/ports/index.html.erb << 'ERB'
<% content_for :title, "Ports" %>
<header>
  <h1>OpenBSD Ports</h1>
  <%= form_with url: ports_path, method: :get do |f| %>
    <%= f.search_field :q, value: params[:q], placeholder: "Search ports…", class: "search" %>
  <% end %>
</header>
<% if @category %>
  <p><span class="badge badge-category"><%= @category.name %></span> &mdash; <%= @category.description %></p>
<% end %>
<div id="ports">
  <% @ports.each do |port| %>
    <div class="port-row">
      <%= link_to port.name, port, class: "port-name" %>
      <span class="badge badge-version"><%= port.version %></span>
      <span class="badge badge-category"><%= link_to port.category.name, category_path(port.category) %></span>
      <span class="port-comment"><%= port.comment %></span>
    </div>
  <% end %>
</div>
<%= @pagy.series_nav if @pagy.pages > 1 %>
ERB

cat > app/views/ports/show.html.erb << 'ERB'
<% content_for :title, @port.name %>
<article class="card">
  <header>
    <h1><%= @port.name %> <span class="badge badge-version"><%= @port.version %></span></h1>
    <span class="dim"><%= link_to @port.category.name, category_path(@port.category) %></span>
  </header>
  <p><%= @port.comment %></p>
  <p><%= @port.description %></p>
  <dl class="meta">
    <dt>Maintainer</dt><dd><%= @port.maintainer %></dd>
    <dt>Pkgpath</dt><dd><code><%= @port.pkgpath %></code></dd>
    <% if @port.homepage.present? %><dt>Homepage</dt><dd><%= link_to @port.homepage, @port.homepage %></dd><% end %>
    <dt>Updated</dt><dd><%= @port.last_updated&.strftime("%Y-%m-%d") %></dd>
  </dl>
  <% if @dependencies.any? %>
    <h2>Dependencies</h2>
    <% @dependencies.each do |dep| %>
      <div class="port-row">
        <%= link_to dep.depends_on.name, port_path(dep.depends_on), class: "port-name" %>
        <span class="badge badge-category"><%= dep.dep_type %></span>
      </div>
    <% end %>
  <% end %>
  <% if @updates.any? %>
    <h2>Version history</h2>
    <% @updates.each do |update| %>
      <div class="port-row">
        <span class="badge badge-version"><%= update.old_version %> → <%= update.new_version %></span>
        <span class="port-comment"><%= update.commit_message %></span>
        <span class="dim"><%= update.committed_at&.strftime("%Y-%m-%d") %></span>
      </div>
    <% end %>
  <% end %>
  <nav>
    <% if authenticated? %>
      <% if @watching %>
        <%= button_to "Unwatch", unwatch_port_path(@port), method: :delete, class: "btn btn-primary" %>
      <% else %>
        <%= button_to "Watch", watch_port_path(@port), method: :post, class: "btn btn-primary" %>
      <% end %>
    <% end %>
  </nav>
</article>
<section class="card" id="comments">
  <h2>Comments</h2>
  <%= render @comments %>
  <% if authenticated? %>
    <%= form_with url: port_comments_path(@port), class: "form" do |f| %>
      <div class="field"><%= f.text_area :content, rows: 3, placeholder: "Add a comment…" %></div>
      <div class="actions"><%= f.submit "Comment", class: "btn btn-primary" %></div>
    <% end %>
  <% end %>
</section>
ERB

cat > app/views/categories/index.html.erb << 'ERB'
<% content_for :title, "Categories" %>
<h1>Categories</h1>
<div id="categories">
  <% @categories.each do |cat| %>
    <div class="port-row">
      <%= link_to cat.name, category_path(cat), class: "port-name" %>
      <span class="port-comment"><%= cat.description %></span>
    </div>
  <% end %>
</div>
ERB

cat > app/views/categories/show.html.erb << 'ERB'
<% content_for :title, @category.name %>
<header>
  <h1><%= @category.name %></h1>
  <p class="dim"><%= @category.description %></p>
</header>
<%= render "ports/index" %>
ERB

cat > app/views/comments/_comment.html.erb << 'ERB'
<article class="comment" id="<%= dom_id(comment) %>">
  <span class="dim"><%= comment.user.email_address.split("@").first %></span>
  <p><%= comment.content %></p>
  <% if authenticated? && comment.user == Current.user %>
    <%= button_to "Delete", port_comment_path(@port, comment), method: :delete, class: "btn-sm" %>
  <% end %>
</article>
ERB

write_layout "BSDports"
write_falcon_config "$APP_PORT"
configure_production
install_rcd bsdports "$APP_DIR" "$APP_PORT" bsdports

log_ok "BSDports setup complete — start: doas rcctl start bsdports"
