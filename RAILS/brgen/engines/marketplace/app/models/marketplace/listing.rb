# frozen_string_literal: true

class Marketplace::Listing < ApplicationRecord
  include CityTenantable
  include Shared::Sluggable # /listings/<title-slug>; from :title, unique per city
  include Shared::MediaProcessable
  include Shared::GeoLocatable
  tracks_activity created: "ListingCreated", source_vertical: "marketplace", actor: :user

  include Shared::Reactable
  include Shared::Notifiable
  belongs_to :user
  belongs_to :store, class_name: "Marketplace::Store", optional: true
  belongs_to :category, class_name: "Marketplace::Category",
             foreign_key: :category_id, optional: true
  # :restrict_with_error, not :destroy -- an order is a financial record and a
  # buyer's receipt, and the seller who withdraws a listing does not own the
  # buyer's half of it. Operator decision 2026-08-09.
  #
  # The listings controller withdraws rather than destroys (status: "removed",
  # which ListingPolicy::Scope filters out of every index and show? hides from
  # non-owners), so this does not fire on the normal path. What it guards is the
  # cascade: User has_many :marketplace_listings, dependent: :destroy, so
  # destroying a seller previously destroyed every order placed against them,
  # including the buyers' side.
  #
  # That cascade is now refused, which leaves an open question rather than a
  # closed door: account deletion has no controller path today, and when one is
  # built it has to reconcile the buyer's right to a receipt with the seller's
  # right to erasure. Anonymising the seller and keeping the order is the usual
  # answer; that is a product decision, not this file's.
  has_many :orders, class_name: "Marketplace::Order",
           foreign_key: :listing_id, dependent: :restrict_with_error
  has_many :favorites, class_name: "Marketplace::ListingFavorite",
           foreign_key: :listing_id, dependent: :destroy
  has_many :deals, class_name: "Marketplace::Deal", dependent: :destroy
  has_many :reviews, class_name: "Marketplace::Review", dependent: :destroy
  # Public questions and the seller's answers — see Marketplace::Question for
  # why they are on the listing rather than in an offer thread.
  has_many :questions, class_name: "Marketplace::Question", dependent: :destroy
  # Size and colour as rows. A listing with variants is bought by the variant,
  # not by the listing — see Marketplace::Variant.
  has_many :variants, class_name: "Marketplace::Variant", dependent: :destroy
  has_many :favorited_by_users, through: :favorites, source: :user
  has_many_attached :photos
  process_media_variants :photos, variants: {
    thumb: { resize_to_limit: [ 360, 360 ], format: :webp },
    card: { resize_to_limit: [ 800, 800 ], format: :webp },
  }

  CONDITIONS = %w[new like_new good fair poor].freeze
  STATUSES   = %w[active sold reserved removed].freeze
  DEFAULT_RADIUS_KM = 5.0
  MAX_RADIUS_KM = 50.0

  validates :title, presence: true, length: { maximum: 200 }
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :condition, inclusion: { in: CONDITIONS }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }
  validates :latitude, :longitude, numericality: true, allow_nil: true

  before_validation do
    self.status ||= "active"
    self.currency ||= Current.currency.presence || "NOK"
    self.latitude ||= Current.user&.latitude if defined?(Current) && Current.respond_to?(:user)
    self.longitude ||= Current.user&.longitude if defined?(Current) && Current.respond_to?(:user)
  end

  after_create_commit { broadcast_append_later_to "marketplace:listings", partial: "marketplace/listings/card", locals: { listing: self } }

  # A classifieds listing has a life. Without one the marketplace fills with
  # things sold two years ago that nobody took down, and the honest listings
  # drown in them.
  LIFETIME = 45.days
  # Told a week before, so renewing is a choice rather than a surprise.
  RENEWAL_NOTICE = 7.days

  before_validation :set_expiry, on: :create

  # `live` is what every public surface should read: active AND not expired.
  # `active` stays as it was, because seller-facing pages legitimately want
  # their own expired listings back.
  scope :active,   -> { where(status: "active") }
  scope :live,     -> { active.where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :expired,  -> { active.where("expires_at IS NOT NULL AND expires_at <= ?", Time.current) }
  scope :expiring_soon, lambda {
    live.where(renewal_notice_sent_at: nil).where("expires_at <= ?", Time.current + RENEWAL_NOTICE)
  }
  scope :recent,   -> { order(created_at: :desc) }
  scope :popular,  -> { order(views_count: :desc) }
  scope :from_store, ->(store) { where(store: store) }
  # No store = a person selling a chair. The storefront already stores that;
  # these scopes are the chrome the index was missing.
  scope :casual, -> { where(store_id: nil) }
  scope :from_shops, -> { where.not(store_id: nil) }
  scope :near, ->(lat, lng, radius_km = 5) { nearby(lat, lng, radius_km) }
  scope :rated, -> { where("rating > 0") }

  def self.radius_from(value)
    value.to_f.clamp(1.0, MAX_RADIUS_KM)
  end

  # nil stock means one of a kind, which is what a classifieds listing is; a
  # number means a shop with inventory. Defaulting to 1 would have made every
  # private sale read as a shop with one left.
  def one_of_a_kind? = stock.nil?
  def varied? = variants.exists?
  def in_stock? = one_of_a_kind? ? !sold? : stock.to_i.positive?

  def available_quantity = one_of_a_kind? ? (sold? ? 0 : 1) : stock.to_i

  # Called when an order is paid. update_column-style so a legacy listing with a
  # since-tightened validation cannot block a sale that has already been paid
  # for, and updated_at goes with it because the card is cached on [listing].
  def consume_stock!(quantity = 1)
    raise "listing is not in stock" unless in_stock?

    return mark_sold! if one_of_a_kind?

    remaining = [ stock.to_i - quantity.to_i, 0 ].max
    update_columns(stock: remaining, status: remaining.zero? ? "sold" : status, updated_at: Time.current)
  end

  def mark_sold! = update_columns(status: "sold", updated_at: Time.current)

  def expired? = expires_at.present? && expires_at <= Time.current
  def expires_in_days = expires_at.nil? ? nil : ((expires_at - Time.current) / 1.day).ceil
  def buyable? = status == "active" && !expired? && in_stock?

  # Renewing restarts the window from now rather than extending the old one, so
  # a listing renewed a week late does not immediately expire again.
  def renew!
    update!(expires_at: Time.current + LIFETIME, renewal_notice_sent_at: nil)
  end

  def price_display = Shared::MoneyDisplay.format(price_cents, currency)
  def casual? = store_id.nil?
  def sold? = status == "sold"
  def favorite_for(user) = favorites.find_by(user: user)
  def store_name = store&.name

  def reviewable_by?(account)
    return false if account.blank? || account == user
    return false if reviews.exists?(user: account)

    orders.where(buyer: account, status: %w[accepted completed]).exists?
  end

  def update_rating!
    # updated_at with it -- the rating is on every listing card, and skipping the
    # timestamp leaves [listing] fragment caches serving the pre-review score.
    update_columns(rating: reviews.average(:rating)&.round(2) || 0, updated_at: Time.current)
  end

  private

  def set_expiry
    self.expires_at ||= Time.current + LIFETIME
  end
end
