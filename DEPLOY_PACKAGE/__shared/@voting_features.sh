#!/usr/bin/env zsh
set -euo pipefail

# Reddit-style social features: Comments, Votes, Karma
# Shared across brgen, amber, and other social apps

setup_reddit_models() {
  log "Setting up Reddit-style models: Comment, Vote, Karma"

  # Comment model with threading (parent_id for nested comments)
  bin/rails generate model Comment content:text user:references commentable:references{polymorphic} parent_id:integer

  # Vote model (upvote/downvote on posts, comments, listings)
  bin/rails generate model Vote value:integer user:references votable:references{polymorphic}

  # Add karma column to users
  bin/rails generate migration AddKarmaToUsers karma:integer

  log "Reddit models generated"
}

generate_comment_model() {
  log "Configuring Comment model with threading"

  cat <<'EOF' > app/models/comment.rb
class Comment < ApplicationRecord

  belongs_to :user
  belongs_to :commentable, polymorphic: true

  belongs_to :parent, class_name: "Comment", optional: true
  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy

  has_many :votes, as: :votable, dependent: :destroy

  validates :content, presence: true, length: { minimum: 1, maximum: 10000 }

  # Karma calculation

  def score

    votes.sum(:value)

  end
  def upvotes
    votes.where(value: 1).count

  end

  def downvotes

    votes.where(value: -1).count
  end

  # Threading helpers

  def root?
    parent_id.nil?

  end

  def depth
    parent ? parent.depth + 1 : 0

  end

  # Sort comments Reddit-style

  scope :best, -> { left_joins(:votes).group(:id).order("SUM(COALESCE(votes.value, 0)) DESC") }
  scope :top, -> { best }

  scope :new, -> { order(created_at: :desc) }

  scope :old, -> { order(created_at: :asc) }
  scope :controversial, -> {

    left_joins(:votes)

      .group(:id)

      .having("COUNT(CASE WHEN votes.value = 1 THEN 1 END) > 0")

      .having("COUNT(CASE WHEN votes.value = -1 THEN 1 END) > 0")

      .order("ABS(SUM(votes.value)) ASC")

  }

end

EOF

  log "Comment model configured"

}

generate_vote_model() {

  log "Configuring Vote model"

  cat <<'EOF' > app/models/vote.rb
class Vote < ApplicationRecord

  belongs_to :user
  belongs_to :votable, polymorphic: true

  validates :value, inclusion: { in: [-1, 1] }
  validates :user_id, uniqueness: { scope: [:votable_type, :votable_id] }

  after_save :update_user_karma

  after_destroy :update_user_karma

  private
  def update_user_karma

    return unless votable.respond_to?(:user)
    votable.user.update_karma!

  end
end
EOF

  log "Vote model configured"
}

generate_user_karma_methods() {

  log "Adding karma methods to User model"

  # Append karma methods to User model
  cat <<'EOF' >> app/models/user.rb

  # Karma calculation
  has_many :votes_received, through: :posts, source: :votes

  has_many :comment_votes_received, through: :comments, source: :votes
  def update_karma!

    total_karma = Vote.joins("INNER JOIN posts ON posts.id = votes.votable_id AND votes.votable_type = 'Post'")
                      .where(posts: { user_id: id })

                      .sum(:value)

    total_karma += Vote.joins("INNER JOIN comments ON comments.id = votes.votable_id AND votes.votable_type = 'Comment'")
                       .where(comments: { user_id: id })

                       .sum(:value)

    update_column(:karma, total_karma)

  end
  def post_karma

    Vote.joins("INNER JOIN posts ON posts.id = votes.votable_id AND votes.votable_type = 'Post'")

        .where(posts: { user_id: id })
        .sum(:value)

  end
  def comment_karma

    Vote.joins("INNER JOIN comments ON comments.id = votes.votable_id AND votes.votable_type = 'Comment'")

        .where(comments: { user_id: id })

        .sum(:value)

  end
EOF

  log "User karma methods added"

}

generate_votable_concern() {

  log "Generating Votable concern"

  mkdir -p app/models/concerns
  cat <<'EOF' > app/models/concerns/votable.rb

module Votable
  extend ActiveSupport::Concern

  included do
    has_many :votes, as: :votable, dependent: :destroy
  end

  def score

    votes.sum(:value)
  end

  def upvotes

    votes.where(value: 1).count
  end

  def downvotes

    votes.where(value: -1).count
  end

  def voted_by?(user)

    return nil unless user
    votes.find_by(user: user)&.value

  end

  def upvoted_by?(user)
    voted_by?(user) == 1

  end

  def downvoted_by?(user)

    voted_by?(user) == -1
  end

end

EOF
  log "Votable concern generated"

}

generate_commentable_concern() {

  log "Generating Commentable concern"

  mkdir -p app/models/concerns
  cat <<'EOF' > app/models/concerns/commentable.rb

module Commentable
  extend ActiveSupport::Concern

  included do
    has_many :comments, as: :commentable, dependent: :destroy
  end

  def root_comments

    comments.where(parent_id: nil)
  end

  def comment_count

    comments.count
  end

end

EOF
  log "Commentable concern generated"

}

generate_votes_controller() {

  log "Generating VotesController"

  cat <<'EOF' > app/controllers/votes_controller.rb
class VotesController < ApplicationController

  before_action :authenticate_user!
  def create

    @votable = find_votable
    @vote = @votable.votes.find_or_initialize_by(user: current_user)

    if @vote.persisted? && @vote.value == vote_params[:value].to_i

      # User clicked same vote button - remove vote
      @vote.destroy

      @action = "removed"

    else
      # New vote or changed vote

      @vote.value = vote_params[:value]

      @vote.save!

      @action = @vote.value == 1 ? "upvoted" : "downvoted"

    end

    respond_to do |format|

      format.turbo_stream

      format.html { redirect_back(fallback_location: root_path, notice: "Vote #{@action}") }

    end

  end
  private

  def find_votable

    votable_type = params[:votable_type].classify

    votable_id = params[:votable_id]

    votable_type.constantize.find(votable_id)
  end
  def vote_params

    params.require(:vote).permit(:value)

  end

end

EOF
  log "VotesController generated"

}

generate_comments_controller() {

  log "Generating CommentsController"

  cat <<'EOF' > app/controllers/comments_controller.rb
class CommentsController < ApplicationController

  before_action :authenticate_user!, except: [:index]
  before_action :set_commentable

  before_action :set_comment, only: [:edit, :update, :destroy]
  def index

    @comments = @commentable.root_comments.send(params[:sort] || "best")

    @comment = Comment.new

  end

  def create
    @comment = @commentable.comments.build(comment_params)

    @comment.user = current_user

    if @comment.save

      current_user.update_karma! if @commentable.respond_to?(:user)
      respond_to do |format|

        format.turbo_stream

        format.html { redirect_to polymorphic_path(@commentable), notice: "Comment added" }
      end

    else
      render :new, status: :unprocessable_entity

    end

  end

  def edit

  end

  def update

    if @comment.update(comment_params)

      respond_to do |format|
        format.turbo_stream

        format.html { redirect_to polymorphic_path(@commentable), notice: "Comment updated" }
      end

    else

      render :edit, status: :unprocessable_entity

    end

  end

  def destroy

    @comment.destroy

    respond_to do |format|

      format.turbo_stream

      format.html { redirect_to polymorphic_path(@commentable), notice: "Comment deleted" }
    end

  end
  private

  def set_commentable

    commentable_type = params[:commentable_type].classify

    commentable_id = params[:commentable_id]

    @commentable = commentable_type.constantize.find(commentable_id)
  end
  def set_comment

    @comment = Comment.find(params[:id])

    redirect_to root_path, alert: "Not authorized" unless @comment.user == current_user

  end

  def comment_params
    params.require(:comment).permit(:content, :parent_id)

  end

end

EOF
  log "CommentsController generated"

}

generate_vote_partial() {

  log "Generating vote partial"

  mkdir -p app/views/shared
  cat <<'EOF' > app/views/shared/_vote.html.erb

<%= tag.div class: "vote-buttons", data: { controller: "vote" } do %>
  <% score = votable.score %>

  <% upvoted = current_user && votable.upvoted_by?(current_user) %>
  <% downvoted = current_user && votable.downvoted_by?(current_user) %>
  <%= form_with(

    url: votes_path(votable_type: votable.class.name, votable_id: votable.id),

    method: :post,

    data: { turbo_frame: "vote_#{dom_id(votable)}" },

    class: "vote-form"
  ) do |form| %>

    <%= form.hidden_field :value, value: 1 %>

    <%= form.button type: :submit, class: "vote-btn upvote #{upvoted ? 'active' : ''}", "aria-label": "Upvote" do %>

      <span class="arrow">▲</span>

    <% end %>

  <% end %>

  <%= turbo_frame_tag "vote_#{dom_id(votable)}" do %>

    <%= tag.span score, class: "vote-score #{score > 0 ? 'positive' : score < 0 ? 'negative' : ''}" %>

  <% end %>

  <%= form_with(

    url: votes_path(votable_type: votable.class.name, votable_id: votable.id),
    method: :post,

    data: { turbo_frame: "vote_#{dom_id(votable)}" },

    class: "vote-form"
  ) do |form| %>

    <%= form.hidden_field :value, value: -1 %>

    <%= form.button type: :submit, class: "vote-btn downvote #{downvoted ? 'active' : ''}", "aria-label": "Downvote" do %>

      <span class="arrow">▼</span>

    <% end %>

  <% end %>

<% end %>

EOF

  log "Vote partial generated"

}

generate_comment_partial() {

  log "Generating comment partial"

  mkdir -p app/views/comments
  cat <<'EOF' > app/views/comments/_comment.html.erb

<%= turbo_frame_tag dom_id(comment) do %>
  <%= tag.div class: "comment depth-#{comment.depth}", id: dom_id(comment), style: "margin-left: #{comment.depth * 20}px;" do %>

    <%= tag.div class: "comment-header" do %>
      <%= tag.span comment.user.email, class: "comment-author" %>
      <%= tag.span time_ago_in_words(comment.created_at), class: "comment-time" %>

      <%= tag.span "#{comment.score} points", class: "comment-score" %>

    <% end %>

    <%= tag.div class: "comment-body" do %>

      <%= simple_format comment.content %>

    <% end %>

    <%= tag.div class: "comment-actions" do %>

      <%= render partial: "shared/vote", locals: { votable: comment } %>
      <%= link_to "Reply", "#", data: { action: "click->comments#showReplyForm" }, class: "comment-action-link" if current_user %>

      <%= link_to "Edit", edit_comment_path(comment, commentable_type: comment.commentable_type, commentable_id: comment.commentable_id), class: "comment-action-link" if current_user && comment.user == current_user %>

      <%= button_to "Delete", comment_path(comment, commentable_type: comment.commentable_type, commentable_id: comment.commentable_id), method: :delete, data: { turbo_confirm: "Delete comment?" }, class: "comment-action-link" if current_user && comment.user == current_user %>
    <% end %>

    <%= tag.div id: "reply-form-#{comment.id}", class: "reply-form hidden", data: { "comments-target": "replyForm" } do %>
      <%= render partial: "comments/form", locals: { comment: Comment.new(parent_id: comment.id), commentable: comment.commentable } %>
    <% end %>
    <% if comment.replies.any? %>

      <%= tag.div class: "comment-replies" do %>
        <% comment.replies.send(params[:sort] || "best").each do |reply| %>

          <%= render partial: "comments/comment", locals: { comment: reply } %>

        <% end %>
      <% end %>

    <% end %>

  <% end %>

<% end %>

EOF

  log "Comment partial generated"

}

generate_comment_form_partial() {

  log "Generating comment form partial"

  cat <<'EOF' > app/views/comments/_form.html.erb
<%= form_with(

  model: comment,
  url: comments_path(commentable_type: commentable.class.name, commentable_id: commentable.id),

  data: { turbo: true },
  class: "comment-form"

) do |form| %>

  <%= form.hidden_field :parent_id if comment.parent_id %>

  <%= tag.fieldset do %>

    <%= form.label :content, "Comment", class: "sr-only" %>

    <%= form.text_area :content,

      required: true,

      placeholder: "What are your thoughts?",
      data: { "textarea-autogrow-target": "input", action: "input->textarea-autogrow#resize" },

      rows: 3

    %>

  <% end %>

  <%= form.submit "Post Comment", class: "button" %>

<% end %>

EOF

  log "Comment form partial generated"

}
generate_comment_section_partial() {

  log "Generating comment section partial"

  cat <<'EOF' > app/views/shared/_comments.html.erb
<%= tag.section class: "comments-section", "aria-labelledby": "comments-heading" do %>

  <%= tag.h2 "Comments (#{commentable.comment_count})", id: "comments-heading" %>
  <%= tag.div class: "comment-sort", data: { controller: "comments" } do %>

    <%= link_to "Best", polymorphic_path(commentable, sort: "best"), class: params[:sort] == "best" ? "active" : "" %>
    <%= link_to "Top", polymorphic_path(commentable, sort: "top"), class: params[:sort] == "top" ? "active" : "" %>

    <%= link_to "New", polymorphic_path(commentable, sort: "new"), class: params[:sort] == "new" ? "active" : "" %>

    <%= link_to "Old", polymorphic_path(commentable, sort: "old"), class: params[:sort] == "old" ? "active" : "" %>
    <%= link_to "Controversial", polymorphic_path(commentable, sort: "controversial"), class: params[:sort] == "controversial" ? "active" : "" %>

  <% end %>

  <% if current_user %>

    <%= tag.div class: "comment-form-wrapper" do %>

      <%= render partial: "comments/form", locals: { comment: Comment.new, commentable: commentable } %>

    <% end %>

  <% else %>
    <%= tag.p "#{link_to 'Log in', new_session_path} or #{link_to 'sign up', new_registration_path} to comment.".html_safe %>

  <% end %>

  <%= tag.div id: "comments-list" do %>

    <% commentable.root_comments.send(params[:sort] || "best").each do |comment| %>

      <%= render partial: "comments/comment", locals: { comment: comment } %>

    <% end %>

  <% end %>
<% end %>

EOF

  log "Comment section partial generated"

}

add_reddit_routes() {

  log "Adding Reddit feature routes"

  # Insert routes inside the Rails.application.routes.draw block
  # Find the last 'end' and insert before it

  local routes_file="config/routes.rb"
  local temp_file="${routes_file}.tmp"

  # Read all lines except the last 'end', add routes, then add 'end'
  # Pure zsh route handling

  cat <<'EOF' >> "$temp_file"

  # Reddit features

  resources :votes, only: [:create]
  resources :comments, only: [:create, :edit, :update, :destroy]

end

EOF
  mv "$temp_file" "$routes_file"

  log "Reddit routes added"

}

setup_voting_features() {

  setup_reddit_models
  generate_comment_model
  generate_vote_model

  generate_user_karma_methods
  generate_votable_concern

  generate_commentable_concern

  generate_votes_controller

  generate_comments_controller

  generate_vote_partial

  generate_comment_partial

  generate_comment_form_partial

  generate_comment_section_partial

  add_reddit_routes

  log "Reddit features fully configured!"

}

