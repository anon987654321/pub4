# frozen_string_literal: true

require "zlib"

class Takeaway::Restaurant < ApplicationRecord
  include CityTenantable
  include Shared::Sluggable # /restaurants/<name-slug>; from :name, unique per city
  sluggable_from :name
  include Shared::StrictSafeAssociations

  include Shared::Notifiable
  include Shared::Reactable
  include Shared::GeoLocatable
  tracks_activity created: "TakeawayRestaurantCreated", updated: "TakeawayRestaurantUpdated", source_vertical: "takeaway", actor: :user

  belongs_to :user
  belongs_to :place, optional: true
  has_many :menu_items, class_name: "Takeaway::MenuItem", dependent: :destroy
  has_many :orders, class_name: "Takeaway::Order", dependent: :destroy
  has_many :favorites, class_name: "Takeaway::FavoriteRestaurant", dependent: :destroy
  has_many :reviews, class_name: "Takeaway::Review", dependent: :destroy
  has_many :opening_hours, class_name: "Takeaway::OpeningHour", dependent: :destroy

  CUISINE_TYPES = %w[Norwegian Italian Chinese Japanese Indian Thai Mexican Pizza Burger Kebab Sushi Vegetarian Vegan].freeze
  CENTS_PER_KRONE = 100.0

  validates :name, :address, :cuisine_type, presence: true
  validates :delivery_fee_cents, :min_order_cents,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  before_validation :geocode_if_needed

  scope :active, -> { where(active: true) }
  scope :popular, -> { order(rating: :desc) }
  scope :near, ->(lat, lng, radius_km = 5) { nearby(lat, lng, radius_km) }

# A restaurant with no hours recorded is treated as open, not shut: most of
# them have none yet, and defaulting to closed would empty the listing.
# `active` remains the switch for "not taking orders at all".
def open_now?(moment = Time.current)
  return false unless active?
  return true unless Takeaway::OpeningHour.exists?(restaurant_id: id)

  Takeaway::OpeningHour.open_at?(id, moment)
end

# An order for later is still allowed while the kitchen is shut — that is
# most of what scheduling is for.
def accepting_orders?(scheduled_for: nil)
  return active? if scheduled_for.present?

  open_now?
end

def hours_for(wday) = opening_hours.for_weekday(wday).order(:opens_minute)

  def owner?(account)
    user_id == account&.id
  end

  # This is the one table carrying both a `city` string column and a `city_id`.
  # CityTenantable's belongs_to shadows the column reader, so `restaurant.city`
  # in a view renders a City object — or raises on strict loading when the
  # query did not preload it. Views want the label, so name it.
  def city_label
    strict_safe_attribute(:city, :name).presence || self[:city].presence
  end

  def delivery_fee_display
    Shared::MoneyDisplay.format(delivery_fee_cents)
  end

  def min_order_display
    Shared::MoneyDisplay.format(min_order_cents)
  end

  def update_rating!
    avg = reviews.average(:rating)
    # updated_at with it -- same reason as Marketplace::Listing#update_rating!:
    # the rating is displayed, so the fragment cache has to see the write.
    update_columns(rating: avg&.round(1) || 0, updated_at: Time.current)
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
