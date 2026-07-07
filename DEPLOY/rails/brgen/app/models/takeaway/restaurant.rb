# frozen_string_literal: true

require "zlib"

class Takeaway::Restaurant < ApplicationRecord
  include CityTenantable

  # Engine-ized Shared concerns (via pub4-shared)
  include Shared.concern(:Notifiable) rescue nil
  include Shared.concern(:Reactable) rescue nil
  include Shared.concern(:GeoLocatable) rescue nil
  include Shared.concern(:ActivityTrackable) rescue nil
  tracks_activity created: "TakeawayRestaurantCreated", updated: "TakeawayRestaurantUpdated", source_vertical: "takeaway", actor: :user

  belongs_to :user
  has_many :menu_items, class_name: "Takeaway::MenuItem", dependent: :destroy
  has_many :orders, class_name: "Takeaway::Order", dependent: :destroy
  has_many :favorites, class_name: "Takeaway::FavoriteRestaurant", dependent: :destroy
  has_many :reviews, class_name: "Takeaway::Review", dependent: :destroy

  CUISINE_TYPES = %w[Norwegian Italian Chinese Japanese Indian Thai Mexican Pizza Burger Kebab Sushi Vegetarian Vegan].freeze
  CENTS_PER_KRONE = 100.0

  validates :name, :address, :cuisine_type, presence: true
  validates :delivery_fee_cents, :min_order_cents,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  before_validation :geocode_if_needed

  scope :active, -> { where(active: true) }
  scope :popular, -> { order(rating: :desc) }
  scope :near, ->(lat, lng, radius_km = 5) { nearby(lat, lng, radius_km) }

  include Shared::GeoLocatable

  def owner?(account)
    user_id == account&.id
  end

  def delivery_fee_display
    format("%.2f NOK", delivery_fee_cents.to_i / CENTS_PER_KRONE)
  end

  def min_order_display
    format("%.2f NOK", min_order_cents.to_i / CENTS_PER_KRONE)
  end

  def update_rating!
    avg = reviews.average(:rating)
    update_columns(rating: avg&.round(1) || 0)
  end

  def geocode!
    anchor = geocode_anchor
    return super unless anchor

    lat_offset, lng_offset = stable_coordinate_offsets
    self.latitude = anchor.latitude.to_f + lat_offset
    self.longitude = anchor.longitude.to_f + lng_offset
    self
  end

  private

  def geocode_if_needed
    return if latitude.present? && longitude.present?
    return if address.blank? && self[:city].blank?

    geocode!
  end

  def geocode_anchor
    City.find_by(id: self[:city_id]) || Current.city_record || City.find_by("lower(name) = ?", self[:city].to_s.downcase)
  end

  def stable_coordinate_offsets
    seed = Zlib.crc32([ address, self[:city], name ].join("|"))
    lat = ((seed % 2_000) - 1_000) / 100_000.0
    lng = (((seed / 2_000) % 2_000) - 1_000) / 100_000.0
    [ lat, lng ]
  end
end
