#!/usr/bin/env zsh
# __shared/@twitter_features.sh — Twitter-style posts, follows, hashtags for Rails 8
# Source from app installers. Do not execute directly.
set -euo pipefail

setup_twitter_models() {
  log "Setting up Twitter-style models"

  generate_model Post \
    user:references content:string \
    likes_count:integer:default[0] \
    reposts_count:integer:default[0] \
    replies_count:integer:default[0] \
    in_reply_to_id:integer

  generate_model Follow \
    follower:references{User} following:references{User}

  generate_model Like \
    user:references likeable:references{polymorphic}:index

  generate_model Repost \
    user:references post:references quote:text

  generate_model Hashtag name:string:uniq posts_count:integer:default[0]

  generate_model Tagging \
    post:references hashtag:references

  generate_model Notification \
    user:references actor:references{User} \
    notifiable:references{polymorphic}:index \
    action:string read_at:datetime

  log_ok "Twitter models ready"
}

write_twitter_model_logic() {
  cat > app/models/post.rb << 'RUBY'
class Post < ApplicationRecord
  belongs_to :user
  belongs_to :reply_to, class_name: "Post", foreign_key: :in_reply_to_id, optional: true

  has_many :replies, class_name: "Post", foreign_key: :in_reply_to_id, dependent: :destroy
  has_many :likes, as: :likeable, dependent: :destroy
  has_many :reposts, dependent: :destroy
  has_many :taggings, dependent: :destroy
  has_many :hashtags, through: :taggings

  validates :content, presence: true, length: { maximum: 280 }

  after_create_commit :extract_hashtags
  after_create_commit :notify_mentions
  after_create_commit :broadcast_to_followers

  scope :chronological, -> { order(created_at: :desc) }
  scope :for_feed, ->(user) {
    where(user: user.following + [user])
      .where(in_reply_to_id: nil)
      .chronological
  }

  private

  def extract_hashtags
    tags = content.scan(/#([\w]+)/).flatten.uniq
    tags.each do |tag|
      h = Hashtag.find_or_create_by!(name: tag.downcase)
      taggings.find_or_create_by!(hashtag: h)
      h.increment!(:posts_count)
    end
  end

  def notify_mentions
    content.scan(/@(\w+)/).flatten.each do |handle|
      mentioned = User.find_by(username: handle)
      next unless mentioned && mentioned != user
      Notification.create!(
        user: mentioned, actor: user,
        notifiable: self, action: "mention"
      )
    end
  end

  def broadcast_to_followers
    user.followers.each do |follower|
      broadcast_prepend_to [follower, "feed"], partial: "posts/post", locals: { post: self }
    end
  end
end
RUBY

  cat > app/models/follow.rb << 'RUBY'
class Follow < ApplicationRecord
  belongs_to :follower, class_name: "User"
  belongs_to :following, class_name: "User"

  validates :follower_id, uniqueness: { scope: :following_id }
  validate :no_self_follow

  after_create_commit  :notify_following
  after_destroy :decrement_counts

  private

  def no_self_follow
    errors.add(:base, "cannot follow yourself") if follower_id == following_id
  end

  def notify_following
    Notification.create!(
      user: following, actor: follower,
      notifiable: self, action: "follow"
    )
  end

  def decrement_counts; end
end
RUBY

  cat > app/models/user.rb << 'RUBY'
class User < ApplicationRecord
  has_secure_password

  has_many :sessions, dependent: :destroy
  has_many :posts, dependent: :destroy
  has_many :likes, dependent: :destroy
  has_many :reposts, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :sent_follows,     class_name: "Follow", foreign_key: :follower_id,  dependent: :destroy
  has_many :received_follows, class_name: "Follow", foreign_key: :following_id, dependent: :destroy
  has_many :following, through: :sent_follows,    source: :following
  has_many :followers, through: :received_follows, source: :follower

  has_one_attached :avatar

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :username, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }, length: { maximum: 30 }

  normalizes :email_address, with: -> e { e.strip.downcase }

  def follow!(other)
    sent_follows.find_or_create_by!(following: other)
  end

  def unfollow!(other)
    sent_follows.find_by(following: other)&.destroy!
  end

  def following?(other)
    sent_follows.exists?(following: other)
  end
end
RUBY
  log_ok "Twitter model logic written"
}

write_twitter_controllers() {
  cat > app/controllers/posts_controller.rb << 'RUBY'
class PostsController < ApplicationController
  before_action :require_authentication, except: %i[index show]

  def index
    @posts = Post.includes(:user).for_feed(Current.user).limit(50)
  end

  def show
    @post    = Post.find(params[:id])
    @replies = @post.replies.includes(:user).chronological
    @reply   = Post.new(in_reply_to_id: @post.id)
  end

  def new
    @post = Post.new
  end

  def create
    @post = Current.user.posts.build(post_params)
    if @post.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to root_path }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @post = Current.user.posts.find(params[:id])
    @post.destroy!
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to root_path }
    end
  end

  private

  def post_params
    params.require(:post).permit(:content, :in_reply_to_id)
  end
end
RUBY

  cat > app/controllers/follows_controller.rb << 'RUBY'
class FollowsController < ApplicationController
  before_action :require_authentication

  def create
    user = User.find(params[:user_id])
    Current.user.follow!(user)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to user }
    end
  end

  def destroy
    user = User.find(params[:user_id])
    Current.user.unfollow!(user)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to user }
    end
  end
end
RUBY

  cat > app/controllers/likes_controller.rb << 'RUBY'
class LikesController < ApplicationController
  before_action :require_authentication

  LIKEABLE_TYPES = %w[Post].freeze

  def create
    likeable = find_likeable
    unless Like.exists?(user: Current.user, likeable: likeable)
      Like.create!(user: Current.user, likeable: likeable)
      likeable.increment!(:likes_count)
    end
    respond_to do |format|
      format.turbo_stream
      format.json { render json: { count: likeable.likes_count } }
    end
  end

  def destroy
    likeable = find_likeable
    like = Like.find_by(user: Current.user, likeable: likeable)
    if like
      like.destroy!
      likeable.decrement!(:likes_count)
    end
    respond_to do |format|
      format.turbo_stream
      format.json { render json: { count: likeable.likes_count } }
    end
  end

  private

  def find_likeable
    type = params[:likeable_type]
    raise ArgumentError unless LIKEABLE_TYPES.include?(type)
    type.constantize.find(params[:likeable_id])
  end
end
RUBY
  log_ok "Twitter controllers written"
}
