# Votable Concern
# Include in any model that needs voting (posts, comments, products, etc.)

module Votable
  extend ActiveSupport::Concern
  
  included do
    acts_as_votable
    has_many :reviews, as: :reviewable, dependent: :destroy
    
    scope :top_voted, -> { order(cached_votes_score: :desc) }
    scope :controversial, -> { where('cached_votes_up > 0 AND cached_votes_down > 0').order('cached_votes_up + cached_votes_down DESC') }
  end
  
  def vote_score
    cached_votes_score
  end
  
  def upvote_percentage
    return 0 if cached_votes_total.zero?
    (cached_votes_up.to_f / cached_votes_total * 100).round
  end
  
  def average_rating
    reviews.average(:rating)&.round(1) || 0
  end
  
  def review_count
    reviews.count
  end
  
  def review_summary
    {
      average: average_rating,
      count: review_count,
      distribution: rating_distribution
    }
  end
  
  def update_review_stats
    update_columns(
      average_rating: average_rating,
      review_count: review_count
    ) if respond_to?(:average_rating=)
  end
  
  private
  
  def rating_distribution
    reviews.group(:rating).count.transform_keys(&:to_i)
  end
end
