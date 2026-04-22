#!/usr/bin/env sh
# -*- sh -*-

# Strict mode: abort on error, undefined variable, or pipe failure
set -euo pipefail

#=== Configuration ============================================================
APP_NAME="amber"
BASE_DIR="/home/amber"
APP_PORT=10006
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/@shared_functions.sh"

#=== Helpers ================================================================
check_file() { [ -f "$1" ]; }

install_gem_if_missing() {
  gem list -i "$1" >/dev/null 2>&1 || gem install "$1"
}

ensure_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log "ERROR: $1 required"
    exit 1
  }
}

#=== Prerequisites ===========================================================
ensure_cmd ruby
ensure_cmd node
ensure_cmd bundle
install_gem_if_missing pagy
install_gem_if_missing faker

#=== Idempotent exit =========================================================
if check_file "${BASE_DIR}/app/models/item.rb"; then
  log "Amber already set up – exiting"
  exit 0
fi

log "Starting Amber setup – AI Fashion Wardrobe Assistant"

#=== Layout ================================================================
cat > app/views/layouts/application.html.erb <<'EOF'
<!DOCTYPE html>
<html lang="<%= I18n.locale %>">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title><%= content_for?(:title) ? yield(:title) + " - Amber" : "Amber - AI Fashion Assistant" %></title>
  <meta name="description" content="<%= content_for?(:description) ? yield(:description) : 'Organize your wardrobe with AI-powered style assistance' %>">
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>
  <%= pwa_meta_tags %>
  <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
  <%= javascript_importmap_tags %>
  <%= register_service_worker %>
  <%= yield :head %>
</head>
<body>
  <%= yield %>
</body>
</html>
EOF

#=== Routes ================================================================
cat > config/routes.rb <<'EOF'
Rails.application.routes.draw do
  devise_for :users
  root "home#index"

  resources :items do
    member do
      post :spark_joy
      post :declutter
      post :analyze_joy, to: "kondo_ai#analyze_item"
    end
  end

  resources :outfits do
    member { post :like }
  end

  resources :profiles, only: [:show, :edit, :update]
  resource  :session
  resources :passwords, param: :token

  # Kondo AI
  get  "kondo/tips",      to: "kondo_ai#organization_tips", as: :kondo_tips
  get  "kondo/outfits",   to: "kondo_ai#suggest_outfits",    as: :kondo_outfits
  get  "kondo/declutter", to: "kondo_ai#declutter_guide",   as: :kondo_declutter

  get "up" => "rails/health#show", as: :rails_health_check
end
EOF

#=== Seed data ==============================================================
cat > db/seeds.rb <<'EOF'
categories = %w[Tops Bottoms Dresses Shoes Accessories Outerwear]
seasons    = %w[Spring Summer Fall Winter All\ Season]
colors     = %w[Black White Red Blue Green Yellow Pink Purple]

user = User.find_or_create_by(email_address: "demo@amber.example") { |u| u.password = "password123" }

puts "Seeding Amber wardrobe..."
10.times do
  Item.create!(
    title:         Faker::Commerce.product_name,
    category:      categories.sample,
    color:         colors.sample,
    season:        seasons.sample,
    material:      %w[Cotton Polyester Wool Silk Leather].sample,
    brand:         Faker::Company.name,
    price:         Faker::Commerce.price(range: 20..500),
    times_worn:    rand(0..50),
    purchase_date: Faker::Date.backward(days: 365),
    spark_joy:    [true, false].sample,
    user:          user
  )
end
puts "Seeded #{Item.count} fashion items"
EOF

#=== Models ================================================================
bundle exec bin/rails generate model Item title:string category:string color:string size:string material:string brand:string price:decimal times_worn:integer purchase_date:date spark_joy:boolean user:references
bundle exec bin/rails generate model Outfit name:string description:text category:string season:string occasion:string likes_count:integer user:references
bundle exec bin/rails generate model OutfitItem outfit:references item:references position:integer

cat > app/models/item.rb <<'EOF'
class Item < ApplicationRecord
  belongs_to :user
  has_many :outfit_items, dependent: :destroy
  has_many :outfits, through: :outfit_items

  validates :title, :category, presence: true

  scope :spark_joy, -> { where(spark_joy: true) }
  scope :by_category, ->(cat) { where(category: cat) }
end
EOF

cat > app/models/outfit.rb <<'EOF'
class Outfit < ApplicationRecord
  belongs_to :user
  has_many :outfit_items, dependent: :destroy
  has_many :items, through: :outfit_items

  validates :name, presence: true

  def increment_likes!
    increment!(:likes_count)
  end
end
EOF

cat > app/models/outfit_item.rb <<'EOF'
class OutfitItem < ApplicationRecord
  belongs_to :outfit
  belongs_to :item

  validates :outfit, :item, presence: true
end
EOF

#=== Controllers ============================================================
cat > app/controllers/home_controller.rb <<'EOF'
class HomeController < ApplicationController
  def index
    if user_signed_in?
      @items_count      = current_user.items.count
      @spark_joy_count  = current_user.items.where(spark_joy: true).count
      @recent_items     = current_user.items.order(created_at: :desc).limit(6)
    end
  end
end
EOF

cat > app/controllers/items_controller.rb <<'EOF'
class ItemsController < ApplicationController
  before_action :authenticate_user!, except: %i[index show]
  before_action :set_item, only: %i[show edit update destroy spark_joy declutter]
  before_action :authorize_user!, only: %i[edit update destroy spark_joy declutter]

  def index
    @pagy, @items = pagy(current_user.items.order(created_at: :desc))
  end

  def show; end

  def new
    @item = current_user.items.build
  end

  def create
    @item = current_user.items.build(item_params)
    if @item.save
      redirect_to items_path, notice: "Item added to wardrobe"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @item.update(item_params)
      redirect_to @item, notice: "Item updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def spark_joy
    @item.update(spark_joy: true)
    redirect_to items_path, notice: "✨ This item sparks joy!"
  end

  def declutter
    @item.destroy
    redirect_to items_path, notice: "Item removed from wardrobe"
  end

  private

  def set_item
    @item = Item.find(params[:id])
  end

  def authorize_user!
    redirect_to items_path, alert: "Unauthorized" unless @item.user == current_user
  end

  def item_params
    params.require(:item).permit(:title, :category, :color, :size, :material, :brand, :price, :times_worn, :purchase_date)
  end
end
EOF

cat > app/controllers/outfits_controller.rb <<'EOF'
class OutfitsController < ApplicationController
  before_action :authenticate_user!, except: %i[index show]
  before_action :set_outfit, only: %i[show edit update destroy like]
  before_action :authorize_user!, only: %i[edit update destroy]

  def index
    @pagy, @outfits = pagy(current_user.outfits.order(created_at: :desc))
  end

  def show; end

  def new
    @outfit = current_user.outfits.build
  end

  def create
    @outfit = current_user.outfits.build(outfit_params)
    if @outfit.save
      redirect_to @outfit, notice: "Outfit created"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @outfit.update(outfit_params)
      redirect_to @outfit, notice: "Outfit updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @outfit.destroy
    redirect_to outfits_path, notice: "Outfit deleted"
  end

  def like
    @outfit.increment_likes!
    redirect_to @outfit, notice: "Liked!"
  end

  private

  def set_outfit
    @outfit = Outfit.find(params[:id])
  end

  def authorize_user!
    redirect_to outfits_path, alert: "Unauthorized" unless @outfit.user == current_user
  end

  def outfit_params
    params.require(:outfit).permit(:name, :description, :category, :season, :occasion)
  end
end
EOF

#=== Kondo AI Service =======================================================
cat > app/services/marie_kondo_ai_service.rb <<'EOF'
# frozen_string_literal: true

class MarieKondoAiService
  def initialize(user)
    @user = user
    @llm  = Langchain::LLM::OpenAI.new(api_key: ENV["OPENAI_API_KEY"])
  end

  def sparks_joy?(item)
    prompt = <<~PROMPT
      Analyze this clothing item and say YES if it sparks joy, otherwise NO.
      Item: #{item.title}
      Category: #{item.category}
      Color: #{item.color}
      Material: #{item.material}
      Times worn: #{item.times_worn}
      Purchase date: #{item.purchase_date}
    PROMPT

    response = @llm.chat(messages: [{ role: "user", content: prompt }])
    content  = response.dig("choices", 0, "message", "content").to_s
    { sparks_joy: content.downcase.include?("yes"), reason: content }
  end

  def get_organization_tips(category: nil, season: nil)
    query = build_query(category, season)
    embeds = generate_embedding(query)

    tips = OrganizationTip
           .nearest_neighbors(:embedding, embeds, distance: "cosine")
           .limit(5)

    context = tips.map { |t| "\#{t.title}: \#{t.content}" }.join("\n")

    prompt = <<~PROMPT
      Provide 3‑5 actionable wardrobe organization tips.
      User stats: \#{summary_stats}
      Context: \#{context}
      Question: \#{query}
    PROMPT

    @llm.chat(messages: [{ role: "user", content: prompt }])
        .dig("choices", 0, "message", "content")
  end

  private

  def generate_embedding(text)
    Langchain::LLM::OpenAI.new(api_key: ENV["OPENAI_API_KEY"])
      .embed(text: text).dig("embedding")
  end

  def build_query(category, season)
    parts = ["How to organize"]
    parts << category if category
    parts << "for \#{season}" if season
    parts.join(" ")
  end

  def summary_stats
    {
      total_items: @user.items.count,
      spark_joy:   @user.items.where(spark_joy: true).count
    }.inspect
  end
end
EOF

#=== Kondo AI Controller ====================================================
cat > app/controllers/kondo_ai_controller.rb <<'EOF'
class KondoAiController < ApplicationController
  before_action :authenticate_user!

  def analyze_item
    item = current_user.items.find(params[:id])
    ai   = MarieKondoAiService.new(current_user)
    res  = ai.sparks_joy?(item)

    item.update(spark_joy: res[:sparks_joy], declutter_reason: res[:reason])

    respond_to do |fmt|
      fmt.turbo_stream
      fmt.json { render json: res }
    end
  end

  def organization_tips
    @tips = MarieKondoAiService.new(current_user)
            .get_organization_tips(category: params[:category], season: params[:season])

    respond_to { |fmt| fmt.html; fmt.turbo_stream }
  end

  def suggest_outfits
    @suggestions = MarieKondoAiService.new(current_user).suggest_outfits(
      occasion: params[:occasion],
      season:   params[:season],
      weather:  params[:weather]
    )
    respond_to { |fmt| fmt.html; fmt.turbo_stream }
  end

  def declutter_guide
    @recommendations = MarieKondoAiService.new(current_user).declutter_recommendations
    respond_to { |fmt| fmt.html; fmt.turbo_stream }
  end
end
EOF

#=== Database ==============================================================
log "Running migrations and seeds"
bundle exec bin/rails db:migrate
bundle exec bin/rails db:seed

#=== Verification ==========================================================
log "Verifying Amber app structure"
for f in config/routes.rb app/views/layouts/application.html.erb app/assets/stylesheets; do
  [ -e "$f" ] && log "✓ $f present"
done

log "Amber setup complete. Start with: doas rcctl start amber"
log "Version: v1.0.0 – 2025-12-19"