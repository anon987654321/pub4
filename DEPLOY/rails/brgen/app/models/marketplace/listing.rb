# frozen_string_literal: true

class Marketplace::Listing < ApplicationRecord
  belongs_to :user
  belongs_to :store, class_name: "Marketplace::Store", optional: true
  belongs_to :category, class_name: "Marketplace::Category",
             foreign_key: :category_id, optional: true
  has_many :orders, class_name: "Marketplace::Order",
           foreign_key: :listing_id, dependent: :destroy
  has_many :favorites, class_name: "Marketplace::ListingFavorite",
           foreign_key: :listing_id, dependent: :destroy
  has_many :deals, class_name: "Marketplace::Deal", dependent: :destroy
  has_many :favorited_by_users, through: :favorites, source: :user
  has_many_attached :photos

  CONDITIONS = %w[new like_new good fair poor].freeze
  STATUSES   = %w[active sold reserved removed].freeze

  validates :title, presence: true, length: { maximum: 200 }
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :condition, inclusion: { in: CONDITIONS }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }

  before_validation { self.status ||= "active"; self.currency ||= "NOK" }

  scope :active,   -> { where(status: "active") }
  scope :recent,   -> { order(created_at: :desc) }
  scope :popular,  -> { order(views_count: :desc) }
  scope :from_store, ->(store) { where(store: store) }
  scope :search, ->(q) {
    term = q.to_s.strip
    return none if term.empty?

    ids = connection.select_values(
      sanitize_sql_array(["SELECT rowid FROM marketplace_listings_fts WHERE marketplace_listings_fts MATCH ?", term])
    )
    ids.any? ? where(id: ids) : none
  }

  def price_display = "#{price_cents / 100.0} #{currency}"
  def sold? = status == "sold"
  def favorite_for(user) = favorites.find_by(user: user)
  def store_name = store&.name
end
