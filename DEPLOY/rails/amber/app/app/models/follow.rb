class Follow < ApplicationRecord
  belongs_to :follower, class_name: "User", touch: true
  belongs_to :followee, class_name: "User", touch: true

  validates :follower_id, uniqueness: { scope: :followee_id }
  validate :no_self_follow

  private

  def no_self_follow
    errors.add(:followee, "can't follow yourself") if follower_id == followee_id
  end
end
