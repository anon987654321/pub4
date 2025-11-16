#!/usr/bin/env zsh
set -euo pipefail

# Airbnb marketplace features: Bookings, Reviews, Host Profiles, Calendar, Pricing
# Shared across marketplace apps (brgen listings, hjerterom)

setup_airbnb_models() {
  log "Setting up Airbnb models: Booking, Review, Availability, HostProfile"

  # Booking model for reservations
  bin/rails generate model Booking listing:references guest:references{user} host:references{user} check_in:date check_out:date guests_count:integer total_price:decimal status:string

  # Review model (guests review listings, hosts review guests)
  bin/rails generate model Review reviewable:references{polymorphic} reviewer:references{user} rating:integer content:text cleanliness:integer accuracy:integer communication:integer location:integer value:integer

  # Availability calendar for listings
  bin/rails generate model Availability listing:references date:date available:boolean price_override:decimal

  # Host profile with verification
  bin/rails generate model HostProfile user:references bio:text response_rate:decimal response_time:integer verified:boolean joined_date:date languages:string superhost:boolean

  # Amenity model
  bin/rails generate model Amenity name:string category:string icon:string

  # Join table for listing amenities
  bin/rails generate model ListingAmenity listing:references amenity:references

  log "Airbnb models generated"
}

generate_booking_model() {
  log "Configuring Booking model"

  cat <<'EOF' > app/models/booking.rb
class Booking < ApplicationRecord

  belongs_to :listing
  belongs_to :guest, class_name: "User"

  belongs_to :host, class_name: "User"

  validates :check_in, :check_out, :guests_count, :total_price, :status, presence: true

  validate :check_out_after_check_in

  validate :listing_available
  validate :within_max_guests

  enum status: {

    pending: "pending",

    accepted: "accepted",
    declined: "declined",

    cancelled: "cancelled",

    completed: "completed"

  }

  scope :upcoming, -> { where("check_in > ?", Date.today).where(status: [:accepted, :pending]) }

  scope :past, -> { where("check_out < ?", Date.today).where(status: [:completed]) }

  scope :current, -> { where("check_in <= ? AND check_out >= ?", Date.today, Date.today).where(status: :accepted) }
  def nights

    (check_out - check_in).to_i

  end
  def calculate_total_price

    return 0 if nights <= 0

    total = 0
    (check_in...check_out).each do |date|

      availability = listing.availabilities.find_by(date: date)
      price = availability&.price_override || listing.price

      total += price

    end

    total

  end

  def overlaps?(other_booking)

    check_in < other_booking.check_out && check_out > other_booking.check_in

  end
  private

  def check_out_after_check_in

    return unless check_in && check_out
    errors.add(:check_out, "must be after check-in") if check_out <= check_in
  end

  def listing_available

    return unless check_in && check_out

    # Check for conflicting bookings
    conflicting = listing.bookings.where(status: [:accepted, :pending])

                        .where.not(id: id)
                        .where("check_in < ? AND check_out > ?", check_out, check_in)

    errors.add(:base, "Listing not available for these dates") if conflicting.exists?

  end

  def within_max_guests
    return unless listing && guests_count

    errors.add(:guests_count, "exceeds maximum") if guests_count > listing.max_guests
  end

end

EOF

  log "Booking model configured"

}

generate_review_model() {
  log "Configuring Review model"

  cat <<'EOF' > app/models/review.rb
class Review < ApplicationRecord

  belongs_to :reviewable, polymorphic: true
  belongs_to :reviewer, class_name: "User"

  validates :rating, presence: true, inclusion: { in: 1..5 }

  validates :content, presence: true, length: { minimum: 20, maximum: 1000 }

  validates :reviewer_id, uniqueness: { scope: [:reviewable_type, :reviewable_id] }
  # For listing reviews

  validates :cleanliness, :accuracy, :communication, :location, :value,

            inclusion: { in: 1..5 }, allow_nil: true
  scope :recent, -> { order(created_at: :desc) }

  scope :top_rated, -> { where("rating >= 4").order(rating: :desc, created_at: :desc) }

  def overall_rating
    return rating unless reviewable_type == "Listing"

    [cleanliness, accuracy, communication, location, value, rating].compact.sum.to_f / 6
  end

end
EOF

  log "Review model configured"

}

generate_availability_model() {
  log "Configuring Availability model"

  cat <<'EOF' > app/models/availability.rb
class Availability < ApplicationRecord

  belongs_to :listing
  validates :date, presence: true, uniqueness: { scope: :listing_id }

  scope :available, -> { where(available: true) }

  scope :unavailable, -> { where(available: false) }
  scope :in_range, ->(start_date, end_date) { where(date: start_date..end_date) }
  def self.generate_for_listing(listing, months_ahead: 12)

    start_date = Date.today

    end_date = start_date + months_ahead.months
    (start_date..end_date).each do |date|

      find_or_create_by(listing: listing, date: date) do |availability|

        availability.available = true
        availability.price_override = nil

      end

    end

  end

end

EOF

  log "Availability model configured"

}

generate_host_profile_model() {
  log "Configuring HostProfile model"

  cat <<'EOF' > app/models/host_profile.rb
class HostProfile < ApplicationRecord

  belongs_to :user
  validates :user_id, uniqueness: true

  def response_rate_percentage

    (response_rate * 100).round if response_rate
  end
  def response_time_text

    return "Within an hour" if response_time && response_time < 60

    return "Within a day" if response_time && response_time < 1440
    "Within a few days"

  end

end

EOF

  log "HostProfile model configured"

}

generate_amenity_model() {
  log "Configuring Amenity model"

  cat <<'EOF' > app/models/amenity.rb
class Amenity < ApplicationRecord

  has_many :listing_amenities, dependent: :destroy
  has_many :listings, through: :listing_amenities

  validates :name, presence: true, uniqueness: true

  validates :category, presence: true

  scope :by_category, ->(category) { where(category: category) }
  CATEGORIES = ["basics", "facilities", "safety", "accessibility"].freeze

end
EOF
  log "Amenity model configured"

}

generate_reviewable_concern() {
  log "Generating Reviewable concern"

  mkdir -p app/models/concerns
  cat <<'EOF' > app/models/concerns/reviewable.rb

module Reviewable
  extend ActiveSupport::Concern
  included do

    has_many :reviews, as: :reviewable, dependent: :destroy

  end
  def average_rating

    return 0 if reviews.empty?

    (reviews.average(:rating) || 0).round(2)
  end

  def review_count

    reviews.count

  end
  def reviews_by_rating

    reviews.group(:rating).count

  end
end

EOF

  log "Reviewable concern generated"

}

extend_listing_for_bookings() {
  log "Extending Listing model with booking features"

  cat <<'EOF' >> app/models/listing.rb
  # Airbnb booking features

  include Reviewable
  has_many :bookings, dependent: :destroy
  has_many :availabilities, dependent: :destroy

  has_many :listing_amenities, dependent: :destroy
  has_many :amenities, through: :listing_amenities

  validates :max_guests, presence: true, numericality: { greater_than: 0 }

  validates :price, presence: true, numericality: { greater_than: 0 }

  after_create :generate_availability_calendar
  def available_on?(date)

    availability = availabilities.find_by(date: date)
    return false unless availability&.available
    !bookings.where(status: [:accepted, :pending])

             .where("check_in <= ? AND check_out > ?", date, date)

             .exists?
  end

  def available_between?(start_date, end_date)

    (start_date...end_date).all? { |date| available_on?(date) }

  end
  def host

    user

  end
  private

  def generate_availability_calendar

    Availability.generate_for_listing(self)
  end
EOF

  log "Listing extended with booking features"

}

extend_user_for_hosting() {
  log "Extending User model with host features"

  cat <<'EOF' >> app/models/user.rb
  # Airbnb host features

  has_one :host_profile, dependent: :destroy
  has_many :hosted_listings, class_name: "Listing", dependent: :destroy
  has_many :bookings_as_guest, class_name: "Booking", foreign_key: :guest_id, dependent: :destroy

  has_many :bookings_as_host, class_name: "Booking", foreign_key: :host_id, dependent: :destroy

  def is_host?

    hosted_listings.any?

  end
  def become_host!

    create_host_profile(joined_date: Date.today) unless host_profile

  end
  def hosting_stats

    {

      total_bookings: bookings_as_host.where(status: :completed).count,
      total_reviews: hosted_listings.sum { |l| l.review_count },

      average_rating: hosted_listings.sum { |l| l.average_rating } / [hosted_listings.count, 1].max

    }

  end

EOF

  log "User extended with host features"

}

generate_bookings_controller() {
  log "Generating BookingsController"

  cat <<'EOF' > app/controllers/bookings_controller.rb
class BookingsController < ApplicationController

  before_action :authenticate_user!
  before_action :set_listing, only: [:new, :create]

  before_action :set_booking, only: [:show, :accept, :decline, :cancel]

  def index

    @bookings_as_guest = current_user.bookings_as_guest.order(check_in: :desc)

    @bookings_as_host = current_user.bookings_as_host.order(check_in: :desc)
  end

  def show

  end

  def new
    @booking = @listing.bookings.build

  end
  def create

    @booking = @listing.bookings.build(booking_params)

    @booking.guest = current_user
    @booking.host = @listing.user

    @booking.status = :pending

    @booking.total_price = @booking.calculate_total_price

    if @booking.save

      # BookingMailer.booking_request(@booking).deliver_later

      redirect_to booking_path(@booking), notice: "Booking request sent"
    else

      render :new, status: :unprocessable_entity

    end

  end

  def accept

    authorize_host!

    if @booking.update(status: :accepted)
      # BookingMailer.booking_accepted(@booking).deliver_later

      redirect_to booking_path(@booking), notice: "Booking accepted"
    else

      redirect_to booking_path(@booking), alert: "Could not accept booking"

    end

  end

  def decline

    authorize_host!

    if @booking.update(status: :declined)
      # BookingMailer.booking_declined(@booking).deliver_later

      redirect_to booking_path(@booking), notice: "Booking declined"
    else

      redirect_to booking_path(@booking), alert: "Could not decline booking"

    end

  end

  def cancel

    if current_user == @booking.guest

      if @booking.update(status: :cancelled)
        # BookingMailer.booking_cancelled_by_guest(@booking).deliver_later

        redirect_to bookings_path, notice: "Booking cancelled"

      else

        redirect_to booking_path(@booking), alert: "Could not cancel booking"

      end

    else

      redirect_to booking_path(@booking), alert: "Not authorized"

    end

  end

  private

  def set_listing

    @listing = Listing.find(params[:listing_id])
  end
  def set_booking

    @booking = Booking.find(params[:id])

  end
  def authorize_host!

    redirect_to root_path, alert: "Not authorized" unless current_user == @booking.host

  end
  def booking_params

    params.require(:booking).permit(:check_in, :check_out, :guests_count)

  end
end

EOF

  log "BookingsController generated"

}

generate_reviews_controller() {
  log "Generating ReviewsController"

  cat <<'EOF' > app/controllers/reviews_controller.rb
class ReviewsController < ApplicationController

  before_action :authenticate_user!
  before_action :set_reviewable

  def new

    @review = @reviewable.reviews.build

  end
  def create

    @review = @reviewable.reviews.build(review_params)

    @review.reviewer = current_user
    if @review.save

      respond_to do |format|

        format.turbo_stream
        format.html { redirect_to polymorphic_path(@reviewable), notice: "Review posted" }

      end

    else

      render :new, status: :unprocessable_entity

    end

  end

  private

  def set_reviewable

    reviewable_type = params[:reviewable_type].classify
    reviewable_id = params[:reviewable_id]
    @reviewable = reviewable_type.constantize.find(reviewable_id)

  end

  def review_params

    params.require(:review).permit(:rating, :content, :cleanliness, :accuracy,

                                   :communication, :location, :value)
  end

end

EOF

  log "ReviewsController generated"

}

generate_host_profiles_controller() {
  log "Generating HostProfilesController"

  cat <<'EOF' > app/controllers/host_profiles_controller.rb
class HostProfilesController < ApplicationController

  before_action :authenticate_user!, only: [:new, :create, :edit, :update]
  def show

    @user = User.find(params[:id])

    @host_profile = @user.host_profile
    @listings = @user.hosted_listings

  end

  def new

    @host_profile = current_user.build_host_profile

  end
  def create

    current_user.become_host!

    @host_profile = current_user.host_profile
    @host_profile.attributes = host_profile_params

    if @host_profile.save

      redirect_to host_profile_path(current_user), notice: "Welcome to hosting!"

    else
      render :new, status: :unprocessable_entity

    end

  end

  def edit

    @host_profile = current_user.host_profile

  end
  def update

    @host_profile = current_user.host_profile

    if @host_profile.update(host_profile_params)
      redirect_to host_profile_path(current_user), notice: "Profile updated"

    else
      render :edit, status: :unprocessable_entity

    end

  end

  private

  def host_profile_params

    params.require(:host_profile).permit(:bio, :languages)
  end
end

EOF

  log "HostProfilesController generated"

}

generate_booking_calendar_partial() {
  log "Generating booking calendar partial"

  mkdir -p app/views/shared
  cat <<'EOF' > app/views/shared/_booking_calendar.html.erb

<%= tag.div class: "booking-calendar", data: { controller: "calendar" } do %>
  <%= tag.h3 "Select Dates" %>
  <%= form_with model: [@listing, Booking.new], class: "booking-form" do |form| %>

    <%= tag.div class: "form-field" do %>

      <%= form.label :check_in, "Check-in" %>
      <%= form.date_field :check_in, required: true, min: Date.today,

          data: { action: "change->calendar#updateAvailability" } %>

    <% end %>

    <%= tag.div class: "form-field" do %>

      <%= form.label :check_out, "Check-out" %>

      <%= form.date_field :check_out, required: true, min: Date.today + 1,
          data: { action: "change->calendar#updateAvailability" } %>

    <% end %>

    <%= tag.div class: "form-field" do %>

      <%= form.label :guests_count, "Guests" %>

      <%= form.number_field :guests_count, required: true, min: 1, max: @listing.max_guests %>
    <% end %>

    <%= tag.div id: "price-breakdown", class: "price-breakdown" do %>

      <% if @listing.price %>

        <%= tag.p "€#{@listing.price} × night" %>
      <% end %>

    <% end %>

    <%= form.submit "Request to Book", class: "btn-primary" %>

  <% end %>

<% end %>
EOF

  log "Booking calendar partial generated"

}

generate_review_partial() {
  log "Generating review partial"

  cat <<'EOF' > app/views/shared/_reviews.html.erb
<%= tag.div class: "reviews-section" do %>

  <%= tag.h3 "Reviews (#{reviewable.review_count})" %>
  <% if reviewable.review_count > 0 %>

    <%= tag.div class: "rating-summary" do %>

      <%= tag.span "⭐ #{reviewable.average_rating}", class: "average-rating" %>
    <% end %>

  <% end %>

  <%= tag.div class: "reviews-list" do %>

    <% reviewable.reviews.recent.limit(10).each do |review| %>

      <%= tag.div class: "review", id: dom_id(review) do %>
        <%= tag.div class: "review-header" do %>

          <%= tag.span review.reviewer.email, class: "reviewer-name" %>

          <%= tag.span "⭐" * review.rating, class: "rating-stars" %>

          <%= tag.span time_ago_in_words(review.created_at), class: "review-time" %>

        <% end %>

        <%= tag.div class: "review-content" do %>

          <%= simple_format review.content %>

        <% end %>
        <% if reviewable.is_a?(Listing) && review.overall_rating %>

          <%= tag.div class: "review-breakdown" do %>

            <%= tag.span "Cleanliness: #{review.cleanliness}/5" %>
            <%= tag.span "Accuracy: #{review.accuracy}/5" %>

            <%= tag.span "Communication: #{review.communication}/5" %>

          <% end %>

        <% end %>

      <% end %>

    <% end %>

  <% end %>

  <% if current_user %>

    <%= link_to "Write a Review", new_review_path(reviewable_type: reviewable.class.name, reviewable_id: reviewable.id), class: "btn-secondary" %>

  <% end %>
<% end %>

EOF

  log "Review partial generated"

}

seed_amenities() {
  log "Seeding standard amenities"

  cat <<'EOF' >> db/seeds.rb
# Airbnb amenities

amenities = [
  { name: "WiFi", category: "basics", icon: "📶" },
  { name: "Kitchen", category: "basics", icon: "🍳" },

  { name: "Washer", category: "basics", icon: "🧺" },

  { name: "Dryer", category: "basics", icon: "🌬" },

  { name: "Air conditioning", category: "basics", icon: "❄️" },

  { name: "Heating", category: "basics", icon: "🔥" },

  { name: "TV", category: "basics", icon: "📺" },

  { name: "Hair dryer", category: "basics", icon: "💇" },

  { name: "Iron", category: "basics", icon: "👔" },

  { name: "Pool", category: "facilities", icon: "🏊" },

  { name: "Hot tub", category: "facilities", icon: "🛁" },

  { name: "Gym", category: "facilities", icon: "🏋" },

  { name: "Parking", category: "facilities", icon: "🚗" },

  { name: "EV charger", category: "facilities", icon: "🔌" },

  { name: "Smoke detector", category: "safety", icon: "🚨" },

  { name: "Carbon monoxide detector", category: "safety", icon: "⚠️" },

  { name: "Fire extinguisher", category: "safety", icon: "🧯" },

  { name: "First aid kit", category: "safety", icon: "⚕️" },

  { name: "Wheelchair accessible", category: "accessibility", icon: "♿" },

  { name: "Step-free entrance", category: "accessibility", icon: "🚪" }

]

amenities.each do |amenity|

  Amenity.find_or_create_by(name: amenity[:name]) do |a|

    a.category = amenity[:category]
    a.icon = amenity[:icon]

  end

end

puts "Created #{Amenity.count} amenities"

EOF

  log "Amenities seeding added to seeds.rb"
}

add_airbnb_routes() {
  log "Adding Airbnb feature routes"

  local routes_file="config/routes.rb"
  local temp_file="${routes_file}.tmp"

  # Pure zsh route handling
  cat <<'EOF' >> "$temp_file"

  # Airbnb marketplace features
  resources :listings do

    resources :bookings, only: [:new, :create]
  end

  resources :bookings, only: [:index, :show] do

    member do

      patch :accept
      patch :decline

      patch :cancel

    end

  end

  resources :reviews, only: [:new, :create]

  resources :host_profiles, only: [:show, :new, :create, :edit, :update]

end
EOF

  mv "$temp_file" "$routes_file"

  log "Airbnb routes added"

}
setup_airbnb_features() {
  setup_airbnb_models

  generate_booking_model
  generate_review_model

  generate_availability_model

  generate_host_profile_model

  generate_amenity_model

  generate_reviewable_concern

  extend_listing_for_bookings

  extend_user_for_hosting

  generate_bookings_controller

  generate_reviews_controller

  generate_host_profiles_controller

  generate_booking_calendar_partial

  generate_review_partial

  seed_amenities

  add_airbnb_routes

  log "Airbnb marketplace features fully configured!"

}

