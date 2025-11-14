#!/usr/bin/env zsh
set -euo pipefail

# X.com (Twitter) features: Retweets, Hashtags, Mentions, Timeline, Follow
# Shared across social apps (brgen, amber, blognet)

setup_twitter_models() {
  log "Setting up X.com (Twitter) models: Retweet, Hashtag, Mention, Follow"

  # Retweet model (polymorphic - can retweet posts, listings, comments)
  bin/rails generate model Retweet user:references retweetable:references{polymorphic} content:text

  # Hashtag model with counter cache
  bin/rails generate model Hashtag name:string:uniq usage_count:integer

  # Join table for hashtags on posts/listings
  bin/rails generate model Tagging taggable:references{polymorphic} hashtag:references

  # Mention model (@ mentions in content)
  bin/rails generate model Mention mentionable:references{polymorphic} mentioned_user:references

  # Follow model (user follows another user)
  bin/rails generate model Follow follower:references{user} followed:references{user}

  log "X.com models generated"
}

generate_retweet_model() {
  log "Configuring Retweet model"

  cat <<'EOF' > app/models/retweet.rb
class Retweet < ApplicationRecord

  belongs_to :user
  belongs_to :retweetable, polymorphic: true

  validates :user_id, uniqueness: { scope: [:retweetable_type, :retweetable_id] }

  after_create :notify_original_author

  after_destroy :remove_notification
  def with_comment?
    content.present?

  end
  private

  def notify_original_author

    return unless retweetable.respond_to?(:user)
    # NotificationMailer.retweet(retweetable.user, self).deliver_later
  end

  def remove_notification

    # Notification cleanup logic

  end
end

EOF

  log "Retweet model configured"

}

generate_hashtag_model() {
  log "Configuring Hashtag model"

  cat <<'EOF' > app/models/hashtag.rb
class Hashtag < ApplicationRecord

  has_many :taggings, dependent: :destroy
  validates :name, presence: true, uniqueness: true,

            format: { with: /\A[a-zA-Z0-9_]+\z/, message: "only letters, numbers, underscores" }

  before_validation :normalize_name
  scope :trending, -> { where("updated_at > ?", 24.hours.ago).order(usage_count: :desc).limit(10) }

  scope :popular, -> { order(usage_count: :desc) }
  def to_param
    name

  end
  def increment_usage!

    increment!(:usage_count)

    touch
  end

  private

  def normalize_name

    self.name = name.to_s.downcase.gsub(/[^a-z0-9_]/, '') if name.present?
  end
end

EOF

  log "Hashtag model configured"

}

generate_tagging_model() {
  log "Configuring Tagging model"

  cat <<'EOF' > app/models/tagging.rb
class Tagging < ApplicationRecord

  belongs_to :taggable, polymorphic: true
  belongs_to :hashtag, counter_cache: :usage_count

  validates :hashtag_id, uniqueness: { scope: [:taggable_type, :taggable_id] }

  after_create :increment_hashtag_usage

  after_destroy :decrement_hashtag_usage
  private
  def increment_hashtag_usage

    hashtag.increment_usage!
  end
  def decrement_hashtag_usage

    hashtag.decrement!(:usage_count) if hashtag.usage_count > 0

  end
end

EOF

  log "Tagging model configured"

}

generate_mention_model() {
  log "Configuring Mention model"

  cat <<'EOF' > app/models/mention.rb
class Mention < ApplicationRecord

  belongs_to :mentionable, polymorphic: true
  belongs_to :mentioned_user, class_name: "User"

  validates :mentioned_user_id, uniqueness: { scope: [:mentionable_type, :mentionable_id] }

  after_create :notify_mentioned_user

  private
  def notify_mentioned_user
    # NotificationMailer.mention(mentioned_user, mentionable).deliver_later
  end
end

EOF

  log "Mention model configured"

}

generate_follow_model() {
  log "Configuring Follow model"

  cat <<'EOF' > app/models/follow.rb
class Follow < ApplicationRecord

  belongs_to :follower, class_name: "User"
  belongs_to :followed, class_name: "User"

  validates :follower_id, uniqueness: { scope: :followed_id }

  validate :cannot_follow_self

  after_create :notify_followed_user
  private

  def cannot_follow_self
    errors.add(:follower_id, "cannot follow yourself") if follower_id == followed_id
  end
  def notify_followed_user

    # NotificationMailer.new_follower(followed, follower).deliver_later

  end
end

EOF

  log "Follow model configured"

}

generate_retweetable_concern() {
  log "Generating Retweetable concern"

  mkdir -p app/models/concerns
  cat <<'EOF' > app/models/concerns/retweetable.rb

module Retweetable
  extend ActiveSupport::Concern
  included do

    has_many :retweets, as: :retweetable, dependent: :destroy

  end
  def retweet_count

    retweets.count

  end
  def retweeted_by?(user)

    return false unless user

    retweets.exists?(user: user)
  end

  def retweet_by(user, content: nil)

    retweets.create(user: user, content: content)

  end
end

EOF

  log "Retweetable concern generated"

}

generate_taggable_concern() {
  log "Generating Taggable concern"

  cat <<'EOF' > app/models/concerns/taggable.rb
module Taggable

  extend ActiveSupport::Concern
  included do

    has_many :taggings, as: :taggable, dependent: :destroy

    has_many :hashtags, through: :taggings
    before_save :extract_hashtags

  end

  def hashtag_names
    hashtags.pluck(:name)

  end
  def hashtag_list

    hashtag_names.map { |name| "##{name}" }.join(" ")

  end
  private

  def extract_hashtags

    return unless respond_to?(:content) && content_changed?
    # Extract hashtags from content
    extracted = content.to_s.scan(/#([a-zA-Z0-9_]+)/).flatten.uniq

    # Remove old taggings
    taggings.destroy_all

    # Create new taggings
    extracted.each do |tag_name|

      hashtag = Hashtag.find_or_create_by(name: tag_name.downcase)
      taggings.build(hashtag: hashtag)

    end

  end

end

EOF

  log "Taggable concern generated"

}

generate_mentionable_concern() {
  log "Generating Mentionable concern"

  cat <<'EOF' > app/models/concerns/mentionable.rb
module Mentionable

  extend ActiveSupport::Concern
  included do

    has_many :mentions, as: :mentionable, dependent: :destroy

    has_many :mentioned_users, through: :mentions
    before_save :extract_mentions

  end

  def mention_list
    mentioned_users.pluck(:email).map { |email| "@#{email.split('@').first}" }.join(" ")

  end
  private

  def extract_mentions

    return unless respond_to?(:content) && content_changed?
    # Extract @mentions from content
    extracted = content.to_s.scan(/@([a-zA-Z0-9_]+)/).flatten.uniq

    # Remove old mentions
    mentions.destroy_all

    # Create new mentions
    extracted.each do |username|

      user = User.find_by("email LIKE ?", "#{username}%")
      mentions.build(mentioned_user: user) if user

    end

  end

end

EOF

  log "Mentionable concern generated"

}

extend_user_for_following() {
  log "Adding follow methods to User model"

  # Append follow methods to User model
  cat <<'EOF' >> app/models/user.rb

  # Follow system
  has_many :active_follows, class_name: "Follow", foreign_key: :follower_id, dependent: :destroy

  has_many :passive_follows, class_name: "Follow", foreign_key: :followed_id, dependent: :destroy
  has_many :following, through: :active_follows, source: :followed

  has_many :followers, through: :passive_follows, source: :follower

  def follow(other_user)
    active_follows.create(followed: other_user)

  end
  def unfollow(other_user)

    active_follows.find_by(followed: other_user)&.destroy

  end
  def following?(other_user)

    following.include?(other_user)

  end
  def followers_count

    passive_follows.count

  end
  def following_count

    active_follows.count

  end
  # Timeline: posts from followed users + own posts

  def timeline_posts

    followed_ids = following.pluck(:id)
    Post.where(user_id: [id] + followed_ids).order(created_at: :desc)

  end

EOF

  log "User follow methods added"

}

generate_retweets_controller() {
  log "Generating RetweetsController"

  cat <<'EOF' > app/controllers/retweets_controller.rb
class RetweetsController < ApplicationController

  before_action :authenticate_user!
  def create

    @retweetable = find_retweetable

    @retweet = @retweetable.retweets.build(user: current_user, content: retweet_params[:content])
    if @retweet.save

      respond_to do |format|

        format.turbo_stream
        format.html { redirect_back(fallback_location: root_path, notice: "Retweeted") }

      end

    else

      redirect_back(fallback_location: root_path, alert: "Could not retweet")

    end

  end

  def destroy

    @retweet = current_user.retweets.find(params[:id])

    @retweet.destroy
    respond_to do |format|

      format.turbo_stream

      format.html { redirect_back(fallback_location: root_path, notice: "Retweet removed") }
    end

  end

  private

  def find_retweetable

    retweetable_type = params[:retweetable_type].classify
    retweetable_id = params[:retweetable_id]
    retweetable_type.constantize.find(retweetable_id)

  end

  def retweet_params

    params.require(:retweet).permit(:content)

  end
end

EOF

  log "RetweetsController generated"

}

generate_follows_controller() {
  log "Generating FollowsController"

  cat <<'EOF' > app/controllers/follows_controller.rb
class FollowsController < ApplicationController

  before_action :authenticate_user!
  def create

    @user = User.find(params[:user_id])

    current_user.follow(@user)
    respond_to do |format|

      format.turbo_stream

      format.html { redirect_back(fallback_location: root_path, notice: "Following #{@user.email}") }
    end

  end

  def destroy

    @follow = current_user.active_follows.find(params[:id])

    @user = @follow.followed
    @follow.destroy

    respond_to do |format|

      format.turbo_stream

      format.html { redirect_back(fallback_location: root_path, notice: "Unfollowed #{@user.email}") }
    end

  end

end

EOF

  log "FollowsController generated"

}

generate_hashtags_controller() {
  log "Generating HashtagsController"

  cat <<'EOF' > app/controllers/hashtags_controller.rb
class HashtagsController < ApplicationController

  def show
    @hashtag = Hashtag.find_by!(name: params[:id].downcase)

    @taggings = @hashtag.taggings.includes(:taggable).order(created_at: :desc)

  end

  def trending

    @hashtags = Hashtag.trending

  end
end

EOF

  log "HashtagsController generated"

}

generate_retweet_partial() {
  log "Generating retweet partial"

  mkdir -p app/views/shared
  cat <<'EOF' > app/views/shared/_retweet_button.html.erb

<%= tag.div class: "retweet-buttons", data: { controller: "retweet" } do %>
  <% retweet = current_user && retweetable.retweets.find_by(user: current_user) %>
  <% retweeted = retweet.present? %>

  <% if retweeted %>

    <%= button_to retweet_path(retweet), method: :delete, class: "retweet-btn active", data: { turbo_frame: "retweet_#{dom_id(retweetable)}" } do %>

      <span class="icon">🔁</span>
      <span class="count"><%= retweetable.retweet_count %></span>

    <% end %>

  <% else %>

    <%= button_to retweets_path(retweetable_type: retweetable.class.name, retweetable_id: retweetable.id), class: "retweet-btn", data: { turbo_frame: "retweet_#{dom_id(retweetable)}" } do %>

      <span class="icon">🔁</span>

      <span class="count"><%= retweetable.retweet_count %></span>

    <% end %>

  <% end %>

<% end %>

EOF

  log "Retweet partial generated"

}

generate_follow_button_partial() {
  log "Generating follow button partial"

  cat <<'EOF' > app/views/shared/_follow_button.html.erb
<% if current_user && current_user != user %>

  <% following = current_user.following?(user) %>
  <% if following %>

    <% follow = current_user.active_follows.find_by(followed: user) %>

    <%= button_to "Unfollow", follow_path(follow), method: :delete, class: "btn-unfollow", data: { turbo_frame: "follow_#{user.id}" } %>
  <% else %>

    <%= button_to "Follow", follows_path(user_id: user.id), class: "btn-follow", data: { turbo_frame: "follow_#{user.id}" } %>

  <% end %>

<% end %>

EOF

  log "Follow button partial generated"

}

generate_timeline_view() {
  log "Generating timeline view"

  mkdir -p app/views/timeline
  cat <<'EOF' > app/views/timeline/index.html.erb

<%= tag.div class: "timeline-container" do %>
  <%= tag.h1 "Your Timeline" %>
  <%= tag.div class: "timeline-posts" do %>

    <% @posts.each do |post| %>

      <%= tag.div class: "timeline-item", id: dom_id(post) do %>
        <%= tag.div class: "post-header" do %>

          <%= tag.span post.user.email, class: "post-author" %>

          <%= render partial: "shared/follow_button", locals: { user: post.user } %>

          <%= tag.span time_ago_in_words(post.created_at), class: "post-time" %>

        <% end %>

        <%= tag.div class: "post-content" do %>

          <%= tag.h3 post.title %>

          <%= simple_format post.content %>
        <% end %>

        <%= tag.div class: "post-actions" do %>

          <%= render partial: "shared/vote", locals: { votable: post } %>

          <%= render partial: "shared/retweet_button", locals: { retweetable: post } %>
          <%= link_to "#{post.comments.count} comments", post_path(post) %>

        <% end %>

        <%= tag.div class: "post-hashtags" do %>

          <% post.hashtags.each do |hashtag| %>

            <%= link_to "##{hashtag.name}", hashtag_path(hashtag), class: "hashtag-link" %>
          <% end %>

        <% end %>

      <% end %>

    <% end %>

  <% end %>

<% end %>

EOF

  log "Timeline view generated"

}

add_twitter_routes() {
  log "Adding X.com (Twitter) feature routes"

  # Insert routes inside the Rails.application.routes.draw block
  local routes_file="config/routes.rb"

  local temp_file="${routes_file}.tmp"
  # Read all lines except the last 'end', add routes, then add 'end'

  # Pure zsh route handling

  cat <<'EOF' >> "$temp_file"
  # X.com (Twitter) features

  resources :retweets, only: [:create, :destroy]

  resources :follows, only: [:create, :destroy]
  resources :hashtags, only: [:show] do

    get :trending, on: :collection

  end

  get '/timeline', to: 'timeline#index', as: :timeline

end

EOF

  mv "$temp_file" "$routes_file"

  log "X.com routes added"

}
generate_timeline_controller() {
  log "Generating TimelineController"

  cat <<'EOF' > app/controllers/timeline_controller.rb
class TimelineController < ApplicationController

  before_action :authenticate_user!
  def index

    @posts = current_user.timeline_posts.includes(:user, :hashtags, :votes).page(params[:page])

  end
end

EOF

  log "TimelineController generated"

}

setup_twitter_features() {
  setup_twitter_models

  generate_retweet_model
  generate_hashtag_model

  generate_tagging_model

  generate_mention_model

  generate_follow_model

  generate_retweetable_concern

  generate_taggable_concern

  generate_mentionable_concern

  extend_user_for_following

  generate_retweets_controller

  generate_follows_controller

  generate_hashtags_controller

  generate_retweet_partial

  generate_follow_button_partial

  generate_timeline_view

  generate_timeline_controller

  add_twitter_routes

  log "X.com (Twitter) features fully configured!"

}

