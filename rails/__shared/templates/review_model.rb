# Review Model
class Review < ApplicationRecord
  belongs_to :reviewable, polymorphic: true
  belongs_to :user
  acts_as_votable
  
  validates :rating, presence: true, inclusion: { in: 1..5 }
  validates :title, presence: true, length: { maximum: 100 }
  validates :body, presence: true, length: { minimum: 20, maximum: 5000 }
  validates :user_id, uniqueness: { scope: [:reviewable_type, :reviewable_id] }
  
  scope :recent, -> { order(created_at: :desc) }
  scope :top_rated, -> { order(rating: :desc) }
  scope :verified, -> { where(verified_purchase: true) }
  
  after_create :update_reviewable_stats
  after_update :update_reviewable_stats
  after_destroy :update_reviewable_stats
  
  def helpful?
    helpful_count.to_i > 0
  end
  
  def mark_helpful(user)
    increment!(:helpful_count) if can_mark_helpful?(user)
  end
  
  private
  
  def can_mark_helpful?(user)
    user != self.user && !voted_by?(user)
  end
  
  def update_reviewable_stats
    return unless reviewable.respond_to?(:update_review_stats)
    reviewable.update_review_stats
  end
end
