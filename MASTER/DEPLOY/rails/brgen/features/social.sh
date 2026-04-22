#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# ----------------------------------------------------------------------
# Social feature bootstrap – follows, timelines, hashtags, mentions
# ----------------------------------------------------------------------
APP_DIR="${0:A:h}/../../.."  # project root relative to script location
SCRIPT_TITLE="[social]"
GENERATE_CMD="bin/rails generate model"
MIGRATE_CMD="bin/rails db:migrate"

# ----------------------------------------------------------------------
# Guard: abort if the Rails application is not present
# ----------------------------------------------------------------------
[[ -d $APP_DIR ]] || {
  printf 'APP_DIR not found: %s\n' "$APP_DIR" >&2
  exit 1
}

printf '==> %s Starting\n' "$SCRIPT_TITLE"
cd "$APP_DIR" || exit 1

# ----------------------------------------------------------------------
# Helper: write a file, creating parent directories if needed.
# Overwrites only when content differs to keep idempotence.
# ----------------------------------------------------------------------
write_file() {
  local path=$1
  local content=$2
  local dir=${path:h}
  mkdir -p "$dir"
  if [[ -f $path && $(<"$path") == "$content" ]]; then
    return
  fi
  printf '%s\n' "$content" > "$path"
}

# ----------------------------------------------------------------------
# Generate models – idempotent: skip if model file already exists
# ----------------------------------------------------------------------
generate_if_missing() {
  local name=$1
  shift
  local dest="app/models/${${name:l}.underscore}.rb"
  if [[ -f $dest ]]; then
    printf 'model %s already exists, skipping generation\n' "$name"
  else
    $GENERATE_CMD "$name" "$@"
  fi
}

generate_if_missing Follow follower_id:integer:index followed_id:integer:index
generate_if_missing Hashtag name:string:uniq usage_count:integer:default[0]
generate_if_missing Tagging taggable:references{polymorphic} hashtag:references
generate_if_missing Mention mentionable:references{polymorphic} mentioned_user:references{user}

# ----------------------------------------------------------------------
# Model definitions – frozen string literal, minimal dependencies
# ----------------------------------------------------------------------
write_file app/models/follow.rb <<'RUBY'
# frozen_string_literal: true

class Follow < ApplicationRecord
  belongs_to :follower, class_name: "User"
  belongs_to :followed, class_name: "User"

  validates :follower_id, uniqueness: { scope: :followed_id }
  validate :no_self_follow

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
  end

  def hashtag_list = hashtags.pluck(:name).join(" ")

  private

  def sync_hashtags
    names = Hashtag.extract([try(:content), try(:title)].compact.join(" "))
    tags = names.map { |n| Hashtag.find_or_create_by!(name: n).tap { |h| h.increment!(:usage_count) } }
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
    usernames = [try(:content), try(:title)].compact.join(" ").scan(/@(\w+)/).flatten.uniq
    usernames.each do |uname|
      user = User.find_by(username: uname)
      next unless user && user != try(:user)

      mentions.find_or_create_by!(mentioned_user: user)
    end
  end
end
RUBY

# ----------------------------------------------------------------------
# Append associations & timeline helpers to User model – idempotent
# ----------------------------------------------------------------------
USER_MODEL="app/models/user.rb"
if [[ -f $USER_MODEL ]]; then
  if ! grep -q "has_many :follows_as_follower" "$USER_MODEL"; then
    cat >>"$USER_MODEL" <<'RUBY'

  # Social associations
  has_many :follows_as_follower, class_name: "Follow", foreign_key: :follower_id, dependent: :destroy
  has_many :follows_as_followed,  class_name: "Follow", foreign_key: :followed_id, dependent: :destroy
  has_many :following, through: :follows_as_follower, source: :followed
  has_many :followers, through: :follows_as_followed, source: :follower

  # Convenience helpers
  def follow!(other)
    follows_as_follower.find_or_create_by!(followed: other) unless other == self
  end

  def unfollow!(other)
    follows_as_follower.find_by(followed: other)&.destroy
  end

  def following?(other)
    follows_as_follower.exists?(followed: other)
  end

  def timeline_posts
    Post.where(user: [self] + following).order(created_at: :desc)
  end
RUBY
  else
    printf 'User model already contains social associations, skipping append\n'
  fi
else
  printf 'User model not found at %s, cannot append social code\n' "$USER_MODEL" >&2
fi

# ----------------------------------------------------------------------
# Controller for follow actions
# ----------------------------------------------------------------------
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

# ----------------------------------------------------------------------
# Run migrations – fail fast if migration errors occur
# ----------------------------------------------------------------------
$MIGRATE_CMD

printf '==> %s done\n' "$SCRIPT_TITLE"
