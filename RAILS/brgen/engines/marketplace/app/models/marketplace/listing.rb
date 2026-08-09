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

  scope :active,   -> { where(status: "active") }
  scope :recent,   -> { order(created_at: :desc) }
  scope :popular,  -> { order(views_count: :desc) }
  scope :from_store, ->(store) { where(store: store) }
  scope :near, ->(lat, lng, radius_km = 5) { nearby(lat, lng, radius_km) }
  scope :rated, -> { where("rating > 0") }

  def self.radius_from(value)
    value.to_f.clamp(1.0, MAX_RADIUS_KM)
  end

  def price_display = "#{price_cents / 100.0} #{currency}"
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
end
