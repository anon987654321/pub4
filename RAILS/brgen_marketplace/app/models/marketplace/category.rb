# frozen_string_literal: true

class Marketplace::Category < ApplicationRecord
  # Engine-ize
  include Shared::Reactable
  include Shared::Notifiable
  belongs_to :parent, class_name: "Marketplace::Category", optional: true
  has_many :children, class_name: "Marketplace::Category", foreign_key: :parent_id, dependent: :nullify,
           inverse_of: :parent
  has_many :listings, class_name: "Marketplace::Listing", foreign_key: :category_id, dependent: :nullify,
           inverse_of: :category

  # A city's category page is worth a search engine's time from this many
  # live listings: below it the page says "nothing here" in a city's name, so
  # it is noindex and left out of the sitemap rather than sold as an answer.
  INDEXABLE_LISTINGS = 3

  # The categories with INDEXABLE_LISTINGS or more publicly visible listings
  # in the current city: the city-by-category pages a crawler is offered.
  def self.indexable_in_current_city
    ids = Marketplace::Listing.publicly_visible.in_current_city.group(:category_id)
                              .having("COUNT(*) >= ?", INDEXABLE_LISTINGS).count.keys
    where(id: ids)
  end

  def indexable_with?(listing_count) = listing_count >= INDEXABLE_LISTINGS

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true

  before_validation { self.slug ||= name.to_s.parameterize }

  scope :roots, -> { where(parent_id: nil) }

  def to_param = slug
end
