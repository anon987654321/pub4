#!/usr/bin/env zsh
# brgen_playlist.sh — Add Playlist:: namespace to the main brgen Rails app
set -euo pipefail

APP_DIR=/home/brgen/app
SCRIPT_DIR=${0:a:h}

. "${SCRIPT_DIR}/@shared_functions.sh" 2>/dev/null || . /tmp/shared_functions.sh

need_cmd ruby34 bundle rails doas

already_done "${APP_DIR}/app/models/playlist/playlist.rb" && exit 0

log "Brgen Playlist — adding Playlist namespace to brgen app"
cd "$APP_DIR"

# ── Models ─────────────────────────────────────────────────────────────────
bin/rails generate model Playlist::Playlist \
  user:references name:string description:text \
  public_access:boolean plays_count:integer \
  likes_count:integer tracks_count:integer \
  --no-test-framework

bin/rails generate model Playlist::Track \
  title:string artist:string album:string \
  duration_seconds:integer genre:string \
  source_type:string source_url:string \
  --no-test-framework

bin/rails generate model Playlist::PlaylistTrack \
  playlist_playlist:references playlist_track:references \
  position:integer user:references \
  --no-test-framework

bin/rails generate model Playlist::Listen \
  user:references playlist_track:references \
  --no-test-framework

RAILS_ENV=production bin/rails db:migrate

# ── Model logic ─────────────────────────────────────────────────────────────
mkdir -p app/models/playlist

cat > app/models/playlist/playlist.rb << 'RUBY'
class Playlist::Playlist < ApplicationRecord
  belongs_to :user
  has_many :playlist_tracks, class_name: "Playlist::PlaylistTrack",
           foreign_key: :playlist_playlist_id, dependent: :destroy
  has_many :tracks, through: :playlist_tracks, class_name: "Playlist::Track",
           source: :track

  validates :name, presence: true, length: { maximum: 100 }

  scope :public_playlists, -> { where(public_access: true) }
  scope :popular,           -> { order(plays_count: :desc) }
  scope :recent,            -> { order(created_at: :desc) }

  def add_track!(track, user:)
    pos = playlist_tracks.maximum(:position).to_i + 1
    playlist_tracks.find_or_create_by!(track: track) do |pt|
      pt.position = pos
      pt.user     = user
    end
    increment!(:tracks_count)
  end
end
RUBY

cat > app/models/playlist/track.rb << 'RUBY'
class Playlist::Track < ApplicationRecord
  has_many :playlist_tracks, class_name: "Playlist::PlaylistTrack",
           foreign_key: :playlist_track_id, dependent: :destroy
  has_many :playlists, through: :playlist_tracks, class_name: "Playlist::Playlist"
  has_many :listens, class_name: "Playlist::Listen",
           foreign_key: :playlist_track_id, dependent: :destroy

  SOURCE_TYPES = %w[youtube spotify soundcloud direct].freeze

  validates :title, :artist, presence: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }, allow_nil: true

  def duration_formatted
    return "—" unless duration_seconds
    min, sec = duration_seconds.divmod(60)
    "#{min}:%02d" % sec
  end
end
RUBY

cat > app/models/playlist/playlist_track.rb << 'RUBY'
class Playlist::PlaylistTrack < ApplicationRecord
  belongs_to :playlist, class_name: "Playlist::Playlist", foreign_key: :playlist_playlist_id
  belongs_to :track,    class_name: "Playlist::Track",    foreign_key: :playlist_track_id
  belongs_to :user

  validates :playlist_playlist_id, uniqueness: { scope: :playlist_track_id }
  default_scope { order(:position) }
end
RUBY

cat > app/models/playlist/listen.rb << 'RUBY'
class Playlist::Listen < ApplicationRecord
  belongs_to :user
  belongs_to :track, class_name: "Playlist::Track", foreign_key: :playlist_track_id

  after_create :increment_plays

  private
  def increment_plays
    track.playlists.each { |pl| pl.increment!(:plays_count) }
  end
end
RUBY

# ── Controllers ─────────────────────────────────────────────────────────────
mkdir -p app/controllers/playlist

cat > app/controllers/playlist/base_controller.rb << 'RUBY'
class Playlist::BaseController < ApplicationController

end
RUBY

cat > app/controllers/playlist/playlists_controller.rb << 'RUBY'
class Playlist::PlaylistsController < Playlist::BaseController
  allow_unauthenticated_access only: %i[index show]
  before_action :set_playlist, only: %i[show edit update destroy]

  def index
    @pagy, @playlists = pagy(Playlist::Playlist.public_playlists.popular.includes(:user))
  end

  def show
    @tracks = @playlist.playlist_tracks.includes(:track)
  end

  def new
    @playlist = Playlist::Playlist.new
  end

  def create
    @playlist = Current.user.playlist_playlists.build(playlist_params)
    @playlist.save ?
      redirect_to(playlist_playlist_path(@playlist), notice: "Playlist created") :
      render(:new, status: :unprocessable_entity)
  end

  def edit; end

  def update
    @playlist.update(playlist_params) ?
      redirect_to(playlist_playlist_path(@playlist)) :
      render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @playlist.destroy
    redirect_to playlist_playlists_path
  end

  private
  def set_playlist    = (@playlist = Playlist::Playlist.find(params[:id]))
  def playlist_params = params.require(:playlist_playlist).permit(:name, :description, :public_access)
end
RUBY

cat > app/controllers/playlist/tracks_controller.rb << 'RUBY'
class Playlist::TracksController < Playlist::BaseController
  before_action :set_playlist

  def create
    track = Playlist::Track.find_or_create_by!(title: params.dig(:playlist_track, :title),
                                               artist: params.dig(:playlist_track, :artist)) do |t|
      t.assign_attributes(track_params.except(:title, :artist))
    end
    @playlist.add_track!(track, user: Current.user)
    redirect_to playlist_playlist_path(@playlist), notice: "Track added"
  end

  def destroy
    pt = @playlist.playlist_tracks.find(params[:id])
    pt.destroy
    redirect_to playlist_playlist_path(@playlist)
  end

  private
  def set_playlist  = (@playlist = Playlist::Playlist.find(params[:playlist_id]))
  def track_params  = params.require(:playlist_track).permit(:title, :artist, :album, :duration_seconds, :source_type, :source_url, :genre)
end
RUBY

cat > app/controllers/playlist/listens_controller.rb << 'RUBY'
class Playlist::ListensController < Playlist::BaseController
  def create
    track = Playlist::Track.find(params[:track_id])
    Playlist::Listen.create!(user: Current.user, track: track)
    render json: { ok: true }
  end
end
RUBY

# ── Views ────────────────────────────────────────────────────────────────────
mkdir -p app/views/playlist/playlists app/views/playlist/tracks

cat > app/views/playlist/playlists/index.html.erb << 'ERB'
<% content_for :title, "Playlists" %>
<h1>Playlists</h1>
<% if authenticated? %><%= link_to "New playlist", new_playlist_playlist_path, class: "btn btn--primary" %><% end %>
<div class="playlist-grid">
  <% @playlists.each do |pl| %>
    <article>
      <%= link_to pl.name, playlist_playlist_path(pl) %>
      <small><%= pl.tracks_count %> tracks · <%= pl.plays_count %> plays · <%= pl.user.email_address.split("@").first %></small>
    </article>
  <% end %>
</div>
<%= @pagy.series_nav if @pagy.pages > 1 %>
ERB

cat > app/views/playlist/playlists/show.html.erb << 'ERB'
<% content_for :title, @playlist.name %>
<h1><%= @playlist.name %></h1>
<p><%= @playlist.description %></p>
<p><small><%= @playlist.tracks_count %> tracks · <%= @playlist.plays_count %> plays</small></p>

<% if authenticated? && Current.user == @playlist.user %>
  <nav>
    <%= link_to "Edit", edit_playlist_playlist_path(@playlist), class: "btn" %>
    <%= button_to "Delete", playlist_playlist_path(@playlist), method: :delete, class: "btn", data: { turbo_confirm: "Delete?" } %>
  </nav>
<% end %>

<ol>
  <% @tracks.each do |pt| %>
    <li>
      <strong><%= pt.track.title %></strong> — <%= pt.track.artist %>
      <small><%= pt.track.duration_formatted %></small>
      <% if authenticated? && (Current.user == pt.user || Current.user == @playlist.user) %>
        <%= button_to "Remove", playlist_playlist_track_path(@playlist, pt), method: :delete %>
      <% end %>
    </li>
  <% end %>
</ol>

<% if authenticated? %>
  <h2>Add a track</h2>
  <%= form_with url: playlist_playlist_tracks_path(@playlist) do |f| %>
    <%= f.text_field :title, placeholder: "Title", name: "playlist_track[title]" %>
    <%= f.text_field :artist, placeholder: "Artist", name: "playlist_track[artist]" %>
    <%= f.text_field :source_url, placeholder: "URL (optional)", name: "playlist_track[source_url]" %>
    <%= f.submit "Add" %>
  <% end %>
<% end %>
ERB

cat > app/views/playlist/playlists/new.html.erb << 'ERB'
<h1>New playlist</h1>
<%= form_with model: @playlist, url: playlist_playlists_path do |f| %>
  <%= render "shared/errors", object: @playlist %>
  <div class="field">
    <%= f.label :name %><%= f.text_field :name %>
  </div>
  <div class="field">
    <%= f.label :description %><%= f.text_area :description, rows: 3 %>
  </div>
  <div class="field">
    <%= f.check_box :public_access %> <%= f.label :public_access, "Public" %>
  </div>
  <div class="actions"><%= f.submit "Create", class: "btn btn--primary" %></div>
<% end %>
ERB

cat > app/views/playlist/playlists/edit.html.erb << 'ERB'
<h1>Edit playlist</h1>
<%= form_with model: @playlist, url: playlist_playlist_path(@playlist), method: :patch do |f| %>
  <%= render "shared/errors", object: @playlist %>
  <div class="field">
    <%= f.label :name %><%= f.text_field :name %>
  </div>
  <div class="field">
    <%= f.label :description %><%= f.text_area :description, rows: 3 %>
  </div>
  <div class="field">
    <%= f.check_box :public_access %> <%= f.label :public_access, "Public" %>
  </div>
  <div class="actions"><%= f.submit "Save", class: "btn btn--primary" %></div>
<% end %>
ERB

# ── Route patch ─────────────────────────────────────────────────────────────
ruby34 -e "
r = File.read('config/routes.rb')
unless r.include?('namespace :playlist')
  patch = %q(
  namespace :playlist do
    root 'playlists#index'
    resources :playlists do
      resources :tracks, only: %i[create destroy]
    end
    resources :listens, only: :create
  end
)
  r.sub!('root \"home#index\"', patch + '  root \"home#index\"')
  File.write('config/routes.rb', r)
  puts 'Routes patched'
end
"

# ── User association ─────────────────────────────────────────────────────────
ruby34 -e "
u = File.read('app/models/user.rb')
unless u.include?('playlist_playlists')
  u.sub!('has_secure_password', %Q(has_secure_password
  has_many :playlist_playlists, class_name: 'Playlist::Playlist', dependent: :destroy
  has_many :playlist_listens,   class_name: 'Playlist::Listen',   dependent: :destroy))
  File.write('app/models/user.rb', u)
  puts 'User model patched'
end
"

doas rcctl restart brgen 2>/dev/null || true
log_ok "Brgen Playlist namespace added — visit /playlist"
