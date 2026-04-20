#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Social setup script – twitter style follow/timeline/hashtags/mentionsAPP_DIR="/home/brgen/app"
SCRIPT_TITLE="[social]"
GENERATE_CMD="bin/rails generate model"
MIGRATE_CMD="bin/rails db:migrate"

# Guard clause: exit early if app directory is missing
[[ -d $APP_DIR ]] || { echo "APP_DIR not found: $APP_DIR" >&2; exit 1; }

echo "==> $SCRIPT_TITLE Follow / timeline / hashtags / mentions"
cd "$APP_DIR" || exit 1

# Generate all models in a single command to reduce duplication
$GENERATE_CMD Follow follower_id:integer:index followed_id:integer:index
$GENERATE_CMD Hashtag name:string:uniq usage_count:integer:default[0]
$GENERATE_CMD Tagging taggable:references{polymorphic} hashtag:references
$GENERATE_CMD Mention mentionable:references{polymorphic} mentioned_user:references{user}

# Write file helper – avoids repeated redirection logic
write_file() {
  local path=$1 content=$2
  printf '%s\n' "$content" > "$path"
}

# Write generated model files with frozen string literal
write_file app/models/follow.rb <<'RUBY'
# frozen_string_literal: true
class Follow < ApplicationRecord
  belongs_to :follower, class_name: "User"
  belongs_to :followed, class_name: "User"
  validates :follower_id, uniqueness: { scope: :followed_id }
  validate  :no_self_follow

  private
  def no_self_follow
    errors.add(:base, "cannot follow yourself") if follower_id == followed_id
  end
end
RUBY

write_file app/models/hashtag.rb <<'RUBY'
# frozen_string_literal: true
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

write_file app/models/concerns/taggable.rb <<'RUBY'
# frozen_string_literal: true
module Taggable
  extend ActiveSupport::Concern
  included do
    has_many :taggings, as: :taggable, dependent: :destroy
    has_many :hashtags, through: :taggings
    after_save :sync_hashtags
  end  def hashtag_list = hashtags.pluck(:name).join(" ")
  private
  def sync_hashtags
    names = Hashtag.extract(try(:content).to_s + " " + try(:title).to_s)
    tags  = names.map { |n| Hashtag.find_or_create_by!(name: n).tap { |h| h.increment!(:usage_count) } }
    self.hashtags = tags
  end
end
RUBY

write_file app/models/concerns/mentionable.rb <<'RUBY'
# frozen_string_literal: true
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
    end  end
end
RUBY

# Append association and timeline methods to User
append_to_user!() {
  local snippet=$1  printf '%s\n' "$snippet" >> app/models/user.rb
}
append_to_user! '
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
  def following?
    follows_as_follower.exists?(followed: other)
  end
  def timeline_posts    Post.where(user: [self] + following).order(created_at: :desc)
  end
'

# Create follows controller
write_file app/controllers/follows_controller.rb <<'RUBY'
# frozen_string_literal: true
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

# Run database migrations
$MIGRATE_CMD

echo "==> $SCRIPT_TITLE done"