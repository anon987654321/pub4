#!/usr/bin/env zsh
# amber.sh — Amber AI Fashion Wardrobe Assistant (Rails 8)
# Usage: zsh amber.sh
set -euo pipefail

APP_NAME=amber
APP_DIR=/home/${APP_NAME}/app
APP_PORT=61352
SCRIPT_DIR=${0:a:h}

. "${SCRIPT_DIR:h}/@shared_functions.sh"

need_cmd ruby34 bundle rails doas

already_done "${APP_DIR}/app/models/item.rb" && exit 0

log "Amber — AI Fashion Wardrobe Assistant"

# ── Create app ─────────────────────────────────────────────────────────────
create_rails_app "$APP_DIR"

# ── Gems ────────────────────────────────────────────────────────────────────
add_gem pagy
add_gem image_processing
add_gem ruby-openai
install_solid_stack
install_security_tools

# ── Auth ───────────────────────────────────────────────────────────────────
install_auth

# ── Active Storage ─────────────────────────────────────────────────────────
install_active_storage

# ── Models ─────────────────────────────────────────────────────────────────
bin/rails generate model Item \
  title:string category:string color:string size:string \
  material:string brand:string price:decimal \
  times_worn:integer purchase_date:date spark_joy:boolean \
  user:references \
  --no-test-framework

bin/rails generate model Outfit \
  name:string description:text category:string \
  season:string occasion:string likes_count:integer:default[0] \
  user:references \
  --no-test-framework

bin/rails generate model OutfitItem \
  outfit:references item:references position:integer \
  --no-test-framework

bin/rails db:migrate

# ── Model files ─────────────────────────────────────────────────────────────
cat > app/models/item.rb << 'RUBY'
class Item < ApplicationRecord
  belongs_to :user
  has_many :outfit_items, dependent: :destroy
  has_many :outfits, through: :outfit_items
  has_many_attached :photos

  validates :title, :category, presence: true
  validates :times_worn, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :joy,        -> { where(spark_joy: true) }
  scope :by_category, ->(c) { where(category: c) }
  scope :recent,     -> { order(created_at: :desc) }
  scope :worn_most,  -> { order(times_worn: :desc) }
  scope :never_worn, -> { where("times_worn = 0 OR times_worn IS NULL") }

  CATEGORIES = %w[Tops Bottoms Dresses Shoes Accessories Outerwear].freeze
  SEASONS    = %w[Spring Summer Fall Winter All\ Season].freeze

  def wear!
    increment!(:times_worn)
    touch
  end
end
RUBY

cat > app/models/outfit.rb << 'RUBY'
class Outfit < ApplicationRecord
  belongs_to :user
  has_many :outfit_items, dependent: :destroy
  has_many :items, through: :outfit_items

  validates :name, presence: true

  def like!
    increment!(:likes_count)
  end
end
RUBY

cat > app/models/outfit_item.rb << 'RUBY'
class OutfitItem < ApplicationRecord
  belongs_to :outfit
  belongs_to :item

  validates :outfit, :item, presence: true
  validates :item_id, uniqueness: { scope: :outfit_id }
  default_scope { order(:position) }
end
RUBY

# ── Controllers ─────────────────────────────────────────────────────────────
cat > app/controllers/application_controller.rb << 'RUBY'
class ApplicationController < ActionController::Base
  include Pagy::Backend
  allow_browser versions: :modern
end
RUBY

cat > app/controllers/home_controller.rb << 'RUBY'
class HomeController < ApplicationController
  def index
    return unless authenticated?
    @items_count     = Current.user.items.count
    @joy_count       = Current.user.items.joy.count
    @never_worn      = Current.user.items.never_worn.count
    @recent_items    = Current.user.items.recent.limit(6)
    @recent_outfits  = Current.user.outfits.order(created_at: :desc).limit(3)
  end
end
RUBY

cat > app/controllers/items_controller.rb << 'RUBY'
class ItemsController < ApplicationController
  before_action :require_authentication
  before_action :set_item, only: %i[show edit update destroy spark_joy declutter wear]
  before_action :authorize!, only: %i[edit update destroy spark_joy declutter wear]

  def index
    @pagy, @items = pagy(Current.user.items.recent)
  end

  def show; end

  def new
    @item = Current.user.items.build
  end

  def create
    @item = Current.user.items.build(item_params)
    @item.save ? redirect_to(@item, notice: "Item added") : render(:new, status: :unprocessable_entity)
  end

  def edit; end

  def update
    @item.update(item_params) ? redirect_to(@item, notice: "Updated") : render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @item.destroy
    redirect_to items_path, notice: "Removed from wardrobe"
  end

  def spark_joy
    @item.update!(spark_joy: true)
    redirect_to items_path, notice: "This item sparks joy!"
  end

  def declutter
    @item.update!(spark_joy: false)
    redirect_to items_path, notice: "Marked for declutter"
  end

  def wear
    @item.wear!
    redirect_to @item, notice: "Worn today — +1"
  end

  private

  def set_item    = @item = Item.find(params[:id])
  def authorize!  = redirect_to(items_path, alert: "Unauthorized") unless @item.user == Current.user

  def item_params
    params.require(:item).permit(
      :title, :category, :color, :size, :material,
      :brand, :price, :times_worn, :purchase_date, photos: []
    )
  end
end
RUBY

cat > app/controllers/outfits_controller.rb << 'RUBY'
class OutfitsController < ApplicationController
  before_action :require_authentication
  before_action :set_outfit, only: %i[show edit update destroy like]
  before_action :authorize!, only: %i[edit update destroy]

  def index
    @pagy, @outfits = pagy(Current.user.outfits.order(created_at: :desc))
  end

  def show; end

  def new
    @outfit = Current.user.outfits.build
  end

  def create
    @outfit = Current.user.outfits.build(outfit_params)
    @outfit.save ? redirect_to(@outfit, notice: "Outfit created") : render(:new, status: :unprocessable_entity)
  end

  def edit; end

  def update
    @outfit.update(outfit_params) ? redirect_to(@outfit, notice: "Updated") : render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @outfit.destroy
    redirect_to outfits_path, notice: "Outfit deleted"
  end

  def like
    @outfit.like!
    redirect_to @outfit
  end

  private

  def set_outfit   = @outfit = Outfit.find(params[:id])
  def authorize!   = redirect_to(outfits_path, alert: "Unauthorized") unless @outfit.user == Current.user

  def outfit_params
    params.require(:outfit).permit(:name, :description, :category, :season, :occasion)
  end
end
RUBY

# ── AI Service ─────────────────────────────────────────────────────────────
mkdir -p app/services
cat > app/services/wardrobe_ai_service.rb << 'RUBY'
# frozen_string_literal: true

class WardrobeAiService
  OPENROUTER_BASE = "https://openrouter.ai/api/v1"
  MODEL = "google/gemini-2.0-flash-001"

  def initialize(user)
    @user   = user
    @client = OpenAI::Client.new(
      access_token: ENV.fetch("OPENROUTER_API_KEY"),
      uri_base:     OPENROUTER_BASE
    )
  end

  def analyze_joy(item)
    prompt = <<~PROMPT
      Analyze this clothing item from a Marie Kondo perspective.
      Reply with JSON: {"sparks_joy": true/false, "reason": "brief explanation", "suggestion": "action to take"}

      Item: #{item.title}
      Category: #{item.category}
      Color: #{item.color}
      Times worn: #{item.times_worn || 0}
      Age: #{item.purchase_date ? "#{((Date.today - item.purchase_date) / 365).to_i} years" : "unknown"}
    PROMPT

    response = @client.chat(
      parameters: {
        model: MODEL,
        messages: [{ role: "user", content: prompt }],
        response_format: { type: "json_object" }
      }
    )
    JSON.parse(response.dig("choices", 0, "message", "content"))
  rescue => e
    Rails.logger.error("WardrobeAI error: #{e.message}")
    { "sparks_joy" => nil, "reason" => "Analysis unavailable", "suggestion" => "Trust your instincts" }
  end

  def suggest_outfits(occasion: nil, season: nil)
    items_summary = @user.items.joy.limit(20).map { |i| "#{i.title} (#{i.category}, #{i.color})" }.join(", ")
    prompt = <<~PROMPT
      Suggest 3 outfit combinations from these wardrobe items.
      #{occasion ? "Occasion: #{occasion}" : ""}
      #{season ? "Season: #{season}" : ""}
      Items: #{items_summary}
      Reply with JSON: {"outfits": [{"name": "outfit name", "items": ["item1", ...], "description": "why it works"}]}
    PROMPT

    response = @client.chat(
      parameters: {
        model: MODEL,
        messages: [{ role: "user", content: prompt }],
        response_format: { type: "json_object" }
      }
    )
    JSON.parse(response.dig("choices", 0, "message", "content"))["outfits"] || []
  rescue => e
    Rails.logger.error("WardrobeAI suggest error: #{e.message}")
    []
  end

  def declutter_candidates
    @user.items.never_worn.where("purchase_date < ?", 1.year.ago).order(price: :desc)
  end
end
RUBY

cat > app/controllers/ai_controller.rb << 'RUBY'
class AiController < ApplicationController
  before_action :require_authentication

  def analyze_item
    item = Current.user.items.find(params[:id])
    result = WardrobeAiService.new(Current.user).analyze_joy(item)
    item.update!(spark_joy: result["sparks_joy"]) if result["sparks_joy"].in?([true, false])
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("item_#{item.id}_analysis", partial: "ai/analysis", locals: { result: result, item: item }) }
      format.json { render json: result }
    end
  end

  def suggest_outfits
    @suggestions = WardrobeAiService.new(Current.user).suggest_outfits(
      occasion: params[:occasion], season: params[:season]
    )
    respond_to { |f| f.html; f.turbo_stream }
  end

  def declutter_guide
    @candidates = WardrobeAiService.new(Current.user).declutter_candidates
    respond_to { |f| f.html; f.turbo_stream }
  end
end
RUBY

# ── Routes ─────────────────────────────────────────────────────────────────
cat > config/routes.rb << 'RUBY'
Rails.application.routes.draw do
  resource  :session
  resources :passwords, param: :token

  resources :items do
    member do
      post :spark_joy
      post :declutter
      post :wear
    end
  end

  resources :outfits do
    member { post :like }
  end

  scope :ai do
    post "items/:id/analyze", to: "ai#analyze_item",  as: :ai_analyze_item
    get  "outfits/suggest",   to: "ai#suggest_outfits", as: :ai_suggest_outfits
    get  "declutter",         to: "ai#declutter_guide", as: :ai_declutter
  end

  root "home#index"
  get "up", to: "rails/health#show", as: :rails_health_check
end
RUBY

# ── Views ───────────────────────────────────────────────────────────────────
mkdir -p app/views/home app/views/items app/views/outfits app/views/ai

write_shared_partials
write_auth_views

cat > app/views/home/index.html.erb << 'ERB'
<% content_for :title, "Dashboard" %>
<% if authenticated? %>
  <header class="dash-stats">
    <dl>
      <div><dt>Items</dt><dd><%= @items_count %></dd></div>
      <div><dt>Spark joy</dt><dd><%= @joy_count %></dd></div>
      <div><dt>Never worn</dt><dd><%= @never_worn %></dd></div>
    </dl>
    <%= link_to "Add item", new_item_path, class: "btn" %>
    <%= link_to "AI suggestions", ai_suggest_outfits_path, class: "btn" %>
  </header>
  <% if @recent_items.any? %>
    <h2>Recent</h2>
    <div class="item-grid"><%= render @recent_items %></div>
    <p><%= link_to "All items →", items_path %></p>
  <% else %>
    <p><%= link_to "Add your first item", new_item_path %></p>
  <% end %>
  <% if @recent_outfits.any? %>
    <h2>Outfits</h2>
    <div class="item-grid"><%= render @recent_outfits %></div>
  <% end %>
<% else %>
  <p>Welcome to Amber. <%= link_to "Sign in", new_session_path %> to manage your wardrobe.</p>
<% end %>
ERB

cat > app/views/items/index.html.erb << 'ERB'
<% content_for :title, "Wardrobe" %>
<section data-controller="filter">
  <header>
    <h1>Wardrobe (<%= @pagy.count %>)</h1>
    <%= link_to "Add item", new_item_path, class: "btn" %>
    <select data-action="change->filter#filter" data-filter-target="select">
      <option value="">All</option>
      <% Item::CATEGORIES.each do |cat| %>
        <option value="<%= cat %>"><%= cat %></option>
      <% end %>
    </select>
  </header>
  <div class="item-grid" id="items" data-filter-target="grid">
    <%= render @items %>
  </div>
  <%= pagy_nav(@pagy) if @pagy.pages > 1 %>
</section>
ERB

cat > app/views/items/_item.html.erb << 'ERB'
<article class="item-card" id="<%= dom_id(item) %>" data-category="<%= item.category %>">
  <% if item.photos.attached? %>
    <%= image_tag item.photos.first.variant(resize_to_fill: [300, 300]), class: "item-photo" %>
  <% end %>
  <%= link_to item.title, item, class: "item-title" %>
  <span class="dim"><%= item.category %><%= " · #{item.color}" if item.color.present? %></span>
  <span class="dim">Worn <%= item.times_worn.to_i %>×<%= " · #{number_to_currency(item.price)}" if item.price? %></span>
  <nav>
    <%= button_to "Wear", wear_item_path(item), method: :post, class: "btn-sm" %>
    <% unless item.spark_joy? %>
      <%= button_to "Joy", spark_joy_item_path(item), method: :post, class: "btn-sm" %>
    <% end %>
    <%= link_to "Edit", edit_item_path(item), class: "btn-sm" %>
  </nav>
</article>
ERB

cat > app/views/items/show.html.erb << 'ERB'
<% content_for :title, @item.title %>
<article class="item-detail">
  <% if @item.photos.attached? %>
    <div class="item-photos">
      <% @item.photos.each do |p| %>
        <%= image_tag p.variant(resize_to_limit: [600, 600]) %>
      <% end %>
    </div>
  <% end %>
  <header>
    <h1><%= @item.title %></h1>
    <% if @item.spark_joy? %><span class="badge">Sparks joy</span><% end %>
  </header>
  <dl class="meta">
    <dt>Category</dt><dd><%= @item.category %></dd>
    <% if @item.color.present? %><dt>Color</dt><dd><%= @item.color %></dd><% end %>
    <% if @item.size.present? %><dt>Size</dt><dd><%= @item.size %></dd><% end %>
    <% if @item.material.present? %><dt>Material</dt><dd><%= @item.material %></dd><% end %>
    <% if @item.brand.present? %><dt>Brand</dt><dd><%= @item.brand %></dd><% end %>
    <% if @item.price? %><dt>Price</dt><dd><%= number_to_currency(@item.price) %></dd><% end %>
    <dt>Worn</dt><dd><%= @item.times_worn.to_i %> times</dd>
    <% if @item.purchase_date? %><dt>Purchased</dt><dd><%= @item.purchase_date.strftime("%b %Y") %></dd><% end %>
  </dl>
  <div id="item_<%= @item.id %>_analysis"></div>
  <nav>
    <%= button_to "Worn today", wear_item_path(@item), method: :post, class: "btn" %>
    <%= button_to "AI analyze", ai_analyze_item_path(@item), method: :post, class: "btn" %>
    <%= link_to "Edit", edit_item_path(@item), class: "btn" %>
    <%= button_to "Delete", @item, method: :delete, data: { turbo_confirm: "Remove this item?" }, class: "btn btn-danger" %>
  </nav>
</article>
ERB

cat > app/views/items/new.html.erb << 'ERB'
<% content_for :title, "Add item" %>
<h1>Add item</h1>
<%= render "form", item: @item %>
ERB

cat > app/views/items/edit.html.erb << 'ERB'
<% content_for :title, "Edit" %>
<h1>Edit <%= @item.title %></h1>
<%= render "form", item: @item %>
ERB

cat > app/views/items/_form.html.erb << 'ERB'
<%= form_with model: item, class: "form" do |f| %>
  <%= render "shared/errors", object: item %>
  <div class="field"><%= f.label :title %><%= f.text_field :title, autofocus: true %></div>
  <div class="field">
    <%= f.label :category %>
    <%= f.select :category, Item::CATEGORIES, include_blank: "Select…" %>
  </div>
  <div class="field"><%= f.label :color %><%= f.text_field :color %></div>
  <div class="field"><%= f.label :size %><%= f.text_field :size %></div>
  <div class="field"><%= f.label :material %><%= f.text_field :material %></div>
  <div class="field"><%= f.label :brand %><%= f.text_field :brand %></div>
  <div class="field"><%= f.label :price %><%= f.number_field :price, step: "0.01", min: 0 %></div>
  <div class="field"><%= f.label :purchase_date %><%= f.date_field :purchase_date %></div>
  <div class="field"><%= f.label :photos %><%= f.file_field :photos, multiple: true, accept: "image/*" %></div>
  <div class="actions"><%= f.submit class: "btn" %> <%= link_to "Cancel", items_path %></div>
<% end %>
ERB

cat > app/views/outfits/index.html.erb << 'ERB'
<% content_for :title, "Outfits" %>
<header>
  <h1>Outfits</h1>
  <%= link_to "New outfit", new_outfit_path, class: "btn" %>
</header>
<div class="item-grid" id="outfits"><%= render @outfits %></div>
<%= pagy_nav(@pagy) if @pagy.pages > 1 %>
ERB

cat > app/views/outfits/_outfit.html.erb << 'ERB'
<article class="item-card" id="<%= dom_id(outfit) %>">
  <%= link_to outfit.name, outfit, class: "item-title" %>
  <span class="dim"><%= [outfit.season, outfit.occasion].compact.join(" · ") %></span>
  <span class="dim"><%= outfit.items.count %> items · <%= outfit.likes_count %> likes</span>
</article>
ERB

cat > app/views/outfits/show.html.erb << 'ERB'
<% content_for :title, @outfit.name %>
<header>
  <h1><%= @outfit.name %></h1>
  <span class="dim"><%= [@outfit.season, @outfit.category, @outfit.occasion].compact.join(" · ") %></span>
</header>
<p><%= @outfit.description %></p>
<div class="item-grid"><%= render @outfit.items %></div>
<nav>
  <%= button_to "Like (#{@outfit.likes_count})", like_outfit_path(@outfit), method: :post, class: "btn" %>
  <%= link_to "Edit", edit_outfit_path(@outfit), class: "btn" %>
  <%= button_to "Delete", @outfit, method: :delete, data: { turbo_confirm: "Delete?" }, class: "btn btn-danger" %>
</nav>
ERB

cat > app/views/outfits/new.html.erb << 'ERB'
<% content_for :title, "New outfit" %>
<h1>New outfit</h1>
<%= render "form", outfit: @outfit %>
ERB

cat > app/views/outfits/edit.html.erb << 'ERB'
<% content_for :title, "Edit outfit" %>
<h1>Edit <%= @outfit.name %></h1>
<%= render "form", outfit: @outfit %>
ERB

cat > app/views/outfits/_form.html.erb << 'ERB'
<%= form_with model: outfit, class: "form" do |f| %>
  <%= render "shared/errors", object: outfit %>
  <div class="field"><%= f.label :name %><%= f.text_field :name, autofocus: true %></div>
  <div class="field"><%= f.label :description %><%= f.text_area :description, rows: 3 %></div>
  <div class="field">
    <%= f.label :category %>
    <%= f.select :category, %w[Casual Formal Work Workout Evening], include_blank: "Select…" %>
  </div>
  <div class="field">
    <%= f.label :season %>
    <%= f.select :season, Item::SEASONS, include_blank: "Select…" %>
  </div>
  <div class="field"><%= f.label :occasion %><%= f.text_field :occasion %></div>
  <div class="actions"><%= f.submit class: "btn" %> <%= link_to "Cancel", outfits_path %></div>
<% end %>
ERB

cat > app/views/ai/_analysis.html.erb << 'ERB'
<aside class="ai-card">
  <% if result["sparks_joy"].nil? %>
    <p class="dim">Analysis unavailable</p>
  <% else %>
    <strong><%= result["sparks_joy"] ? "Sparks joy" : "Does not spark joy" %></strong>
    <p><%= result["reason"] %></p>
    <p class="dim"><em><%= result["suggestion"] %></em></p>
  <% end %>
</aside>
ERB

cat > app/views/ai/suggest_outfits.html.erb << 'ERB'
<% content_for :title, "Outfit suggestions" %>
<h1>Outfit suggestions</h1>
<% @suggestions.each_with_index do |s, i| %>
  <article class="ai-card">
    <h2><%= s["name"] || "Option #{i + 1}" %></h2>
    <p class="dim"><%= s["items"]&.join(", ") %></p>
    <p><%= s["description"] %></p>
  </article>
<% end %>
<p><%= link_to "Back to wardrobe", items_path %></p>
ERB

cat > app/views/ai/declutter_guide.html.erb << 'ERB'
<% content_for :title, "Declutter guide" %>
<h1>Declutter guide</h1>
<% if @candidates.any? %>
  <p class="dim">Items to consider letting go:</p>
  <div class="item-grid"><%= render @candidates %></div>
<% else %>
  <p>No declutter candidates — your wardrobe is in great shape.</p>
<% end %>
<p><%= link_to "Back", items_path %></p>
ERB

# ── Stimulus ────────────────────────────────────────────────────────────────
setup_stimulus

mkdir -p app/javascript/controllers
cat > app/javascript/controllers/filter_controller.js << 'JS'
import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["select", "grid"]
  filter() {
    const val = this.selectTarget.value
    this.gridTarget.querySelectorAll("[data-category]").forEach(c => {
      c.hidden = val && c.dataset.category !== val
    })
  }
}
JS

# ── Assets + Layout ─────────────────────────────────────────────────────────
install_dartsass
write_base_scss

cat >> app/assets/stylesheets/application.scss << 'SCSS'

.dash-stats dl { display: flex; gap: var(--space-lg); margin-bottom: var(--space-md); }
.dash-stats dt { font-size: .75rem; color: #666; text-transform: uppercase; }
.dash-stats dd { font-size: 1.5rem; font-weight: 700; }

.item-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: var(--space-md); }
.item-card { display: flex; flex-direction: column; gap: var(--space-xs); padding: var(--space-sm); border: 1px solid var(--color-extra-light-grey); border-radius: 4px; }
.item-card .item-photo { width: 100%; aspect-ratio: 1; object-fit: cover; border-radius: 2px; }
.item-card .item-title { font-weight: 600; }
.item-card nav { display: flex; gap: var(--space-xs); flex-wrap: wrap; margin-top: auto; }

.item-detail { max-width: 700px; }
.item-detail .item-photos { display: flex; gap: var(--space-sm); flex-wrap: wrap; margin-bottom: var(--space-md); }
.item-detail .item-photos img { width: 200px; border-radius: 4px; }

.meta { display: grid; grid-template-columns: max-content 1fr; gap: var(--space-xs) var(--space-md); margin: var(--space-md) 0; }
.meta dt { font-weight: 600; }

.ai-card { background: var(--color-extra-light-grey); border-radius: 4px; padding: var(--space-md); margin: var(--space-md) 0; }

.btn { display: inline-block; padding: .3rem .8rem; background: var(--color-black); color: var(--color-white); border: none; border-radius: 3px; cursor: pointer; font-size: .85rem; text-decoration: none; }
.btn-sm { padding: .2rem .5rem; font-size: .75rem; background: #444; color: #fff; border: none; border-radius: 3px; cursor: pointer; }
.btn-danger { background: #c00; }
.btn-joy { background: #c5820a; }
.badge { display: inline-block; background: #f0c040; padding: .1rem .4rem; border-radius: 3px; font-size: .75rem; font-weight: 600; }
.dim { color: #666; font-size: .85rem; }

.form { max-width: 480px; }
.form .field { display: flex; flex-direction: column; gap: .2rem; margin-bottom: var(--space-sm); }
.form input, .form select, .form textarea { border: 1px solid #ccc; border-radius: 3px; padding: .4rem .6rem; font: inherit; }
.form .actions { display: flex; gap: var(--space-sm); align-items: center; margin-top: var(--space-md); }

h1, h2 { margin-bottom: var(--space-sm); }
SCSS

write_layout "Amber"

# ── Puma + production ───────────────────────────────────────────────────────
write_falcon_config "$APP_PORT"
configure_production

# ── rc.d service ───────────────────────────────────────────────────────────
install_rcd amber "$APP_DIR" "$APP_PORT" amber

# ── Seed ───────────────────────────────────────────────────────────────────
cat > db/seeds.rb << 'RUBY'
user = User.find_or_create_by!(email_address: "demo@amber.example") do |u|
  u.password = u.password_confirmation = "password123"
end

categories = %w[Tops Bottoms Dresses Shoes Accessories Outerwear]
colors     = %w[Black White Red Blue Green Yellow Pink Purple Grey Beige]

20.times do
  Item.create!(
    title:         ["Classic T-Shirt","Slim Jeans","Wool Blazer","Leather Boots","Silk Blouse","Cargo Pants","Maxi Dress","Sneakers","Cashmere Sweater","Trench Coat"].sample,
    category:      categories.sample,
    color:         colors.sample,
    material:      %w[Cotton Polyester Wool Silk Leather Linen Denim].sample,
    brand:         ["Uniqlo","Zara","H&M","COS","Arket","Norse Projects"].sample,
    price:         (rand * 400 + 20).round(2),
    times_worn:    rand(0..30),
    purchase_date: Date.today - rand(0..730),
    spark_joy:     [true, true, false].sample,
    user:          user
  )
end
puts "Seeded #{Item.count} items for #{user.email_address}"
RUBY

bin/rails db:seed

log_ok "Amber setup complete — start: doas rcctl start amber"
