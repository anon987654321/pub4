#!/usr/bin/env zsh
# brgen.sh — Brgen social network (Reddit-style, Rails 8)
# Usage: zsh brgen.sh
set -euo pipefail

APP_NAME=brgen
APP_DIR=/home/${APP_NAME}/app
APP_PORT=11006
SCRIPT_DIR=${0:a:h}

. "${SCRIPT_DIR:h}/@shared_functions.sh"
. "${SCRIPT_DIR:h}/__shared/@reddit_features.sh"

need_cmd ruby34 bundle rails doas

already_done "${APP_DIR}/app/models/community.rb" && exit 0

log "Brgen — Social Network"

# ── Create app ─────────────────────────────────────────────────────────────
create_rails_app "$APP_DIR"

# ── Gems ────────────────────────────────────────────────────────────────────
add_gem pagy
add_gem image_processing
install_solid_stack
install_security_tools

# ── Auth ───────────────────────────────────────────────────────────────────
install_auth
install_active_storage

# ── Core models ─────────────────────────────────────────────────────────────
bin/rails generate migration AddUsernameAndKarmaToUsers \
  username:string:uniq karma:integer \
  --no-test-framework

bin/rails generate model Community \
  name:string description:text slug:string:uniq \
  subscribers_count:integer:default[0] \
  user:references \
  --no-test-framework

bin/rails generate model CommunityMembership \
  community:references user:references role:string \
  --no-test-framework

bin/rails generate model Post \
  title:string content:text url:string \
  community:references user:references \
  score:integer:default[0] \
  upvotes:integer:default[0] downvotes:integer:default[0] \
  comments_count:integer:default[0] \
  post_type:string \
  --no-test-framework

bin/rails db:migrate

# ── Reddit features ─────────────────────────────────────────────────────────
setup_reddit_models
write_reddit_model_logic
write_vote_controller

# ── Model overrides ─────────────────────────────────────────────────────────
cat > app/models/user.rb << 'RUBY'
class User < ApplicationRecord
  has_secure_password

  has_many :sessions, dependent: :destroy
  has_many :posts, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :votes, dependent: :destroy
  has_many :community_memberships, dependent: :destroy
  has_many :communities, through: :community_memberships

  has_one_attached :avatar

  validates :email_address, presence: true, uniqueness: true
  validates :username, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9_]+\z/ }, length: { in: 3..30 }

  normalizes :email_address, with: -> e { e.strip.downcase }
  normalizes :username,      with: -> u { u.strip.downcase }

  def recalculate_karma!
    k = posts.sum(:score) + comments.sum(:score)
    update_column(:karma, k)
  end
end
RUBY

cat > app/models/community.rb << 'RUBY'
class Community < ApplicationRecord
  belongs_to :user
  has_many :community_memberships, dependent: :destroy
  has_many :members, through: :community_memberships, source: :user
  has_many :posts, dependent: :destroy
  has_one_attached :banner
  has_one_attached :icon

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }, length: { in: 3..21 }

  before_validation :generate_slug, on: :create

  scope :popular, -> { order(subscribers_count: :desc) }
  scope :recent,  -> { order(created_at: :desc) }

  def to_param = slug

  private

  def generate_slug
    self.slug ||= name.to_s.downcase.gsub(/\W+/, "_").delete_prefix("_").delete_suffix("_")
  end
end
RUBY

cat > app/models/post.rb << 'RUBY'
class Post < ApplicationRecord
  include Votable
  include Commentable

  belongs_to :community
  belongs_to :user
  has_many_attached :images

  POST_TYPES = %w[text link image].freeze

  validates :title, presence: true, length: { maximum: 300 }
  validates :post_type, inclusion: { in: POST_TYPES }
  validates :content, presence: true, if: -> { post_type == "text" }
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }, if: -> { post_type == "link" }

  default_value_for :post_type, "text"

  scope :hot, -> {
    order(Arel.sql("(upvotes - downvotes) / POWER(((julianday('now') - julianday(created_at)) * 24 + 2), 1.5) DESC"))
  }
  scope :top,      -> { order(score: :desc) }
  scope :new_first,-> { order(created_at: :desc) }
  scope :rising,   -> {
    where("created_at > ?", 24.hours.ago).order(score: :desc)
  }
end
RUBY

# ── Controllers ─────────────────────────────────────────────────────────────
cat > app/controllers/application_controller.rb << 'RUBY'
class ApplicationController < ActionController::Base
  include Pagy::Backend
  allow_browser versions: :modern
end
RUBY

cat > app/controllers/communities_controller.rb << 'RUBY'
class CommunitiesController < ApplicationController
  before_action :require_authentication, only: %i[new create subscribe unsubscribe]
  before_action :set_community, only: %i[show subscribe unsubscribe]

  def index
    @pagy, @communities = pagy(Community.popular.includes(:user))
  end

  def show
    @sort = params[:sort] || "hot"
    @pagy, @posts = pagy(@community.posts.includes(:user).public_send(@sort.in?(%w[hot top new_first rising]) ? @sort : "hot"))
  end

  def new
    @community = Current.user.communities.build
  end

  def create
    @community = Current.user.communities.build(community_params)
    if @community.save
      @community.community_memberships.create!(user: Current.user, role: "moderator")
      redirect_to @community, notice: "Community created"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def subscribe
    m = @community.community_memberships.find_or_create_by!(user: Current.user)
    m.update!(role: "member")
    @community.increment!(:subscribers_count)
    redirect_to @community
  end

  def unsubscribe
    @community.community_memberships.find_by(user: Current.user)&.destroy!
    @community.decrement!(:subscribers_count)
    redirect_to @community
  end

  private

  def set_community = @community = Community.find_by!(slug: params[:id])
  def community_params = params.require(:community).permit(:name, :description)
end
RUBY

cat > app/controllers/posts_controller.rb << 'RUBY'
class PostsController < ApplicationController
  before_action :require_authentication, except: %i[index show]
  before_action :set_community, only: %i[new create]
  before_action :set_post,      only: %i[show edit update destroy]
  before_action :authorize!,    only: %i[edit update destroy]

  def index
    @sort = params[:sort] || "hot"
    @pagy, @posts = pagy(Post.includes(:user, :community).public_send(@sort.in?(%w[hot top new_first rising]) ? @sort : "hot"))
  end

  def show
    @comments = @post.comments.roots.top.includes(:user, replies: :user)
    @comment  = Comment.new
  end

  def new
    @post = @community.posts.build
  end

  def create
    @post = @community.posts.build(post_params.merge(user: Current.user))
    @post.save ? redirect_to([@community, @post], notice: "Posted") : render(:new, status: :unprocessable_entity)
  end

  def edit; end

  def update
    @post.update(post_params) ? redirect_to(@post, notice: "Updated") : render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @post.destroy
    redirect_to @post.community, notice: "Deleted"
  end

  private

  def set_community = @community = Community.find_by!(slug: params[:community_id])
  def set_post      = @post = Post.find(params[:id])
  def authorize!    = redirect_to(root_path, alert: "Unauthorized") unless @post.user == Current.user

  def post_params
    params.require(:post).permit(:title, :content, :url, :post_type, images: [])
  end
end
RUBY

cat > app/controllers/comments_controller.rb << 'RUBY'
class CommentsController < ApplicationController
  before_action :require_authentication

  def create
    @post    = Post.find(params[:post_id])
    @comment = @post.comments.build(comment_params.merge(user: Current.user))
    if @comment.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @post }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @comment = Comment.find(params[:id])
    @comment.destroy! if @comment.user == Current.user
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @comment.commentable }
    end
  end

  private

  def comment_params
    params.require(:comment).permit(:content, :parent_id)
  end
end
RUBY

# ── Routes ─────────────────────────────────────────────────────────────────
cat > config/routes.rb << 'RUBY'
Rails.application.routes.draw do
  resource  :session
  resources :passwords, param: :token

  root "communities#index"

  resources :communities, path: "r" do
    member do
      post :subscribe
      post :unsubscribe
    end
    resources :posts, shallow: true do
      resources :comments, only: %i[create destroy]
    end
  end

  resources :votes, only: %i[create]
  resources :users, only: %i[show]

  get "up", to: "rails/health#show", as: :rails_health_check
end
RUBY

# ── Assets + Infrastructure ─────────────────────────────────────────────────
write_base_css
write_layout "Brgen"
write_falcon_config "$APP_PORT"
configure_production
install_rcd brgen "$APP_DIR" "$APP_PORT" brgen
relayd_add_relay brgen.no "$APP_PORT"

# ── Seed ───────────────────────────────────────────────────────────────────
cat > db/seeds.rb << 'RUBY'
admin = User.find_or_create_by!(email_address: "admin@brgen.no") do |u|
  u.username = "admin"
  u.password = u.password_confirmation = "password123"
end

["news", "tech", "bergen", "norge", "kultur"].each do |slug|
  Community.find_or_create_by!(slug: slug) do |c|
    c.name        = slug.capitalize
    c.description = "#{slug.capitalize} community"
    c.user        = admin
  end
end

puts "Seeded #{Community.count} communities"
RUBY

bin/rails db:seed

log_ok "Brgen setup complete — start: doas rcctl start brgen"
