#!/usr/bin/env zsh
# brgen_tv.sh — Add Tv:: namespace to the main brgen Rails app
# Usage: zsh brgen_tv.sh
set -euo pipefail

APP_DIR=/home/brgen/app
SCRIPT_DIR=${0:a:h}

. "${SCRIPT_DIR}/@shared_functions.sh" 2>/dev/null || . /tmp/shared_functions.sh

need_cmd ruby34 bundle rails doas

already_done "${APP_DIR}/app/models/tv/channel.rb" && exit 0

log "Brgen TV — adding Tv namespace to brgen app"
cd "$APP_DIR"

# ── Models ─────────────────────────────────────────────────────────────────
bin/rails generate model Tv::Channel \
  user:references name:string description:text \
  slug:string subscribers_count:integer total_views:integer \
  --no-test-framework

bin/rails generate model Tv::Video \
  tv_channel:references user:references \
  title:string description:text status:string \
  duration_seconds:integer views_count:integer \
  likes_count:integer comments_count:integer \
  published_at:datetime thumbnail_url:string \
  --no-test-framework

bin/rails generate model Tv::Broadcast \
  tv_channel:references user:references \
  title:string description:text status:string \
  stream_key:string viewer_count:integer \
  started_at:datetime ended_at:datetime \
  --no-test-framework

bin/rails generate model Tv::Subscription \
  user:references tv_channel:references \
  notify_on_upload:boolean \
  --no-test-framework

bin/rails generate model Tv::ViewEvent \
  user:references tv_video:references \
  watch_time_seconds:integer completed:boolean \
  --no-test-framework

RAILS_ENV=production bin/rails db:migrate

# ── Model logic ─────────────────────────────────────────────────────────────
mkdir -p app/models/tv

cat > app/models/tv/channel.rb << 'RUBY'
class Tv::Channel < ApplicationRecord
  belongs_to :user
  has_many :videos,        class_name: "Tv::Video",        foreign_key: :tv_channel_id, dependent: :destroy
  has_many :broadcasts,    class_name: "Tv::Broadcast",     foreign_key: :tv_channel_id, dependent: :destroy
  has_many :subscriptions, class_name: "Tv::Subscription",  foreign_key: :tv_channel_id, dependent: :destroy
  has_many :subscribers,   through: :subscriptions, source: :user
  has_one_attached :banner
  has_one_attached :avatar

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9_-]+\z/ }
  before_validation { self.slug ||= name.to_s.parameterize }

  scope :popular, -> { order(subscribers_count: :desc) }

  def to_param = slug
  def live?    = broadcasts.where(status: "live").exists?
end
RUBY

cat > app/models/tv/video.rb << 'RUBY'
class Tv::Video < ApplicationRecord
  belongs_to :channel,     class_name: "Tv::Channel", foreign_key: :tv_channel_id
  belongs_to :user
  has_many :view_events, class_name: "Tv::ViewEvent", foreign_key: :tv_video_id, dependent: :destroy
  has_one_attached :video_file
  has_one_attached :thumbnail

  STATUSES = %w[processing ready published unlisted].freeze
  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }, allow_nil: true

  scope :published, -> { where(status: "published").order(published_at: :desc) }
  scope :trending,  -> { published.order(views_count: :desc) }
  scope :recent,    -> { published.order(published_at: :desc) }

  def duration_formatted
    return "—" unless duration_seconds
    h, rem = duration_seconds.divmod(3600)
    m, s   = rem.divmod(60)
    h > 0 ? "%d:%02d:%02d" % [h, m, s] : "%d:%02d" % [m, s]
  end
end
RUBY

cat > app/models/tv/broadcast.rb << 'RUBY'
class Tv::Broadcast < ApplicationRecord
  belongs_to :channel, class_name: "Tv::Channel", foreign_key: :tv_channel_id
  belongs_to :user
  has_one_attached :thumbnail

  validates :title, presence: true
  before_create { self.stream_key = SecureRandom.hex(16) }

  scope :live,      -> { where(status: "live") }
  scope :scheduled, -> { where(status: "scheduled") }

  def go_live!  = update!(status: "live",  started_at: Time.current)
  def end_live! = update!(status: "ended", ended_at: Time.current)
end
RUBY

cat > app/models/tv/subscription.rb << 'RUBY'
class Tv::Subscription < ApplicationRecord
  belongs_to :user
  belongs_to :channel, class_name: "Tv::Channel", foreign_key: :tv_channel_id
  validates :user_id, uniqueness: { scope: :tv_channel_id }
end
RUBY

# ── Controllers ─────────────────────────────────────────────────────────────
mkdir -p app/controllers/tv

cat > app/controllers/tv/base_controller.rb << 'RUBY'
class Tv::BaseController < ApplicationController

end
RUBY

cat > app/controllers/tv/home_controller.rb << 'RUBY'
class Tv::HomeController < Tv::BaseController
  allow_unauthenticated_access

  def index
    @pagy_trending, @trending = pagy(Tv::Video.trending.includes(:channel), limit: 12)
    @live      = Tv::Broadcast.live.includes(:channel).limit(6)
    @recent    = Tv::Video.recent.includes(:channel).limit(8)
  end
end
RUBY

cat > app/controllers/tv/channels_controller.rb << 'RUBY'
class Tv::ChannelsController < Tv::BaseController
  allow_unauthenticated_access only: %i[index show]
  before_action :set_channel, only: %i[show edit update destroy subscribe unsubscribe]

  def index    = (@pagy, @channels = pagy(Tv::Channel.popular.includes(:user)))
  def show     = (@pagy, @videos = pagy(@channel.videos.published))
  def new      = (@channel = Tv::Channel.new)
  def edit;    end

  def create
    @channel = Current.user.tv_channels.build(channel_params)
    @channel.save ? redirect_to(tv_channel_path(@channel), notice: "Channel created") : render(:new, status: :unprocessable_entity)
  end

  def update
    @channel.update(channel_params) ? redirect_to(tv_channel_path(@channel)) : render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @channel.destroy
    redirect_to tv_channels_path
  end

  def subscribe
    Tv::Subscription.find_or_create_by!(user: Current.user, tv_channel: @channel)
    redirect_back fallback_location: tv_channel_path(@channel)
  end

  def unsubscribe
    Tv::Subscription.find_by(user: Current.user, tv_channel: @channel)&.destroy
    redirect_back fallback_location: tv_channel_path(@channel)
  end

  private
  def set_channel    = (@channel = Tv::Channel.find_by!(slug: params[:id]))
  def channel_params = params.require(:tv_channel).permit(:name, :description, :banner, :avatar)
end
RUBY

cat > app/controllers/tv/videos_controller.rb << 'RUBY'
class Tv::VideosController < Tv::BaseController
  allow_unauthenticated_access only: %i[show]
  before_action :set_video, only: %i[show destroy]

  def show
    @video.view_events.create!(user: Current.user) if authenticated?
    @video.increment!(:views_count)
  end

  def new  = (@video = Tv::Video.new)

  def create
    channel = Current.user.tv_channels.find(params[:tv_channel_id])
    @video  = channel.videos.build(video_params.merge(user: Current.user, status: "ready"))
    @video.save ? redirect_to(tv_video_path(@video), notice: "Video uploaded") : render(:new, status: :unprocessable_entity)
  end

  def destroy
    @video.destroy
    redirect_to tv_root_path
  end

  private
  def set_video    = (@video = Tv::Video.find(params[:id]))
  def video_params = params.require(:tv_video).permit(:title, :description, :video_file, :thumbnail, :tv_channel_id)
end
RUBY

# ── Views ────────────────────────────────────────────────────────────────────
mkdir -p app/views/tv/home app/views/tv/channels app/views/tv/videos

cat > app/views/tv/home/index.html.erb << 'ERB'
<% content_for :title, "Brgen TV" %>
<h1>Brgen TV</h1>
<% if @live.any? %>
  <section>
    <h2>Live now</h2>
    <div class="video-grid">
      <% @live.each do |b| %>
        <article>
          <%= link_to tv_channel_path(b.channel) do %>
            <span class="live-badge">LIVE</span>
            <p><strong><%= b.title %></strong></p>
            <small><%= b.channel.name %> · <%= b.viewer_count %> viewers</small>
          <% end %>
        </article>
      <% end %>
    </div>
  </section>
<% end %>

<section>
  <h2>Trending</h2>
  <div class="video-grid">
    <% @trending.each do |v| %>
      <%= render "tv/videos/video_card", video: v %>
    <% end %>
  </div>
  <%= @pagy_trending.series_nav if @pagy_trending.pages > 1 %>
</section>

<section>
  <h2>Recent uploads</h2>
  <div class="video-grid">
    <% @recent.each do |v| %>
      <%= render "tv/videos/video_card", video: v %>
    <% end %>
  </div>
</section>
ERB

cat > app/views/tv/videos/_video_card.html.erb << 'ERB'
<article class="video-card">
  <%= link_to tv_video_path(video) do %>
    <% if video.thumbnail.attached? %>
      <%= image_tag video.thumbnail, class: "video-thumb" %>
    <% else %>
      <div class="video-thumb-placeholder"><%= video.title[0] %></div>
    <% end %>
    <div class="video-info">
      <p><strong><%= video.title %></strong></p>
      <small><%= video.channel.name %> · <%= video.views_count %> views · <%= video.duration_formatted %></small>
    </div>
  <% end %>
</article>
ERB

cat > app/views/tv/channels/show.html.erb << 'ERB'
<% content_for :title, @channel.name %>
<header>
  <% if @channel.banner.attached? %><%= image_tag @channel.banner, class: "channel-banner" %><% end %>
  <h1><%= @channel.name %></h1>
  <p><%= @channel.subscribers_count %> subscribers · <%= @channel.total_views %> views</p>
  <p><%= @channel.description %></p>
  <% if authenticated? && Current.user != @channel.user %>
    <% if @channel.subscriptions.exists?(user: Current.user) %>
      <%= button_to "Unsubscribe", unsubscribe_tv_channel_path(@channel), method: :delete, class: "btn" %>
    <% else %>
      <%= button_to "Subscribe", subscribe_tv_channel_path(@channel), method: :post, class: "btn btn--primary" %>
    <% end %>
  <% end %>
</header>
<div class="video-grid">
  <%= render @videos %>
  <%= @pagy.series_nav if @pagy.pages > 1 %>
</div>
ERB

cat > app/views/tv/channels/index.html.erb << 'ERB'
<h1>Channels</h1>
<% if authenticated? %><%= link_to "Create channel", new_tv_channel_path, class: "btn btn--primary" %><% end %>
<div class="channel-grid">
  <% @channels.each do |c| %>
    <article>
      <%= link_to c.name, tv_channel_path(c) %>
      <small><%= c.subscribers_count %> subscribers</small>
      <% if c.live? %><span class="live-badge">LIVE</span><% end %>
    </article>
  <% end %>
</div>
<%= @pagy.series_nav if @pagy.pages > 1 %>
ERB

cat > app/views/tv/videos/show.html.erb << 'ERB'
<% content_for :title, @video.title %>
<% if @video.video_file.attached? %>
  <%= video_tag url_for(@video.video_file), controls: true, class: "video-player" %>
<% end %>
<h1><%= @video.title %></h1>
<p><%= link_to @video.channel.name, tv_channel_path(@video.channel) %> · <%= @video.views_count %> views · <%= @video.duration_formatted %></p>
<p><%= @video.description %></p>
ERB

# ── Route patch ─────────────────────────────────────────────────────────────
ruby34 -e "
r = File.read('config/routes.rb')
unless r.include?('namespace :tv')
  patch = %q(
  namespace :tv do
    root 'home#index'
    resources :channels, param: :slug do
      member { post :subscribe; delete :unsubscribe }
      resources :videos, only: %i[new create]
    end
    resources :videos, only: %i[show destroy]
    resources :broadcasts, only: %i[show]
  end
)
  r.sub!('root \"home#index\"', patch + '  root \"home#index\"')
  File.write('config/routes.rb', r)
  puts 'Routes patched'
end
"

# ── User associations ────────────────────────────────────────────────────────
ruby34 -e "
u = File.read('app/models/user.rb')
unless u.include?('tv_channels')
  u.sub!('has_secure_password', %Q(has_secure_password
  has_many :tv_channels,       class_name: \"Tv::Channel\",       dependent: :destroy
  has_many :tv_videos,         class_name: \"Tv::Video\",         dependent: :destroy
  has_many :tv_subscriptions,  class_name: \"Tv::Subscription\",  dependent: :destroy
  has_many :subscribed_channels, through: :tv_subscriptions, class_name: \"Tv::Channel\", foreign_key: :tv_channel_id))
  File.write('app/models/user.rb', u)
  puts 'User model patched'
end
"

doas rcctl restart brgen 2>/dev/null || true
log_ok "Brgen TV namespace added — visit /tv"
