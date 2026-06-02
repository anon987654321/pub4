# frozen_string_literal: true

class Takeaway::Review < ApplicationRecord
  belongs_to :user
  belongs_to :order, class_name: "Takeaway::Order"
  belongs_to :restaurant, class_name: "Takeaway::Restaurant", counter_cache: :reviews_count

  validates :rating, presence: true, inclusion: { in: 1..5 }
  validates :order_id, uniqueness: { scope: :user_id }, allow_nil: true

  after_commit :refresh_restaurant_rating, on: %i[create destroy]

  private

  def refresh_restaurant_rating
    restaurant&.update_rating!
  end
end
