#!/usr/bin/env zsh
# __shared/@reddit_features.sh — Reddit-style voting and comments for Rails 8
# Source from app installers. Do not execute directly.
set -euo pipefail

setup_reddit_models() {
  log "Setting up Reddit-style vote+comment models"

  generate_model Vote \
    user:references votable:references{polymorphic}:index \
    value:integer

  generate_model Comment \
    user:references commentable:references{polymorphic}:index \
    parent_id:integer content:text \
    score:integer:'default[0]' \
    upvotes:integer:'default[0]' downvotes:integer:'default[0]'

  log_ok "Reddit models ready"
}

write_reddit_model_logic() {
  cat > app/models/vote.rb << 'RUBY'
class Vote < ApplicationRecord
  belongs_to :user
  belongs_to :votable, polymorphic: true

  validates :value, inclusion: { in: [1, -1] }
  validates :user_id, uniqueness: { scope: %i[votable_type votable_id] }

  after_save    :sync_votable_score
  after_destroy :sync_votable_score

  private

  def sync_votable_score
    votable.recalculate_score! if votable.respond_to?(:recalculate_score!)
  end
end
RUBY

  cat > app/models/concerns/votable.rb << 'RUBY'
module Votable
  extend ActiveSupport::Concern

  included do
    has_many :votes, as: :votable, dependent: :destroy
  end

  def upvote_by(user)
    cast_vote(user, 1)
  end

  def downvote_by(user)
    cast_vote(user, -1)
  end

  def vote_by(user)
    votes.find_by(user: user)
  end

  def recalculate_score!
    up   = votes.where(value: 1).count
    down = votes.where(value: -1).count
    update_columns(score: up - down, upvotes: up, downvotes: down)
  end

  private

  def cast_vote(user, value)
    existing = votes.find_by(user: user)
    if existing
      existing.value == value ? existing.destroy! : existing.update!(value: value)
    else
      votes.create!(user: user, value: value)
    end
    recalculate_score!
  end
end
RUBY

  cat > app/models/comment.rb << 'RUBY'
class Comment < ApplicationRecord
  include Votable

  belongs_to :user
  belongs_to :commentable, polymorphic: true
  belongs_to :parent, class_name: "Comment", optional: true
  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy

  validates :content, presence: true, length: { maximum: 10_000 }

  scope :roots,    -> { where(parent_id: nil) }
  scope :top,      -> { order(score: :desc) }
  scope :new_first,-> { order(created_at: :desc) }

  def depth
    parent ? parent.depth + 1 : 0
  end

  def tree
    [self] + replies.top.flat_map(&:tree)
  end
end
RUBY

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
  log_ok "Reddit model logic written"
}

write_vote_controller() {
  cat > app/controllers/votes_controller.rb << 'RUBY'
class VotesController < ApplicationController
  before_action :require_authentication

  VOTABLE_TYPES = %w[Post Comment].freeze

  def create
    votable = find_votable
    value   = params[:value].to_i
    raise ArgumentError, "invalid value" unless value.in?([-1, 1])
    votable.public_send(value == 1 ? :upvote_by : :downvote_by, Current.user)
    respond_to do |format|
      format.turbo_stream
      format.json { render json: { score: votable.score } }
    end
  end

  private

  def find_votable
    type = params[:votable_type]
    raise ArgumentError, "invalid type" unless VOTABLE_TYPES.include?(type)
    type.constantize.find(params[:votable_id])
  end
end
RUBY
  log_ok "Vote controller written"
}
