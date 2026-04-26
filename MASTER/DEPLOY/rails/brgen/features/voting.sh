#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

APP_DIR="/home/brgen/app"
MESSAGE="Reddit‑style votes + comments + karma"

# -------------------------------------------------------------------
# Preconditions
# -------------------------------------------------------------------
if [[ ! -d $APP_DIR ]]; then
  printf '[%s] missing APP_DIR %s\n' "$MESSAGE" "$APP_DIR" >&2
  exit 1
fi
if [[ ! -w $APP_DIR ]]; then
  printf '[%s] APP_DIR %s not writable\n' "$MESSAGE" "$APP_DIR" >&2
  exit 1
fi

cd "$APP_DIR"

# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------
run_rails() {
  bin/rails "$@" || {
    printf '[%s] rails command failed: %s\n' "$MESSAGE" "$*" >&2
    exit 1
  }
}

# -------------------------------------------------------------------
# Start
# -------------------------------------------------------------------
printf '==> [%s] starting\n' "$MESSAGE"

# -------------------------------------------------------------------
# Generate Vote model (idempotent)
# -------------------------------------------------------------------
if ! bin/rails generate model Vote value:integer user:references votable:references{polymorphic} --skip > /dev/null 2>&1; then
  printf '[%s] model Vote already exists – skipping\n' "$MESSAGE"
fi
run_rails db:migrate

# -------------------------------------------------------------------
# Concerns & models (write only if missing)
# -------------------------------------------------------------------
VOTABLE_PATH="app/models/concerns/votable.rb"
if [[ ! -f $VOTABLE_PATH ]]; then
  cat > "$VOTABLE_PATH" <<'RUBY'
module Votable
  extend ActiveSupport::Concern

  included do
    has_many :votes, as: :votable, dependent: :destroy
  end

  def score = votes.sum(:value)
  def upvotes = votes.where(value: 1).count
  def downvotes = votes.where(value: -1).count
  def voted_by?(u) = u && votes.find_by(user: u)&.value
  def upvoted_by?(u) = voted_by?(u) == 1
  def downvoted_by?(u) = voted_by?(u) == -1
end
RUBY
fi

VOTE_MODEL="app/models/vote.rb"
if [[ ! -f $VOTE_MODEL ]]; then
  cat > "$VOTE_MODEL" <<'RUBY'
class Vote < ApplicationRecord
  belongs_to :user
  belongs_to :votable, polymorphic: true

  validates :value, inclusion: { in: [-1, 1] }
  validates :user_id, uniqueness: { scope: %i[votable_type votable_id] }

  after_save    :update_author_karma
  after_destroy :update_author_karma

  private

  def update_author_karma
    return unless votable.respond_to?(:user) && votable.user

    votable.user.update_karma!
  end
end
RUBY
fi

USER_MODEL="app/models/user.rb"
if ! grep -q "def update_karma!" "$USER_MODEL"; then
  cat >> "$USER_MODEL" <<'RUBY'

  def update_karma!
    post_karma = Vote.joins("JOIN posts ON posts.id = votes.votable_id AND votes.votable_type = 'Post'")
                     .where(posts: { user_id: id }).sum(:value)

    comment_karma = Vote.joins("JOIN comments ON comments.id = votes.votable_id AND votes.votable_type = 'Comment'")
                        .where(comments: { user_id: id }).sum(:value)

    update_column(:karma, post_karma + comment_karma)
  end
RUBY
fi

COMMENTABLE_PATH="app/models/concerns/commentable.rb"
if [[ ! -f $COMMENTABLE_PATH ]]; then
  cat > "$COMMENTABLE_PATH" <<'RUBY'
module Commentable
  extend ActiveSupport::Concern

  included do
    has_many :comments, as: :commentable, dependent: :destroy
  end

  def root_comments = comments.where(parent_id: nil)
  def comment_count = comments.count
end
RUBY
fi

COMMENT_MODEL="app/models/comment.rb"
if [[ ! -f $COMMENT_MODEL ]]; then
  cat > "$COMMENT_MODEL" <<'RUBY'
class Comment < ApplicationRecord
  include Votable

  belongs_to :user
  belongs_to :commentable, polymorphic: true
  belongs_to :parent, class_name: "Comment", optional: true

  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy

  validates :content, presence: true, length: { minimum: 1, maximum: 10_000 }

  scope :best, -> {
    left_joins(:votes).group(:id).order('SUM(COALESCE(votes.value,0)) DESC')
  }
  scope :top,   -> { best }
  scope :new_first, -> { order(created_at: :desc) }
  scope :old_first, -> { order(created_at: :asc) }
  scope :controversial, -> {
    left_joins(:votes).group(:id)
      .having('COUNT(CASE WHEN votes.value =  1 THEN 1 END) > 0')
      .having('COUNT(CASE WHEN votes.value = -1 THEN 1 END) > 0')
      .order('ABS(SUM(votes.value)) ASC')
  }

  def root? = parent_id.nil?
  def depth = parent ? parent.depth + 1 : 0
end
RUBY
fi

# -------------------------------------------------------------------
# Controller
# -------------------------------------------------------------------
VOTES_CONTROLLER="app/controllers/votes_controller.rb"
if [[ ! -f $VOTES_CONTROLLER ]]; then
  cat > "$VOTES_CONTROLLER" <<'RUBY'
class VotesController < ApplicationController
  before_action :authenticate_user!
  ALLOWED = %w[Post Comment].freeze

  def create
    votable = find_votable
    vote    = votable.votes.find_or_initialize_by(user: current_user)

    if vote.persisted? && vote.value == params.dig(:vote, :value).to_i
      vote.destroy
    else
      vote.update!(value: params.dig(:vote, :value).to_i)
    end

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: root_path }
    end
  end

  private

  def find_votable
    type = params[:votable_type].to_s.classify
    raise ArgumentError, "Invalid votable type" unless ALLOWED.include?(type)

    type.constantize.find(params[:votable_id])
  end
end
RUBY
fi

# -------------------------------------------------------------------
# Views
# -------------------------------------------------------------------
mkdir -p app/views/shared app/views/comments

cat > app/views/shared/_vote.html.erb <<'ERB'
<div class="vote-buttons" data-controller="vote">
  <%= form_with url: votes_path(votable_type: votable.class.name, votable_id: votable.id), method: :post do |f| %>
    <%= f.hidden_field :value, value: 1 %>
    <%= f.button "▲", class: "vote-btn upvote <%= 'active' if votable.upvoted_by?(current_user) %>", type: :submit %>
  <% end %>
  <span class="vote-score"><%= votable.score %></span>
  <%= form_with url: votes_path(votable_type: votable.class.name, votable_id: votable.id), method: :post do |f| %>
    <%= f.hidden_field :value, value: -1 %>
    <%= f.button "▼", class: "vote-btn downvote <%= 'active' if votable.downvoted_by?(current_user) %>", type: :submit %>
  <% end %>
</div>
ERB

cat > app/views/comments/_comment.html.erb <<'ERB'
<%= turbo_frame_tag dom_id(comment) do %>
  <div class="comment depth-<%= comment.depth %>" style="margin-left:<%= comment.depth * 20 %>px">
    <div class="comment-meta">
      <span class="author"><%= comment.user.username %></span>
      <span class="time"><%= time_ago_in_words(comment.created_at) %> ago</span>
      <%= render "shared/vote", votable: comment if user_signed_in? %>
    </div>
    <div class="comment-body"><%= simple_format comment.content %></div>
    <% comment.replies.best.each do |r| %>
      <%= render "comments/comment", comment: r %>
    <% end %>
  </div>
<% end %>
ERB

run_rails db:migrate

printf '==> [%s] done\n' "$MESSAGE"
