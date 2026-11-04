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
  include Shared::MediaProcessable
  tracks_activity created: "TakeawayRestaurantCreated", updated: "TakeawayRestaurantUpdated", source_vertical: "takeaway", actor: :user

  belongs_to :user
  belongs_to :place, optional: true
  has_one_attached :cover
  process_media_variants :cover, variants: {
    card: { resize_to_limit: [ 960, 640 ], format: :webp },
    hero: { resize_to_limit: [ 1_600, 1_000 ], format: :webp },
  }
  # Order history is a receipt, not a child resource the restaurant owner can erase. It is declared
  # before menu_items because dependent callbacks run in declaration order: the refusal has to come
  # first, or destroy deletes menu items that order_items still reference and the database raises.
  has_many :orders, class_name: "Takeaway::Order", dependent: :restrict_with_error
  has_many :menu_items, class_name: "Takeaway::MenuItem", dependent: :destroy
  has_many :menu_categories, class_name: "Takeaway::MenuCategory", dependent: :destroy
  has_many :favorites, class_name: "Takeaway::FavoriteRestaurant", dependent: :destroy
  has_many :reviews, class_name: "Takeaway::Review", dependent: :destroy
  has_many :opening_hours, class_name: "Takeaway::OpeningHour", dependent: :destroy

  CUISINE_TYPES = %w[Norwegian Italian Chinese Japanese Indian Thai Mexican Pizza Burger Kebab Sushi Vegetarian Vegan].freeze
  CENTS_PER_KRONE = 100.0

  # Upper bound on a stated delivery radius. Bergen end to end is about 10 km
  # (see Order::Delivery::DISPATCH_RADIUS_KM), so anything beyond this reads as
  # a typo rather than an ambition; the form enforces the same ceiling.
  MAX_DELIVERY_RADIUS_KM = 50

  MAX_COVER_BYTES = 8.megabytes
  COVER_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze

  validates :name, :address, :cuisine_type, presence: true
  validate :cover_must_be_a_supported_image
  validates :delivery_fee_cents, :min_order_cents,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :delivery_radius_km,
            numericality: { greater_than: 0, less_than_or_equal_to: MAX_DELIVERY_RADIUS_KM },
            allow_nil: true

  scope :active, -> { where(active: true) }
  scope :publicly_visible, -> { active.joins(:user).where(users: { deleted_at: nil, deletion_scheduled_at: nil }) }
  scope :popular, -> { order(rating: :desc, updated_at: :desc, id: :desc) }
  scope :near, ->(lat, lng, radius_km = 5) { nearby(lat, lng, radius_km) }

  # What a search engine may be told about. A demo restaurant — `demo` is set by
  # the seeders, never by an owner's form — keeps its page but is not presented
  # as a business: no sitemap entry, no LocalBusiness, and noindex on the page.
  scope :indexable, -> { publicly_visible.where(demo: false) }

  # Open only when recorded hours say so. A restaurant with no hours is not
  # known to be open, so it is not reported open; hours_known? tells that apart
  # from shut.
  def open_now?(moment = Time.current)
    return false unless active? && hours_known?

    Takeaway::OpeningHour.open_at?(id, moment)
  end

  def hours_known? = Takeaway::OpeningHour.exists?(restaurant_id: id)

  # An order for later is still allowed while the kitchen is shut — that is
  # most of what scheduling is for — but only for a time the kitchen is open.
  # With no hours recorded the kitchen has said nothing about when it cooks, so
  # `active` alone decides: most restaurants have no hours yet, and refusing
  # their orders would empty the vertical.
  def accepting_orders?(scheduled_for: nil)
    return active? unless hours_known?
    return open_now? if scheduled_for.blank?

    moment = Time.zone.parse(scheduled_for.to_s)
    active? && moment.present? && Takeaway::OpeningHour.open_at?(id, moment)
  rescue ArgumentError
    false
  end

  def hours_for(wday) = opening_hours.for_weekday(wday).order(:opens_minute)

  OpeningDay = Data.define(:weekday, :windows)
  WEEK_FROM_MONDAY = [ 1, 2, 3, 4, 5, 6, 0 ].freeze

  # The week as the restaurant page lists it, Monday first: every day once any
  # hours are recorded, a day with none being a closed one; nothing at all for
  # a restaurant that has said nothing about its hours.
  def weekly_hours
    by_day = opening_hours.order(:opens_minute).group_by(&:weekday)
    return [] if by_day.empty?

    WEEK_FROM_MONDAY.map { |wday| OpeningDay.new(weekday: wday, windows: by_day.fetch(wday, []).map(&:to_s)) }
  end

  # Whether this kitchen carries to a coordinate. Only a stated radius
  # constrains anything: nil means the restaurant has said nothing, which is
  # not the same as "nowhere", so the answer is yes until the owner types a
  # number. Every input may be missing — an unset pin or a reader who never
  # shared a position — and a missing fact does not make a refusal.
  def delivers_to?(lat, lng)
    return true if delivery_radius_km.blank?
    return false if lat.blank? || lng.blank?
    return false if latitude.blank? || longitude.blank?

    Takeaway::DeliveryDriver.haversine(latitude, longitude, lat, lng) <= delivery_radius_km
  end

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

  private

  def cover_must_be_a_supported_image
    return unless cover.attached?

    blob = cover.blob
    unless COVER_CONTENT_TYPES.include?(blob.content_type)
      errors.add(:cover, I18n.t("takeaway.cover_image_invalid"))
    end
    if blob.byte_size > MAX_COVER_BYTES
      errors.add(:cover, I18n.t("takeaway.cover_image_too_large"))
    end
  end
end
