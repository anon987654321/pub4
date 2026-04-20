#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

APP_DIR="/home/brgen/app"
MESSAGE="Reddit-style votes + comments + karma"

# Guard: ensure APP_DIR exists and is writable
[[ -d $APP_DIR ]] || { echo "[$MESSAGE] APP_DIR $APP_DIR missing" >&2; exit 1; }
cd "$APP_DIR" || { echo "[$MESSAGE] cannot cd $APP_DIR" >&2; exit 1; }

# Helper to run rails command or abort
run_rails() {
  bin/rails "$@" || { echo "[$MESSAGE] rails command failed: $*" >&2; exit 1; }
}

echo "==> [$MESSAGE]"

# Generate model and migration
run_rails generate model Vote value:integer user:references votable:references{polymorphic}
run_rails db:migrate

# Create Votable concern
cat > app/models/concerns/votable.rb <<'RUBY'
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

# Create Vote model
cat > app/models/vote.rb <<'RUBY'
class Vote < ApplicationRecord
  belongs_to :user
  belongs_to :votable, polymorphic: true
  validates :value, inclusion: { in: [-1, 1] }
  validates :user_id, uniqueness: { scope: [:votable_type, :votable_id] }
  after_save :update_author_karma
  after_destroy :update_author_karma
  private  def update_author_karma
    votable.user.update_karma! if votable.respond_to?(:user)
  endend
RUBY

# Append karma helpers to User
cat >> app/models/user.rb <<'RUBY'
  def update_karma!
    k = Vote.joins("JOIN posts    ON posts.id    = votes.votable_id AND votes.votable_type = 'Post'")
             .where(posts: { user_id: id }).sum(:value)
    k += Vote.joins("JOIN comments ON comments.id = votes.votable_id AND votes.votable_type = 'Comment'")
             .where(comments: { user_id: id }).sum(:value)
    update_column(:karma, k)
  endRUBY

# Commentable concern
cat > app/models/concerns/commentable.rb <<'RUBY'
module Commentable  extend ActiveSupport::Concern
  included do
    has_many :comments, as: :commentable, dependent: :destroy
  end
  def root_comments = comments.where(parent_id: nil)
  def comment_count = comments.count
end
RUBY

# Comment model
cat > app/models/comment.rb <<'RUBY'
class Comment < ApplicationRecord  include Votable
  belongs_to :user
  belongs_to :commentable, polymorphic: true
  belongs_to :parent, class_name: "Comment", optional: true
  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy
  has_many :votes, as: :votable, dependent: :destroy
  validates :content, presence: true, length: { minimum: 1, maximum: 10000 }
  scope :best { left_joins(:votes).group(:id).order("SUM(COALESCE(votes.value,0)) DESC") }
  scope :top    { best }
  scope :new_first   -> { order(created_at: :desc) }
  scope :old_first   -> { order(created_at: :asc) }
  scope :controversial {
    left_joins(:votes).group(:id)
      .having("COUNT(CASE WHEN votes.value =  1 THEN 1 END) > 0")
      .having("COUNT(CASE WHEN votes.value = -1 THEN 1 END) > 0")
      .order("ABS(SUM(votes.value)) ASC")
  }
  def root?  = parent_id.nil?
  def depth  = parent ? parent.depth + 1 : 0
end
RUBY

# Votes controller
cat > app/controllers/votes_controller.rb <<'RUBY'
class VotesController < ApplicationController
  before_action :authenticate_user!
  ALLOWED = %w[Post Comment].freeze

  def create
    votable = find_votable
    vote    = votable.votes.find_or_initialize_by(user: current_user)
    if vote.persisted? && vote.value == params[:vote][:value].to_i
      vote.destroy    else
      vote.update!(value: params[:vote][:value])
    end
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: root_path }
    end
  end  private
  def find_votable    type = params[:votable_type].to_s.classify
    raise ArgumentError unless ALLOWED.include?(type)
    type.constantize.find(params[:votable_id])
  endend
RUBY

# Folders for views
mkdir -p app/views/shared app/views/comments

# Vote partial
cat > app/views/shared/_vote.html.erb <<'ERB'
<div class="vote-buttons" data-controller="vote">
  <%= form_with url: votes_path(votable_type: votable.class.name, votable_id: votable.id), method: :post do |f| %>
    <%= f.hidden_field :value, value: 1 %>
    <%= f.button "▲", class: "vote-btn upvote #{votable.upvoted_by?(current_user) ? 'active' : ''}", type: :submit %>
  <% end %>
  <span class="vote-score"><%= votable.score %></span>
  <%= form_with url: votes_path(votable_type: votable.class.name, votable_id: votable.id), method: :post do |f| %>
    <%= f.hidden_field :value, value: -1 %>
    <%= f.button "▼", class: "vote-btn downvote #{votable.downvoted_by?(current_user) ? 'active' : ''}", type: :submit %>
  <% end %>
</div>
ERB

# Comment partial
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

# Run DB migrations again (idempotent)
run_rails db:migrate
echo "==> [$MESSAGE] done"