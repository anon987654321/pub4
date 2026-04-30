#!/usr/bin/env zsh
# brgen_tv.sh — Brgen TV video streaming & live broadcast platform (Rails 8)
# Usage: zsh brgen_tv.sh
set -euo pipefail

APP_NAME=brgen_tv
APP_DIR=/home/${APP_NAME}/app
APP_PORT=10012
SCRIPT_DIR=${0:a:h}

. "${SCRIPT_DIR:h}/@shared_functions.sh"

need_cmd ruby34 bundle rails doas

already_done "${APP_DIR}/app/models/channel.rb" && exit 0

log "Brgen TV — Video Streaming and Live Broadcasting"

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

# ── Models ─────────────────────────────────────────────────────────────────
bin/rails generate model Channel \
  user:references name:string description:text \
  slug:string:uniq subscribers_count:integer:default[0] \
  total_views:integer:default[0] \
  --no-test-framework

bin/rails generate model Video \
  channel:references user:references \
  title:string description:text \
  status:string duration_seconds:integer \
  views_count:integer:default[0] \
  likes_count:integer:default[0] \
  comments_count:integer:default[0] \
  published_at:datetime \
  thumbnail_url:string \
  --no-test-framework

bin/rails generate model Broadcast \
  channel:references user:references \
  title:string description:text \
  status:string stream_key:string:uniq \
  viewer_count:integer:default[0] \
  started_at:datetime ended_at:datetime \
  --no-test-framework

bin/rails generate model Subscription \
  subscriber:references{User} channel:references \
  notify_on_upload:boolean:default[true] \
  --no-test-framework

bin/rails generate model Comment \
  user:references commentable:references{polymorphic}:index \
  parent_id:integer content:text \
  likes_count:integer:default[0] \
  --no-test-framework

bin/rails generate model Like \
  user:references likeable:references{polymorphic}:index \
  --no-test-framework

bin/rails generate model WatchLater \
  user:references video:references \
  --no-test-framework

bin/rails generate model ViewEvent \
  user:references video:references \
  watch_time_seconds:integer completed:boolean:default[false] \
  --no-test-framework

bin/rails db:migrate

# ── Model logic ─────────────────────────────────────────────────────────────
cat > app/models/channel.rb << 'RUBY'
class Channel < ApplicationRecord
  belongs_to :user
  has_many :videos, dependent: :destroy
  has_many :broadcasts, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_many :subscribers, through: :subscriptions, source: :subscriber
  has_one_attached :banner
  has_one_attached :avatar

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9_-]+\z/ }

  before_validation :generate_slug, on: :create

  scope :popular, -> { order(subscribers_count: :desc) }

  def to_param = slug
  def live?    = broadcasts.where(status: "live").exists?

  private

  def generate_slug
    self.slug ||= name.to_s.parameterize
  end
end
RUBY

cat > app/models/video.rb << 'RUBY'
class Video < ApplicationRecord
  belongs_to :channel
  belongs_to :user
  has_many :comments, as: :commentable, dependent: :destroy
  has_many :likes, as: :likeable, dependent: :destroy
  has_many :watch_laters, dependent: :destroy
  has_many :view_events, dependent: :destroy
  has_one_attached :video_file
  has_one_attached :thumbnail

  STATUSES = %w[processing ready published unlisted private].freeze

  validates :title, presence: true, length: { maximum: 100 }
  validates :status, inclusion: { in: STATUSES }

  default_value_for :status, "processing"

  before_create :set_published_at

  scope :published, -> { where(status: "published").order(published_at: :desc) }
  scope :trending,  -> { published.order(views_count: :desc) }
  scope :recent,    -> { published.order(published_at: :desc) }

  def duration_formatted
    return "—" unless duration_seconds
    h, rem = duration_seconds.divmod(3600)
    m, s   = rem.divmod(60)
    h > 0 ? "%d:%02d:%02d" % [h, m, s] : "%d:%02d" % [m, s]
  end

  def like_by!(user)
    return if likes.exists?(user: user)
    likes.create!(user: user)
    increment!(:likes_count)
    channel.increment!(:total_views)
  end

  def view_by!(user)
    view_events.create!(user: user)
    increment!(:views_count)
  end

  private

  def set_published_at
    self.published_at = Time.current if status == "published"
  end
end
RUBY

cat > app/models/broadcast.rb << 'RUBY'
class Broadcast < ApplicationRecord
  belongs_to :channel
  belongs_to :user
  has_many :comments, as: :commentable, dependent: :destroy
  has_one_attached :thumbnail

  STATUSES = %w[scheduled live ended].freeze

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :stream_key, uniqueness: true

  before_create :generate_stream_key

  scope :live,      -> { where(status: "live") }
  scope :scheduled, -> { where(status: "scheduled").where("started_at > ?", Time.current) }

  def go_live!
    update!(status: "live", started_at: Time.current)
    channel.subscribers.each do |sub|
      broadcast_append_to [sub, "notifications"],
        partial: "shared/live_notification",
        locals: { broadcast: self }
    end
  end

  def end_broadcast!
    update!(status: "ended", ended_at: Time.current)
  end

  private

  def generate_stream_key
    self.stream_key = SecureRandom.hex(16)
  end
end
RUBY

cat > app/models/comment.rb << 'RUBY'
class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :commentable, polymorphic: true
  belongs_to :parent, class_name: "Comment", optional: true
  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy
  has_many :likes, as: :likeable, dependent: :destroy

  validates :content, presence: true, length: { maximum: 2000 }

  after_create_commit :broadcast_comment
  after_create_commit :increment_comment_count

  scope :roots,    -> { where(parent_id: nil).order(created_at: :asc) }

  private

  def broadcast_comment
    broadcast_append_to [commentable, "comments"],
      partial: "comments/comment",
      locals: { comment: self }
  end

  def increment_comment_count
    commentable.increment!(:comments_count) if commentable.respond_to?(:comments_count)
  end
end
RUBY

# ── Controllers ─────────────────────────────────────────────────────────────
cat > app/controllers/application_controller.rb << 'RUBY'
class ApplicationController < ActionController::Base
  include Pagy::Backend
  allow_browser versions: :modern
end
RUBY

cat > app/controllers/home_controller.rb << 'RUBY'
class HomeController < ApplicationController
  def index
    @trending  = Video.trending.includes(:channel).limit(12)
    @live      = Broadcast.live.includes(:channel).limit(6)
    @recent    = Video.recent.includes(:channel).limit(8)
  end
end
RUBY

cat > app/controllers/channels_controller.rb << 'RUBY'
class ChannelsController < ApplicationController
  before_action :require_authentication, only: %i[new create edit update destroy subscribe unsubscribe]
  before_action :set_channel, only: %i[show edit update destroy subscribe unsubscribe]
  before_action :authorize!, only: %i[edit update destroy]

  def show
    @videos    = @channel.videos.published.limit(24)
    @live      = @channel.broadcasts.live.first
    @scheduled = @channel.broadcasts.scheduled.first(3)
  end

  def new
    @channel = Current.user.channels.build
  end

  def create
    @channel = Current.user.channels.build(channel_params)
    @channel.save ? redirect_to(@channel, notice: "Channel created") : render(:new, status: :unprocessable_entity)
  end

  def edit; end

  def update
    @channel.update(channel_params) ? redirect_to(@channel, notice: "Updated") : render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @channel.destroy
    redirect_to root_path, notice: "Channel deleted"
  end

  def subscribe
    @channel.subscriptions.find_or_create_by!(subscriber: Current.user)
    @channel.increment!(:subscribers_count)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @channel }
    end
  end

  def unsubscribe
    @channel.subscriptions.find_by(subscriber: Current.user)&.destroy!
    @channel.decrement!(:subscribers_count)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @channel }
    end
  end

  private

  def set_channel  = @channel = Channel.find_by!(slug: params[:id])
  def authorize!   = redirect_to(root_path, alert: "Unauthorized") unless @channel.user == Current.user
  def channel_params = params.require(:channel).permit(:name, :description, :avatar, :banner)
end
RUBY

cat > app/controllers/videos_controller.rb << 'RUBY'
class VideosController < ApplicationController
  before_action :require_authentication, except: %i[index show]
  before_action :set_channel
  before_action :set_video, only: %i[show edit update destroy like watch_later]
  before_action :authorize!, only: %i[edit update destroy]

  def show
    @video.view_by!(Current.user) if authenticated?
    @comments = @video.comments.roots.includes(:user, replies: :user).limit(50)
    @comment  = Comment.new
  end

  def new
    @video = @channel.videos.build
  end

  def create
    @video = @channel.videos.build(video_params.merge(user: Current.user))
    @video.save ? redirect_to([@channel, @video], notice: "Video uploaded") : render(:new, status: :unprocessable_entity)
  end

  def edit; end

  def update
    @video.update(video_params) ? redirect_to([@channel, @video], notice: "Updated") : render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @video.destroy
    redirect_to @channel, notice: "Video deleted"
  end

  def like
    @video.like_by!(Current.user) if authenticated?
    respond_to do |format|
      format.turbo_stream
      format.json { render json: { count: @video.likes_count } }
    end
  end

  def watch_later
    WatchLater.find_or_create_by!(user: Current.user, video: @video)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @video }
    end
  end

  private

  def set_channel  = @channel = Channel.find_by!(slug: params[:channel_id])
  def set_video    = @video   = @channel.videos.find(params[:id])
  def authorize!   = redirect_to(@channel, alert: "Unauthorized") unless @video.user == Current.user
  def video_params = params.require(:video).permit(:title, :description, :status, :video_file, :thumbnail)
end
RUBY

cat > app/controllers/broadcasts_controller.rb << 'RUBY'
class BroadcastsController < ApplicationController
  before_action :require_authentication, except: %i[show]
  before_action :set_channel
  before_action :set_broadcast, only: %i[show go_live end_broadcast destroy]
  before_action :authorize!, only: %i[go_live end_broadcast destroy]

  def show
    @comments = @broadcast.comments.roots.includes(:user).limit(100)
    @comment  = Comment.new
  end

  def new
    @broadcast = @channel.broadcasts.build
  end

  def create
    @broadcast = @channel.broadcasts.build(broadcast_params.merge(user: Current.user))
    @broadcast.save ? redirect_to([@channel, @broadcast], notice: "Broadcast scheduled") : render(:new, status: :unprocessable_entity)
  end

  def go_live
    @broadcast.go_live!
    redirect_to [@channel, @broadcast]
  end

  def end_broadcast
    @broadcast.end_broadcast!
    redirect_to @channel
  end

  def destroy
    @broadcast.destroy
    redirect_to @channel, notice: "Broadcast deleted"
  end

  private

  def set_channel   = @channel   = Channel.find_by!(slug: params[:channel_id])
  def set_broadcast = @broadcast = @channel.broadcasts.find(params[:id])
  def authorize!    = redirect_to(@channel, alert: "Unauthorized") unless @broadcast.user == Current.user
  def broadcast_params = params.require(:broadcast).permit(:title, :description, :started_at, :thumbnail)
end
RUBY

cat > app/controllers/comments_controller.rb << 'RUBY'
class CommentsController < ApplicationController
  before_action :require_authentication

  def create
    commentable = find_commentable
    @comment = commentable.comments.build(comment_params.merge(user: Current.user))
    if @comment.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back_or_to root_path }
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
      format.html { redirect_back_or_to root_path }
    end
  end

  private

  def find_commentable
    if params[:video_id]
      Channel.find_by!(slug: params[:channel_id]).videos.find(params[:video_id])
    elsif params[:broadcast_id]
      Channel.find_by!(slug: params[:channel_id]).broadcasts.find(params[:broadcast_id])
    end
  end

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

  root "home#index"

  resources :channels, path: "c" do
    member do
      post :subscribe
      delete :unsubscribe
    end
    resources :videos do
      member do
        post :like
        post :watch_later
      end
      resources :comments, only: %i[create destroy]
    end
    resources :broadcasts do
      member do
        post :go_live
        post :end_broadcast
      end
      resources :comments, only: %i[create destroy]
    end
  end

  resources :users, only: %i[show]

  get "up", to: "rails/health#show", as: :rails_health_check
end
RUBY

# ── Assets + Infrastructure ─────────────────────────────────────────────────
mkdir -p app/assets/stylesheets
cat > app/assets/stylesheets/application.css << 'CSS'
:root {
  --bg: #0a0a0a; --surface: #1a1a1a; --text: #ffffff;
  --text-dim: #aaaaaa; --primary: #ff0000; --radius: 4px; --space: 8px;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: "Roboto", system-ui, sans-serif; background: var(--bg); color: var(--text); }
main { max-width: 1400px; margin: 0 auto; padding: var(--space); }
a { color: inherit; text-decoration: none; }
a:hover { color: var(--primary); }
.video-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 1rem; }
.video-card { cursor: pointer; }
.video-thumbnail { aspect-ratio: 16/9; background: #333; border-radius: var(--radius); overflow: hidden; position: relative; }
.video-thumbnail img { width: 100%; height: 100%; object-fit: cover; }
.video-duration { position: absolute; bottom: .3rem; right: .3rem; background: rgba(0,0,0,.8); color: #fff; font-size: .7rem; padding: .1rem .3rem; border-radius: 2px; }
.video-info { padding: .75rem 0; display: flex; gap: .75rem; }
.channel-avatar { width: 36px; height: 36px; border-radius: 50%; flex-shrink: 0; }
.live-badge { background: var(--primary); color: #fff; font-size: .65rem; font-weight: 700; padding: .1rem .4rem; border-radius: 2px; text-transform: uppercase; }
.flash-notice { background: #1a3a1a; color: #81c784; padding: .75rem 1rem; border-radius: var(--radius); margin-bottom: 1rem; }
.flash-alert  { background: #3a1a1a; color: #e57373; padding: .75rem 1rem; border-radius: var(--radius); margin-bottom: 1rem; }
CSS

write_layout "Brgen TV"
write_puma_config "$APP_PORT"
configure_production
install_rcd brgen_tv "$APP_DIR" "$APP_PORT" brgen_tv

log_ok "Brgen TV setup complete — start: doas rcctl start brgen_tv"
