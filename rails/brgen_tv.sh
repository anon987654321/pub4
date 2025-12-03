#!/usr/bin/env zsh
set -euo pipefail

readonly VERSION="1.0.0"
readonly APP_NAME="brgen_tv"

SCRIPT_DIR="${0:a:h}"
source "${SCRIPT_DIR}/__shared/@common.sh"

APP_DIR="/home/brgen/app"
cd "$APP_DIR"

log "Installing Brgen TV - Video streaming & live broadcasting"
# Models
bin/rails generate model Tv::Video user:references channel:references title:string description:text category:string status:integer views:integer:default[0] duration:integer

bin/rails generate model Tv::Channel user:references name:string:uniq description:text subscriber_count:integer:default[0]

bin/rails generate model Tv::LiveStream user:references channel:references title:string stream_key:string status:integer viewer_count:integer:default[0] scheduled_at:datetime

bin/rails generate model Tv::Subscription channel:references user:references

bin/rails generate model Tv::Comment video:references user:references content:text timestamp:integer

bin/rails generate model Tv::StreamChat live_stream:references user:references message:text

bin/rails db:migrate
# Routes
add_route "namespace :tv do"

add_route "  resources :videos, only: [:index, :show, :create] do"

add_route "    resources :comments, only: [:create]"

add_route "    member do"

add_route "      post :increment_views"

add_route "    end"

add_route "  end"

add_route "  resources :channels do"

add_route "    resources :live_streams"

add_route "    member do"

add_route "      post :subscribe"

add_route "      delete :unsubscribe"

add_route "    end"

add_route "  end"

add_route "  resources :live_streams, only: [:index, :show] do"

add_route "    resources :stream_chats, only: [:create]"

add_route "  end"

add_route "end"

# Models
print > app/models/tv/video.rb << 'RUBY'

module Tv

  class Video < ApplicationRecord

    belongs_to :user

    belongs_to :channel, optional: true, class_name: 'Tv::Channel'

    has_many :comments, dependent: :destroy, class_name: 'Tv::Comment'

    has_one_attached :video_file
    has_one_attached :thumbnail

    validates :title, presence: true, length: { maximum: 100 }
    validates :description, length: { maximum: 5000 }

    validates :category, inclusion: { in: %w[entertainment education news sports gaming music] }

    enum status: { draft: 0, published: 1, private: 2, unlisted: 3 }
    scope :published, -> { where(status: 'published') }
    scope :by_category, ->(cat) { where(category: cat) }

    scope :trending, -> { order(views: :desc, created_at: :desc) }

    after_create_commit -> { broadcast_prepend_to "videos" }
    def formatted_duration
      return '0:00' unless duration

      hours = duration / 3600

      minutes = (duration % 3600) / 60

      seconds = duration % 60

      hours > 0 ? format('%d:%02d:%02d', hours, minutes, seconds) : format('%d:%02d', minutes, seconds)

    end

  end

end

RUBY

print > app/models/tv/live_stream.rb << 'RUBY'
module Tv

  class LiveStream < ApplicationRecord

    belongs_to :user

    belongs_to :channel, class_name: 'Tv::Channel'

    has_many :stream_chats, dependent: :destroy, class_name: 'Tv::StreamChat'

    validates :title, presence: true
    validates :stream_key, presence: true, uniqueness: true

    enum status: { scheduled: 0, live: 1, ended: 2 }
    before_create :generate_stream_key
    after_update_commit -> { broadcast_replace_to "live_streams" }

    def live?
      status == 'live' && viewer_count > 0

    end

    private
    def generate_stream_key
      self.stream_key ||= SecureRandom.hex(16)

    end

  end

end

RUBY

print > app/models/tv/channel.rb << 'RUBY'
module Tv

  class Channel < ApplicationRecord

    belongs_to :user

    has_many :videos, dependent: :destroy, class_name: 'Tv::Video'

    has_many :live_streams, dependent: :destroy, class_name: 'Tv::LiveStream'

    has_many :subscriptions, dependent: :destroy, class_name: 'Tv::Subscription'

    has_many :subscribers, through: :subscriptions, source: :user

    has_one_attached :avatar
    has_one_attached :banner

    validates :name, presence: true, uniqueness: true
    validates :description, length: { maximum: 1000 }

    def update_subscriber_count!
      update(subscriber_count: subscriptions.count)

    end

  end

end

RUBY

# Controllers
print > app/controllers/tv/videos_controller.rb << 'RUBY'

module Tv

  class VideosController < ApplicationController

    def index

      @videos = Video.published.includes(:user, :channel).order(created_at: :desc)

      @videos = @videos.by_category(params[:category]) if params[:category]

    end

    def show
      @video = Video.includes(:comments).find(params[:id])

      @video.increment!(:views)

    end

    def create
      @video = current_user.videos.build(video_params)

      if @video.save
        render json: @video, status: :created

      else

        render json: @video.errors, status: :unprocessable_entity

      end

    end

    private
    def video_params
      params.require(:video).permit(:title, :description, :category, :channel_id, :video_file, :thumbnail)

    end

  end

end

RUBY

print > app/controllers/tv/live_streams_controller.rb << 'RUBY'
module Tv

  class LiveStreamsController < ApplicationController

    before_action :authenticate_user!, except: [:index, :show]

    def index
      @live_streams = LiveStream.live.includes(:channel, :user).order(viewer_count: :desc)

    end

    def show
      @live_stream = LiveStream.includes(:stream_chats).find(params[:id])

      @live_stream.increment!(:viewer_count) if @live_stream.live?

    end

    def create
      @channel = current_user.channels.find(params[:channel_id])

      @live_stream = @channel.live_streams.build(live_stream_params.merge(user: current_user))

      if @live_stream.save
        render json: @live_stream, status: :created

      else

        render json: @live_stream.errors, status: :unprocessable_entity

      end

    end

    private
    def live_stream_params
      params.require(:live_stream).permit(:title, :scheduled_at)

    end

  end

end

RUBY

# Views
print > app/views/tv/videos/index.html.erb << 'ERB'

<%= tag.div class: "tv-index", data: { controller: "video-player" } do %>

  <%= tag.h1 "Videos" %>

  <%= tag.div class: "video-grid" do %>

    <% @videos.each do |video| %>

      <%= link_to tv_video_path(video), class: "video-card" do %>

        <%= image_tag video.thumbnail.variant(resize_to_limit: [320, 180]), class: "thumbnail" if video.thumbnail.attached? %>

        <%= tag.div class: "video-info" do %>

          <%= tag.h3 video.title %>

          <%= tag.p "#{video.user.email} • #{video.views} views" %>

          <%= tag.span video.formatted_duration, class: "duration" %>

        <% end %>

      <% end %>

    <% end %>

  <% end %>

<% end %>

ERB

# Stimulus controller
print > app/javascript/controllers/video_player_controller.js << 'JS'

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["video", "progress", "playButton"]

  connect() {
    this.updateProgress()

  }

  togglePlay() {
    if (this.videoTarget.paused) {

      this.videoTarget.play()

      this.playButtonTarget.textContent = "⏸"

    } else {

      this.videoTarget.pause()

      this.playButtonTarget.textContent = "▶"

    }

  }

  updateProgress() {
    if (!this.hasVideoTarget) return

    const progress = (this.videoTarget.currentTime / this.videoTarget.duration) * 100

    this.progressTarget.style.width = `${progress}%`

  }

  seek(event) {
    const rect = event.currentTarget.getBoundingClientRect()

    const percent = (event.clientX - rect.left) / rect.width

    this.videoTarget.currentTime = percent * this.videoTarget.duration

  }

}

JS

# SCSS
print >> app/assets/stylesheets/application.scss << 'SCSS'

.video-grid {

  display: grid;

  grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));

  gap: 16px;

  padding: 16px;

}

.video-card {
  background: var(--color-surface);

  border-radius: 8px;

  overflow: hidden;

  transition: transform 0.2s;

  text-decoration: none;

  color: inherit;

  &:hover {
    transform: scale(1.02);

  }

  .thumbnail {
    width: 100%;

    aspect-ratio: 16/9;

    object-fit: cover;

  }

  .video-info {
    padding: 12px;

  }

  .duration {
    background: rgba(0,0,0,0.8);

    color: white;

    padding: 2px 6px;

    border-radius: 4px;

    font-size: 12px;

  }

}

SCSS

log "Brgen TV setup complete"
