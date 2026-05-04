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
  acts_as_list scope: :outfit if respond_to?(:acts_as_list)
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
  before_action :require_authentication, except: %i[index show]
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
  before_action :require_authentication, except: %i[index show]
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
  def initialize(user)
    @user   = user
    @client = OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY"))
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
        model: "gpt-4o-mini",
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
      Reply with JSON array: [{"name": "outfit name", "items": ["item1", ...], "description": "why it works"}]
    PROMPT

    response = @client.chat(
      parameters: {
        model: "gpt-4o-mini",
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

# ── Assets + Layout ─────────────────────────────────────────────────────────
install_dartsass
write_base_scss
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
