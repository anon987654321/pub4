#!/usr/bin/env zsh
# brgen_marketplace.sh — Add Marketplace:: namespace to the main brgen Rails app
set -euo pipefail

APP_DIR=/home/brgen/app
SCRIPT_DIR=${0:a:h}

. "${SCRIPT_DIR}/@shared_functions.sh" 2>/dev/null || . /tmp/shared_functions.sh

need_cmd ruby34 bundle rails doas

already_done "${APP_DIR}/app/models/marketplace/listing.rb" && exit 0

log "Brgen Marketplace — adding Marketplace namespace to brgen app"
cd "$APP_DIR"

# ── Models ─────────────────────────────────────────────────────────────────
bin/rails generate model Marketplace::Category \
  name:string slug:string parent_id:integer \
  --no-test-framework

bin/rails generate model Marketplace::Listing \
  user:references category:references \
  title:string description:text \
  price_cents:integer currency:string \
  condition:string status:string \
  location:string views_count:integer \
  --no-test-framework

bin/rails generate model Marketplace::Order \
  buyer:references listing:references \
  status:string message:text \
  price_cents:integer \
  --no-test-framework

RAILS_ENV=production bin/rails db:migrate

# ── Model logic ─────────────────────────────────────────────────────────────
mkdir -p app/models/marketplace

cat > app/models/marketplace/category.rb << 'RUBY'
class Marketplace::Category < ApplicationRecord
  belongs_to :parent, class_name: "Marketplace::Category", optional: true
  has_many :children, class_name: "Marketplace::Category", foreign_key: :parent_id, dependent: :nullify
  has_many :listings, class_name: "Marketplace::Listing", foreign_key: :category_id, dependent: :nullify

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true

  before_validation { self.slug ||= name.to_s.parameterize }

  scope :roots, -> { where(parent_id: nil) }

  def to_param = slug
end
RUBY

cat > app/models/marketplace/listing.rb << 'RUBY'
class Marketplace::Listing < ApplicationRecord
  belongs_to :user
  belongs_to :category, class_name: "Marketplace::Category",
             foreign_key: :category_id, optional: true
  has_many :orders, class_name: "Marketplace::Order",
           foreign_key: :listing_id, dependent: :destroy
  has_many_attached :photos

  CONDITIONS = %w[new like_new good fair poor].freeze
  STATUSES   = %w[active sold reserved removed].freeze

  validates :title, presence: true, length: { maximum: 200 }
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :condition, inclusion: { in: CONDITIONS }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }

  before_validation { self.status ||= "active"; self.currency ||= "NOK" }

  scope :active,   -> { where(status: "active") }
  scope :recent,   -> { order(created_at: :desc) }
  scope :popular,  -> { order(views_count: :desc) }

  def price_display  = "#{price_cents / 100.0} #{currency}"
  def sold?          = status == "sold"
end
RUBY

cat > app/models/marketplace/order.rb << 'RUBY'
class Marketplace::Order < ApplicationRecord
  belongs_to :buyer,   class_name: "User"
  belongs_to :listing, class_name: "Marketplace::Listing"

  STATUSES = %w[pending accepted declined completed].freeze

  validates :status, inclusion: { in: STATUSES }
  before_validation { self.status ||= "pending" }

  def seller = listing.user
  def accept! = update!(status: "accepted")
  def decline! = update!(status: "declined")
end
RUBY

# ── Controllers ─────────────────────────────────────────────────────────────
mkdir -p app/controllers/marketplace

cat > app/controllers/marketplace/base_controller.rb << 'RUBY'
class Marketplace::BaseController < ApplicationController

end
RUBY

cat > app/controllers/marketplace/listings_controller.rb << 'RUBY'
class Marketplace::ListingsController < Marketplace::BaseController
  allow_unauthenticated_access only: %i[index show]
  before_action :set_listing, only: %i[show edit update destroy]

  def index
    scope = Marketplace::Listing.active.includes(:user, :category)
    scope = scope.where("title LIKE ?", "%#{params[:q]}%") if params[:q].present?
    scope = scope.where(category_id: params[:category_id]) if params[:category_id].present?
    @pagy, @listings = pagy(scope.recent)
    @categories = Marketplace::Category.roots.includes(:children)
  end

  def show
    @listing.increment!(:views_count)
    @order = Marketplace::Order.new if authenticated?
  end

  def new
    @listing   = Marketplace::Listing.new
    @categories = Marketplace::Category.all
  end

  def create
    @listing = Current.user.marketplace_listings.build(listing_params)
    @listing.save ?
      redirect_to(marketplace_listing_path(@listing), notice: "Listed") :
      render(:new, status: :unprocessable_entity)
  end

  def edit
    @categories = Marketplace::Category.all
  end

  def update
    @listing.update(listing_params) ?
      redirect_to(marketplace_listing_path(@listing)) :
      render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @listing.update!(status: "removed")
    redirect_to marketplace_listings_path
  end

  private
  def set_listing    = (@listing = Marketplace::Listing.find(params[:id]))
  def listing_params = params.require(:marketplace_listing).permit(
    :title, :description, :price_cents, :condition, :status, :location,
    :category_id, photos: []
  )
end
RUBY

cat > app/controllers/marketplace/orders_controller.rb << 'RUBY'
class Marketplace::OrdersController < Marketplace::BaseController
  before_action :set_listing

  def create
    @order = @listing.orders.build(buyer: Current.user,
                                   message: params.dig(:marketplace_order, :message),
                                   price_cents: @listing.price_cents)
    @order.save ?
      redirect_to(marketplace_listing_path(@listing), notice: "Offer sent") :
      redirect_to(marketplace_listing_path(@listing), alert: "Could not send offer")
  end

  def update
    @order = Marketplace::Order.find(params[:id])
    if @order.seller == Current.user
      @order.accept!   if params[:accept]
      @order.decline!  if params[:decline]
    end
    redirect_to marketplace_listing_path(@listing)
  end

  private
  def set_listing = (@listing = Marketplace::Listing.find(params[:listing_id]))
end
RUBY

cat > app/controllers/marketplace/categories_controller.rb << 'RUBY'
class Marketplace::CategoriesController < Marketplace::BaseController
  allow_unauthenticated_access only: %i[show]

  def show
    @category = Marketplace::Category.find_by!(slug: params[:id])
    @pagy, @listings = pagy(@category.listings.active.recent)
  end
end
RUBY

# ── Views ────────────────────────────────────────────────────────────────────
mkdir -p app/views/marketplace/listings app/views/marketplace/categories

cat > app/views/marketplace/listings/index.html.erb << 'ERB'
<% content_for :title, "Marketplace" %>
<h1>Marketplace</h1>
<% if authenticated? %><%= link_to "Sell something", new_marketplace_listing_path, class: "btn btn--primary" %><% end %>

<form method="get">
  <input name="q" value="<%= params[:q] %>" placeholder="Search listings…">
  <button type="submit">Search</button>
</form>

<% if @categories.any? %>
  <nav>
    <% @categories.each do |cat| %>
      <%= link_to cat.name, marketplace_category_path(cat) %>
    <% end %>
  </nav>
<% end %>

<div class="listing-grid">
  <% @listings.each do |l| %>
    <article>
      <% if l.photos.attached? %>
        <%= link_to marketplace_listing_path(l) do %>
          <%= image_tag l.photos.first %>
        <% end %>
      <% end %>
      <%= link_to l.title, marketplace_listing_path(l) %>
      <p><strong><%= l.price_display %></strong></p>
      <small><%= l.location %> · <%= l.condition %></small>
    </article>
  <% end %>
</div>
<%= @pagy.series_nav if @pagy.pages > 1 %>
ERB

cat > app/views/marketplace/listings/show.html.erb << 'ERB'
<% content_for :title, @listing.title %>
<% if @listing.photos.attached? %>
  <div>
    <% @listing.photos.each do |photo| %>
      <%= image_tag photo %>
    <% end %>
  </div>
<% end %>

<h1><%= @listing.title %></h1>
<p><strong><%= @listing.price_display %></strong></p>
<p><%= @listing.description %></p>
<p>Condition: <%= @listing.condition %> · Location: <%= @listing.location %></p>
<p>Seller: <%= @listing.user.email_address.split("@").first %></p>

<% if authenticated? && Current.user != @listing.user && !@listing.sold? %>
  <h2>Make an offer</h2>
  <%= form_with model: @order, url: marketplace_listing_orders_path(@listing) do |f| %>
    <%= f.text_area :message, placeholder: "Message to seller (optional)", rows: 3 %>
    <%= f.submit "Send offer", class: "btn btn--primary" %>
  <% end %>
<% end %>

<% if authenticated? && Current.user == @listing.user %>
  <h2>Offers</h2>
  <% @listing.orders.includes(:buyer).each do |o| %>
    <article>
      <p><%= o.buyer.email_address.split("@").first %> — <%= o.status %></p>
      <% if o.message.present? %><p><%= o.message %></p><% end %>
      <% if o.status == "pending" %>
        <%= button_to "Accept", marketplace_listing_order_path(@listing, o), params: { accept: true }, method: :patch, class: "btn btn--primary" %>
        <%= button_to "Decline", marketplace_listing_order_path(@listing, o), params: { decline: true }, method: :patch, class: "btn" %>
      <% end %>
    </article>
  <% end %>
  <nav>
    <%= link_to "Edit", edit_marketplace_listing_path(@listing), class: "btn" %>
    <%= button_to "Remove", marketplace_listing_path(@listing), method: :delete, class: "btn" %>
  </nav>
<% end %>
ERB

cat > app/views/marketplace/listings/new.html.erb << 'ERB'
<h1>New listing</h1>
<%= form_with model: @listing, url: marketplace_listings_path do |f| %>
  <%= render "shared/errors", object: @listing %>
  <div class="field"><%= f.label :title %><%= f.text_field :title %></div>
  <div class="field"><%= f.label :description %><%= f.text_area :description, rows: 4 %></div>
  <div class="field"><%= f.label :price_cents, "Price (øre)" %><%= f.number_field :price_cents %></div>
  <div class="field">
    <%= f.label :condition %>
    <%= f.select :condition, Marketplace::Listing::CONDITIONS, { include_blank: "—" } %>
  </div>
  <div class="field">
    <%= f.label :category_id, "Category" %>
    <%= f.collection_select :category_id, @categories, :id, :name, { include_blank: "—" } %>
  </div>
  <div class="field"><%= f.label :location %><%= f.text_field :location %></div>
  <div class="field"><%= f.label :photos %><%= f.file_field :photos, multiple: true, accept: "image/*" %></div>
  <div class="actions"><%= f.submit "List it", class: "btn btn--primary" %></div>
<% end %>
ERB

cat > app/views/marketplace/listings/edit.html.erb << 'ERB'
<h1>Edit listing</h1>
<%= form_with model: @listing, url: marketplace_listing_path(@listing), method: :patch do |f| %>
  <%= render "shared/errors", object: @listing %>
  <div class="field"><%= f.label :title %><%= f.text_field :title %></div>
  <div class="field"><%= f.label :description %><%= f.text_area :description, rows: 4 %></div>
  <div class="field"><%= f.label :price_cents, "Price (øre)" %><%= f.number_field :price_cents %></div>
  <div class="field">
    <%= f.label :condition %>
    <%= f.select :condition, Marketplace::Listing::CONDITIONS, { include_blank: "—" } %>
  </div>
  <div class="field">
    <%= f.label :category_id, "Category" %>
    <%= f.collection_select :category_id, @categories, :id, :name, { include_blank: "—" } %>
  </div>
  <div class="field"><%= f.label :location %><%= f.text_field :location %></div>
  <div class="field">
    <%= f.label :status %>
    <%= f.select :status, Marketplace::Listing::STATUSES %>
  </div>
  <div class="field"><%= f.label :photos %><%= f.file_field :photos, multiple: true, accept: "image/*" %></div>
  <div class="actions"><%= f.submit "Save", class: "btn btn--primary" %></div>
<% end %>
ERB

cat > app/views/marketplace/categories/show.html.erb << 'ERB'
<% content_for :title, @category.name %>
<h1><%= @category.name %></h1>
<div class="listing-grid">
  <% @listings.each do |l| %>
    <article>
      <%= link_to l.title, marketplace_listing_path(l) %>
      <p><strong><%= l.price_display %></strong></p>
    </article>
  <% end %>
</div>
<%= @pagy.series_nav if @pagy.pages > 1 %>
ERB

# ── Route patch ─────────────────────────────────────────────────────────────
ruby34 -e "
r = File.read('config/routes.rb')
unless r.include?('namespace :marketplace')
  patch = %q(
  namespace :marketplace do
    root 'listings#index'
    resources :listings do
      resources :orders, only: %i[create update]
    end
    resources :categories, only: :show, param: :id
  end
)
  r.sub!('root \"home#index\"', patch + '  root \"home#index\"')
  File.write('config/routes.rb', r)
  puts 'Routes patched'
end
"

# ── User association ─────────────────────────────────────────────────────────
ruby34 -e "
u = File.read('app/models/user.rb')
unless u.include?('marketplace_listings')
  u.sub!('has_secure_password', %Q(has_secure_password
  has_many :marketplace_listings, class_name: 'Marketplace::Listing', dependent: :destroy
  has_many :marketplace_orders,   class_name: 'Marketplace::Order',   foreign_key: :buyer_id, dependent: :destroy))
  File.write('app/models/user.rb', u)
  puts 'User model patched'
end
"

# ── Seed categories ──────────────────────────────────────────────────────────
ruby34 -e "
require_relative 'config/environment'
%w[Electronics Clothing Books Furniture Sports Vehicles Homes Other].each do |name|
  Marketplace::Category.find_or_create_by!(name: name)
end
puts 'Categories seeded'
" 2>/dev/null || true

doas rcctl restart brgen 2>/dev/null || true
log_ok "Brgen Marketplace namespace added — visit /marketplace"
