#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

typeset -r APP_DIR="/home/brgen/app"
echo "==> [models] Core models + concerns"
cd "$APP_DIR"

# Current
cat > app/models/current.rb << 'RUBY'
class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :user
end
RUBY

# Votable concern
mkdir -p app/models/concerns
cat > app/models/concerns/votable.rb << 'RUBY'
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
RUBY

# Vote
cat > app/models/vote.rb << 'RUBY'
class Vote < ApplicationRecord
  belongs_to :user
  belongs_to :votable, polymorphic: true

  validates :value, inclusion: { in: [-1, 1] }
  validates :user_id, uniqueness: { scope: [:votable_type, :votable_id] }

  after_save    :update_author_karma
  after_destroy :update_author_karma

  private

  def update_author_karma
    votable.user.update_karma! if votable.respond_to?(:user)
  end
end
RUBY

# Post
cat > app/models/post.rb << 'RUBY'
class Post < ApplicationRecord
  include Votable

  belongs_to :user
  belongs_to :community, optional: true

  has_many :comments, as: :commentable, dependent: :destroy
  has_many :votes, as: :votable, dependent: :destroy
  has_many :taggings, dependent: :destroy
  has_many :hashtags, through: :taggings
  has_many :mentions, dependent: :destroy

  validates :title,   presence: true, length: { maximum: 300 }
  validates :content, length: { maximum: 40_000 }

  VOTE_SQL = Arel.sql("SUM(COALESCE(votes.value,0)) DESC, posts.created_at DESC")
  TOP_SQL  = Arel.sql("SUM(COALESCE(votes.value,0)) DESC")

  scope :hot,   -> { left_joins(:votes).group(:id).order(VOTE_SQL) }
  scope :fresh, -> { order(created_at: :desc) }
  scope :top,   -> { left_joins(:votes).group(:id).order(TOP_SQL) }

  def comment_count = comments.count
  def author_name   = user&.username.presence || "anon"
end
RUBY

# Community
cat > app/models/community.rb << 'RUBY'
class Community < ApplicationRecord
  belongs_to :user, optional: true

  has_many :posts, dependent: :destroy

  validates :name,        presence: true, uniqueness: true, length: { maximum: 100 }
  validates :description, length: { maximum: 500 }

  POPULAR_SQL = Arel.sql("COUNT(posts.id) DESC")
  scope :popular, -> { left_joins(:posts).group(:id).order(POPULAR_SQL) }
end
RUBY

# Comment
cat > app/models/comment.rb << 'RUBY'
class Comment < ApplicationRecord
  include Votable

  belongs_to :user
  belongs_to :commentable, polymorphic: true
  belongs_to :parent, class_name: "Comment", optional: true

  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy
  has_many :votes, as: :votable, dependent: :destroy

  validates :content, presence: true, length: { minimum: 1, maximum: 10000 }

  scope :best,      -> { left_joins(:votes).group(:id).order(Arel.sql("SUM(COALESCE(votes.value,0)) DESC")) }
  scope :top,       -> { best }
  scope :new_first, -> { order(created_at: :desc) }

  def root?  = parent_id.nil?
  def depth  = parent ? parent.depth + 1 : 0
end
RUBY

echo "==> [models] done"
