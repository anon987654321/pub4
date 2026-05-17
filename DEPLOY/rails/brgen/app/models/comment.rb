class Comment < ApplicationRecord
  include Votable

  belongs_to :user
  belongs_to :commentable, polymorphic: true, touch: true
  belongs_to :parent, class_name: "Comment", optional: true

  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy
  has_many :votes, as: :votable, dependent: :destroy

  validates :content, presence: true, length: { minimum: 1, maximum: 10000 }

  scope :best,          -> { left_joins(:votes).group(:id).order("SUM(COALESCE(votes.value, 0)) DESC") }
  scope :top,           -> { best }
  scope :new_first,     -> { order(created_at: :desc) }
  scope :controversial, -> {
    left_joins(:votes).group(:id)
      .having("COUNT(CASE WHEN votes.value =  1 THEN 1 END) > 0")
      .having("COUNT(CASE WHEN votes.value = -1 THEN 1 END) > 0")
      .order("ABS(SUM(votes.value)) ASC")
  }

  def root?  = parent_id.nil?
  def depth  = parent ? parent.depth + 1 : 0
end
