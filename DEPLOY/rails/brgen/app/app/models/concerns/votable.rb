module Votable
  extend ActiveSupport::Concern

  included do
    has_many :votes, as: :votable, dependent: :destroy
  end

  def score         = votes.sum(:value)
  def upvotes       = votes.where(value: 1).count
  def downvotes     = votes.where(value: -1).count
  def voted_by?(u)  = u && votes.find_by(user: u)&.value
  def upvoted_by?(u)   = voted_by?(u) == 1
  def downvoted_by?(u) = voted_by?(u) == -1
end
