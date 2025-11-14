#!/usr/bin/env zsh
set -euo pipefail

# Momondo travel search features: Flights, Hotels, Cars, Price Comparison, Alerts
# Shared across travel apps

setup_momondo_models() {
  log "Setting up Momondo models: FlightSearch, HotelSearch, PriceAlert, TravelDeal"

  # Flight search with flexible dates
  bin/rails generate model FlightSearch user:references origin:string destination:string departure_date:date return_date:date passengers:integer cabin_class:string flexible_dates:boolean

  # Hotel search
  bin/rails generate model HotelSearch user:references city:string check_in:date check_out:date guests:integer rooms:integer stars:integer

  # Car rental search
  bin/rails generate model CarSearch user:references pickup_location:string dropoff_location:string pickup_date:date dropoff_date:date car_type:string

  # Price alert for tracking deals
  bin/rails generate model PriceAlert user:references alertable:references{polymorphic} target_price:decimal current_price:decimal active:boolean

  # Travel deal aggregation
  bin/rails generate model TravelDeal deal_type:string title:string description:text origin:string destination:string price:decimal currency:string valid_from:date valid_until:date url:string provider:string

  # Search history for recommendations
  bin/rails generate model SearchHistory user:references searchable:references{polymorphic} search_params:json executed_at:datetime

  log "Momondo models generated"
}

generate_flight_search_model() {
  log "Configuring FlightSearch model"

  cat <<'EOF' > app/models/flight_search.rb
class FlightSearch < ApplicationRecord

  belongs_to :user, optional: true
  has_many :price_alerts, as: :alertable, dependent: :destroy

  has_one :search_history, as: :searchable, dependent: :destroy
  validates :origin, :destination, :departure_date, :passengers, presence: true

  validate :departure_before_return

  enum cabin_class: {

    economy: "economy",

    premium_economy: "premium_economy",
    business: "business",

    first: "first"
  }

  scope :recent, -> { order(created_at: :desc) }

  scope :popular_routes, -> {

    group(:origin, :destination)

      .select("origin, destination, COUNT(*) as search_count")

      .order("search_count DESC")
      .limit(10)

  }

  def roundtrip?

    return_date.present?

  end

  def one_way?

    !roundtrip?
  end

  def flexible_date_range

    return nil unless flexible_dates?
    (departure_date - 3.days)..(departure_date + 3.days)

  end

  def search_params
    {

      origin: origin,
      destination: destination,

      departure_date: departure_date,
      return_date: return_date,

      passengers: passengers,

      cabin_class: cabin_class

    }

  end

  private

  def departure_before_return

    return unless return_date && departure_date

    errors.add(:return_date, "must be after departure") if return_date < departure_date

  end
end
EOF

  log "FlightSearch model configured"

}

generate_hotel_search_model() {

  log "Configuring HotelSearch model"

  cat <<'EOF' > app/models/hotel_search.rb
class HotelSearch < ApplicationRecord

  belongs_to :user, optional: true
  has_many :price_alerts, as: :alertable, dependent: :destroy

  has_one :search_history, as: :searchable, dependent: :destroy
  validates :city, :check_in, :check_out, :guests, :rooms, presence: true

  validate :check_out_after_check_in

  scope :recent, -> { order(created_at: :desc) }

  scope :popular_destinations, -> {

    group(:city)
      .select("city, COUNT(*) as search_count")

      .order("search_count DESC")
      .limit(10)

  }

  def nights

    (check_out - check_in).to_i

  end

  def search_params

    {
      city: city,

      check_in: check_in,

      check_out: check_out,
      guests: guests,

      rooms: rooms,

      stars: stars

    }

  end

  private

  def check_out_after_check_in

    return unless check_in && check_out

    errors.add(:check_out, "must be after check-in") if check_out <= check_in

  end
end
EOF

  log "HotelSearch model configured"

}

generate_car_search_model() {

  log "Configuring CarSearch model"

  cat <<'EOF' > app/models/car_search.rb
class CarSearch < ApplicationRecord

  belongs_to :user, optional: true
  has_one :search_history, as: :searchable, dependent: :destroy

  validates :pickup_location, :pickup_date, :dropoff_date, presence: true
  enum car_type: {

    economy: "economy",

    compact: "compact",

    midsize: "midsize",
    fullsize: "fullsize",
    suv: "suv",

    van: "van",

    luxury: "luxury"

  }

  scope :recent, -> { order(created_at: :desc) }

  def same_location?

    dropoff_location.blank? || dropoff_location == pickup_location

  end

  def rental_days
    (dropoff_date - pickup_date).to_i
  end

  def search_params

    {
      pickup_location: pickup_location,

      dropoff_location: dropoff_location || pickup_location,

      pickup_date: pickup_date,
      dropoff_date: dropoff_date,

      car_type: car_type

    }

  end

end

EOF

  log "CarSearch model configured"

}

generate_price_alert_model() {

  log "Configuring PriceAlert model"

  cat <<'EOF' > app/models/price_alert.rb
class PriceAlert < ApplicationRecord

  belongs_to :user
  belongs_to :alertable, polymorphic: true

  validates :target_price, presence: true, numericality: { greater_than: 0 }
  scope :active, -> { where(active: true) }

  scope :triggered, -> { active.where("current_price <= target_price") }

  def check_price!(new_price)

    update(current_price: new_price)
    if new_price <= target_price && active?
      trigger_alert!

    end
  end

  def trigger_alert!
    # PriceAlertMailer.price_drop(self).deliver_later

    # Send push notification

  end

  def price_drop_percentage
    return 0 unless current_price && target_price

    ((target_price - current_price) / target_price * 100).round(2)

  end

end
EOF

  log "PriceAlert model configured"
}

generate_travel_deal_model() {

  log "Configuring TravelDeal model"

  cat <<'EOF' > app/models/travel_deal.rb
class TravelDeal < ApplicationRecord

  validates :deal_type, :title, :price, :currency, presence: true
  enum deal_type: {

    flight: "flight",
    hotel: "hotel",

    package: "package",

    car: "car",
    activity: "activity"

  }

  scope :active, -> { where("valid_until >= ?", Date.today) }

  scope :by_type, ->(type) { where(deal_type: type) }

  scope :by_destination, ->(destination) { where("destination ILIKE ?", "%#{destination}%") }

  scope :by_price, ->(max_price) { where("price <= ?", max_price) }

  scope :featured, -> { active.order(created_at: :desc).limit(10) }
  def expired?

    valid_until && valid_until < Date.today

  end

  def days_remaining

    return 0 if expired?
    (valid_until - Date.today).to_i

  end

  def formatted_price
    "#{currency} #{price}"

  end

end

EOF
  log "TravelDeal model configured"

}

generate_search_history_model() {

  log "Configuring SearchHistory model"

  cat <<'EOF' > app/models/search_history.rb
class SearchHistory < ApplicationRecord

  belongs_to :user
  belongs_to :searchable, polymorphic: true

  scope :recent, -> { order(executed_at: :desc) }
  scope :by_type, ->(type) { where(searchable_type: type) }

  def self.track(user, searchable)

    create(

      user: user,
      searchable: searchable,

      search_params: searchable.search_params,
      executed_at: Time.current

    )

  end

  def search_type

    searchable_type.demodulize.underscore.humanize

  end

end

EOF
  log "SearchHistory model configured"

}

generate_flight_searches_controller() {

  log "Generating FlightSearchesController"

  cat <<'EOF' > app/controllers/flight_searches_controller.rb
class FlightSearchesController < ApplicationController

  def new
    @flight_search = FlightSearch.new

    @popular_routes = FlightSearch.popular_routes
  end

  def create

    @flight_search = FlightSearch.new(flight_search_params)

    @flight_search.user = current_user if current_user

    if @flight_search.save

      SearchHistory.track(current_user, @flight_search) if current_user
      redirect_to flight_search_results_path(@flight_search)

    else

      render :new, status: :unprocessable_entity
    end

  end

  def show

    @flight_search = FlightSearch.find(params[:id])

    # In production, integrate with flight API (Skyscanner, Amadeus, etc)

    @results = mock_flight_results(@flight_search)

  end
  private

  def flight_search_params

    params.require(:flight_search).permit(:origin, :destination, :departure_date,

                                          :return_date, :passengers, :cabin_class,

                                          :flexible_dates)
  end
  def mock_flight_results(search)

    # Mock data for development

    [

      { airline: "Norwegian", price: 299, duration: "2h 15m", stops: 0 },

      { airline: "SAS", price: 450, duration: "2h 30m", stops: 0 },
      { airline: "KLM", price: 350, duration: "4h 10m", stops: 1 }

    ]

  end

end

EOF

  log "FlightSearchesController generated"

}

generate_hotel_searches_controller() {

  log "Generating HotelSearchesController"

  cat <<'EOF' > app/controllers/hotel_searches_controller.rb
class HotelSearchesController < ApplicationController

  def new
    @hotel_search = HotelSearch.new

    @popular_destinations = HotelSearch.popular_destinations
  end

  def create

    @hotel_search = HotelSearch.new(hotel_search_params)

    @hotel_search.user = current_user if current_user

    if @hotel_search.save

      SearchHistory.track(current_user, @hotel_search) if current_user
      redirect_to hotel_search_results_path(@hotel_search)

    else

      render :new, status: :unprocessable_entity
    end

  end

  def show

    @hotel_search = HotelSearch.find(params[:id])

    # In production, integrate with hotel API (Booking.com, Hotels.com, etc)

    @results = mock_hotel_results(@hotel_search)

  end
  private

  def hotel_search_params

    params.require(:hotel_search).permit(:city, :check_in, :check_out,

                                         :guests, :rooms, :stars)

  end
  def mock_hotel_results(search)
    [

      { name: "Grand Hotel", stars: 5, price: 250, rating: 9.2 },

      { name: "Central Inn", stars: 4, price: 120, rating: 8.5 },

      { name: "Budget Stay", stars: 3, price: 80, rating: 7.8 }
    ]

  end

end

EOF

  log "HotelSearchesController generated"

}

generate_price_alerts_controller() {

  log "Generating PriceAlertsController"

  cat <<'EOF' > app/controllers/price_alerts_controller.rb
class PriceAlertsController < ApplicationController

  before_action :authenticate_user!
  def index

    @price_alerts = current_user.price_alerts.active.includes(:alertable)
  end

  def create

    @alertable = find_alertable
    @price_alert = @alertable.price_alerts.build(price_alert_params)

    @price_alert.user = current_user

    @price_alert.active = true
    if @price_alert.save

      respond_to do |format|

        format.turbo_stream

        format.html { redirect_back(fallback_location: root_path, notice: "Price alert created") }

      end
    else

      redirect_back(fallback_location: root_path, alert: "Could not create alert")

    end

  end

  def destroy

    @price_alert = current_user.price_alerts.find(params[:id])

    @price_alert.destroy

    respond_to do |format|

      format.turbo_stream
      format.html { redirect_to price_alerts_path, notice: "Alert removed" }

    end

  end
  private

  def find_alertable

    alertable_type = params[:alertable_type].classify

    alertable_id = params[:alertable_id]

    alertable_type.constantize.find(alertable_id)
  end
  def price_alert_params

    params.require(:price_alert).permit(:target_price)

  end

end

EOF
  log "PriceAlertsController generated"

}

generate_travel_deals_controller() {

  log "Generating TravelDealsController"

  cat <<'EOF' > app/controllers/travel_deals_controller.rb
class TravelDealsController < ApplicationController

  def index
    @deals = TravelDeal.active

    @deals = @deals.by_type(params[:type]) if params[:type].present?
    @deals = @deals.by_destination(params[:destination]) if params[:destination].present?

    @deals = @deals.by_price(params[:max_price]) if params[:max_price].present?

    @deals = @deals.page(params[:page])

  end

  def show

    @deal = TravelDeal.find(params[:id])

  end

end

EOF
  log "TravelDealsController generated"

}

generate_search_form_partial() {

  log "Generating multi-tab search form partial"

  mkdir -p app/views/shared
  cat <<'EOF' > app/views/shared/_travel_search.html.erb

<%= tag.div class: "travel-search", data: { controller: "tabs" } do %>
  <%= tag.div class: "search-tabs" do %>

    <%= tag.button "Flights", class: "tab-btn active", data: { action: "click->tabs#switch", tabs_target: "tab", tab: "flights" } %>
    <%= tag.button "Hotels", class: "tab-btn", data: { action: "click->tabs#switch", tabs_target: "tab", tab: "hotels" } %>
    <%= tag.button "Cars", class: "tab-btn", data: { action: "click->tabs#switch", tabs_target: "tab", tab: "cars" } %>

    <%= tag.button "Deals", class: "tab-btn", data: { action: "click->tabs#switch", tabs_target: "tab", tab: "deals" } %>

  <% end %>

  <%= tag.div class: "tab-content active", data: { tabs_target: "content", tab: "flights" } do %>

    <%= render partial: "flight_searches/form" %>

  <% end %>

  <%= tag.div class: "tab-content", data: { tabs_target: "content", tab: "hotels" } do %>

    <%= render partial: "hotel_searches/form" %>
  <% end %>

  <%= tag.div class: "tab-content", data: { tabs_target: "content", tab: "cars" } do %>

    <%= render partial: "car_searches/form" %>
  <% end %>

  <%= tag.div class: "tab-content", data: { tabs_target: "content", tab: "deals" } do %>

    <%= render partial: "travel_deals/featured" %>
  <% end %>

<% end %>

EOF
  log "Travel search form partial generated"

}

generate_price_comparison_partial() {

  log "Generating price comparison partial"

  cat <<'EOF' > app/views/shared/_price_comparison.html.erb
<%= tag.div class: "price-comparison" do %>

  <%= tag.h3 "Price Comparison" %>
  <%= tag.div class: "providers" do %>

    <% providers.each do |provider| %>
      <%= tag.div class: "provider-card" do %>

        <%= tag.div class: "provider-logo" do %>

          <%= image_tag provider[:logo], alt: provider[:name] if provider[:logo] %>
        <% end %>

        <%= tag.div class: "provider-info" do %>

          <%= tag.span provider[:name], class: "provider-name" %>

          <%= tag.span provider[:price], class: "provider-price" %>

        <% end %>

        <%= link_to "Book Now", provider[:url], class: "btn-book", target: "_blank", rel: "noopener" %>
        <% if current_user %>

          <%= button_to "Create Alert", price_alerts_path(alertable_type: alertable.class.name, alertable_id: alertable.id, price_alert: { target_price: provider[:price] * 0.9 }), class: "btn-alert-sm" %>

        <% end %>

      <% end %>
    <% end %>
  <% end %>

<% end %>

EOF

  log "Price comparison partial generated"

}

generate_flexible_dates_stimulus() {

  log "Generating Stimulus controller for flexible dates"

  mkdir -p app/javascript/controllers
  cat <<'EOF' > app/javascript/controllers/flexible_dates_controller.js

import { Controller } from "@hotwired/stimulus"
export default class extends Controller {

  static targets = ["calendar", "dateInput", "priceChart"]
  connect() {
    this.loadFlexiblePrices()

  }
  async loadFlexiblePrices() {

    const baseDate = this.dateInputTarget.value
    if (!baseDate) return

    // In production, fetch from API

    const prices = this.mockFlexiblePrices(baseDate)
    this.renderPriceCalendar(prices)

  }

  mockFlexiblePrices(baseDate) {
    const prices = {}

    const base = new Date(baseDate)

    for (let i = -3; i <= 3; i++) {

      const date = new Date(base)
      date.setDate(date.getDate() + i)

      const dateStr = date.toISOString().split('T')[0]

      prices[dateStr] = 300 + Math.random() * 200
    }

    return prices

  }

  renderPriceCalendar(prices) {

    const html = Object.entries(prices).map(([date, price]) => {

      const priceClass = price < 350 ? 'low-price' : price < 400 ? 'medium-price' : 'high-price'
      return `

        <div class="date-price ${priceClass}" data-date="${date}">
          <span class="date">${date}</span>

          <span class="price">€${Math.round(price)}</span>

        </div>

      `

    }).join('')

    this.priceChartTarget.innerHTML = html

  }

}

EOF

  log "Flexible dates Stimulus controller generated"
}

add_momondo_routes() {

  log "Adding Momondo travel search routes"

  local routes_file="config/routes.rb"
  local temp_file="${routes_file}.tmp"

  # Pure zsh route handling
  cat <<'EOF' >> "$temp_file"

  # Momondo travel search features
  resources :flight_searches, only: [:new, :create, :show] do

    get :results, on: :member, to: 'flight_searches#show'
  end

  resources :hotel_searches, only: [:new, :create, :show] do
    get :results, on: :member, to: 'hotel_searches#show'

  end

  resources :car_searches, only: [:new, :create, :show]

  resources :price_alerts, only: [:index, :create, :destroy]
  resources :travel_deals, only: [:index, :show]

  get '/search', to: 'search#index', as: :search

end
EOF

  mv "$temp_file" "$routes_file"

  log "Momondo routes added"

}

setup_travel_search_features() {

  setup_momondo_models
  generate_flight_search_model
  generate_hotel_search_model

  generate_car_search_model
  generate_price_alert_model

  generate_travel_deal_model

  generate_search_history_model

  generate_flight_searches_controller

  generate_hotel_searches_controller

  generate_price_alerts_controller

  generate_travel_deals_controller

  generate_search_form_partial

  generate_price_comparison_partial

  generate_flexible_dates_stimulus

  add_momondo_routes

  log "Momondo travel search features fully configured!"

}

