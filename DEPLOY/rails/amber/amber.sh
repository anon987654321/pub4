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
add_gem pagy '"~> 9.3"'
add_gem image_processing
add_gem ruby-openai
install_solid_stack
install_security_tools
setup_pagy

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
  season:string occasion:string "likes_count:integer:default[0]" \
  user:references \
  --no-test-framework

bin/rails generate model OutfitItem \
  outfit:references item:references position:integer \
  --no-test-framework

bin/rails generate model PlannedOutfit \
  user:references outfit:references \
  planned_date:date notes:text \
  --no-test-framework

bin/rails generate migration AddExtendedFieldsToItems \
  mood_effect:string life_phase:string \
  occasion_tags:string season:string \
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

  scope :joy,          -> { where(spark_joy: true) }
  scope :by_category,  ->(c) { where(category: c) }
  scope :by_mood,      ->(m) { where(mood_effect: m) }
  scope :by_occasion,  ->(o) { where("occasion_tags LIKE ?", "%#{o}%") }
  scope :current_self, -> { where(life_phase: "current") }
  scope :recent,       -> { order(created_at: :desc) }
  scope :worn_most,    -> { order(times_worn: :desc) }
  scope :never_worn,   -> { where("times_worn = 0 OR times_worn IS NULL") }
  scope :aging_unworn, -> { never_worn.where("purchase_date < ?", 6.months.ago) }

  CATEGORIES   = %w[Tops Bottoms Dresses Shoes Accessories Outerwear].freeze
  SEASONS      = %w[Spring Summer Autumn Winter All-Season].freeze
  MOOD_EFFECTS = %w[energising calming confident playful neutral].freeze
  LIFE_PHASES  = %w[current past-self aspirational].freeze
  OCCASIONS    = %w[work casual formal gym date travel].freeze

  def cost_per_wear
    return nil unless price.present? && times_worn.to_i > 0
    (price / times_worn).round(2)
  end

  def occasions
    occasion_tags.to_s.split(",").map(&:strip)
  end

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

cat > app/models/planned_outfit.rb << 'RUBY'
class PlannedOutfit < ApplicationRecord
  belongs_to :user
  belongs_to :outfit

  validates :planned_date, presence: true
  validates :planned_date, uniqueness: { scope: :user_id }

  scope :upcoming, -> { where("planned_date >= ?", Date.today).order(:planned_date) }
  scope :this_week, -> { where(planned_date: Date.today..7.days.from_now) }
end
RUBY

# ── Controllers ─────────────────────────────────────────────────────────────
cat > app/controllers/application_controller.rb << 'RUBY'
class ApplicationController < ActionController::Base
  include Authentication
  include Pagy::Backend
  allow_browser versions: :modern
end
RUBY

cat > app/controllers/home_controller.rb << 'RUBY'
class HomeController < ApplicationController
  def index
    return unless authenticated?
    items = Current.user.items
    @items_count      = items.count
    @joy_count        = items.joy.count
    @never_worn_count = items.never_worn.count
    @worn_this_month  = items.where("updated_at > ?", 30.days.ago).where("times_worn > 0").count
    @utilization_rate = @items_count > 0 ? (@worn_this_month * 100.0 / @items_count).round : 0
    @worst_cpw        = items.where("price > 0 AND times_worn > 0")
                             .select { |i| i.cost_per_wear }
                             .sort_by { |i| -i.cost_per_wear }
                             .first(3)
    @aging_unworn     = items.aging_unworn.limit(4)
    @recent_items     = items.recent.limit(6)
    @planned_this_week = Current.user.planned_outfits.this_week.includes(:outfit)
    @weather          = WeatherService.today
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

  def set_item   = @item = Item.find(params[:id])

  def authorize!
    redirect_to(items_path, alert: "Unauthorized") unless @item.user == Current.user
  end

  def item_params
    params.require(:item).permit(
      :title, :category, :color, :size, :material,
      :brand, :price, :times_worn, :purchase_date,
      :mood_effect, :life_phase, :occasion_tags, :season,
      photos: []
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

  def set_outfit = @outfit = Outfit.find(params[:id])

  def authorize!
    redirect_to(outfits_path, alert: "Unauthorized") unless @outfit.user == Current.user
  end

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

    chat(prompt).tap do |r|
      r["sparks_joy"] = nil unless r.key?("sparks_joy")
      r["reason"]     ||= "Analysis unavailable"
      r["suggestion"] ||= "Trust your instincts"
    end
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
    chat(prompt)["outfits"] || []
  end

  def declutter_candidates
    @user.items.aging_unworn.order(price: :desc)
  end

  def capsule_optimizer
    catalog = @user.items.map { |i| "#{i.id}:#{i.title}(#{i.category},#{i.color})" }.join("; ")
    prompt = <<~P
      You are a capsule wardrobe expert. Given this wardrobe catalog, select a minimum keep-set
      that maximises outfit combinations. For each item return: keep/consider/release and reason.
      Respond with JSON: {"items":[{"id":N,"title":"...","decision":"keep|consider|release","reason":"..."}],"gap_items":["description of missing pieces"]}
      Catalog: #{catalog}
    P
    chat(prompt)
  end

  def color_palette_analysis
    items_desc = @user.items.map { |i| "#{i.title}: #{i.color}" }.join(", ")
    prompt = <<~P
      Analyse this wardrobe color list and identify the dominant palette, harmony gaps,
      and any clashing items. Map to a seasonal color system where possible.
      Respond with JSON: {"palette":"...","season_type":"...","harmonious":["item desc"],"clashing":["item desc"],"suggestions":["..."]}
      Items: #{items_desc}
    P
    chat(prompt)
  end

  def natural_language_search(query)
    catalog = @user.items.map { |i| "id=#{i.id} #{i.title} #{i.category} #{i.color} #{i.material} #{i.occasion_tags} #{i.season}" }.join("\n")
    prompt = <<~P
      From this wardrobe, find items matching: "#{query}"
      Return JSON: {"item_ids":[array of matching ids],"explanation":"..."}
      Wardrobe:
      #{catalog}
    P
    chat(prompt)
  end

  def mood_board_match(description)
    catalog = @user.items.map { |i| "id=#{i.id} #{i.title} #{i.category} #{i.color} #{i.material}" }.join("\n")
    prompt = <<~P
      Style reference: "#{description}"
      From this wardrobe, suggest the best outfit matching that aesthetic.
      Return JSON: {"item_ids":[array of ids],"outfit_name":"...","description":"why this matches"}
      Wardrobe:
      #{catalog}
    P
    chat(prompt)
  end

  def enclothed_cognition_tag(item)
    prompt = <<~P
      For this clothing item, suggest the most likely psychological/mood effect when worn.
      Choose one: energising, calming, confident, playful, neutral.
      Also suggest life_phase: current, past-self, or aspirational.
      Reply JSON: {"mood_effect":"...","life_phase":"...","reason":"..."}
      Item: #{item.title}, category: #{item.category}, color: #{item.color}, brand: #{item.brand}
    P
    chat(prompt)
  end

  private

  def chat(prompt)
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
    {}
  end
end
RUBY

mkdir -p app/services
cat > app/services/weather_service.rb << 'RUBY'
# frozen_string_literal: true

class WeatherService
  BERGEN_LAT  = 60.39
  BERGEN_LNG  = 5.32
  API_URL     = "https://api.open-meteo.com/v1/forecast"

  def self.today
    uri = URI("#{API_URL}?latitude=#{BERGEN_LAT}&longitude=#{BERGEN_LNG}" \
              "&current=temperature_2m,weathercode,windspeed_10m" \
              "&forecast_days=1")
    data = JSON.parse(Net::HTTP.get(uri))
    current = data["current"]
    {
      temp:        current["temperature_2m"].to_f,
      code:        current["weathercode"].to_i,
      wind:        current["windspeed_10m"].to_f,
      description: decode_weather(current["weathercode"].to_i)
    }
  rescue => e
    Rails.logger.warn("WeatherService: #{e.message}")
    nil
  end

  def self.decode_weather(code)
    case code
    when 0       then "Clear"
    when 1..3    then "Partly cloudy"
    when 45, 48  then "Foggy"
    when 51..67  then "Rainy"
    when 71..77  then "Snowy"
    when 80..82  then "Showers"
    when 95..99  then "Thunderstorm"
    else              "Mixed"
    end
  end
end
RUBY

cat > app/controllers/ai_controller.rb << 'RUBY'
class AiController < ApplicationController
  before_action :require_authentication

  def analyze_item
    item   = Current.user.items.find(params[:id])
    result = WardrobeAiService.new(Current.user).analyze_joy(item)
    item.update!(spark_joy: result["sparks_joy"]) if result["sparks_joy"].in?([true, false])
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("item_#{item.id}_analysis", partial: "ai/analysis", locals: { result: result, item: item }) }
      format.json { render json: result }
    end
  end

  def tag_item
    item   = Current.user.items.find(params[:id])
    result = WardrobeAiService.new(Current.user).enclothed_cognition_tag(item)
    item.update!(mood_effect: result["mood_effect"], life_phase: result["life_phase"])
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("item_#{item.id}_tags", partial: "ai/item_tags", locals: { item: item.reload, result: result }) }
      format.html { redirect_to item }
    end
  end

  def suggest_outfits
    @suggestions = WardrobeAiService.new(Current.user).suggest_outfits(
      occasion: params[:occasion], season: params[:season]
    )
  end

  def declutter_guide
    @candidates = WardrobeAiService.new(Current.user).declutter_candidates
  end

  def capsule
    @result = WardrobeAiService.new(Current.user).capsule_optimizer
  end

  def color_palette
    @result = WardrobeAiService.new(Current.user).color_palette_analysis
  end

  def search
    @query  = params[:q].to_s.strip
    if @query.present?
      result     = WardrobeAiService.new(Current.user).natural_language_search(@query)
      ids        = Array(result["item_ids"])
      @items     = Current.user.items.where(id: ids)
      @explanation = result["explanation"]
    else
      @items = Current.user.items.none
    end
  end

  def mood_board
    @description = params[:description].to_s.strip
    if @description.present?
      result   = WardrobeAiService.new(Current.user).mood_board_match(@description)
      ids      = Array(result["item_ids"])
      @items   = Current.user.items.where(id: ids)
      @outfit_name = result["outfit_name"]
      @reasoning   = result["description"]
    end
  end

  def occasion_map
    @coverage = Item::OCCASIONS.each_with_object({}) do |occ, h|
      h[occ] = Current.user.items.by_occasion(occ).to_a
    end
  end
end
RUBY

cat > app/controllers/planned_outfits_controller.rb << 'RUBY'
class PlannedOutfitsController < ApplicationController
  before_action :require_authentication

  def index
    @planned = Current.user.planned_outfits.upcoming.includes(:outfit)
    @outfits = Current.user.outfits.order(:name)
  end

  def create
    @plan = Current.user.planned_outfits.build(plan_params)
    @plan.save ? redirect_to(planned_outfits_path, notice: "Planned") : redirect_to(planned_outfits_path, alert: @plan.errors.full_messages.first)
  end

  def destroy
    Current.user.planned_outfits.find(params[:id]).destroy!
    redirect_to planned_outfits_path
  end

  private

  def plan_params = params.require(:planned_outfit).permit(:outfit_id, :planned_date, :notes)
end
RUBY

# ── Routes ─────────────────────────────────────────────────────────────────
cat > config/routes.rb << 'RUBY'
Rails.application.routes.draw do
  resource  :session
  resource  :registration, only: %i[new create]
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

  resources :planned_outfits, only: %i[index create destroy]

  scope :ai do
    post "items/:id/analyze", to: "ai#analyze_item",    as: :ai_analyze_item
    post "items/:id/tag",     to: "ai#tag_item",        as: :ai_tag_item
    get  "outfits/suggest",   to: "ai#suggest_outfits", as: :ai_suggest_outfits
    get  "declutter",         to: "ai#declutter_guide", as: :ai_declutter
    get  "capsule",           to: "ai#capsule",         as: :ai_capsule
    get  "palette",           to: "ai#color_palette",   as: :ai_palette
    get  "search",            to: "ai#search",          as: :ai_search
    get  "moodboard",         to: "ai#mood_board",      as: :ai_mood_board
    get  "occasions",         to: "ai#occasion_map",    as: :ai_occasions
  end

  root "home#index"
  get "up", to: "rails/health#show", as: :rails_health_check
end
RUBY

# ── Views ───────────────────────────────────────────────────────────────────
mkdir -p app/views/home app/views/items app/views/outfits app/views/ai

write_shared_partials
write_auth_views
write_registration

cat > app/views/home/index.html.erb << 'ERB'
<% content_for :title, "Dashboard" %>
<% if authenticated? %>
  <% if @weather %>
    <div class="weather-bar">
      <%= @weather[:description] %> · <%= @weather[:temp] %>°C
      <% if @weather[:temp] < 10 %>· Wear layers<% elsif @weather[:temp] > 20 %>· Light fabrics<% end %>
    </div>
  <% end %>

  <header class="dash-stats">
    <dl>
      <div><dt>Items</dt><dd><%= @items_count %></dd></div>
      <div><dt>Spark joy</dt><dd><%= @joy_count %></dd></div>
      <div><dt>Never worn</dt><dd><%= @never_worn_count %></dd></div>
      <div><dt>Utilisation</dt><dd class="<%= @utilization_rate < 20 ? 'stat-warn' : '' %>"><%= @utilization_rate %>%</dd></div>
    </dl>
    <nav>
      <%= link_to "Add item", new_item_path, class: "btn" %>
      <%= link_to "Search wardrobe", ai_search_path, class: "btn" %>
      <%= link_to "Capsule plan", ai_capsule_path, class: "btn" %>
    </nav>
  </header>

  <% if @planned_this_week.any? %>
    <section>
      <h2>This week</h2>
      <div class="plan-list">
        <% @planned_this_week.each do |plan| %>
          <div class="plan-row">
            <span class="plan-date"><%= plan.planned_date.strftime("%a %-d") %></span>
            <%= link_to plan.outfit.name, plan.outfit %>
            <%= button_to "✕", planned_outfit_path(plan), method: :delete, class: "btn-link" %>
          </div>
        <% end %>
      </div>
    </section>
  <% end %>

  <% if @worst_cpw.any? %>
    <section>
      <h2>Worst cost-per-wear</h2>
      <div class="cpw-list">
        <% @worst_cpw.each do |item| %>
          <div class="cpw-row">
            <%= link_to item.title, item %>
            <span class="cpw-val">£<%= item.cost_per_wear %>/wear · worn <%= item.times_worn %>×</span>
          </div>
        <% end %>
      </div>
    </section>
  <% end %>

  <% if @aging_unworn.any? %>
    <section>
      <h2>Aging unworn</h2>
      <div class="item-grid"><%= render @aging_unworn %></div>
    </section>
  <% end %>

  <% if @recent_items.any? %>
    <h2>Recent</h2>
    <div class="item-grid"><%= render @recent_items %></div>
    <p><%= link_to "All items →", items_path %></p>
  <% else %>
    <p><%= link_to "Add your first item", new_item_path %></p>
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
  <% if @item.mood_effect.present? || @item.life_phase.present? %>
    <div class="tag-row">
      <% if @item.mood_effect.present? %><span class="tag">Mood: <%= @item.mood_effect %></span><% end %>
      <% if @item.life_phase.present? %><span class="tag tag--phase"><%= @item.life_phase %></span><% end %>
    </div>
  <% end %>
  <div id="item_<%= @item.id %>_analysis"></div>
  <div id="item_<%= @item.id %>_tags"></div>
  <nav>
    <%= button_to "Worn today", wear_item_path(@item), method: :post, class: "btn" %>
    <%= button_to "AI analyse", ai_analyze_item_path(@item), method: :post, class: "btn" %>
    <%= button_to "AI tag mood", ai_tag_item_path(@item), method: :post, class: "btn" %>
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
  <div class="field">
    <%= f.label :season %>
    <%= f.select :season, Item::SEASONS, include_blank: "Select…" %>
  </div>
  <div class="field">
    <%= f.label :occasion_tags, "Occasions (comma-separated)" %>
    <%= f.text_field :occasion_tags, placeholder: "work, casual, formal" %>
  </div>
  <div class="field">
    <%= f.label :mood_effect, "Mood effect" %>
    <%= f.select :mood_effect, Item::MOOD_EFFECTS, include_blank: "Not set" %>
  </div>
  <div class="field">
    <%= f.label :life_phase, "Life phase" %>
    <%= f.select :life_phase, Item::LIFE_PHASES, include_blank: "Not set" %>
  </div>
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

mkdir -p app/views/planned_outfits

cat > app/views/planned_outfits/index.html.erb << 'ERB'
<% content_for :title, "Planner" %>
<h1>Outfit Planner</h1>
<%= form_with model: PlannedOutfit.new, url: planned_outfits_path do |f| %>
  <div class="field-row">
    <%= f.date_field :planned_date, min: Date.today, class: "input" %>
    <%= f.select :outfit_id, @outfits.map { |o| [o.name, o.id] }, { include_blank: "Select outfit…" } %>
    <%= f.text_field :notes, placeholder: "Notes…" %>
    <%= f.submit "Plan it", class: "btn" %>
  </div>
<% end %>
<div class="plan-list">
  <% @planned.each do |plan| %>
    <div class="plan-row">
      <span class="plan-date"><%= plan.planned_date.strftime("%A %-d %b") %></span>
      <%= link_to plan.outfit.name, plan.outfit %>
      <% if plan.notes.present? %><span class="dim"><%= plan.notes %></span><% end %>
      <%= button_to "✕", planned_outfit_path(plan), method: :delete, class: "btn-link" %>
    </div>
  <% end %>
  <% if @planned.empty? %>
    <p class="dim">No outfits planned yet.</p>
  <% end %>
</div>
ERB

cat > app/views/ai/capsule.html.erb << 'ERB'
<% content_for :title, "Capsule Optimizer" %>
<h1>Capsule Wardrobe Optimizer</h1>
<% if @result["items"] %>
  <div class="capsule-list">
    <% @result["items"].each do |item| %>
      <div class="capsule-row capsule-row--<%= item["decision"] %>">
        <span class="capsule-decision"><%= item["decision"] %></span>
        <strong><%= item["title"] %></strong>
        <span class="dim"><%= item["reason"] %></span>
      </div>
    <% end %>
  </div>
  <% if @result["gap_items"]&.any? %>
    <h2>Gap items to consider buying</h2>
    <ul><% @result["gap_items"].each do |g| %><li><%= g %></li><% end %></ul>
  <% end %>
<% else %>
  <p class="dim">Add more items to your wardrobe first.</p>
<% end %>
<p><%= link_to "← Dashboard", root_path %></p>
ERB

cat > app/views/ai/color_palette.html.erb << 'ERB'
<% content_for :title, "Colour Palette" %>
<h1>Wardrobe Colour Palette</h1>
<% if @result["palette"] %>
  <div class="ai-card">
    <p><strong>Palette:</strong> <%= @result["palette"] %></p>
    <% if @result["season_type"].present? %><p><strong>Seasonal type:</strong> <%= @result["season_type"] %></p><% end %>
  </div>
  <% if @result["clashing"]&.any? %>
    <h2>Clashing items</h2>
    <ul><% @result["clashing"].each do |i| %><li><%= i %></li><% end %></ul>
  <% end %>
  <% if @result["suggestions"]&.any? %>
    <h2>Suggestions</h2>
    <ul><% @result["suggestions"].each do |s| %><li><%= s %></li><% end %></ul>
  <% end %>
<% else %>
  <p class="dim">Not enough items to analyse.</p>
<% end %>
<p><%= link_to "← Dashboard", root_path %></p>
ERB

cat > app/views/ai/search.html.erb << 'ERB'
<% content_for :title, "Search Wardrobe" %>
<h1>Search your wardrobe</h1>
<%= form_with url: ai_search_path, method: :get do |f| %>
  <div class="field-row">
    <%= f.search_field :q, value: @query, placeholder: "e.g. something warm but not bulky for a meeting", autofocus: true, class: "input input--wide" %>
    <%= f.submit "Search", class: "btn" %>
  </div>
<% end %>
<% if @explanation.present? %>
  <p class="dim"><%= @explanation %></p>
<% end %>
<% if @items&.any? %>
  <div class="item-grid"><%= render @items %></div>
<% elsif @query.present? %>
  <p class="dim">No matches found.</p>
<% end %>
ERB

cat > app/views/ai/mood_board.html.erb << 'ERB'
<% content_for :title, "Mood Board Match" %>
<h1>Mood board match</h1>
<%= form_with url: ai_mood_board_path, method: :get do |f| %>
  <div class="field">
    <%= f.label :description, "Describe the aesthetic or paste a style reference" %>
    <%= f.text_area :description, value: @description, rows: 3, class: "input input--wide" %>
  </div>
  <div class="actions"><%= f.submit "Match from wardrobe", class: "btn" %></div>
<% end %>
<% if @outfit_name.present? %>
  <div class="ai-card">
    <h2><%= @outfit_name %></h2>
    <p><%= @reasoning %></p>
  </div>
  <div class="item-grid"><%= render @items %></div>
<% end %>
ERB

cat > app/views/ai/occasion_map.html.erb << 'ERB'
<% content_for :title, "Occasion Coverage" %>
<h1>Occasion coverage map</h1>
<div class="occasion-grid">
  <% @coverage.each do |occasion, items| %>
    <div class="occasion-card occasion-card--<%= items.size < 2 ? 'sparse' : 'covered' %>">
      <h3><%= occasion.capitalize %></h3>
      <span class="occasion-count"><%= items.size %> items</span>
      <% if items.size < 2 %>
        <p class="dim occasion-warn">Gap — consider adding pieces</p>
      <% end %>
      <% items.first(3).each do |item| %>
        <div class="dim"><%= link_to item.title, item %></div>
      <% end %>
    </div>
  <% end %>
</div>
<p><%= link_to "← Dashboard", root_path %></p>
ERB

cat > app/views/ai/_item_tags.html.erb << 'ERB'
<div id="item_<%= item.id %>_tags" class="ai-card">
  <% if item.mood_effect.present? %>
    <span class="tag">Mood: <%= item.mood_effect %></span>
  <% end %>
  <% if item.life_phase.present? %>
    <span class="tag tag--phase"><%= item.life_phase %></span>
  <% end %>
  <% if result["reason"].present? %>
    <p class="dim"><%= result["reason"] %></p>
  <% end %>
</div>
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

.weather-bar { background: #e8f4fd; border-bottom: 1px solid #b3d9f5; padding: .4rem var(--space-md); font-size: .85rem; color: #1a5276; }
.stat-warn { color: #c0392b; }
.plan-list { display: flex; flex-direction: column; gap: .4rem; margin: var(--space-sm) 0; }
.plan-row { display: flex; gap: var(--space-md); align-items: center; padding: .35rem 0; border-bottom: 1px solid var(--color-extra-light-grey); }
.plan-date { font-weight: 600; min-width: 4rem; font-size: .85rem; color: #555; }
.cpw-list { display: flex; flex-direction: column; gap: .35rem; margin: var(--space-sm) 0; }
.cpw-row { display: flex; justify-content: space-between; align-items: center; padding: .3rem 0; border-bottom: 1px solid var(--color-extra-light-grey); }
.cpw-val { font-size: .8rem; color: #c0392b; font-weight: 600; }
.field-row { display: flex; gap: var(--space-sm); align-items: center; flex-wrap: wrap; margin-bottom: var(--space-md); }
.input { border: 1px solid #ccc; border-radius: 3px; padding: .4rem .6rem; font: inherit; }
.input--wide { flex: 1; min-width: 280px; }
.tag { display: inline-block; background: #f0c040; padding: .15rem .5rem; border-radius: 3px; font-size: .75rem; font-weight: 600; margin-right: .3rem; }
.tag--phase { background: #d5e8d4; color: #2d6a4f; }
.tag-row { display: flex; flex-wrap: wrap; gap: .3rem; margin: .5rem 0; }
.occasion-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); gap: var(--space-md); margin: var(--space-md) 0; }
.occasion-card { border: 2px solid var(--color-extra-light-grey); border-radius: 6px; padding: var(--space-sm); }
.occasion-card--sparse { border-color: #f0a500; background: #fffbf0; }
.occasion-card--covered { border-color: #4caf50; }
.occasion-count { font-size: 1.2rem; font-weight: 700; display: block; }
.occasion-warn { font-size: .75rem; }
.capsule-list { display: flex; flex-direction: column; gap: .4rem; }
.capsule-row { display: flex; gap: var(--space-sm); align-items: flex-start; padding: .5rem; border-radius: 4px; }
.capsule-row--keep { background: #d5e8d4; }
.capsule-row--consider { background: #fff3cd; }
.capsule-row--release { background: #fde8e8; }
.capsule-decision { font-size: .7rem; font-weight: 700; text-transform: uppercase; min-width: 60px; padding-top: .15rem; }
SCSS

write_full_layout "Amber" '<%= link_to "Wardrobe", items_path %><%= link_to "Planner", planned_outfits_path %><%= link_to "Search", ai_search_path %><%= link_to "Occasions", ai_occasions_path %>'

# ── Initializer: stdlib requires ────────────────────────────────────────────
mkdir -p config/initializers
cat > config/initializers/requires.rb << 'RUBY'
require "net/http"
require "uri"
require "json"
RUBY

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
