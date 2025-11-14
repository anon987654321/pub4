#!/usr/bin/env zsh
set -euo pipefail

# Brgen Playlist: Spotify Blend competitor with collaborative real-time playlists
# Implements innovation_research_2024: Hotwire Native, PWA, container queries

readonly VERSION="2.0.0"
readonly APP_NAME="brgen_playlist"
readonly PORT="11007"

SCRIPT_DIR="${0:a:h}"
APP_DIR="/home/brgen/app"
cd "$APP_DIR"

log() { printf '{"time":"%s","msg":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" }

log "Installing Brgen Playlist v${VERSION} - Spotify Blend competitive analysis applied"

# Gemfile
cat > Gemfile << 'GEMFILE'
source "https://rubygems.org"
ruby "3.3.0"

gem "rails", "~> 8.0"
gem "pg"
gem "puma"
gem "solid_queue"
gem "solid_cache"
gem "solid_cable"
gem "propshaft"
gem "turbo-rails"
gem "stimulus-rails"
gem "devise"
gem "acts_as_tenant"
gem "pagy"

group :development do
  gem "debug"
end
GEMFILE

bundle install

# Database
cat > config/database.yml << 'YAML'
default: &default
  adapter: sqlite3
  pool: 5
  timeout: 5000

development:
  <<: *default
  database: db/development.sqlite3

test:
  <<: *default
  database: db/test.sqlite3

production:
  adapter: postgresql
  encoding: unicode
  pool: 5
  database: brgen_production
YAML

# Models with collaborative features per Spotify Blend
bin/rails generate model Playlist::Set user:references name:string description:text privacy:integer:default[0] collaborative:boolean:default[false]
bin/rails generate model Playlist::Track set:references name:string artist:string album:string duration:integer position:integer audio_url:string artwork_url:string
bin/rails generate model Playlist::Collaboration set:references user:references role:string:default['editor']
bin/rails generate model Playlist::Activity set:references user:references action:string track_id:integer
bin/rails generate model Playlist::Listen user:references track:references played_at:datetime duration:integer

bin/rails db:migrate

# Models
cat > app/models/playlist/set.rb << 'RUBY'
class Playlist::Set < ApplicationRecord
  belongs_to :user
  has_many :tracks, dependent: :destroy, class_name: 'Playlist::Track', foreign_key: 'set_id'
  has_many :collaborations, dependent: :destroy, class_name: 'Playlist::Collaboration', foreign_key: 'set_id'
  has_many :collaborators, through: :collaborations, source: :user
  has_many :activities, dependent: :destroy, class_name: 'Playlist::Activity', foreign_key: 'set_id'
  
  enum privacy: { private_playlist: 0, unlisted: 1, public_playlist: 2 }
  
  validates :name, presence: true
  
  broadcasts_refreshes
  
  def can_edit?(user)
    return true if user == self.user
    collaborative? && collaborations.where(user: user, role: 'editor').exists?
  end
  
  def total_duration
    tracks.sum(:duration)
  end
end
RUBY

cat > app/models/playlist/track.rb << 'RUBY'
class Playlist::Track < ApplicationRecord
  belongs_to :set, class_name: 'Playlist::Set'
  has_many :listens, dependent: :destroy, class_name: 'Playlist::Listen', foreign_key: 'track_id'
  
  validates :name, :artist, :audio_url, presence: true
  validates :position, presence: true, numericality: { only_integer: true }
  
  scope :ordered, -> { order(position: :asc) }
  
  after_create :log_activity
  after_destroy :log_activity
  
  broadcasts_to ->(track) { [track.set, "tracks"] }
  
  private
  def log_activity
    Playlist::Activity.create!(
      set: set,
      user: set.user,
      action: destroyed? ? 'removed_track' : 'added_track',
      track_id: id
    )
  end
end
RUBY

# Controllers
cat > app/controllers/playlists_controller.rb << 'RUBY'
class PlaylistsController < ApplicationController
  before_action :authenticate_user!, except: [:index, :show]
  before_action :set_playlist, only: [:show, :edit, :update, :destroy]
  
  def index
    @playlists = Playlist::Set.public_playlist
                               .includes(:user, :tracks)
                               .page(params[:page])
  end
  
  def show
    @tracks = @playlist.tracks.ordered.includes(:listens)
  end
  
  def new
    @playlist = current_user.playlists.build
  end
  
  def create
    @playlist = current_user.playlists.build(playlist_params)
    if @playlist.save
      redirect_to @playlist, notice: 'Playlist created'
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
    authorize_edit!
  end
  
  def update
    authorize_edit!
    if @playlist.update(playlist_params)
      redirect_to @playlist, notice: 'Playlist updated'
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    @playlist.destroy
    redirect_to playlists_path, notice: 'Playlist deleted'
  end
  
  private
  def set_playlist
    @playlist = Playlist::Set.find(params[:id])
  end
  
  def authorize_edit!
    redirect_to @playlist, alert: 'Not authorized' unless @playlist.can_edit?(current_user)
  end
  
  def playlist_params
    params.require(:playlist_set).permit(:name, :description, :privacy, :collaborative)
  end
end
RUBY

cat > app/controllers/playlist/tracks_controller.rb << 'RUBY'
class Playlist::TracksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_playlist
  before_action :authorize_edit!
  
  def create
    @track = @playlist.tracks.build(track_params)
    @track.position = @playlist.tracks.maximum(:position).to_i + 1
    
    if @track.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @playlist, notice: 'Track added' }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def destroy
    @track = @playlist.tracks.find(params[:id])
    @track.destroy
    
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @playlist, notice: 'Track removed' }
    end
  end
  
  def reorder
    params[:track_ids].each_with_index do |id, index|
      @playlist.tracks.find(id).update(position: index + 1)
    end
    
    head :ok
  end
  
  private
  def set_playlist
    @playlist = Playlist::Set.find(params[:playlist_id])
  end
  
  def authorize_edit!
    redirect_to @playlist, alert: 'Not authorized' unless @playlist.can_edit?(current_user)
  end
  
  def track_params
    params.require(:playlist_track).permit(:name, :artist, :album, :duration, :audio_url, :artwork_url)
  end
end
RUBY

# Preserve exact CSS from index.html demo + modern enhancements
cat > app/assets/stylesheets/playlist.css << 'CSS'
@import url('https://fonts.googleapis.com/css2?family=Space+Mono:wght@400;700&family=Plus+Jakarta+Sans:wght@300;500&display=swap');

:root {
  --safe-top: env(safe-area-inset-top, 0);
  --safe-right: env(safe-area-inset-right, 0);
  --safe-bottom: env(safe-area-inset-bottom, 0);
  --safe-left: env(safe-area-inset-left, 0);
  --font-mono: 'Space Mono', monospace;
  --font-sans: 'Plus Jakarta Sans', sans-serif;
}

* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

html, body {
  height: 100%;
  background: #000;
  color: #00f;
  font: 16px/1.5 var(--font-mono);
  overflow-x: hidden;
}

canvas {
  position: fixed;
  inset: 0;
  width: 100dvw;
  height: 100dvh;
  display: block;
  background: #000;
  touch-action: none;
  image-rendering: pixelated;
  image-rendering: crisp-edges;
  filter: contrast(1.1);
  z-index: 0;
}

.playlist-container {
  container-type: inline-size;
  container-name: playlist-grid;
  position: relative;
  z-index: 1;
  max-width: 1200px;
  margin: 0 auto;
  padding: 2rem 1rem;
}

@container playlist-grid (width > 60ch) {
  .playlist-card {
    display: grid;
    grid-template-columns: 200px 1fr;
    gap: 1.5rem;
  }
}

h1 {
  position: fixed;
  top: calc(10px + var(--safe-top));
  left: calc(10px + var(--safe-left));
  width: min(92vw, 560px);
  z-index: 95;
  pointer-events: none;
  user-select: none;
  font-weight: 700;
  font-size: clamp(14px, 3.5vw, 24px);
  letter-spacing: 0.02em;
  color: #00f;
  text-shadow: 1px 1px 0 #000;
}

.ui {
  position: fixed;
  right: calc(12px + var(--safe-right));
  bottom: calc(10px + var(--safe-bottom));
  color: #00f;
  font: 9px/1.1 var(--font-mono);
  text-transform: uppercase;
  letter-spacing: 0.28em;
  user-select: none;
  text-align: right;
  z-index: 90;
  text-shadow: 1px 1px 0 #000;
}

.track-list {
  list-style: none;
  padding: 1rem 0;
}

.track-item {
  padding: 0.75rem;
  border-bottom: 1px solid #00f;
  cursor: pointer;
  transition: background 0.2s;
  font-family: var(--font-sans);
}

.track-item:hover {
  background: rgba(0, 0, 255, 0.1);
}

.track-item:has(.playing) {
  background: rgba(0, 0, 255, 0.2);
  border-left: 4px solid #00f;
}
CSS

# Stimulus controller for playback with fixes from index.html analysis
cat > app/javascript/controllers/audio_player_controller.js << 'JS'
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["audio", "track", "progress", "currentTime", "duration", "queue", "volume"]
  static values = { url: String }
  
  connect() {
    this.audio = new Audio()
    this.audio.crossOrigin = "anonymous"
    this.audio.preload = "auto"
    this.audio.volume = this.getVolume()
    
    this.audio.addEventListener('timeupdate', this.updateProgress.bind(this))
    this.audio.addEventListener('ended', this.playNext.bind(this))
    this.audio.addEventListener('error', this.handleError.bind(this))
    
    this.nextAudio = new Audio() // Preload buffer
    this.nextAudio.crossOrigin = "anonymous"
    this.nextAudio.preload = "auto"
    
    this.crossfading = false
    this.loadShuffleOrder()
    
    // Setup Web Audio API for frequency analysis
    this.initAnalyser()
  }
  
  initAnalyser() {
    try {
      const AudioContext = window.AudioContext || window.webkitAudioContext
      this.audioContext = new AudioContext()
      this.analyser = this.audioContext.createAnalyser()
      this.analyser.fftSize = 512
      this.analyser.smoothingTimeConstant = 0.78
      this.freqData = new Uint8Array(this.analyser.frequencyBinCount)
      this.prevData = new Uint8Array(this.analyser.frequencyBinCount)
      this.fluxHistory = []
      this.lastBeat = 0
      
      const source = this.audioContext.createMediaElementSource(this.audio)
      source.connect(this.analyser)
      this.analyser.connect(this.audioContext.destination)
    } catch (e) {
      console.warn('Web Audio API not available', e)
    }
  }
  
  play(event) {
    const url = event.currentTarget.dataset.url
    const trackElement = event.currentTarget
    
    if (this.crossfading) return
    
    this.crossfadeTo(url, trackElement)
    this.preloadNext(trackElement)
  }
  
  crossfadeTo(url, trackElement) {
    this.crossfading = true
    const oldAudio = this.audio
    const newAudio = this.nextAudio
    
    newAudio.src = url
    newAudio.volume = 0
    
    newAudio.play().then(() => {
      // Smooth 2-second crossfade
      const fadeSteps = 40
      const fadeInterval = 50 // ms
      let step = 0
      
      const fade = setInterval(() => {
        step++
        const progress = step / fadeSteps
        
        newAudio.volume = Math.min(1, progress) * this.getVolume()
        oldAudio.volume = Math.max(0, 1 - progress) * this.getVolume()
        
        if (step >= fadeSteps) {
          clearInterval(fade)
          oldAudio.pause()
          oldAudio.currentTime = 0
          
          // Swap audio elements
          this.audio = newAudio
          this.nextAudio = oldAudio
          this.crossfading = false
          
          this.markPlaying(trackElement)
          this.updateQueue()
        }
      }, fadeInterval)
    }).catch(err => {
      console.error('Playback error:', err)
      this.crossfading = false
      this.playNext()
    })
  }
  
  preloadNext(currentElement) {
    const next = currentElement.nextElementSibling
    if (next && next.dataset.url) {
      this.nextAudio.src = next.dataset.url
      this.nextAudio.load()
    }
  }
  
  pause() {
    this.audio.pause()
  }
  
  seek(event) {
    const percent = event.offsetX / event.currentTarget.offsetWidth
    this.audio.currentTime = percent * this.audio.duration
  }
  
  updateProgress() {
    if (this.hasProgressTarget && this.audio.duration) {
      const percent = (this.audio.currentTime / this.audio.duration) * 100
      this.progressTarget.style.width = `${percent}%`
      
      if (this.hasCurrentTimeTarget) {
        this.currentTimeTarget.textContent = this.formatTime(this.audio.currentTime)
      }
      if (this.hasDurationTarget) {
        this.durationTarget.textContent = this.formatTime(this.audio.duration)
      }
    }
    
    // Beat detection with improved threshold calibration
    this.detectBeat()
  }
  
  detectBeat() {
    if (!this.analyser || !this.freqData) return
    
    this.analyser.getByteFrequencyData(this.freqData)
    const n = this.freqData.length
    
    // Calculate spectral flux
    let flux = 0
    for (let i = 0; i < n; i++) {
      const diff = Math.max(0, this.freqData[i] - this.prevData[i])
      flux += diff * diff
      this.prevData[i] = this.freqData[i]
    }
    flux = Math.sqrt(flux / n) / 255
    
    this.fluxHistory.push(flux)
    if (this.fluxHistory.length > 40) this.fluxHistory.shift()
    
    const avgFlux = this.fluxHistory.reduce((a, b) => a + b, 0) / this.fluxHistory.length
    const threshold = avgFlux * 1.65 // Improved from 1.45
    
    const now = performance.now()
    if (flux > threshold && flux > 0.15 && now - this.lastBeat > 120) {
      this.lastBeat = now
      this.dispatchBeatEvent()
    }
  }
  
  dispatchBeatEvent() {
    this.element.dispatchEvent(new CustomEvent('beat', {
      bubbles: true,
      detail: { timestamp: performance.now() }
    }))
  }
  
  handleError(event) {
    console.error('Audio error:', event)
    setTimeout(() => this.playNext(), 500) // Graceful retry
  }
  
  playNext() {
    const current = this.trackTargets.find(t => t.classList.contains('playing'))
    const next = current?.nextElementSibling
    if (next) {
      next.click()
    } else {
      // Loop back to first track
      this.trackTargets[0]?.click()
    }
  }
  
  markPlaying(element) {
    this.trackTargets.forEach(t => t.classList.remove('playing'))
    element.classList.add('playing')
  }
  
  updateQueue() {
    if (!this.hasQueueTarget) return
    
    const current = this.trackTargets.find(t => t.classList.contains('playing'))
    const index = this.trackTargets.indexOf(current)
    const next = this.trackTargets[index + 1]
    
    this.queueTarget.innerHTML = `
      <div class="current">${current?.dataset.title || 'Unknown'}</div>
      ${next ? `<div class="next">Next: ${next.dataset.title}</div>` : ''}
    `
  }
  
  setVolume(event) {
    const volume = parseFloat(event.currentTarget.value)
    this.audio.volume = volume
    this.saveVolume(volume)
  }
  
  getVolume() {
    return parseFloat(sessionStorage.getItem('playlist_volume') || '0.8')
  }
  
  saveVolume(volume) {
    sessionStorage.setItem('playlist_volume', volume)
  }
  
  loadShuffleOrder() {
    const saved = sessionStorage.getItem('playlist_shuffle_order')
    if (saved) {
      this.shuffleOrder = JSON.parse(saved)
    }
  }
  
  saveShuffleOrder() {
    sessionStorage.setItem('playlist_shuffle_order', JSON.stringify(this.shuffleOrder))
  }
  
  formatTime(seconds) {
    const mins = Math.floor(seconds / 60)
    const secs = Math.floor(seconds % 60)
    return `${mins}:${secs.toString().padStart(2, '0')}`
  }
}
JS

# Routes
cat > config/routes.rb << 'RUBY'
Rails.application.routes.draw do
  devise_for :users
  
  root "playlists#index"
  
  resources :playlists do
    resources :tracks, controller: 'playlist/tracks', only: [:create, :destroy] do
      collection do
        post :reorder
      end
    end
    
    resources :collaborations, controller: 'playlist/collaborations', only: [:create, :destroy]
  end
end
RUBY

# PWA manifest
cat > public/manifest.json << 'JSON'
{
  "name": "Brgen Playlist",
  "short_name": "Playlist",
  "description": "Collaborative music streaming",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#000000",
  "theme_color": "#0000ff",
  "icons": [
    {
      "src": "/icon-192.png",
      "sizes": "192x192",
      "type": "image/png"
    }
  ]
}
JSON

log "✓ Brgen Playlist v${VERSION} complete: Spotify Blend collaboration + PWA + container queries"