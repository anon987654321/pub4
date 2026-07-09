# frozen_string_literal: true

class Marketplace::Review < ApplicationRecord
  tracks_activity created: "MarketplaceReviewCreated", source_vertical: "marketplace", actor: :user

  belongs_to :user
  belongs_to :listing, class_name: "Marketplace::Listing", counter_cache: :reviews_count

  validates :rating, presence: true, inclusion: { in: 1..5 }
  validates :user_id, uniqueness: { scope: :listing_id }
  validates :body, length: { maximum: 2_000 }, allow_blank: true
  validate :buyer_has_completed_interaction
  validate :seller_cannot_review_own_listing

  after_commit :refresh_listing_rating, on: %i[create update destroy]

  private

  def buyer_has_completed_interaction
    return if listing&.orders&.where(buyer: user, status: %w[accepted completed])&.exists?

    errors.add(:base, "review requires an accepted or completed marketplace order")
  end

  def seller_cannot_review_own_listing
    errors.add(:user, "cannot review your own listing") if listing&.user_id == user_id
  end

  def refresh_listing_rating
    listing&.update_rating!
  end
end
