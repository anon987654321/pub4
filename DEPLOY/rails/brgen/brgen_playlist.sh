#!/usr/bin/env zsh
# brgen_playlist.sh — Brgen Playlist music/media curator (Rails 8)
# Usage: zsh brgen_playlist.sh
set -euo pipefail

APP_NAME=brgen_playlist
APP_DIR=/home/${APP_NAME}/app
APP_PORT=10010
SCRIPT_DIR=${0:a:h}

. "${SCRIPT_DIR:h}/@shared_functions.sh"

need_cmd ruby34 bundle rails doas

already_done "${APP_DIR}/app/models/playlist.rb" && exit 0

log "Brgen Playlist — Music Curation Platform"

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
bin/rails generate model Playlist \
  user:references name:string description:text \
  public_access:boolean:default[true] \
  plays_count:integer:default[0] \
  likes_count:integer:default[0] \
  tracks_count:integer:default[0] \
  cover_color:string \
  --no-test-framework

bin/rails generate model Track \
  title:string artist:string album:string \
  duration_seconds:integer genre:string \
  year:integer bpm:integer \
  source_type:string source_id:string source_url:string \
  --no-test-framework

bin/rails generate model PlaylistTrack \
  playlist:references track:references \
  position:integer added_by:references{User} \
  --no-test-framework

bin/rails generate model Follow \
  follower:references{User} followable:references{polymorphic}:index \
  --no-test-framework

bin/rails generate model Like \
  user:references likeable:references{polymorphic}:index \
  --no-test-framework

bin/rails generate model Listening \
  user:references track:references \
  playlist:references started_at:datetime completed:boolean:default[false] \
  --no-test-framework

bin/rails db:migrate

# ── Model logic ─────────────────────────────────────────────────────────────
cat > app/models/playlist.rb << 'RUBY'
class Playlist < ApplicationRecord
  belongs_to :user
  has_many :playlist_tracks, dependent: :destroy
  has_many :tracks, through: :playlist_tracks
  has_many :likes, as: :likeable, dependent: :destroy
  has_many :follows, as: :followable, dependent: :destroy
  has_one_attached :cover

  validates :name, presence: true, length: { maximum: 100 }

  COVER_COLORS = %w[#e91e63 #9c27b0 #3f51b5 #2196f3 #00bcd4 #4caf50 #ff9800 #f44336].freeze

  before_create :assign_cover_color

  scope :public_playlists, -> { where(public_access: true) }
  scope :popular,          -> { order(plays_count: :desc) }
  scope :recent,           -> { order(created_at: :desc) }

  def add_track!(track, user:, position: nil)
    pos = position || (playlist_tracks.maximum(:position) || 0) + 1
    playlist_tracks.find_or_create_by!(track: track) do |pt|
      pt.position  = pos
      pt.added_by  = user
    end
    increment!(:tracks_count)
  end

  def like_by!(user)
    likes.find_or_create_by!(user: user)
    increment!(:likes_count)
  end

  private

  def assign_cover_color
    self.cover_color ||= COVER_COLORS.sample
  end
end
RUBY

cat > app/models/track.rb << 'RUBY'
class Track < ApplicationRecord
  has_many :playlist_tracks, dependent: :destroy
  has_many :playlists, through: :playlist_tracks
  has_many :listenings, dependent: :destroy

  SOURCE_TYPES = %w[youtube spotify soundcloud direct].freeze

  validates :title, :artist, presence: true
  validates :duration_seconds, numericality: { greater_than: 0 }, allow_nil: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }, allow_nil: true

  scope :by_genre, ->(g) { where(genre: g) }
  scope :recent,   -> { order(created_at: :desc) }

  def duration_formatted
    return "—" unless duration_seconds
    min, sec = duration_seconds.divmod(60)
    "#{min}:%02d" % sec
  end
end
RUBY

cat > app/models/listening.rb << 'RUBY'
class Listening < ApplicationRecord
  belongs_to :user
  belongs_to :track
  belongs_to :playlist

  after_create_commit :increment_play_count

  private

  def increment_play_count
    playlist.increment!(:plays_count)
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

cat > app/controllers/playlists_controller.rb << 'RUBY'
class PlaylistsController < ApplicationController
  before_action :require_authentication, except: %i[index show]
  before_action :set_playlist, only: %i[show edit update destroy like]
  before_action :authorize!, only: %i[edit update destroy]

  def index
    scope = Playlist.public_playlists.includes(:user)
    scope = scope.where("name LIKE ?", "%#{params[:q]}%") if params[:q].present?
    @pagy, @playlists = pagy(scope.popular)
  end

  def show
    @tracks   = @playlist.playlist_tracks.order(:position).includes(:track)
    @add_form = Track.new
  end

  def new
    @playlist = Current.user.playlists.build
  end

  def create
    @playlist = Current.user.playlists.build(playlist_params)
    @playlist.save ? redirect_to(@playlist, notice: "Playlist created") : render(:new, status: :unprocessable_entity)
  end

  def edit; end

  def update
    @playlist.update(playlist_params) ? redirect_to(@playlist, notice: "Updated") : render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @playlist.destroy
    redirect_to playlists_path, notice: "Playlist deleted"
  end

  def like
    @playlist.like_by!(Current.user)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @playlist }
    end
  end

  private

  def set_playlist  = @playlist = Playlist.find(params[:id])
  def authorize!    = redirect_to(playlists_path, alert: "Unauthorized") unless @playlist.user == Current.user

  def playlist_params
    params.require(:playlist).permit(:name, :description, :public_access, :cover)
  end
end
RUBY

cat > app/controllers/tracks_controller.rb << 'RUBY'
class TracksController < ApplicationController
  before_action :require_authentication, except: %i[index show]
  before_action :set_playlist

  def create
    track    = Track.find_or_create_by!(track_create_params)
    @playlist.add_track!(track, user: Current.user)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @playlist, notice: "Track added" }
    end
  end

  def destroy
    pt = @playlist.playlist_tracks.find(params[:id])
    if pt.added_by == Current.user || @playlist.user == Current.user
      pt.destroy!
      @playlist.decrement!(:tracks_count)
    end
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @playlist }
    end
  end

  private

  def set_playlist = @playlist = Playlist.find(params[:playlist_id])

  def track_create_params
    params.require(:track).permit(:title, :artist, :album, :duration_seconds, :source_type, :source_url, :genre, :year)
  end
end
RUBY

cat > app/controllers/listenings_controller.rb << 'RUBY'
class ListeningsController < ApplicationController
  before_action :require_authentication

  def create
    playlist = Playlist.find(params[:playlist_id])
    track    = Track.find(params[:track_id])
    Listening.create!(user: Current.user, track: track, playlist: playlist, started_at: Time.current)
    render json: { status: "ok" }
  end
end
RUBY

# ── Routes ─────────────────────────────────────────────────────────────────
cat > config/routes.rb << 'RUBY'
Rails.application.routes.draw do
  resource  :session
  resources :passwords, param: :token

  root "playlists#index"

  resources :playlists do
    member { post :like }
    resources :tracks, only: %i[create destroy]
    resources :listenings, only: %i[create]
  end

  resources :users, only: %i[show]

  get "up", to: "rails/health#show", as: :rails_health_check
end
RUBY

# ── Assets + Infrastructure ─────────────────────────────────────────────────
mkdir -p app/assets/stylesheets
cat > app/assets/stylesheets/application.css << 'CSS'
:root {
  --bg: #050505; --surface: #121212; --surface-alt: #1e1e1e;
  --text: #ffffff; --text-dim: #b3b3b3;
  --primary: #1db954; --radius: 8px; --space: 8px;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: "Circular","Helvetica Neue",Helvetica,Arial,sans-serif; background: var(--bg); color: var(--text); }
main { max-width: 1400px; margin: 0 auto; padding: calc(var(--space)*2); }
a { color: inherit; text-decoration: none; }
a:hover { color: var(--primary); }
.card { background: var(--surface); border-radius: var(--radius); padding: 1rem; transition: background .2s; }
.card:hover { background: var(--surface-alt); }
.playlist-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 1.5rem; }
.playlist-cover { aspect-ratio: 1; border-radius: 4px; display: flex; align-items: center; justify-content: center; font-size: 3rem; }
.track-row { display: flex; align-items: center; gap: 1rem; padding: .75rem; border-radius: 4px; }
.track-row:hover { background: var(--surface-alt); }
.btn { display: inline-block; padding: .4rem 1rem; border-radius: 2rem; border: none; cursor: pointer; }
.btn-primary { background: var(--primary); color: #000; font-weight: 700; }
.flash-notice { background: #1a3a1a; color: #81c784; padding: .75rem 1rem; border-radius: var(--radius); margin-bottom: 1rem; }
.flash-alert  { background: #3a1a1a; color: #e57373; padding: .75rem 1rem; border-radius: var(--radius); margin-bottom: 1rem; }
CSS

write_layout "Brgen Playlist"
write_falcon_config "$APP_PORT"
configure_production
install_rcd brgen_playlist "$APP_DIR" "$APP_PORT" brgen_playlist

log_ok "Brgen Playlist setup complete — start: doas rcctl start brgen_playlist"
