#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Twitter-style: follow, timeline, hashtags, mentions — pub3/@twitter_features.sh

typeset -r APP_DIR="/home/brgen/app"

echo "==> [social] Follow / timeline / hashtags / mentions"
cd "$APP_DIR"

bin/rails generate model Follow  follower_id:integer:index followed_id:integer:index
bin/rails generate model Hashtag name:string:uniq usage_count:integer:default[0]
bin/rails generate model Tagging  taggable:references{polymorphic} hashtag:references
bin/rails generate model Mention  mentionable:references{polymorphic} mentioned_user:references{user}

cat > app/models/follow.rb << 'RUBY'
class Follow < ApplicationRecord
  belongs_to :follower,  class_name: "User"
  belongs_to :followed,  class_name: "User"

  validates :follower_id, uniqueness: { scope: :followed_id }
  validate  :no_self_follow

  private
  def no_self_follow
    errors.add(:base, "cannot follow yourself") if follower_id == followed_id
  end
end
RUBY

cat > app/models/hashtag.rb << 'RUBY'
class Hashtag < ApplicationRecord
  has_many :taggings, dependent: :destroy

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  before_validation { self.name = name.to_s.downcase.gsub(/[^a-z0-9_]/, "") }

  scope :trending, -> { order(usage_count: :desc) }

  def self.extract(text)
    text.to_s.scan(/#([a-zA-Z0-9_]+)/).flatten.map(&:downcase).uniq
  end
end
RUBY

cat > app/models/concerns/taggable.rb << 'RUBY'
module Taggable
  extend ActiveSupport::Concern

  included do
    has_many :taggings, as: :taggable, dependent: :destroy
    has_many :hashtags, through: :taggings
    after_save :sync_hashtags
  end

  def hashtag_list = hashtags.pluck(:name).join(" ")

  private

  def sync_hashtags
    names = Hashtag.extract(try(:content).to_s + " " + try(:title).to_s)
    tags  = names.map { |n| Hashtag.find_or_create_by!(name: n).tap { |h| h.increment!(:usage_count) } }
    self.hashtags = tags
  end
end
RUBY

cat > app/models/concerns/mentionable.rb << 'RUBY'
module Mentionable
  extend ActiveSupport::Concern

  included do
    after_save :sync_mentions
  end

  private

  def sync_mentions
    usernames = (try(:content).to_s + " " + try(:title).to_s).scan(/@(\w+)/).flatten.uniq
    usernames.each do |uname|
      user = User.find_by(username: uname)
      mentions.find_or_create_by!(mentioned_user: user) if user && user != try(:user)
    end
  end
end
RUBY

# Append follow methods to User
cat >> app/models/user.rb << 'RUBY'

  has_many :follows_as_follower, class_name: "Follow", foreign_key: :follower_id, dependent: :destroy
  has_many :follows_as_followed, class_name: "Follow", foreign_key: :followed_id, dependent: :destroy
  has_many :following, through: :follows_as_follower, source: :followed
  has_many :followers,  through: :follows_as_followed, source: :follower

  def follow!(other)
    follows_as_follower.find_or_create_by!(followed: other) unless other == self
  end

  def unfollow!(other)
    follows_as_follower.find_by(followed: other)&.destroy
  end

  def following?(other) = follows_as_follower.exists?(followed: other)

  def timeline_posts
    Post.where(user: [self] + following).order(created_at: :desc)
  end
RUBY

cat > app/controllers/follows_controller.rb << 'RUBY'
class FollowsController < ApplicationController
  before_action :authenticate_user!

  def create
    user = User.find(params[:user_id])
    current_user.follow!(user)
    redirect_back fallback_location: root_path
  end

  def destroy
    user = User.find(params[:user_id])
    current_user.unfollow!(user)
    redirect_back fallback_location: root_path
  end
end
RUBY

bin/rails db:migrate
echo "==> [social] done"
