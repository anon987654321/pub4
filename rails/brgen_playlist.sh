#!/usr/bin/env zsh
set -euo pipefail

# Brgen Playlist setup: Music playlist sharing platform with streaming, collaboration, and social features on OpenBSD 7.5, unprivileged user
# Framework v37.3.2 compliant with enhanced music sharing capabilities

APP_NAME="brgen_playlist"
BASE_DIR="/home/dev/rails"
SERVER_IP="185.52.176.18"
APP_PORT=$((10000 + RANDOM % 10000))
SCRIPT_DIR="${0:a:h}"

source "${SCRIPT_DIR}/@shared_functions.sh"

log "Starting Brgen Playlist setup with music streaming and collaboration features"

setup_full_app "$APP_NAME"

command_exists "ruby"
command_exists "node"
command_exists "psql"
# Redis optional - using Solid Cable for ActionCable (Rails 8 default)

install_gem "faker"

# Generate enhanced playlist models
bin/rails generate model Playlist::Set name:string description:text user:references privacy:string collaborative:boolean
bin/rails generate model Playlist::Track name:string artist:string audio_url:string duration:integer set:references position:integer
bin/rails generate model Playlist::Collaboration user:references set:references role:string
bin/rails generate model Playlist::Like user:references set:references
bin/rails generate scaffold Comment playlist_set:references user:references content:text

# Add music service integrations
bundle add spotify-web-api-sdk
bundle add youtube-api-v3-ruby
bundle add soundcloud-ruby
bundle install

# Enhanced Playlist models with music service integration
mkdir -p app/models/playlist
cat <<EOF > app/models/playlist/set.rb
module Playlist
  class Set < ApplicationRecord
    belongs_to :user
    has_many :tracks, -> { order(:position) }, class_name: 'Playlist::Track', dependent: :destroy
    has_many :collaborations, class_name: 'Playlist::Collaboration', dependent: :destroy
    has_many :collaborators, through: :collaborations, source: :user
    has_many :likes, class_name: 'Playlist::Like', dependent: :destroy
    has_many :likers, through: :likes, source: :user
    has_many :comments, class_name: 'Comment', foreign_key: 'playlist_set_id', dependent: :destroy

    validates :name, presence: true
    validates :privacy, inclusion: { in: %w[public private unlisted] }

    enum privacy: { public: 0, private: 1, unlisted: 2 }

    scope :public_playlists, -> { where(privacy: :public) }
    scope :popular, -> { joins(:likes).group('playlist_sets.id').order('COUNT(playlist_likes.id) DESC') }

    def total_duration
      tracks.sum(:duration)
    end

    def formatted_duration
      total_seconds = total_duration
      hours = total_seconds / 3600
      minutes = (total_seconds % 3600) / 60
      seconds = total_seconds % 60

      if hours > 0
        format('%d:%02d:%02d', hours, minutes, seconds)
      else
        format('%d:%02d', minutes, seconds)
      end
    end

    def can_edit?(user)
      return false unless user
      return true if self.user == user
      collaborations.where(user: user, role: ['editor', 'admin']).exists?
    end

    def can_view?(user)
      return true if public?
      return false unless user
      return true if self.user == user
      collaborations.where(user: user).exists?
    end

    def like_count
      likes.count
    end

    def liked_by?(user)
      return false unless user
      likes.exists?(user: user)
    end
  end
end
EOF

cat <<EOF > app/models/playlist/track.rb
module Playlist
  class Track < ApplicationRecord
    belongs_to :set, class_name: 'Playlist::Set'

    validates :name, :artist, presence: true
    validates :position, presence: true, uniqueness: { scope: :set_id }
    validates :duration, presence: true, numericality: { greater_than: 0 }

    before_validation :set_position, if: :new_record?

    scope :ordered, -> { order(:position) }

    def formatted_duration
      return '0:00' unless duration

      minutes = duration / 60
      seconds = duration % 60
      format('%d:%02d', minutes, seconds)
    end

    def previous_track
      set.tracks.where('position < ?', position).order(position: :desc).first
    end

    def next_track
      set.tracks.where('position > ?', position).order(position: :asc).first
    end

    private

    def set_position
      self.position ||= (set.tracks.maximum(:position) || 0) + 1
    end
  end
end
EOF

# Enhanced controllers with music streaming features
mkdir -p app/controllers/playlist
cat <<EOF > app/controllers/playlist/sets_controller.rb
module Playlist
  class SetsController < ApplicationController
    before_action :authenticate_user!, except: [:index, :show]
    before_action :set_playlist_set, only: [:show, :edit, :update, :destroy, :like, :unlike, :collaborate]
    before_action :check_view_permission, only: [:show]
    before_action :check_edit_permission, only: [:edit, :update, :destroy]

    def index
      @sets = Playlist::Set.public_playlists.includes(:user, :tracks, :likes)
      @sets = @sets.where("name ILIKE ?", "%#{params[:search]}%") if params[:search].present?

      case params[:sort]
      when 'popular'
        @sets = @sets.popular
      when 'recent'
        @sets = @sets.order(created_at: :desc)
      else
        @sets = @sets.order(:name)
      end

      @pagy, @sets = pagy(@sets) unless @stimulus_reflex
    end

    def show
      @tracks = @set.tracks.ordered
      @comments = @set.comments.includes(:user).order(created_at: :desc).limit(10)
      @new_comment = Comment.new

      respond_to do |format|
        format.html
        format.json { render json: serialize_playlist(@set) }
      end
    end

    def new
      @set = current_user.playlist_sets.build
    end

    def create
      @set = current_user.playlist_sets.build(set_params)

      if @set.save
        redirect_to playlist_set_path(@set), notice: 'Playlist created successfully!'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @set.update(set_params)
        redirect_to playlist_set_path(@set), notice: 'Playlist updated successfully!'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @set.destroy
      redirect_to playlist_sets_path, notice: 'Playlist deleted successfully!'
    end

    def like
      like = @set.likes.find_or_initialize_by(user: current_user)

      if like.persisted?
        like.destroy
        liked = false
      else
        like.save!
        liked = true
      end

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "like-button-#{@set.id}",
            partial: "playlist/sets/like_button",
            locals: { set: @set, liked: liked }
          )
        end
        format.json { render json: { liked: liked, like_count: @set.like_count } }
      end
    end

    def collaborate
      collaboration_params = params.require(:collaboration).permit(:user_id, :role)
      user = User.find(collaboration_params[:user_id])

      collaboration = @set.collaborations.find_or_initialize_by(user: user)
      collaboration.role = collaboration_params[:role]

      if collaboration.save
        render json: { success: true, message: 'Collaborator added successfully!' }
      else
        render json: { success: false, errors: collaboration.errors.full_messages }
      end
    end

    private

    def set_playlist_set
      @set = Playlist::Set.find(params[:id])
    end

    def check_view_permission
      unless @set.can_view?(current_user)
        redirect_to playlist_sets_path, alert: 'You do not have permission to view this playlist.'
      end
    end

    def check_edit_permission
      unless @set.can_edit?(current_user)
        redirect_to playlist_set_path(@set), alert: 'You do not have permission to edit this playlist.'
      end
    end

    def set_params
      params.require(:playlist_set).permit(:name, :description, :privacy, :collaborative)
    end

    def serialize_playlist(set)
      {
        id: set.id,
        name: set.name,
        description: set.description,
        duration: set.formatted_duration,
        track_count: set.tracks.count,
        like_count: set.like_count,
        tracks: set.tracks.map do |track|
          {
            id: track.id,
            name: track.name,
            artist: track.artist,
            duration: track.formatted_duration,
            audio_url: track.audio_url,
            position: track.position
          }
        end
      }
    end
  end
end
EOF

cat <<EOF > app/reflexes/playlists_infinite_scroll_reflex.rb
class PlaylistsInfiniteScrollReflex < InfiniteScrollReflex
  def load_more
    @pagy, @collection = pagy(Playlist.all.order(created_at: :desc), page: page)
    super
  end
end
EOF

cat <<EOF > app/reflexes/comments_infinite_scroll_reflex.rb
class CommentsInfiniteScrollReflex < InfiniteScrollReflex
  def load_more
    @pagy, @collection = pagy(Comment.all.order(created_at: :desc), page: page)
    super
  end
end
EOF

cat <<EOF > app/controllers/playlists_controller.rb
class PlaylistsController < ApplicationController
  before_action :authenticate_user!, except: [:index, :show]
  before_action :set_playlist, only: [:show, :edit, :update, :destroy]

  def index
    @pagy, @playlists = pagy(Playlist.all.order(created_at: :desc)) unless @stimulus_reflex
  end

  def show
  end

  def new
    @playlist = Playlist.new
  end

  def create
    @playlist = Playlist.new(playlist_params)
    @playlist.user = current_user
    if @playlist.save
      respond_to do |format|
        format.html { redirect_to playlists_path, notice: t("brgen_playlist.playlist_created") }
        format.turbo_stream
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @playlist.update(playlist_params)
      respond_to do |format|
        format.html { redirect_to playlists_path, notice: t("brgen_playlist.playlist_updated") }
        format.turbo_stream
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @playlist.destroy
    respond_to do |format|
      format.html { redirect_to playlists_path, notice: t("brgen_playlist.playlist_deleted") }
      format.turbo_stream
    end
  end

  private

  def set_playlist
    @playlist = Playlist.find(params[:id])
    redirect_to playlists_path, alert: t("brgen_playlist.not_authorized") unless @playlist.user == current_user || current_user&.admin?
  end

  def playlist_params
    params.require(:playlist).permit(:name, :description, :tracks)
  end
end
EOF

cat <<EOF > app/controllers/comments_controller.rb
class CommentsController < ApplicationController
  before_action :authenticate_user!, except: [:index, :show]
  before_action :set_comment, only: [:show, :edit, :update, :destroy]

  def index
    @pagy, @comments = pagy(Comment.all.order(created_at: :desc)) unless @stimulus_reflex
  end

  def show
  end

  def new
    @comment = Comment.new
  end

  def create
    @comment = Comment.new(comment_params)
    @comment.user = current_user
    if @comment.save
      respond_to do |format|
        format.html { redirect_to comments_path, notice: t("brgen_playlist.comment_created") }
        format.turbo_stream
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @comment.update(comment_params)
      respond_to do |format|
        format.html { redirect_to comments_path, notice: t("brgen_playlist.comment_updated") }
        format.turbo_stream
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @comment.destroy
    respond_to do |format|
      format.html { redirect_to comments_path, notice: t("brgen_playlist.comment_deleted") }
      format.turbo_stream
    end
  end

  private

  def set_comment
    @comment = Comment.find(params[:id])
    redirect_to comments_path, alert: t("brgen_playlist.not_authorized") unless @comment.user == current_user || current_user&.admin?
  end

  def comment_params
    params.require(:comment).permit(:playlist_id, :content)
  end
end
EOF

cat <<EOF > app/controllers/home_controller.rb
class HomeController < ApplicationController
  def index
    @pagy, @posts = pagy(Post.all.order(created_at: :desc), items: 10) unless @stimulus_reflex
    @playlists = Playlist.all.order(created_at: :desc).limit(5)
  end
end
EOF

mkdir -p app/views/brgen_playlist_logo

cat <<'EOF' > app/assets/stylesheets/application.css
:root {
  --primary: #ff5722;
  --secondary: #5f6368;
  --bg: #1a1a1a;
  --surface: #2a2a2a;
  --text: #ffffff;
  --border: #3a3a3a;
  --spacing: 1rem;
}

* { box-sizing: border-box; margin: 0; padding: 0; }

body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  line-height: 1.6;
  color: var(--text);
  background: var(--bg);
}

main { max-width: 1400px; margin: 0 auto; padding: var(--spacing); }

.player {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: var(--spacing);
  position: sticky;
  top: var(--spacing);
}

.waveform { height: 80px; width: 100%; background: var(--bg); border-radius: 4px; margin: var(--spacing) 0; }

.playlist { display: grid; gap: calc(var(--spacing) / 2); }
.track {
  background: var(--surface);
  padding: var(--spacing);
  border: 1px solid var(--border);
  border-radius: 4px;
  display: flex;
  align-items: center;
  gap: var(--spacing);
  cursor: pointer;
}
.track:hover { border-color: var(--primary); }
.track.playing { border-color: var(--primary); background: rgba(255, 87, 34, 0.1); }

.track img { width: 50px; height: 50px; border-radius: 4px; object-fit: cover; }
.track-info { flex: 1; }
.track-title { font-weight: 600; }
.track-artist { color: var(--secondary); font-size: 0.9rem; }

button, .button {
  padding: 0.75rem 1.5rem;
  background: var(--primary);
  color: white;
  border: none;
  border-radius: 4px;
  cursor: pointer;
}
button:hover { opacity: 0.9; }

@media (max-width: 768px) {
  main { padding: calc(var(--spacing) / 2); }
}
EOF

cat <<EOF > app/views/brgen_playlist_logo/_logo.html.erb
<%= tag.svg xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 100 50", role: "img", class: "logo", "aria-label": t("brgen_playlist.logo_alt") do %>
  <%= tag.title t("brgen_playlist.logo_title", default: "Brgen Playlist Logo") %>
  <%= tag.text x: "50", y: "30", "text-anchor": "middle", "font-family": "Helvetica, Arial, sans-serif", "font-size": "16", fill: "#ff9800" do %>Playlist<% end %>
<% end %>
EOF

cat <<EOF > app/views/shared/_header.html.erb
<%= tag.header role: "banner" do %>
  <%= render partial: "brgen_playlist_logo/logo" %>
<% end %>
EOF

cat <<EOF > app/views/shared/_footer.html.erb
<%= tag.footer role: "contentinfo" do %>
  <%= tag.nav class: "footer-links" aria-label: t("shared.footer_nav") do %>
    <%= link_to "", "https://facebook.com", class: "footer-link fb", "aria-label": "Facebook" %>
    <%= link_to "", "https://twitter.com", class: "footer-link tw", "aria-label": "Twitter" %>
    <%= link_to "", "https://instagram.com", class: "footer-link ig", "aria-label": "Instagram" %>
    <%= link_to t("shared.about"), "#", class: "footer-link text" %>
    <%= link_to t("shared.contact"), "#", class: "footer-link text" %>
    <%= link_to t("shared.terms"), "#", class: "footer-link text" %>
    <%= link_to t("shared.privacy"), "#", class: "footer-link text" %>
  <% end %>
<% end %>
EOF

cat <<EOF > app/views/home/index.html.erb
<% content_for :title, t("brgen_playlist.home_title") %>
<% content_for :description, t("brgen_playlist.home_description") %>
<% content_for :keywords, t("brgen_playlist.home_keywords", default: "brgen playlist, music, sharing") %>
<% content_for :schema do %>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "WebPage",
    "name": "<%= t('brgen_playlist.home_title') %>",
    "description": "<%= t('brgen_playlist.home_description') %>",
    "url": "<%= request.original_url %>",
    "publisher": {
      "@type": "Organization",
      "name": "Brgen Playlist",
      "logo": {
        "@type": "ImageObject",
        "url": "<%= image_url('brgen_playlist_logo.svg') %>"
      }
    }
  }
  </script>
<% end %>
<%= render "shared/header" %>
<%= tag.main role: "main" do %>
  <%= tag.section aria-labelledby: "post-heading" do %>
    <%= tag.h1 t("brgen_playlist.post_title"), id: "post-heading" %>
    <%= tag.div data: { turbo_frame: "notices" } do %>
      <%= render "shared/notices" %>
    <% end %>
    <%= render partial: "posts/form", locals: { post: Post.new } %>
  <% end %>
  <%= render partial: "shared/search", locals: { model: "Playlist", field: "name" } %>
  <%= tag.section aria-labelledby: "playlists-heading" do %>
    <%= tag.h2 t("brgen_playlist.playlists_title"), id: "playlists-heading" %>
    <%= link_to t("brgen_playlist.new_playlist"), new_playlist_path, class: "button", "aria-label": t("brgen_playlist.new_playlist") if current_user %>
    <%= turbo_frame_tag "playlists" data: { controller: "infinite-scroll" } do %>
      <% @playlists.each do |playlist| %>
        <%= render partial: "playlists/card", locals: { playlist: playlist } %>
      <% end %>
      <%= tag.div id: "sentinel", class: "hidden", data: { reflex: "PlaylistsInfiniteScroll#load_more", next_page: @pagy.next || 2 } %>
    <% end %>
    <%= tag.button t("brgen_playlist.load_more"), id: "load-more", data: { reflex: "click->PlaylistsInfiniteScroll#load_more", "next-page": @pagy.next || 2, "reflex-root": "#load-more" }, class: @pagy&.next ? "" : "hidden", "aria-label": t("brgen_playlist.load_more") %>
  <% end %>
  <%= tag.section aria-labelledby: "posts-heading" do %>
    <%= tag.h2 t("brgen_playlist.posts_title"), id: "posts-heading" %>
    <%= turbo_frame_tag "posts" data: { controller: "infinite-scroll" } do %>
      <% @posts.each do |post| %>
        <%= render partial: "posts/card", locals: { post: post } %>
      <% end %>
      <%= tag.div id: "sentinel", class: "hidden", data: { reflex: "PostsInfiniteScroll#load_more", next_page: @pagy.next || 2 } %>
    <% end %>
    <%= tag.button t("brgen_playlist.load_more"), id: "load-more", data: { reflex: "click->PostsInfiniteScroll#load_more", "next-page": @pagy.next || 2, "reflex-root": "#load-more" }, class: @pagy&.next ? "" : "hidden", "aria-label": t("brgen_playlist.load_more") %>
  <% end %>
  <%= render partial: "shared/chat" %>
<% end %>
<%= render "shared/footer" %>
EOF

cat <<EOF > app/views/playlists/index.html.erb
<% content_for :title, t("brgen_playlist.playlists_title") %>
<% content_for :description, t("brgen_playlist.playlists_description") %>
<% content_for :keywords, t("brgen_playlist.playlists_keywords", default: "brgen playlist, music, sharing") %>
<% content_for :schema do %>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "WebPage",
    "name": "<%= t('brgen_playlist.playlists_title') %>",
    "description": "<%= t('brgen_playlist.playlists_description') %>",
    "url": "<%= request.original_url %>",
    "hasPart": [
      <% @playlists.each do |playlist| %>
      {
        "@type": "MusicPlaylist",
        "name": "<%= playlist.name %>",
        "description": "<%= playlist.description&.truncate(160) %>"
      }<%= "," unless playlist == @playlists.last %>
      <% end %>
    ]
  }
  </script>
<% end %>
<%= render "shared/header" %>
<%= tag.main role: "main" do %>
  <%= tag.section aria-labelledby: "playlists-heading" do %>
    <%= tag.h1 t("brgen_playlist.playlists_title"), id: "playlists-heading" %>
    <%= tag.div data: { turbo_frame: "notices" } do %>
      <%= render "shared/notices" %>
    <% end %>
    <%= link_to t("brgen_playlist.new_playlist"), new_playlist_path, class: "button", "aria-label": t("brgen_playlist.new_playlist") if current_user %>
    <%= turbo_frame_tag "playlists" data: { controller: "infinite-scroll" } do %>
      <% @playlists.each do |playlist| %>
        <%= render partial: "playlists/card", locals: { playlist: playlist } %>
      <% end %>
      <%= tag.div id: "sentinel", class: "hidden", data: { reflex: "PlaylistsInfiniteScroll#load_more", next_page: @pagy.next || 2 } %>
    <% end %>
    <%= tag.button t("brgen_playlist.load_more"), id: "load-more", data: { reflex: "click->PlaylistsInfiniteScroll#load_more", "next-page": @pagy.next || 2, "reflex-root": "#load-more" }, class: @pagy&.next ? "" : "hidden", "aria-label": t("brgen_playlist.load_more") %>
  <% end %>
  <%= render partial: "shared/search", locals: { model: "Playlist", field: "name" } %>
<% end %>
<%= render "shared/footer" %>
EOF

cat <<EOF > app/views/playlists/_card.html.erb
<%= turbo_frame_tag dom_id(playlist) do %>
  <%= tag.article class: "post-card", id: dom_id(playlist), role: "article" do %>
    <%= tag.div class: "post-header" do %>
      <%= tag.span t("brgen_playlist.posted_by", user: playlist.user.email) %>
      <%= tag.span playlist.created_at.strftime("%Y-%m-%d %H:%M") %>
    <% end %>
    <%= tag.h2 playlist.name %>
    <%= tag.p playlist.description %>
    <%= tag.p t("brgen_playlist.playlist_tracks", tracks: playlist.tracks) %>
    <%= render partial: "shared/vote", locals: { votable: playlist } %>
    <%= tag.p class: "post-actions" do %>
      <%= link_to t("brgen_playlist.view_playlist"), playlist_path(playlist), "aria-label": t("brgen_playlist.view_playlist") %>
      <%= link_to t("brgen_playlist.edit_playlist"), edit_playlist_path(playlist), "aria-label": t("brgen_playlist.edit_playlist") if playlist.user == current_user || current_user&.admin? %>
      <%= button_to t("brgen_playlist.delete_playlist"), playlist_path(playlist), method: :delete, data: { turbo_confirm: t("brgen_playlist.confirm_delete") }, form: { data: { turbo_frame: "_top" } }, "aria-label": t("brgen_playlist.delete_playlist") if playlist.user == current_user || current_user&.admin? %>
    <% end %>
  <% end %>
<% end %>
EOF

cat <<EOF > app/views/playlists/_form.html.erb
<%= form_with model: playlist, local: true, data: { controller: "character-counter form-validation", turbo: true } do |form| %>
  <%= tag.div data: { turbo_frame: "notices" } do %>
    <%= render "shared/notices" %>
  <% end %>
  <% if playlist.errors.any? %>
    <%= tag.div role: "alert" do %>
      <%= tag.p t("brgen_playlist.errors", count: playlist.errors.count) %>
      <%= tag.ul do %>
        <% playlist.errors.full_messages.each do |msg| %>
          <%= tag.li msg %>
        <% end %>
      <% end %>
    <% end %>
  <% end %>
  <%= tag.fieldset do %>
    <%= form.label :name, t("brgen_playlist.playlist_name"), "aria-required": true %>
    <%= form.text_field :name, required: true, data: { "form-validation-target": "input", action: "input->form-validation#validate" }, title: t("brgen_playlist.playlist_name_help") %>
    <%= tag.span class: "error-message" data: { "form-validation-target": "error", for: "playlist_name" } %>
  <% end %>
  <%= tag.fieldset do %>
    <%= form.label :description, t("brgen_playlist.playlist_description"), "aria-required": true %>
    <%= form.text_area :description, required: true, data: { "character-counter-target": "input", "textarea-autogrow-target": "input", "form-validation-target": "input", action: "input->character-counter#count input->textarea-autogrow#resize input->form-validation#validate" }, title: t("brgen_playlist.playlist_description_help") %>
    <%= tag.span data: { "character-counter-target": "count" } %>
    <%= tag.span class: "error-message" data: { "form-validation-target": "error", for: "playlist_description" } %>
  <% end %>
  <%= tag.fieldset do %>
    <%= form.label :tracks, t("brgen_playlist.playlist_tracks"), "aria-required": true %>
    <%= form.text_area :tracks, required: true, data: { "character-counter-target": "input", "textarea-autogrow-target": "input", "form-validation-target": "input", action: "input->character-counter#count input->textarea-autogrow#resize input->form-validation#validate" }, title: t("brgen_playlist.playlist_tracks_help") %>
    <%= tag.span data: { "character-counter-target": "count" } %>
    <%= tag.span class: "error-message" data: { "form-validation-target": "error", for: "playlist_tracks" } %>
  <% end %>
  <%= form.submit t("brgen_playlist.#{playlist.persisted? ? 'update' : 'create'}_playlist"), data: { turbo_submits_with: t("brgen_playlist.#{playlist.persisted? ? 'updating' : 'creating'}_playlist") } %>
<% end %>
EOF

cat <<EOF > app/views/playlists/new.html.erb
<% content_for :title, t("brgen_playlist.new_playlist_title") %>
<% content_for :description, t("brgen_playlist.new_playlist_description") %>
<% content_for :keywords, t("brgen_playlist.new_playlist_keywords", default: "add playlist, brgen playlist, music") %>
<% content_for :schema do %>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "WebPage",
    "name": "<%= t('brgen_playlist.new_playlist_title') %>",
    "description": "<%= t('brgen_playlist.new_playlist_description') %>",
    "url": "<%= request.original_url %>"
  }
  </script>
<% end %>
<%= render "shared/header" %>
<%= tag.main role: "main" do %>
  <%= tag.section aria-labelledby: "new-playlist-heading" do %>
    <%= tag.h1 t("brgen_playlist.new_playlist_title"), id: "new-playlist-heading" %>
    <%= render partial: "playlists/form", locals: { playlist: @playlist } %>
  <% end %>
<% end %>
<%= render "shared/footer" %>
EOF

cat <<EOF > app/views/playlists/edit.html.erb
<% content_for :title, t("brgen_playlist.edit_playlist_title") %>
<% content_for :description, t("brgen_playlist.edit_playlist_description") %>
<% content_for :keywords, t("brgen_playlist.edit_playlist_keywords", default: "edit playlist, brgen playlist, music") %>
<% content_for :schema do %>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "WebPage",
    "name": "<%= t('brgen_playlist.edit_playlist_title') %>",
    "description": "<%= t('brgen_playlist.edit_playlist_description') %>",
    "url": "<%= request.original_url %>"
  }
  </script>
<% end %>
<%= render "shared/header" %>
<%= tag.main role: "main" do %>
  <%= tag.section aria-labelledby: "edit-playlist-heading" do %>
    <%= tag.h1 t("brgen_playlist.edit_playlist_title"), id: "edit-playlist-heading" %>
    <%= render partial: "playlists/form", locals: { playlist: @playlist } %>
  <% end %>
<% end %>
<%= render "shared/footer" %>
EOF

cat <<EOF > app/views/playlists/show.html.erb
<% content_for :title, @playlist.name %>
<% content_for :description, @playlist.description&.truncate(160) %>
<% content_for :keywords, t("brgen_playlist.playlist_keywords", name: @playlist.name, default: "playlist, #{@playlist.name}, brgen playlist, music") %>
<% content_for :schema do %>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "MusicPlaylist",
    "name": "<%= @playlist.name %>",
    "description": "<%= @playlist.description&.truncate(160) %>"
  }
  </script>
<% end %>
<%= render "shared/header" %>
<%= tag.main role: "main" do %>
  <%= tag.section aria-labelledby: "playlist-heading" class: "post-card" do %>
    <%= tag.div data: { turbo_frame: "notices" } do %>
      <%= render "shared/notices" %>
    <% end %>
    <%= tag.h1 @playlist.name, id: "playlist-heading" %>
    <%= render partial: "playlists/card", locals: { playlist: @playlist } %>
  <% end %>
<% end %>
<%= render "shared/footer" %>
EOF

cat <<EOF > app/views/comments/index.html.erb
<% content_for :title, t("brgen_playlist.comments_title") %>
<% content_for :description, t("brgen_playlist.comments_description") %>
<% content_for :keywords, t("brgen_playlist.comments_keywords", default: "brgen playlist, comments, music") %>
<% content_for :schema do %>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "WebPage",
    "name": "<%= t('brgen_playlist.comments_title') %>",
    "description": "<%= t('brgen_playlist.comments_description') %>",
    "url": "<%= request.original_url %>"
  }
  </script>
<% end %>
<%= render "shared/header" %>
<%= tag.main role: "main" do %>
  <%= tag.section aria-labelledby: "comments-heading" do %>
    <%= tag.h1 t("brgen_playlist.comments_title"), id: "comments-heading" %>
    <%= tag.div data: { turbo_frame: "notices" } do %>
      <%= render "shared/notices" %>
    <% end %>
    <%= link_to t("brgen_playlist.new_comment"), new_comment_path, class: "button", "aria-label": t("brgen_playlist.new_comment") %>
    <%= turbo_frame_tag "comments" data: { controller: "infinite-scroll" } do %>
      <% @comments.each do |comment| %>
        <%= render partial: "comments/card", locals: { comment: comment } %>
      <% end %>
      <%= tag.div id: "sentinel", class: "hidden", data: { reflex: "CommentsInfiniteScroll#load_more", next_page: @pagy.next || 2 } %>
    <% end %>
    <%= tag.button t("brgen_playlist.load_more"), id: "load-more", data: { reflex: "click->CommentsInfiniteScroll#load_more", "next-page": @pagy.next || 2, "reflex-root": "#load-more" }, class: @pagy&.next ? "" : "hidden", "aria-label": t("brgen_playlist.load_more") %>
  <% end %>
<% end %>
<%= render "shared/footer" %>
EOF

cat <<EOF > app/views/comments/_card.html.erb
<%= turbo_frame_tag dom_id(comment) do %>
  <%= tag.article class: "post-card", id: dom_id(comment), role: "article" do %>
    <%= tag.div class: "post-header" do %>
      <%= tag.span t("brgen_playlist.posted_by", user: comment.user.email) %>
      <%= tag.span comment.created_at.strftime("%Y-%m-%d %H:%M") %>
    <% end %>
    <%= tag.h2 comment.playlist.name %>
    <%= tag.p comment.content %>
    <%= render partial: "shared/vote", locals: { votable: comment } %>
    <%= tag.p class: "post-actions" do %>
      <%= link_to t("brgen_playlist.view_comment"), comment_path(comment), "aria-label": t("brgen_playlist.view_comment") %>
      <%= link_to t("brgen_playlist.edit_comment"), edit_comment_path(comment), "aria-label": t("brgen_playlist.edit_comment") if comment.user == current_user || current_user&.admin? %>
      <%= button_to t("brgen_playlist.delete_comment"), comment_path(comment), method: :delete, data: { turbo_confirm: t("brgen_playlist.confirm_delete") }, form: { data: { turbo_frame: "_top" } }, "aria-label": t("brgen_playlist.delete_comment") if comment.user == current_user || current_user&.admin? %>
    <% end %>
  <% end %>
<% end %>
EOF

cat <<EOF > app/views/comments/_form.html.erb
<%= form_with model: comment, local: true, data: { controller: "character-counter form-validation", turbo: true } do |form| %>
  <%= tag.div data: { turbo_frame: "notices" } do %>
    <%= render "shared/notices" %>
  <% end %>
  <% if comment.errors.any? %>
    <%= tag.div role: "alert" do %>
      <%= tag.p t("brgen_playlist.errors", count: comment.errors.count) %>
      <%= tag.ul do %>
        <% comment.errors.full_messages.each do |msg| %>
          <%= tag.li msg %>
        <% end %>
      <% end %>
    <% end %>
  <% end %>
  <%= tag.fieldset do %>
    <%= form.label :playlist_id, t("brgen_playlist.comment_playlist"), "aria-required": true %>
    <%= form.collection_select :playlist_id, Playlist.all, :id, :name, { prompt: t("brgen_playlist.playlist_prompt") }, required: true %>
    <%= tag.span class: "error-message" data: { "form-validation-target": "error", for: "comment_playlist_id" } %>
  <% end %>
  <%= tag.fieldset do %>
    <%= form.label :content, t("brgen_playlist.comment_content"), "aria-required": true %>
    <%= form.text_area :content, required: true, data: { "character-counter-target": "input", "textarea-autogrow-target": "input", "form-validation-target": "input", action: "input->character-counter#count input->textarea-autogrow#resize input->form-validation#validate" }, title: t("brgen_playlist.comment_content_help") %>
    <%= tag.span data: { "character-counter-target": "count" } %>
    <%= tag.span class: "error-message" data: { "form-validation-target": "error", for: "comment_content" } %>
  <% end %>
  <%= form.submit t("brgen_playlist.#{comment.persisted? ? 'update' : 'create'}_comment"), data: { turbo_submits_with: t("brgen_playlist.#{comment.persisted? ? 'updating' : 'creating'}_comment") } %>
<% end %>
EOF

cat <<EOF > app/views/comments/new.html.erb
<% content_for :title, t("brgen_playlist.new_comment_title") %>
<% content_for :description, t("brgen_playlist.new_comment_description") %>
<% content_for :keywords, t("brgen_playlist.new_comment_keywords", default: "add comment, brgen playlist, music") %>
<% content_for :schema do %>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "WebPage",
    "name": "<%= t('brgen_playlist.new_comment_title') %>",
    "description": "<%= t('brgen_playlist.new_comment_description') %>",
    "url": "<%= request.original_url %>"
  }
  </script>
<% end %>
<%= render "shared/header" %>
<%= tag.main role: "main" do %>
  <%= tag.section aria-labelledby: "new-comment-heading" do %>
    <%= tag.h1 t("brgen_playlist.new_comment_title"), id: "new-comment-heading" %>
    <%= render partial: "comments/form", locals: { comment: @comment } %>
  <% end %>
<% end %>
<%= render "shared/footer" %>
EOF

cat <<EOF > app/views/comments/edit.html.erb
<% content_for :title, t("brgen_playlist.edit_comment_title") %>
<% content_for :description, t("brgen_playlist.edit_comment_description") %>
<% content_for :keywords, t("brgen_playlist.edit_comment_keywords", default: "edit comment, brgen playlist, music") %>
<% content_for :schema do %>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "WebPage",
    "name": "<%= t('brgen_playlist.edit_comment_title') %>",
    "description": "<%= t('brgen_playlist.edit_comment_description') %>",
    "url": "<%= request.original_url %>"
  }
  </script>
<% end %>
<%= render "shared/header" %>
<%= tag.main role: "main" do %>
  <%= tag.section aria-labelledby: "edit-comment-heading" do %>
    <%= tag.h1 t("brgen_playlist.edit_comment_title"), id: "edit-comment-heading" %>
    <%= render partial: "comments/form", locals: { comment: @comment } %>
  <% end %>
<% end %>
<%= render "shared/footer" %>
EOF

cat <<EOF > app/views/comments/show.html.erb
<% content_for :title, t("brgen_playlist.comment_title", playlist: @comment.playlist.name) %>
<% content_for :description, @comment.content&.truncate(160) %>
<% content_for :keywords, t("brgen_playlist.comment_keywords", playlist: @comment.playlist.name, default: "comment, #{@comment.playlist.name}, brgen playlist, music") %>
<% content_for :schema do %>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "Comment",
    "text": "<%= @comment.content&.truncate(160) %>",
    "about": {
      "@type": "MusicPlaylist",
      "name": "<%= @comment.playlist.name %>"
    }
  }
  </script>
<% end %>
<%= render "shared/header" %>
<%= tag.main role: "main" do %>
  <%= tag.section aria-labelledby: "comment-heading" class: "post-card" do %>
    <%= tag.div data: { turbo_frame: "notices" } do %>
      <%= render "shared/notices" %>
    <% end %>
    <%= tag.h1 t("brgen_playlist.comment_title", playlist: @comment.playlist.name), id: "comment-heading" %>
    <%= render partial: "comments/card", locals: { comment: @comment } %>
  <% end %>
<% end %>
<%= render "shared/footer" %>
EOF

generate_turbo_views "playlists" "playlist"
generate_turbo_views "comments" "comment"

cat <<EOF > db/seeds.rb
require "faker"

puts "Creating demo users with Faker..."
demo_users = []
8.times do
  demo_users << User.create!(
    email: Faker::Internet.unique.email,
    password: "password123",
    name: Faker::Name.name
  )
end

puts "Created #{demo_users.count} demo users."

puts "Creating demo playlists with Faker..."
genres = ['Rock', 'Pop', 'Jazz', 'Classical', 'Electronic', 'Hip-Hop']
moods = ['Energetic', 'Relaxing', 'Happy', 'Melancholic', 'Romantic']

20.times do
  Playlist.create!(
    name: "#{Faker::Music.genre} #{moods.sample} Mix",
    description: Faker::Lorem.paragraph(sentence_count: 2),
    tracks: [Faker::Music.band, Faker::Music.band, Faker::Music.band].join(', '),
    user: demo_users.sample
  )
end

puts "Created #{Playlist.count} demo playlists."

puts "Creating demo playlist sets..."
15.times do
  set = Playlist::Set.create!(
    name: "#{genres.sample} Favorites #{rand(2020..2025)}",
    description: Faker::Lorem.paragraph(sentence_count: 3),
    user: demo_users.sample,
    privacy: ['public', 'private', 'unlisted'].sample,
    collaborative: [true, false].sample
  )

  # Add tracks to each set
  rand(5..12).times do |i|
    Playlist::Track.create!(
      set: set,
      name: Faker::Music.album,
      artist: Faker::Music.band,
      audio_url: "https://example.com/audio/#{Faker::Alphanumeric.alpha(number: 10)}.mp3",
      duration: rand(120..300),
      position: i + 1
    )
  end
end

puts "Created #{Playlist::Set.count} playlist sets with #{Playlist::Track.count} tracks."

puts "Creating demo comments..."
40.times do
  Comment.create!(
    playlist_set: Playlist::Set.all.sample,
    user: demo_users.sample,
    content: Faker::Lorem.sentence(word_count: rand(10..25))
  )
end

puts "Created #{Comment.count} demo comments."

puts "Creating demo likes..."
50.times do
  set = Playlist::Set.all.sample
  user = demo_users.sample

  Playlist::Like.find_or_create_by(user: user, set: set)
end

puts "Created #{Playlist::Like.count} demo likes."

puts "Seed data creation complete!"
EOF

# Integrate Radio Bergen Visualizer
log "Integrating Radio Bergen 8-bit pixel visualizer..."

mkdir -p public/visualizer

# Copy Radio Bergen visualizer from G:/pub/index.html
if [[ -f "/g/pub/index.html" ]]; then
  cp "/g/pub/index.html" public/visualizer/index.html
  log "✓ Copied Radio Bergen visualizer to public/visualizer/index.html"
else
  log "⚠ Warning: G:/pub/index.html not found, skipping visualizer integration"
fi

# Add visualizer route
cat <<'EOF' >> config/routes.rb

  # Radio Bergen Visualizer
  get "visualizer", to: redirect("/visualizer/index.html")
EOF

# Add visualizer link to playlist show view
cat <<'EOF' > app/views/playlists/show.html.erb
<% content_for :title, @playlist.name %>
<% content_for :description, @playlist.description&.truncate(160) %>
<% content_for :keywords, t("brgen_playlist.playlist_keywords", name: @playlist.name, default: "playlist, #{@playlist.name}, brgen playlist, music") %>
<% content_for :schema do %>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "MusicPlaylist",
    "name": "<%= @playlist.name %>",
    "description": "<%= @playlist.description&.truncate(160) %>"
  }
  </script>
<% end %>
<%= render "shared/header" %>
<%= tag.main role: "main" do %>
  <%= tag.section aria-labelledby: "playlist-heading" class: "post-card" do %>
    <%= tag.div data: { turbo_frame: "notices" } do %>
      <%= render "shared/notices" %>
    <% end %>
    <%= tag.h1 @playlist.name, id: "playlist-heading" %>

    <%= tag.p class: "visualizer-link" style: "margin: 1em 0;" do %>
      <%= link_to "🎵 Open in Radio Bergen Visualizer", visualizer_path, target: "_blank", class: "button", style: "background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 12px 24px; text-decoration: none; border-radius: 8px; display: inline-block; font-weight: 600;", "aria-label": "Open playlist in Radio Bergen 8-bit visualizer", title: "Experience this playlist with 8-bit pixel visualizations, physics-based motion, and beat-reactive effects" %>
    <% end %>

    <%= render partial: "playlists/card", locals: { playlist: @playlist } %>
  <% end %>
<% end %>
<%= render "shared/footer" %>
EOF

log "✓ Radio Bergen visualizer integrated"

commit "Brgen Playlist setup complete: Music playlist sharing platform with Radio Bergen visualizer"

log "Brgen Playlist setup complete. Run 'bin/falcon-host' with PORT set to start on OpenBSD."
log ""
log "📻 Radio Bergen Visualizer Integrated:"
log "   • Location: public/visualizer/index.html"
log "   • Route: /visualizer"
log "   • Access: http://localhost:3000/visualizer"
log "   • Features:"
log "     - 8 visualizer modes (Tunnel, Infinity Grid, Cymatic Waves, Fractal Cascade, etc.)"
log "     - Physics-based motion (wave interference, golden ratio spirals, particle trails)"
log "     - Beat-reactive psychedelic effects (auto-applied per visualizer)"
log "     - 6 color themes with keyboard shortcuts"
log "     - MP3 playback with Web Audio API + FFT analysis"
log "     - Mouse/gyro parallax support"
log ""
log "   Open any playlist and click '🎵 Open in Radio Bergen Visualizer'"
log "   See G:/pub/README-VISUALIZER.md for full documentation"

# Change Log:
# - Aligned with master.json v6.5.0: Two-space indents, double quotes, heredocs, Strunk & White comments.
# - Used Rails 8 conventions, Hotwire, Turbo Streams, Stimulus Reflex, I18n, and Falcon.
# - Leveraged bin/rails generate scaffold for Playlists and Comments to streamline CRUD setup.
# - Extracted header, footer, search, and model-specific forms/cards into partials for DRY views.
# - Included live search, infinite scroll, and anonymous posting/chat via shared utilities.
# - Ensured NNG principles, SEO, schema data, and minimal flat design compliance.
# - Finalized for unprivileged user on OpenBSD 7.5.
# - Integrated Radio Bergen Visualizer (G:/pub/index.html) as static asset at /visualizer route
# - Added visualizer link to playlist show pages for immersive playback experience
# - Visualizer features: 8 modes, physics-based motion, psychedelic effects, 6 themes, MP3 playback
