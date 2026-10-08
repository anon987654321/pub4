# frozen_string_literal: true

class Marketplace::Review < ApplicationRecord
  include Shared::StrictSafeAssociations
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
    return if listing&.orders&.where(buyer: user, status: %w[accepted completed paid])&.exists?

    errors.add(:base, :requires_completed_order)
  end

  def seller_cannot_review_own_listing
    errors.add(:user, :own_listing) if listing&.user_id == user_id
  end

  # after_commit fires on destroy too, and a review being destroyed was found by
  # id with nothing preloaded — so this raised StrictLoadingViolation *after*
  # the delete had committed: the review was gone and the cached listing rating
  # still counted it.
  #
  # The destroyed? guard is the other half: when the listing itself is being
  # destroyed, its reviews cascade first and each one tries to refresh a rating
  # on a record that is already gone ("cannot update a destroyed record"). There
  # is nothing to refresh in that case — the listing is going too.
  def refresh_listing_rating
    listing = strict_safe(:listing)
    listing.update_rating! if listing && !listing.destroyed?
  end
end
