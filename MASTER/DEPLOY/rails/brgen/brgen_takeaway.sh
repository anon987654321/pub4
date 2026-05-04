#!/usr/bin/env zsh
# brgen_takeaway.sh — Brgen Takeaway food delivery platform (Rails 8)
# Usage: zsh brgen_takeaway.sh
set -euo pipefail

APP_NAME=brgen_takeaway
APP_DIR=/home/${APP_NAME}/app
APP_PORT=10011
SCRIPT_DIR=${0:a:h}

. "${SCRIPT_DIR:h}/@shared_functions.sh"

need_cmd ruby34 bundle rails doas

already_done "${APP_DIR}/app/models/restaurant.rb" && exit 0

log "Brgen Takeaway — Food Delivery Platform"

# ── Create app ─────────────────────────────────────────────────────────────
create_rails_app "$APP_DIR"

# ── Gems ────────────────────────────────────────────────────────────────────
add_gem pagy
add_gem image_processing
add_gem geocoder
add_gem money-rails
install_solid_stack
install_security_tools

# ── Auth ───────────────────────────────────────────────────────────────────
install_auth
install_active_storage

# ── Models ─────────────────────────────────────────────────────────────────
bin/rails generate migration AddAddressToUsers \
  address:string city:string postal_code:string \
  latitude:float longitude:float phone:string \
  --no-test-framework

bin/rails generate model Restaurant \
  user:references name:string description:text \
  address:string city:string postal_code:string \
  latitude:float longitude:float phone:string \
  cuisine_type:string open_time:time close_time:time \
  delivery_fee_cents:integer min_order_cents:integer \
  rating:float reviews_count:integer:default[0] \
  active:boolean:default[true] \
  --no-test-framework

bin/rails generate model MenuCategory \
  restaurant:references name:string position:integer \
  --no-test-framework

bin/rails generate model MenuItem \
  menu_category:references restaurant:references \
  name:string description:text \
  price_cents:integer currency:string \
  available:boolean:default[true] \
  vegetarian:boolean:default[false] \
  vegan:boolean:default[false] \
  allergens:string \
  --no-test-framework

bin/rails generate model Order \
  user:references restaurant:references \
  status:string \
  delivery_address:string delivery_city:string \
  subtotal_cents:integer delivery_fee_cents:integer total_cents:integer \
  special_instructions:text \
  estimated_delivery_at:datetime delivered_at:datetime \
  --no-test-framework

bin/rails generate model OrderItem \
  order:references menu_item:references \
  quantity:integer unit_price_cents:integer \
  customizations:text \
  --no-test-framework

bin/rails generate model RestaurantReview \
  user:references restaurant:references order:references \
  food_rating:integer delivery_rating:integer \
  content:text \
  --no-test-framework

bin/rails db:migrate

# ── Model logic ─────────────────────────────────────────────────────────────
cat > app/models/restaurant.rb << 'RUBY'
class Restaurant < ApplicationRecord
  belongs_to :user
  has_many :menu_categories, dependent: :destroy
  has_many :menu_items,      through: :menu_categories
  has_many :orders, dependent: :destroy
  has_many :restaurant_reviews, dependent: :destroy
  has_one_attached :logo
  has_many_attached :gallery

  monetize :delivery_fee_cents, with_currency: :nok
  monetize :min_order_cents,    with_currency: :nok

  validates :name, :address, :cuisine_type, presence: true
  validates :delivery_fee_cents, :min_order_cents, numericality: { greater_than_or_equal_to: 0 }

  geocoded_by :address
  after_validation :geocode, if: :address_changed?

  scope :active,  -> { where(active: true) }
  scope :nearby,  ->(lat, lng, km = 10) {
    where("((latitude - ?) * (latitude - ?) + (longitude - ?) * (longitude - ?)) < ?",
      lat, lat, lng, lng, (km / 111.0)**2).order(rating: :desc)
  }

  CUISINE_TYPES = %w[Norwegian Italian Chinese Japanese Indian Thai Mexican American Pizza Sushi Kebab Burger Vegetarian Vegan].freeze

  def open_now?
    return true if open_time.nil? || close_time.nil?
    now = Time.current
    open_time..(close_time) === now.strftime("%H:%M:%S")
  end

  def update_rating!
    avg = restaurant_reviews.average("(food_rating + delivery_rating) / 2.0")
    update_columns(rating: avg&.round(1) || 0, reviews_count: restaurant_reviews.count)
  end
end
RUBY

cat > app/models/order.rb << 'RUBY'
class Order < ApplicationRecord
  belongs_to :user
  belongs_to :restaurant
  has_many :order_items, dependent: :destroy
  has_many :menu_items, through: :order_items

  STATUSES = %w[pending confirmed preparing ready_for_pickup out_for_delivery delivered cancelled].freeze

  monetize :subtotal_cents,     with_currency: :nok
  monetize :delivery_fee_cents, with_currency: :nok
  monetize :total_cents,        with_currency: :nok

  validates :status, inclusion: { in: STATUSES }
  validates :delivery_address, presence: true

  default_value_for :status, "pending"

  after_create_commit :broadcast_to_restaurant

  scope :active,   -> { where.not(status: %w[delivered cancelled]) }
  scope :recent,   -> { order(created_at: :desc) }

  def calculate_totals!
    sub = order_items.sum { |oi| oi.unit_price_cents * oi.quantity }
    update!(
      subtotal_cents: sub,
      delivery_fee_cents: restaurant.delivery_fee_cents,
      total_cents: sub + restaurant.delivery_fee_cents
    )
  end

  def advance_status!
    idx = STATUSES.index(status)
    update!(status: STATUSES[idx + 1]) if idx && idx < STATUSES.length - 1
  end

  private

  def broadcast_to_restaurant
    broadcast_append_to [restaurant, "orders"], partial: "orders/order", locals: { order: self }
  end
end
RUBY

cat > app/models/menu_item.rb << 'RUBY'
class MenuItem < ApplicationRecord
  belongs_to :menu_category
  belongs_to :restaurant
  has_one_attached :photo

  monetize :price_cents, with_currency: :nok

  validates :name, :price_cents, presence: true
  validates :price_cents, numericality: { greater_than: 0 }

  scope :available, -> { where(available: true) }
end
RUBY

# ── Controllers ─────────────────────────────────────────────────────────────
cat > app/controllers/application_controller.rb << 'RUBY'
class ApplicationController < ActionController::Base
  include Pagy::Backend
  allow_browser versions: :modern
end
RUBY

cat > app/controllers/restaurants_controller.rb << 'RUBY'
class RestaurantsController < ApplicationController
  before_action :require_authentication, only: %i[new create edit update destroy dashboard]
  before_action :set_restaurant, only: %i[show edit update destroy dashboard]
  before_action :authorize!, only: %i[edit update destroy dashboard]

  def index
    scope = Restaurant.active.includes(:user)
    scope = scope.where("name LIKE ? OR cuisine_type LIKE ?", "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?
    scope = scope.where(cuisine_type: params[:cuisine]) if params[:cuisine].present?
    @pagy, @restaurants = pagy(scope.order(rating: :desc))
  end

  def show
    @menu_categories = @restaurant.menu_categories.order(:position).includes(menu_items: :photo_attachment)
  end

  def new
    @restaurant = Current.user.restaurants.build
  end

  def create
    @restaurant = Current.user.restaurants.build(restaurant_params)
    @restaurant.save ? redirect_to(@restaurant, notice: "Restaurant created") : render(:new, status: :unprocessable_entity)
  end

  def edit; end

  def update
    @restaurant.update(restaurant_params) ? redirect_to(@restaurant, notice: "Updated") : render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @restaurant.destroy
    redirect_to restaurants_path, notice: "Restaurant removed"
  end

  def dashboard
    @orders = @restaurant.orders.active.recent.includes(:user, :order_items)
  end

  private

  def set_restaurant  = @restaurant = Restaurant.find(params[:id])
  def authorize!      = redirect_to(restaurants_path, alert: "Unauthorized") unless @restaurant.user == Current.user

  def restaurant_params
    params.require(:restaurant).permit(
      :name, :description, :address, :city, :postal_code, :phone,
      :cuisine_type, :open_time, :close_time,
      :delivery_fee_cents, :min_order_cents, :logo
    )
  end
end
RUBY

cat > app/controllers/orders_controller.rb << 'RUBY'
class OrdersController < ApplicationController
  before_action :require_authentication
  before_action :set_order, only: %i[show update]

  def index
    @pagy, @orders = pagy(Current.user.orders.recent.includes(:restaurant))
  end

  def show; end

  def create
    restaurant = Restaurant.find(params[:restaurant_id])
    @order = restaurant.orders.build(order_params.merge(user: Current.user))

    params[:order][:items]&.each do |item_id, qty|
      item = restaurant.menu_items.find_by(id: item_id)
      next unless item && qty.to_i > 0
      @order.order_items.build(menu_item: item, quantity: qty.to_i, unit_price_cents: item.price_cents)
    end

    if @order.save
      @order.calculate_totals!
      redirect_to @order, notice: "Order placed"
    else
      @restaurant = restaurant
      @menu_categories = restaurant.menu_categories.includes(menu_items: :photo_attachment)
      render "restaurants/show", status: :unprocessable_entity
    end
  end

  def update
    @order.advance_status! if @order.restaurant.user == Current.user
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to restaurant_dashboard_path(@order.restaurant) }
    end
  end

  private

  def set_order  = @order = Order.find(params[:id])

  def order_params
    params.require(:order).permit(:delivery_address, :delivery_city, :special_instructions)
  end
end
RUBY

# ── Routes ─────────────────────────────────────────────────────────────────
cat > config/routes.rb << 'RUBY'
Rails.application.routes.draw do
  resource  :session
  resources :passwords, param: :token

  root "restaurants#index"

  resources :restaurants do
    get :dashboard, on: :member
    resources :orders, only: %i[create]
    resources :menu_categories, only: %i[create update destroy] do
      resources :menu_items, only: %i[create update destroy]
    end
    resources :restaurant_reviews, only: %i[create]
  end

  resources :orders, only: %i[index show update]

  get "up", to: "rails/health#show", as: :rails_health_check
end
RUBY

# ── Assets + Infrastructure ─────────────────────────────────────────────────
write_base_css
write_layout "Brgen Takeaway"
write_falcon_config "$APP_PORT"
configure_production
install_rcd brgen_takeaway "$APP_DIR" "$APP_PORT" brgen_takeaway

log_ok "Brgen Takeaway setup complete — start: doas rcctl start brgen_takeaway"
