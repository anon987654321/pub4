#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

typeset -r APP_DIR="/home/brgen/app"
typeset -r MAX_COMMENT_LENGTH=10000
typeset -r MAX_KARMA_SEED=1000
typeset -r HOT_DECAY_EXPONENT=1.5

echo "==> [models] Core models + concerns"
cd "$APP_DIR"

echo "Generating models"
typeset -a models
models=(
  "Community name:string description:text subdomain:string:uniq slug:string:uniq"
  "Post title:string content:text user:references community:references karma:integer:default[0] anonymous:boolean:default[false]"
  "Comment content:text user:references commentable:references{polymorphic}:index parent_id:integer"
  "Reaction kind:string user:references post:references"
  "Stream content_type:string url:string user:references post:references duration:integer"
)

for model_spec in $models; do
  bin/rails generate model ${=model_spec}
done

bin/rails generate migration AddFieldsToUsers username:string karma:integer:default=0 location:point

cat >> app/models/user.rb << 'RUBY'

# Voting
acts_as_voter

# Associations
has_many :posts, dependent: :destroy
has_many :comments, dependent: :destroy
has_many :communities

# Validations
validates :username, presence: true, uniqueness: true

def update_karma_from_votes
  total_karma = posts.sum { |p| p.cached_votes_score } +
                comments.sum { |c| c.cached_votes_score }
  update_column(:karma, total_karma)
end

RUBY

bin/rails db:migrate

echo "Creating model concerns"
mkdir -p app/models/concerns
cat > app/models/concerns/commentable.rb << 'RUBY'
module Commentable
  extend ActiveSupport::Concern

  included do
    has_many :comments, as: :commentable, dependent: :destroy
  end

  def comment_count
    comments.count
  end
end
RUBY

cat > app/models/community.rb << 'RUBY'
class Community < ApplicationRecord
  has_many :posts, dependent: :destroy
  has_many :users

  validates :name, :subdomain, :slug, presence: true
  validates :subdomain, :slug, uniqueness: true

  before_validation :generate_slug

  private

  def generate_slug
    self.slug ||= name.parameterize if name.present?
  end
end
RUBY

cat > app/models/post.rb << 'RUBY'
class Post < ApplicationRecord
  include Votable
  include Commentable

  acts_as_votable
  acts_as_tenant :community

  belongs_to :user
  belongs_to :community

  has_many :reactions, dependent: :destroy
  has_many :streams, dependent: :destroy
  has_many_attached :photos

  validates :content, presence: true
  validates :title, presence: true, length: { maximum: 300 }

  scope :hot, -> {
    left_joins(:votes)
      .group(:id)
      .select('posts.*, SUM(COALESCE(votes.value, 0)) as vote_sum,
               EXTRACT(EPOCH FROM (NOW() - posts.created_at)) / 3600 as hours_old')
      .order(Arel.sql("vote_sum / POWER(hours_old + 2, 1.5) DESC"))
  }

  scope :top,       -> { left_joins(:votes).group(:id).order("SUM(COALESCE(votes.value, 0)) DESC") }
  scope :new_first, -> { order(created_at: :desc) }

  def update_karma
    update_column(:karma, get_upvotes.size - get_downvotes.size)
  end
end
RUBY

cat > app/models/comment.rb << 'RUBY'
class Comment < ApplicationRecord
  include Votable

  acts_as_votable
  belongs_to :user
  belongs_to :commentable, polymorphic: true
  belongs_to :parent, class_name: "Comment", optional: true

  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy

  validates :content, presence: true, length: { minimum: 1, maximum: 10000 }

  scope :best,      -> { left_joins(:votes).group(:id).order("SUM(COALESCE(votes.value, 0)) DESC") }
  scope :new_first, -> { order(created_at: :desc) }

  def root?  = parent_id.nil?
  def depth  = parent ? parent.depth + 1 : 0
end
RUBY

echo "==> [models] done"
