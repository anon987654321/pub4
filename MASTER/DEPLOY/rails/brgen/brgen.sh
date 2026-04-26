#!/usr/bin/env sh
# -*- mode: sh; -*-
set -euo pipefail

# BRGEN v3.0.0 – Rails 8 Complete Social Network
VERSION=${VERSION:-3.0.0}
APP_DIR=${APP_DIR:-/home/brgen/app}
PORT=${PORT:-11006}
MAX_COMMENT_LENGTH=${MAX_COMMENT_LENGTH:-10000}
MAX_KARMA_SEED=${MAX_KARMA_SEED:-1000}
HOT_DECAY_EXPONENT=${HOT_DECAY_EXPONENT:-1.5}

printf '==> BRGEN v%s – Rails 8 Complete Setup\n' "$VERSION"

# ── Validation ───────────────────────────────────────────────────────────────
if [ ! -d "$APP_DIR" ]; then
  printf 'ERROR: %s missing. Run: doas sh openbsd.sh --pre-point\n' "$APP_DIR" >&2
  exit 1
fi

# Ensure Rails CLI is available
if ! command -v rails >/dev/null 2>&1; then
  printf 'ERROR: rails command not found in PATH\n' >&2
  exit 1
fi

cd "$APP_DIR"
printf 'Working in: %s\n' "$APP_DIR"

# ── Rails app creation ──────────────────────────────────────────────────────
if [ ! -f config/application.rb ]; then
  printf 'Creating Rails 8 application\n'
  rails new . --database=postgresql --skip-git --css=tailwind --javascript=esbuild
fi

# ── Gemfile augmentation ───────────────────────────────────────────────────
printf 'Appending gems to Gemfile\n'
if ! grep -q 'solid_queue' Gemfile; then
  cat >> Gemfile <<'EOF'

# Rails 8 Solid Stack
gem "solid_queue"
gem "solid_cache"
gem "solid_cable"

# Authentication
gem "bcrypt", "~> 3.1"

# Voting
gem "acts_as_votable"

# Real‑time
gem "stimulus_reflex", "~> 3.5"
gem "cable_ready", "~> 5.0"

# Multi‑tenancy
gem "devise"
gem "devise-guests"
gem "acts_as_tenant"

# Misc features
gem "pagy"
gem "image_processing"
gem "geocoder"
gem "langchainrb"
gem "ruby-openai"
gem "serviceworker-rails"

group :development, :test do
  gem "brakeman"
  gem "rubocop-rails-omakase"
  gem "faker"
end

EOF
fi

bundle install

# ── Acts as votable ────────────────────────────────────────────────────────
printf 'Installing acts_as_votable\n'
bin/rails generate acts_as_votable:migration
bin/rails db:migrate

# ── Solid Stack installation ───────────────────────────────────────────────
printf 'Installing Solid Stack\n'
bin/rails generate solid_queue:install
bin/rails generate solid_cache:install
bin/rails generate solid_cable:install

# ── Authentication scaffolding ───────────────────────────────────────────────
printf 'Installing Rails 8 authentication\n'
if [ ! -f app/models/session.rb ]; then
  bin/rails generate authentication
fi

# ── Database configuration ─────────────────────────────────────────────────
printf 'Configuring PostgreSQL\n'
sed -i.bak \
    -e 's/database: app_/database: brgen_/' \
    -e 's/username: brgen/username: brgen_user/' \
    config/database.yml && rm -f config/database.yml.bak

# ── Core models ───────────────────────────────────────────────────────────────
printf 'Generating core models\n'
models=(
  'Community name:string description:text subdomain:string:uniq slug:string:uniq'
  'Post title:string content:text user:references community:references karma:integer:default[0] anonymous:boolean:default[false]'
  'Comment content:text user:references commentable:references{polymorphic}:index parent_id:integer'
  'Reaction kind:string user:references post:references'
  'Stream content_type:string url:string user:references post:references duration:integer'
)
for spec in "${models[@]}"; do
  bin/rails generate model $spec
done

bin/rails generate migration AddFieldsToUsers username:string karma:integer:default=0 location:point

cat >> app/models/user.rb <<'RUBY'

# Voting
acts_as_voter

# Associations
has_many :posts, dependent: :destroy
has_many :comments, dependent: :destroy
has_many :communities

# Validations
validates :username, presence: true, uniqueness: true

# Update karma from votes received
def update_karma_from_votes
  total = posts.sum { |p| p.cached_votes_score } +
          comments.sum { |c| c.cached_votes_score }
  update_column(:karma, total)
end
RUBY

bin/rails db:migrate

# ── Model concerns ────────────────────────────────────────────────────────────
printf 'Creating model concerns\n'
mkdir -p app/models/concerns
cat > app/models/concerns/commentable.rb <<'RUBY'
module Commentable
  extend ActiveSupport::Concern

  included do
    has_many :comments, as: :commentable, dependent: :destroy
  end

  def comment_count
    comments.size
  end
end
RUBY

# ── Model overrides ───────────────────────────────────────────────────────────
cat > app/models/community.rb <<'RUBY'
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

cat > app/models/post.rb <<'RUBY'
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

  validates :title, presence: true, length: { maximum: 300 }
  validates :content, presence: true

  scope :hot, -> {
    left_joins(:votes)
      .group(:id)
      .select(<<~SQL
        posts.*,
        SUM(COALESCE(votes.value, 0)) AS vote_sum,
        EXTRACT(EPOCH FROM (NOW() - posts.created_at)) / 3600 AS hours_old
      SQL
      )
      .order(Arel.sql("vote_sum / POWER(hours_old + 2, #{HOT_DECAY_EXPONENT}) DESC"))
  }

  scope :top, -> { left_joins(:votes).group(:id).order("SUM(COALESCE(votes.value,0)) DESC") }
  scope :new_first, -> { order(created_at: :desc) }

  def update_karma
    update_column(:karma, get_upvotes.size - get_downvotes.size)
  end
end
RUBY

cat > app/models/comment.rb <<'RUBY'
class Comment < ApplicationRecord
  include Votable

  acts_as_votable
  belongs_to :user
  belongs_to :commentable, polymorphic: true
  belongs_to :parent, class_name: 'Comment', optional: true
  has_many :replies, class_name: 'Comment', foreign_key: :parent_id, dependent: :destroy

  validates :content,
            presence: true,
            length: { minimum: 1, maximum: ${MAX_COMMENT_LENGTH} }

  def root?
    parent_id.nil?
  end

  def depth
    parent ? parent.depth + 1 : 0
  end

  scope :best, -> { left_joins(:votes).group(:id).order("SUM(COALESCE(votes.value,0)) DESC") }
  scope :new_first, -> { order(created_at: :desc) }
end
RUBY

# ── Routes ────────────────────────────────────────────────────────────────────
printf 'Configuring routes\n'
cat > config/routes.rb <<'RUBY'
Rails.application.routes.draw do
  devise_for :users

  resources :communities, only: %i[index show] do
    resources :posts, shallow: true
  end

  resources :posts do
    resources :comments, only: %i[create destroy]

    member do
      post :upvote
      post :downvote
    end
  end

  resources :votes, only: %i[create destroy]

  root "communities#index"
end
RUBY

# ── Controllers (authz) ───────────────────────────────────────────────────────
printf 'Generating controllers\n'
cat > app/controllers/posts_controller.rb <<'RUBY'
class PostsController < ApplicationController
  before_action :authenticate_user!, except: %i[index show]
  before_action :set_post, only: %i[show edit update destroy upvote downvote]
  before_action :authorize_user!, only: %i[edit update destroy]

  def index
    @posts = Post.includes(:user, :community).hot.page(params[:page])
  end

  def show
    @comments = @post.comments.best
  end

  def new
    @post = current_user.posts.build
  end

  def create
    @post = current_user.posts.build(post_params)
    if @post.save
      redirect_to @post, notice: t('brgen.post_created')
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @post.update(post_params)
      redirect_to @post, notice: t('brgen.post_updated')
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @post.destroy
    redirect_to posts_path, notice: t('brgen.post_deleted')
  end

  def upvote
    @post.upvote_by(current_user)
    respond_to_vote
  end

  def downvote
    @post.downvote_by(current_user)
    respond_to_vote
  end

  private

  def set_post
    @post = Post.find(params[:id])
  end

  def authorize_user!
    redirect_to posts_path, alert: t('brgen.unauthorized') unless @post.user == current_user
  end

  def post_params
    params.require(:post).permit(:title, :content, :community_id, :anonymous)
  end

  def respond_to_vote
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @post }
      format.json { render json: { score: @post.karma } }
    end
  end
end
RUBY

cat > app/controllers/comments_controller.rb <<'RUBY'
class CommentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_commentable
  before_action :set_comment, only: :destroy
  before_action :authorize_user!, only: :destroy

  def create
    @comment = @commentable.comments.build(comment_params.merge(user: current_user))
    if @comment.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @commentable, notice: t('brgen.comment_created') }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @comment.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @commentable, notice: t('brgen.comment_deleted') }
    end
  end

  private

  def set_commentable
    @commentable = Post.find(params[:post_id])
  end

  def set_comment
    @comment = Comment.find(params[:id])
  end

  def authorize_user!
    redirect_to @commentable, alert: t('brgen.unauthorized') unless @comment.user == current_user
  end

  def comment_params
    params.require(:comment).permit(:content, :parent_id)
  end
end
RUBY

cat > app/controllers/communities_controller.rb <<'RUBY'
class CommunitiesController < ApplicationController
  def index
    @communities = Community.order(:name)
  end

  def show
    @community = Community.find_by!(slug: params[:id])
    @posts = @community.posts.includes(:user).hot.page(params[:page])
  end
end
RUBY

cat > app/controllers/votes_controller.rb <<'RUBY'
class VotesController < ApplicationController
  before_action :authenticate_user!

  ALLOWED_VOTABLE_TYPES = %w[Post Comment].freeze

  def create
    find_votable.upvote_by(current_user)
    render json: { score: find_votable.karma }
  end

  def destroy
    find_votable.downvote_by(current_user)
    render json: { score: find_votable.karma }
  end

  private

  def find_votable
    type = params[:votable_type]
    raise ArgumentError, 'Invalid votable type' unless ALLOWED_VOTABLE_TYPES.include?(type)

    type.constantize.find(params[:votable_id])
  end
end
RUBY

# ── OpenBSD rc.d service ─────────────────────────────────────────────────────
printf 'Creating OpenBSD rc.d service\n'
rc_file="/etc/rc.d/brgen"
cat > "$rc_file" <<EOF
#!/bin/ksh
#
# PROVIDE: brgen
# REQUIRE: DAEMON
# KEYWORD: shutdown

. /etc/rc.subr

name="brgen"
rcvar=brgen_enable

command="/home/brgen/app/bin/rails"
command_args="server -b 0.0.0.0 -p ${PORT} -e production"
pidfile="/var/run/\${name}.pid"
user="brgen"
procname="\${command}"
start_precmd="cd /home/brgen/app"

load_rc_config \$name
run_rc_command "\$1"
EOF
chmod 755 "$rc_file"

printf '==> BRGEN setup complete!\n'
printf 'Next steps:\n'
printf '  1. Review config/database.yml\n'
printf '  2. Test: bin/rails server -b 0.0.0.0 -p %s\n' "$PORT"
printf '  3. Deploy: doas sh openbsd.sh --post-point\n'