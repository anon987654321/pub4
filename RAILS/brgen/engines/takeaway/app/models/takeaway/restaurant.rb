# frozen_string_literal: true

# Coordinates come only from the owner's form or a seed that names them. There
# is no geocoder, so a restaurant without real coordinates has none: a pin near
# the city centre would be published as its location, and every reader of
# latitude — the nearby list, the near filter, courier distance and courier
# dispatch — already handles nil, dispatch by leaving the order unassigned.
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

  scope :active, -> { where(active: true) }
  scope :popular, -> { order(rating: :desc) }
  scope :near, ->(lat, lng, radius_km = 5) { nearby(lat, lng, radius_km) }

  # What a search engine may be told about. A demo restaurant — `demo` is set by
  # the seeders, never by an owner's form — keeps its page but is not presented
  # as a business: no sitemap entry, no LocalBusiness, and noindex on the page.
  scope :indexable, -> { active.where(demo: false) }

  # Open only when recorded hours say so. A restaurant with no hours is not
  # known to be open, so it is not reported open; hours_known? tells that apart
  # from shut.
  def open_now?(moment = Time.current)
    return false unless active? && hours_known?

    Takeaway::OpeningHour.open_at?(id, moment)
  end

  def hours_known? = Takeaway::OpeningHour.exists?(restaurant_id: id)

  # An order for later is still allowed while the kitchen is shut — that is
  # most of what scheduling is for. With no hours recorded the kitchen has said
  # nothing about when it cooks, so `active` alone decides: most restaurants
  # have no hours yet, and refusing their orders would empty the vertical.
  def accepting_orders?(scheduled_for: nil)
    return active? if scheduled_for.present? || !hours_known?

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
end
