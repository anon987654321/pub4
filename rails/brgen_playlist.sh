#!/usr/bin/env zsh
set -euo pipefail

readonly VERSION="1.0.0"
readonly APP_NAME="brgen_playlist"

SCRIPT_DIR="${0:a:h}"
source "${SCRIPT_DIR}/__shared/@common.sh"

APP_DIR="/home/brgen/app"
cd "$APP_DIR"

log "Installing Brgen Playlist - Music streaming & collaboration"

# Models
bin/rails generate model Playlist::Set user:references name:string description:text privacy:integer:default[0] likes_count:integer:default[0]
bin/rails generate model Playlist::Track set:references name:string artist:string album:string duration:integer position:integer audio_url:string external_id:string service:string
bin/rails generate model Playlist::Collaboration set:references user:references role:string
bin/rails generate model Playlist::Like set:references user:references
bin/rails generate model Playlist::Comment set:references user:references content:text

# Controllers
bin/rails generate controller Playlist::Sets index show new create edit update destroy
bin/rails generate controller Playlist::Tracks create destroy update
bin/rails generate controller Playlist::Collaborations create destroy

bin/rails db:migrate

# Routes
add_route "namespace :playlist do"
add_route "  resources :sets do"
add_route "    resources :tracks, only: [:create, :update, :destroy]"
add_route "    resources :collaborations, only: [:create, :destroy]"
add_route "    member do"
add_route "      post :like"
add_route "      delete :unlike"
add_route "    end"
add_route "  end"
add_route "end"

# Models
print > app/models/playlist/set.rb << 'RUBY'
module Playlist
  class Set < ApplicationRecord
    belongs_to :user
    has_many :tracks, -> { order(:position) }, dependent: :destroy, class_name: 'Playlist::Track'
    has_many :collaborations, dependent: :destroy, class_name: 'Playlist::Collaboration'
    has_many :collaborators, through: :collaborations, source: :user
    has_many :likes, dependent: :destroy, class_name: 'Playlist::Like'
    has_many :comments, dependent: :destroy, class_name: 'Playlist::Comment'
    
    validates :name, presence: true
    validates :privacy, inclusion: { in: [0, 1, 2] }
    
    enum privacy: { public_access: 0, private_access: 1, unlisted: 2 }
    
    def total_duration
      tracks.sum(:duration)
    end
    
    def can_edit?(user)
      return false unless user
      return true if self.user == user
      collaborations.where(user: user, role: ['editor', 'admin']).exists?
    end
  end
end
RUBY

print > app/models/playlist/track.rb << 'RUBY'
module Playlist
  class Track < ApplicationRecord
    belongs_to :set, class_name: 'Playlist::Set'
    
    validates :name, :artist, :position, presence: true
    validates :position, uniqueness: { scope: :set_id }
    
    before_validation :set_position, if: :new_record?
    
    def formatted_duration
      return '0:00' unless duration
      minutes = duration / 60
      seconds = duration % 60
      format('%d:%02d', minutes, seconds)
    end
    
    private
    
    def set_position
      self.position = (set.tracks.maximum(:position) || 0) + 1
    end
  end
end
RUBY

# Views
print > app/views/playlist/sets/index.html.erb << 'ERB'
<%= tag.div class: "playlist-index" do %>
  <%= tag.h1 "Playlists" %>
  <%= tag.div class: "playlist-grid" do %>
    <% @sets.each do |set| %>
      <%= link_to playlist_set_path(set), class: "playlist-card" do %>
        <%= tag.div class: "playlist-info" do %>
          <%= tag.h3 set.name %>
          <%= tag.p "#{set.tracks.count} tracks • #{set.formatted_duration}" %>
          <%= tag.p set.user.email %>
        <% end %>
      <% end %>
    <% end %>
  <% end %>
<% end %>
ERB

# Stimulus controller
print > app/javascript/controllers/playlist_controller.js << 'JS'
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["track", "player"]
  
  connect() {
    this.currentTrack = 0
  }
  
  play(event) {
    const trackId = event.currentTarget.dataset.trackId
    this.playerTarget.src = event.currentTarget.dataset.audioUrl
    this.playerTarget.play()
  }
  
  next() {
    this.currentTrack = (this.currentTrack + 1) % this.trackTargets.length
    this.playTrack(this.currentTrack)
  }
  
  previous() {
    this.currentTrack = (this.currentTrack - 1 + this.trackTargets.length) % this.trackTargets.length
    this.playTrack(this.currentTrack)
  }
  
  playTrack(index) {
    const track = this.trackTargets[index]
    this.playerTarget.src = track.dataset.audioUrl
    this.playerTarget.play()
  }
}
JS

# SCSS
print >> app/assets/stylesheets/application.scss << 'SCSS'
.playlist-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 24px;
  padding: 24px;
}

.playlist-card {
  background: var(--color-surface);
  border-radius: 8px;
  padding: 16px;
  transition: transform 0.2s;
  text-decoration: none;
  color: inherit;
  
  &:hover {
    transform: translateY(-4px);
    box-shadow: 0 4px 12px rgba(0,0,0,0.1);
  }
}
SCSS

log "Brgen Playlist setup complete"