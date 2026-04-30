#!/usr/bin/env zsh
# brgen_marketplace.sh — Brgen Marketplace (Rails 8, SQLite, no Solidus)
# Usage: zsh brgen_marketplace.sh
set -euo pipefail

APP_NAME=brgen_marketplace
APP_DIR=/home/${APP_NAME}/app
APP_PORT=10009
SCRIPT_DIR=${0:a:h}

. "${SCRIPT_DIR:h}/@shared_functions.sh"

need_cmd ruby34 bundle rails doas

already_done "${APP_DIR}/app/models/listing.rb" && exit 0

log "Brgen Marketplace — Classifieds and Local Commerce"

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
bin/rails generate model Category \
  name:string slug:string:uniq parent_id:integer \
  description:text icon:string \
  --no-test-framework

bin/rails generate model Listing \
  user:references category:references \
  title:string description:text \
  price_cents:integer currency:string \
  condition:string status:string \
  latitude:float longitude:float city:string \
  views_count:integer:default[0] \
  favorites_count:integer:default[0] \
  --no-test-framework

bin/rails generate model Favorite \
  user:references listing:references \
  --no-test-framework

bin/rails generate model Offer \
  listing:references buyer:references{User} \
  amount_cents:integer currency:string \
  status:string message:text \
  --no-test-framework

bin/rails generate model Conversation \
  listing:references buyer:references{User} seller:references{User} \
  --no-test-framework

bin/rails generate model Message \
  conversation:references user:references \
  content:text read_at:datetime \
  --no-test-framework

bin/rails generate model Review \
  reviewer:references{User} reviewee:references{User} \
  listing:references rating:integer content:text \
  --no-test-framework

bin/rails db:migrate

# ── Model logic ─────────────────────────────────────────────────────────────
cat > app/models/listing.rb << 'RUBY'
class Listing < ApplicationRecord
  belongs_to :user
  belongs_to :category
  has_many :favorites, dependent: :destroy
  has_many :favorited_by, through: :favorites, source: :user
  has_many :offers, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many_attached :photos

  CONDITIONS = %w[new like_new good fair poor].freeze
  STATUSES   = %w[active sold reserved removed].freeze

  monetize :price_cents, with_currency: :nok

  validates :title, presence: true, length: { maximum: 100 }
  validates :description, presence: true, length: { maximum: 5000 }
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :condition, inclusion: { in: CONDITIONS }
  validates :status, inclusion: { in: STATUSES }

  default_value_for :status,   "active"
  default_value_for :currency, "NOK"

  geocoded_by :city
  after_validation :geocode, if: :city_changed?

  scope :active,    -> { where(status: "active") }
  scope :recent,    -> { order(created_at: :desc) }
  scope :nearby,    ->(lat, lng, km = 50) {
    where("((latitude - ?) * (latitude - ?) + (longitude - ?) * (longitude - ?)) < ?",
      lat, lat, lng, lng, (km / 111.0)**2)
  }

  def to_param = id.to_s

  def sold!
    update!(status: "sold")
  end

  def reserve!
    update!(status: "reserved")
  end
end
RUBY

cat > app/models/offer.rb << 'RUBY'
class Offer < ApplicationRecord
  belongs_to :listing
  belongs_to :buyer, class_name: "User"

  STATUSES = %w[pending accepted declined countered].freeze

  monetize :amount_cents, with_currency: :nok

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }

  default_value_for :status, "pending"

  def accept!
    update!(status: "accepted")
    listing.reserve!
  end

  def decline!
    update!(status: "declined")
  end
end
RUBY

cat > app/models/review.rb << 'RUBY'
class Review < ApplicationRecord
  belongs_to :reviewer, class_name: "User"
  belongs_to :reviewee, class_name: "User"
  belongs_to :listing

  validates :rating, inclusion: { in: 1..5 }
  validates :content, presence: true, length: { maximum: 2000 }
  validates :reviewer_id, uniqueness: { scope: :listing_id }
end
RUBY

# ── Controllers ─────────────────────────────────────────────────────────────
cat > app/controllers/application_controller.rb << 'RUBY'
class ApplicationController < ActionController::Base
  include Pagy::Backend
  allow_browser versions: :modern
end
RUBY

cat > app/controllers/listings_controller.rb << 'RUBY'
class ListingsController < ApplicationController
  before_action :require_authentication, except: %i[index show]
  before_action :set_listing, only: %i[show edit update destroy favorite unfavorite]
  before_action :authorize!, only: %i[edit update destroy]

  def index
    scope = Listing.active.includes(:user, :category)
    scope = scope.where(category_id: params[:category_id]) if params[:category_id]
    scope = scope.where("title LIKE ?", "%#{params[:q]}%") if params[:q].present?
    @pagy, @listings = pagy(scope.recent)
  end

  def show
    @listing.increment!(:views_count)
    @similar = Listing.active.where(category: @listing.category).where.not(id: @listing).limit(4)
    @offer   = Offer.new
  end

  def new
    @listing = Current.user.listings.build
  end

  def create
    @listing = Current.user.listings.build(listing_params)
    @listing.save ? redirect_to(@listing, notice: "Listing created") : render(:new, status: :unprocessable_entity)
  end

  def edit; end

  def update
    @listing.update(listing_params) ? redirect_to(@listing, notice: "Updated") : render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @listing.destroy
    redirect_to listings_path, notice: "Listing removed"
  end

  def favorite
    Current.user.favorites.find_or_create_by!(listing: @listing)
    @listing.increment!(:favorites_count)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @listing }
    end
  end

  def unfavorite
    Current.user.favorites.find_by(listing: @listing)&.destroy!
    @listing.decrement!(:favorites_count)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @listing }
    end
  end

  private

  def set_listing   = @listing = Listing.find(params[:id])
  def authorize!    = redirect_to(listings_path, alert: "Unauthorized") unless @listing.user == Current.user

  def listing_params
    params.require(:listing).permit(
      :title, :description, :price_cents, :category_id,
      :condition, :city, photos: []
    )
  end
end
RUBY

cat > app/controllers/offers_controller.rb << 'RUBY'
class OffersController < ApplicationController
  before_action :require_authentication
  before_action :set_listing

  def create
    @offer = @listing.offers.build(offer_params.merge(buyer: Current.user))
    @offer.save ? redirect_to(@listing, notice: "Offer sent") : render(:new, status: :unprocessable_entity)
  end

  def update
    @offer = @listing.offers.find(params[:id])
    authorize_seller!
    case params[:action_type]
    when "accept"  then @offer.accept!
    when "decline" then @offer.decline!
    end
    redirect_to @listing
  end

  private

  def set_listing  = @listing = Listing.find(params[:listing_id])
  def authorize_seller! = redirect_to(@listing, alert: "Unauthorized") unless @listing.user == Current.user
  def offer_params = params.require(:offer).permit(:amount_cents, :message)
end
RUBY

# ── Routes ─────────────────────────────────────────────────────────────────
cat > config/routes.rb << 'RUBY'
Rails.application.routes.draw do
  resource  :session
  resources :passwords, param: :token

  root "listings#index"

  resources :listings do
    member do
      post :favorite
      delete :unfavorite
    end
    resources :offers, only: %i[create update]
  end

  resources :categories, only: %i[index show]
  resources :reviews, only: %i[create]

  get "up", to: "rails/health#show", as: :rails_health_check
end
RUBY

# ── Assets + Infrastructure ─────────────────────────────────────────────────
write_base_css
write_layout "Brgen Marketplace"
write_puma_config "$APP_PORT"
configure_production
install_rcd brgen_marketplace "$APP_DIR" "$APP_PORT" brgen_marketplace

# ── Seed ───────────────────────────────────────────────────────────────────
cat > db/seeds.rb << 'RUBY'
user = User.find_or_create_by!(email_address: "seller@brgen.no") do |u|
  u.password = u.password_confirmation = "password123"
end

cats = [
  { name: "Electronics",  slug: "electronics",  icon: "💻" },
  { name: "Clothing",     slug: "clothing",      icon: "👕" },
  { name: "Furniture",    slug: "furniture",     icon: "🪑" },
  { name: "Vehicles",     slug: "vehicles",      icon: "🚗" },
  { name: "Sports",       slug: "sports",        icon: "⚽" },
]
cats.each { |c| Category.find_or_create_by!(slug: c[:slug]) { |cat| cat.name = c[:name]; cat.icon = c[:icon] } }

5.times do |i|
  Listing.find_or_create_by!(title: "Item #{i + 1}") do |l|
    l.user        = user
    l.category    = Category.first
    l.description = "Great condition item for sale"
    l.price_cents = (rand * 5000 + 100).to_i * 100
    l.currency    = "NOK"
    l.condition   = "good"
    l.city        = "Bergen"
    l.status      = "active"
  end
end
puts "Seeded #{Listing.count} listings"
RUBY

bin/rails db:seed

log_ok "Brgen Marketplace setup complete — start: doas rcctl start brgen_marketplace"
