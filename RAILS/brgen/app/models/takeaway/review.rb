# frozen_string_literal: true

class Takeaway::Review < ApplicationRecord
  # Engine-ized Shared concerns
  tracks_activity created: "TakeawayReviewCreated", source_vertical: "takeaway", actor: :user
  include Shared::Notifiable
  include Shared::Reactable
  include Shared::Votable
  include Shared::StrictSafeAssociations

  belongs_to :user
  belongs_to :order, class_name: "Takeaway::Order"
  belongs_to :restaurant, class_name: "Takeaway::Restaurant", counter_cache: :reviews_count

  validates :rating, presence: true, inclusion: { in: 1..5 }
  validates :order_id, uniqueness: { scope: :user_id }, allow_nil: true

  after_commit :refresh_restaurant_rating, on: %i[create destroy]

  private

  # Same as Marketplace::Review#refresh_listing_rating — the callback runs on
  # destroy, when the review was found by id and nothing is preloaded.
  def refresh_restaurant_rating
    strict_safe(:restaurant)&.update_rating!
  end
end
