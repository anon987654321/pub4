#!/usr/bin/env zsh
set -euo pipefail

readonly VERSION="1.0.0"
readonly APP_NAME="brgen_takeaway"

SCRIPT_DIR="${0:a:h}"
source "${SCRIPT_DIR}/__shared/@common.sh"

APP_DIR="/home/brgen/app"
cd "$APP_DIR"

log "Installing Brgen Takeaway - Hyperlocal food delivery"

# Gems
print >> Gemfile << 'GEMS'
gem "geocoder"
gem "stripe"
gem "money-rails"
GEMS
bundle install

# Models
bin/rails generate model Takeaway::Restaurant name:string address:string latitude:decimal longitude:decimal cuisine:string rating:decimal open_hours:jsonb delivery_radius:integer
bin/rails generate model Takeaway::MenuItem restaurant:references name:string description:text price_cents:integer availability:integer category:string
bin/rails generate model Takeaway::Order restaurant:references user:references status:integer total_cents:integer delivery_address:text delivery_lat:decimal delivery_lng:decimal
bin/rails generate model Takeaway::OrderItem order:references menu_item:references quantity:integer price_cents:integer

bin/rails db:migrate

# Routes
add_route "namespace :takeaway do"
add_route "  resources :restaurants, only: [:index, :show] do"
add_route "    collection do"
add_route "      get :search"
add_route "    end"
add_route "  end"
add_route "  resources :orders, only: [:create, :show, :update]"
add_route "  post 'webhooks/stripe', to: 'webhooks#stripe'"
add_route "end"

# Models
print > app/models/takeaway/restaurant.rb << 'RUBY'
module Takeaway
  class Restaurant < ApplicationRecord
    has_many :menu_items, dependent: :destroy, class_name: 'Takeaway::MenuItem'
    has_many :orders, dependent: :nullify, class_name: 'Takeaway::Order'
    
    validates :name, :address, presence: true
    
    geocoded_by :address
    after_validation :geocode, if: :will_save_change_to_address?
    
    scope :nearby, ->(lat, lng, radius = 8) {
      near([lat, lng], radius, units: :km)
    }
    
    scope :by_cuisine, ->(cuisine) { where(cuisine: cuisine) }
    
    def open_now?
      return false unless open_hours
      current_time = Time.current.strftime("%H:%M")
      day = Date.current.strftime("%A").downcase
      hours = open_hours[day]
      return false unless hours
      current_time.between?(hours["open"], hours["close"])
    end
  end
end
RUBY

print > app/models/takeaway/order.rb << 'RUBY'
module Takeaway
  class Order < ApplicationRecord
    belongs_to :restaurant, class_name: 'Takeaway::Restaurant'
    belongs_to :user
    has_many :order_items, dependent: :destroy, class_name: 'Takeaway::OrderItem'
    
    enum status: { placed: 0, accepted: 1, preparing: 2, dispatched: 3, delivered: 4, canceled: 5 }
    
    monetize :total_cents
    
    validates :delivery_address, presence: true
    
    after_create_commit -> { broadcast_append_to "orders" }
    after_update_commit -> { broadcast_replace_to "order_#{id}", target: "order_#{id}" }
    
    def advance_status!
      case status
      when 'placed' then accepted!
      when 'accepted' then preparing!
      when 'preparing' then dispatched!
      when 'dispatched' then delivered!
      end
    end
  end
end
RUBY

# Controllers
print > app/controllers/takeaway/restaurants_controller.rb << 'RUBY'
module Takeaway
  class RestaurantsController < ApplicationController
    def index
      @restaurants = Restaurant.includes(:menu_items).all
      @restaurants = @restaurants.nearby(params[:lat], params[:lng]) if params[:lat] && params[:lng]
      @restaurants = @restaurants.by_cuisine(params[:cuisine]) if params[:cuisine]
    end
    
    def show
      @restaurant = Restaurant.includes(:menu_items).find(params[:id])
    end
    
    def search
      @restaurants = Restaurant.near([params[:lat], params[:lng]], params[:radius] || 8)
      render :index
    end
  end
end
RUBY

print > app/controllers/takeaway/orders_controller.rb << 'RUBY'
module Takeaway
  class OrdersController < ApplicationController
    before_action :authenticate_user!
    
    def create
      @order = current_user.orders.build(order_params)
      
      if @order.save
        OrderStatusChannel.broadcast_to(current_user, { order_id: @order.id, status: @order.status })
        render json: @order, status: :created
      else
        render json: @order.errors, status: :unprocessable_entity
      end
    end
    
    def show
      @order = current_user.orders.find(params[:id])
    end
    
    def update
      @order = Order.find(params[:id])
      
      if @order.update(status: params[:status])
        head :ok
      else
        render json: @order.errors, status: :unprocessable_entity
      end
    end
    
    private
    
    def order_params
      params.require(:order).permit(:restaurant_id, :delivery_address, :delivery_lat, :delivery_lng, :total_cents, order_items_attributes: [:menu_item_id, :quantity, :price_cents])
    end
  end
end
RUBY

# Views
print > app/views/takeaway/restaurants/index.html.erb << 'ERB'
<%= tag.div class: "takeaway-index", data: { controller: "geolocation" } do %>
  <%= tag.h1 "Restaurants Near You" %>
  <%= tag.div class: "restaurant-grid" do %>
    <% @restaurants.each do |restaurant| %>
      <%= link_to takeaway_restaurant_path(restaurant), class: "restaurant-card" do %>
        <%= tag.div class: "restaurant-info" do %>
          <%= tag.h3 restaurant.name %>
          <%= tag.p restaurant.cuisine %>
          <%= tag.p "⭐ #{restaurant.rating || 'New'}" %>
          <%= tag.span restaurant.open_now? ? "🟢 Open" : "🔴 Closed", class: "status" %>
        <% end %>
      <% end %>
    <% end %>
  <% end %>
<% end %>
ERB

# Stimulus controller
print > app/javascript/controllers/takeaway_controller.js << 'JS'
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cart", "total"]
  
  addToCart(event) {
    const item = event.currentTarget.dataset
    const cartItem = {
      id: item.itemId,
      name: item.itemName,
      price: parseFloat(item.itemPrice),
      quantity: 1
    }
    
    this.cart.push(cartItem)
    this.updateTotal()
  }
  
  get cart() {
    return JSON.parse(this.cartTarget.dataset.items || "[]")
  }
  
  updateTotal() {
    const total = this.cart.reduce((sum, item) => sum + (item.price * item.quantity), 0)
    this.totalTarget.textContent = `$${total.toFixed(2)}`
  }
}
JS

log "Brgen Takeaway setup complete"