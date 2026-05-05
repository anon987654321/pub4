#!/usr/bin/env zsh
# brgen_takeaway.sh — Add Takeaway:: namespace to the main brgen Rails app
set -euo pipefail

APP_DIR=/home/brgen/app
SCRIPT_DIR=${0:a:h}

. "${SCRIPT_DIR}/@shared_functions.sh" 2>/dev/null || . /tmp/shared_functions.sh

need_cmd ruby34 bundle rails doas

already_done "${APP_DIR}/app/models/takeaway/restaurant.rb" && exit 0

log "Brgen Takeaway — adding Takeaway namespace to brgen app"
cd "$APP_DIR"

# ── Models ─────────────────────────────────────────────────────────────────
bin/rails generate model Takeaway::Restaurant \
  user:references name:string description:text \
  address:string city:string phone:string \
  cuisine_type:string \
  delivery_fee_cents:integer min_order_cents:integer \
  rating:decimal reviews_count:integer \
  active:boolean \
  --no-test-framework

bin/rails generate model Takeaway::MenuItem \
  restaurant:references name:string description:text \
  price_cents:integer available:boolean \
  vegetarian:boolean vegan:boolean \
  --no-test-framework

bin/rails generate model Takeaway::Order \
  user:references restaurant:references \
  status:string delivery_address:string \
  subtotal_cents:integer delivery_fee_cents:integer total_cents:integer \
  special_instructions:text \
  --no-test-framework

bin/rails generate model Takeaway::OrderItem \
  order:references menu_item:references \
  quantity:integer unit_price_cents:integer \
  --no-test-framework

RAILS_ENV=production bin/rails db:migrate

# ── Model logic ─────────────────────────────────────────────────────────────
mkdir -p app/models/takeaway

cat > app/models/takeaway/restaurant.rb << 'RUBY'
class Takeaway::Restaurant < ApplicationRecord
  belongs_to :user
  has_many :menu_items, class_name: "Takeaway::MenuItem", dependent: :destroy
  has_many :orders,     class_name: "Takeaway::Order",    dependent: :destroy

  CUISINE_TYPES = %w[Norwegian Italian Chinese Japanese Indian Thai Mexican Pizza Burger Kebab Sushi Vegetarian Vegan].freeze

  validates :name, :address, :cuisine_type, presence: true
  validates :delivery_fee_cents, :min_order_cents,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :active,  -> { where(active: true) }
  scope :popular, -> { order(rating: :desc) }

  def update_rating!
    avg = orders.joins(:reviews).average("takeaway_reviews.rating") rescue nil
    update_columns(rating: avg&.round(1) || 0)
  end
end
RUBY

cat > app/models/takeaway/menu_item.rb << 'RUBY'
class Takeaway::MenuItem < ApplicationRecord
  belongs_to :restaurant, class_name: "Takeaway::Restaurant"
  has_one_attached :photo

  validates :name, :price_cents, presence: true
  validates :price_cents, numericality: { greater_than: 0 }

  scope :available, -> { where(available: true) }

  def price_display = "#{price_cents / 100.0} NOK"
end
RUBY

cat > app/models/takeaway/order.rb << 'RUBY'
class Takeaway::Order < ApplicationRecord
  belongs_to :user
  belongs_to :restaurant, class_name: "Takeaway::Restaurant"
  has_many :order_items, class_name: "Takeaway::OrderItem", dependent: :destroy

  STATUSES = %w[pending confirmed preparing out_for_delivery delivered cancelled].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :delivery_address, presence: true

  before_validation { self.status ||= "pending" }

  scope :active,  -> { where.not(status: %w[delivered cancelled]) }
  scope :recent,  -> { order(created_at: :desc) }

  def calculate_totals!
    sub = order_items.sum { |oi| oi.unit_price_cents * oi.quantity }
    fee = restaurant.delivery_fee_cents.to_i
    update!(subtotal_cents: sub, delivery_fee_cents: fee, total_cents: sub + fee)
  end

  def advance_status!
    idx = STATUSES.index(status)
    update!(status: STATUSES[idx + 1]) if idx && idx < STATUSES.length - 1
  end

  def total_display   = "#{total_cents.to_i / 100.0} NOK"
end
RUBY

cat > app/models/takeaway/order_item.rb << 'RUBY'
class Takeaway::OrderItem < ApplicationRecord
  belongs_to :order,     class_name: "Takeaway::Order"
  belongs_to :menu_item, class_name: "Takeaway::MenuItem"

  validates :quantity, numericality: { greater_than: 0 }

  def subtotal_cents = unit_price_cents * quantity
  def subtotal_display = "#{subtotal_cents / 100.0} NOK"
end
RUBY

# ── Controllers ─────────────────────────────────────────────────────────────
mkdir -p app/controllers/takeaway

cat > app/controllers/takeaway/base_controller.rb << 'RUBY'
class Takeaway::BaseController < ApplicationController

end
RUBY

cat > app/controllers/takeaway/restaurants_controller.rb << 'RUBY'
class Takeaway::RestaurantsController < Takeaway::BaseController
  allow_unauthenticated_access only: %i[index show]
  before_action :set_restaurant, only: %i[show edit update destroy]

  def index
    scope = Takeaway::Restaurant.active.includes(:user)
    scope = scope.where(cuisine_type: params[:cuisine]) if params[:cuisine].present?
    scope = scope.where("name LIKE ?", "%#{params[:q]}%") if params[:q].present?
    @pagy, @restaurants = pagy(scope.popular)
  end

  def show
    @menu_items = @restaurant.menu_items.available
  end

  def new
    @restaurant = Takeaway::Restaurant.new
  end

  def create
    @restaurant = Current.user.takeaway_restaurants.build(restaurant_params)
    @restaurant.save ?
      redirect_to(takeaway_restaurant_path(@restaurant), notice: "Restaurant created") :
      render(:new, status: :unprocessable_entity)
  end

  def edit; end

  def update
    @restaurant.update(restaurant_params) ?
      redirect_to(takeaway_restaurant_path(@restaurant)) :
      render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @restaurant.destroy
    redirect_to takeaway_restaurants_path
  end

  private
  def set_restaurant    = (@restaurant = Takeaway::Restaurant.find(params[:id]))
  def restaurant_params = params.require(:takeaway_restaurant).permit(
    :name, :description, :address, :city, :phone, :cuisine_type,
    :delivery_fee_cents, :min_order_cents, :active
  )
end
RUBY

cat > app/controllers/takeaway/orders_controller.rb << 'RUBY'
class Takeaway::OrdersController < Takeaway::BaseController
  before_action :set_restaurant, only: %i[new create]

  def index
    @pagy, @orders = pagy(Current.user.takeaway_orders.recent.includes(:restaurant))
  end

  def show
    @order = Current.user.takeaway_orders.find(params[:id])
  end

  def new
    @order      = Takeaway::Order.new
    @menu_items = @restaurant.menu_items.available
  end

  def create
    @order = @restaurant.orders.build(order_params.merge(user: Current.user))
    item_params.each do |item_id, qty|
      next unless qty.to_i > 0
      item = @restaurant.menu_items.find_by(id: item_id)
      next unless item
      @order.order_items.build(menu_item: item, quantity: qty.to_i, unit_price_cents: item.price_cents)
    end
    if @order.save
      @order.calculate_totals!
      redirect_to takeaway_order_path(@order), notice: "Order placed"
    else
      @menu_items = @restaurant.menu_items.available
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @order = Takeaway::Order.find(params[:id])
    @order.advance_status! if @order.restaurant.user == Current.user
    redirect_to takeaway_order_path(@order)
  end

  private
  def set_restaurant = (@restaurant = Takeaway::Restaurant.find(params[:restaurant_id]))
  def order_params   = params.require(:takeaway_order).permit(:delivery_address, :special_instructions)
  def item_params    = params.dig(:takeaway_order, :items) || {}
end
RUBY

cat > app/controllers/takeaway/menu_items_controller.rb << 'RUBY'
class Takeaway::MenuItemsController < Takeaway::BaseController
  before_action :set_restaurant

  def create
    @item = @restaurant.menu_items.build(item_params)
    @item.save ?
      redirect_to(takeaway_restaurant_path(@restaurant), notice: "Item added") :
      redirect_to(takeaway_restaurant_path(@restaurant), alert: @item.errors.full_messages.to_sentence)
  end

  def destroy
    @restaurant.menu_items.find(params[:id]).destroy
    redirect_to takeaway_restaurant_path(@restaurant)
  end

  private
  def set_restaurant = (@restaurant = Current.user.takeaway_restaurants.find(params[:restaurant_id]))
  def item_params    = params.require(:takeaway_menu_item).permit(:name, :description, :price_cents, :available, :vegetarian, :vegan, :photo)
end
RUBY

# ── Views ────────────────────────────────────────────────────────────────────
mkdir -p app/views/takeaway/restaurants app/views/takeaway/orders app/views/takeaway/menu_items

cat > app/views/takeaway/restaurants/index.html.erb << 'ERB'
<% content_for :title, "Takeaway" %>
<h1>Order Food</h1>
<% if authenticated? %><%= link_to "Add restaurant", new_takeaway_restaurant_path, class: "btn btn--primary" %><% end %>
<form method="get">
  <input name="q" value="<%= params[:q] %>" placeholder="Search restaurants…">
  <select name="cuisine">
    <option value="">All cuisines</option>
    <% Takeaway::Restaurant::CUISINE_TYPES.each do |c| %>
      <option value="<%= c %>" <%= "selected" if params[:cuisine] == c %>><%= c %></option>
    <% end %>
  </select>
  <button type="submit">Search</button>
</form>
<div class="restaurant-grid">
  <% @restaurants.each do |r| %>
    <article>
      <%= link_to r.name, takeaway_restaurant_path(r) %>
      <small><%= r.cuisine_type %> · <%= r.city %> · ★ <%= r.rating || "—" %></small>
      <small>Min order: <%= r.min_order_cents.to_i / 100.0 %> NOK · Delivery: <%= r.delivery_fee_cents.to_i / 100.0 %> NOK</small>
    </article>
  <% end %>
</div>
<%= @pagy.series_nav if @pagy.pages > 1 %>
ERB

cat > app/views/takeaway/restaurants/show.html.erb << 'ERB'
<% content_for :title, @restaurant.name %>
<h1><%= @restaurant.name %></h1>
<p><%= @restaurant.description %></p>
<p><%= @restaurant.cuisine_type %> · <%= @restaurant.address %>, <%= @restaurant.city %></p>
<p>Min order: <%= @restaurant.min_order_cents.to_i / 100.0 %> NOK · Delivery: <%= @restaurant.delivery_fee_cents.to_i / 100.0 %> NOK</p>

<% if authenticated? && Current.user == @restaurant.user %>
  <nav>
    <%= link_to "Edit", edit_takeaway_restaurant_path(@restaurant), class: "btn" %>
    <h2>Add menu item</h2>
    <%= form_with url: takeaway_restaurant_menu_items_path(@restaurant) do |f| %>
      <input name="takeaway_menu_item[name]" placeholder="Name" required>
      <input name="takeaway_menu_item[price_cents]" type="number" placeholder="Price (øre)" required>
      <input name="takeaway_menu_item[description]" placeholder="Description">
      <button type="submit">Add</button>
    <% end %>
  </nav>
<% end %>

<h2>Menu</h2>
<% if authenticated? %>
  <%= form_with url: takeaway_restaurant_orders_path(@restaurant) do |f| %>
    <ul>
      <% @menu_items.each do |item| %>
        <li>
          <strong><%= item.name %></strong> — <%= item.price_display %>
          <% if item.description.present? %><br><small><%= item.description %></small><% end %>
          <input type="number" name="takeaway_order[items][<%= item.id %>]" min="0" value="0" style="width:4rem">
        </li>
      <% end %>
    </ul>
    <input name="takeaway_order[delivery_address]" placeholder="Delivery address" required>
    <textarea name="takeaway_order[special_instructions]" placeholder="Special instructions (optional)"></textarea>
    <button type="submit" class="btn btn--primary">Place order</button>
  <% end %>
<% else %>
  <%= link_to "Sign in to order", new_session_path, class: "btn btn--primary" %>
<% end %>
ERB

cat > app/views/takeaway/restaurants/new.html.erb << 'ERB'
<h1>Add restaurant</h1>
<%= form_with model: @restaurant, url: takeaway_restaurants_path do |f| %>
  <%= render "shared/errors", object: @restaurant %>
  <div class="field"><%= f.label :name %><%= f.text_field :name %></div>
  <div class="field"><%= f.label :description %><%= f.text_area :description, rows: 3 %></div>
  <div class="field"><%= f.label :address %><%= f.text_field :address %></div>
  <div class="field"><%= f.label :city %><%= f.text_field :city %></div>
  <div class="field"><%= f.label :phone %><%= f.text_field :phone %></div>
  <div class="field">
    <%= f.label :cuisine_type %>
    <%= f.select :cuisine_type, Takeaway::Restaurant::CUISINE_TYPES, { include_blank: "—" } %>
  </div>
  <div class="field"><%= f.label :delivery_fee_cents, "Delivery fee (øre)" %><%= f.number_field :delivery_fee_cents %></div>
  <div class="field"><%= f.label :min_order_cents, "Min order (øre)" %><%= f.number_field :min_order_cents %></div>
  <div class="field"><%= f.check_box :active %> <%= f.label :active, "Active" %></div>
  <div class="actions"><%= f.submit "Save", class: "btn btn--primary" %></div>
<% end %>
ERB

cat > app/views/takeaway/restaurants/edit.html.erb << 'ERB'
<h1>Edit restaurant</h1>
<%= form_with model: @restaurant, url: takeaway_restaurant_path(@restaurant), method: :patch do |f| %>
  <%= render "shared/errors", object: @restaurant %>
  <div class="field"><%= f.label :name %><%= f.text_field :name %></div>
  <div class="field"><%= f.label :description %><%= f.text_area :description, rows: 3 %></div>
  <div class="field"><%= f.label :address %><%= f.text_field :address %></div>
  <div class="field"><%= f.label :city %><%= f.text_field :city %></div>
  <div class="field"><%= f.label :phone %><%= f.text_field :phone %></div>
  <div class="field">
    <%= f.label :cuisine_type %>
    <%= f.select :cuisine_type, Takeaway::Restaurant::CUISINE_TYPES, { include_blank: "—" } %>
  </div>
  <div class="field"><%= f.label :delivery_fee_cents, "Delivery fee (øre)" %><%= f.number_field :delivery_fee_cents %></div>
  <div class="field"><%= f.label :min_order_cents, "Min order (øre)" %><%= f.number_field :min_order_cents %></div>
  <div class="field"><%= f.check_box :active %> <%= f.label :active, "Active" %></div>
  <div class="actions"><%= f.submit "Save", class: "btn btn--primary" %></div>
<% end %>
ERB

cat > app/views/takeaway/orders/index.html.erb << 'ERB'
<% content_for :title, "My Orders" %>
<h1>My Orders</h1>
<% @orders.each do |o| %>
  <article>
    <%= link_to o.restaurant.name, takeaway_order_path(o) %>
    <span><%= o.status %></span>
    <span><%= o.total_display %></span>
    <time><%= o.created_at.strftime("%d %b %Y") %></time>
  </article>
<% end %>
<%= @pagy.series_nav if @pagy.pages > 1 %>
ERB

cat > app/views/takeaway/orders/show.html.erb << 'ERB'
<% content_for :title, "Order ##{@order.id}" %>
<h1>Order #<%= @order.id %></h1>
<p>Status: <strong><%= @order.status %></strong></p>
<p>Restaurant: <%= link_to @order.restaurant.name, takeaway_restaurant_path(@order.restaurant) %></p>
<p>Delivery to: <%= @order.delivery_address %></p>
<ul>
  <% @order.order_items.includes(:menu_item).each do |oi| %>
    <li><%= oi.menu_item.name %> × <%= oi.quantity %> — <%= oi.subtotal_display %></li>
  <% end %>
</ul>
<p>Total: <strong><%= @order.total_display %></strong></p>
<% if Current.user == @order.restaurant.user && @order.status != "delivered" %>
  <%= button_to "Advance status", takeaway_order_path(@order), method: :patch, class: "btn btn--primary" %>
<% end %>
ERB

# ── Route patch ─────────────────────────────────────────────────────────────
ruby34 -e "
r = File.read('config/routes.rb')
unless r.include?('namespace :takeaway')
  patch = %q(
  namespace :takeaway do
    root 'restaurants#index'
    resources :restaurants do
      resources :menu_items, only: %i[create destroy]
      resources :orders,     only: %i[new create]
    end
    resources :orders, only: %i[index show update]
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
unless u.include?('takeaway_restaurants')
  u.sub!('has_secure_password', %Q(has_secure_password
  has_many :takeaway_restaurants, class_name: 'Takeaway::Restaurant', dependent: :destroy
  has_many :takeaway_orders,      class_name: 'Takeaway::Order',      dependent: :destroy))
  File.write('app/models/user.rb', u)
  puts 'User model patched'
end
"

doas rcctl restart brgen 2>/dev/null || true
log_ok "Brgen Takeaway namespace added — visit /takeaway"
