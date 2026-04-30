#!/usr/bin/env zsh
# __shared/@airbnb_features.sh — Airbnb-style rental models for Rails 8
# Source from app installers. Do not execute directly.
set -euo pipefail

setup_airbnb_models() {
  log "Setting up Airbnb rental models"

  generate_model Listing \
    title:string description:text \
    price_per_night:decimal max_guests:integer \
    location:string latitude:float longitude:float \
    user:references

  generate_model Booking \
    listing:references user:references \
    check_in:date check_out:date \
    guests_count:integer total_price:decimal \
    status:string

  generate_model Review \
    listing:references user:references \
    rating:integer content:text \
    cleanliness:integer accuracy:integer \
    communication:integer location:integer value:integer

  generate_model Availability \
    listing:references date:date available:boolean price_override:decimal

  generate_model Amenity name:string category:string icon:string

  generate_model ListingAmenity listing:references amenity:references

  log_ok "Airbnb models ready"
}

write_airbnb_model_logic() {
  cat > app/models/listing.rb << 'RUBY'
class Listing < ApplicationRecord
  belongs_to :user
  has_many :bookings, dependent: :destroy
  has_many :reviews, dependent: :destroy
  has_many :availabilities, dependent: :destroy
  has_many :listing_amenities, dependent: :destroy
  has_many :amenities, through: :listing_amenities
  has_many_attached :photos

  validates :title, :price_per_night, :max_guests, :location, presence: true
  validates :price_per_night, numericality: { greater_than: 0 }
  validates :max_guests, numericality: { only_integer: true, greater_than: 0 }

  scope :available_between, ->(check_in, check_out) {
    where.not(id: Booking.confirmed.select(:listing_id)
      .where("check_in < ? AND check_out > ?", check_out, check_in))
  }

  def average_rating
    reviews.average(:rating)&.round(1) || 0
  end

  def available_on?(date)
    availabilities.find_by(date: date)&.available != false
  end
end
RUBY

  cat > app/models/booking.rb << 'RUBY'
class Booking < ApplicationRecord
  belongs_to :listing
  belongs_to :user

  STATUSES = %w[pending confirmed cancelled completed].freeze

  validates :check_in, :check_out, :guests_count, :total_price, :status, presence: true
  validates :guests_count, numericality: { only_integer: true, greater_than: 0 }
  validates :total_price, numericality: { greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: STATUSES }
  validate :check_out_after_check_in
  validate :guests_within_capacity

  scope :confirmed, -> { where(status: "confirmed") }
  scope :upcoming, -> { where("check_in >= ?", Date.today).order(:check_in) }

  before_validation :calculate_total_price, on: :create

  private

  def check_out_after_check_in
    return if check_in.blank? || check_out.blank?
    errors.add(:check_out, "must be after check-in") if check_out <= check_in
  end

  def guests_within_capacity
    return unless listing && guests_count
    if guests_count > listing.max_guests
      errors.add(:guests_count, "exceeds listing capacity")
    end
  end

  def calculate_total_price
    return unless listing && check_in && check_out
    nights = (check_out - check_in).to_i
    self.total_price = nights * listing.price_per_night
  end
end
RUBY

  cat > app/models/review.rb << 'RUBY'
class Review < ApplicationRecord
  belongs_to :listing
  belongs_to :user

  RATING_FIELDS = %i[rating cleanliness accuracy communication location value].freeze

  validates :content, presence: true, length: { maximum: 2000 }
  RATING_FIELDS.each do |field|
    validates field, numericality: { in: 1..5 }, allow_nil: true
  end
  validates :rating, presence: true

  after_create_commit :broadcast_to_listing

  private

  def broadcast_to_listing
    broadcast_append_to listing, target: "reviews"
  end
end
RUBY
  log_ok "Airbnb model logic written"
}
