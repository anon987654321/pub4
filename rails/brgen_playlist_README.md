# BRGEN Playlist - Music Streaming and Collaboration Platform
## Overview

BRGEN Playlist is a comprehensive music streaming and collaboration platform that allows users to create, share, and collaborate on playlists. Built with modern web technologies, it features real-time collaboration, music service integration, and social sharing capabilities.
## Features

### Core Music Features

- **Playlist Creation**: Create and organize custom playlists with detailed metadata

- **Collaborative Playlists**: Real-time collaboration with multiple users

- **Music Service Integration**: Connect with Spotify, YouTube, and SoundCloud APIs

- **Social Sharing**: Share playlists and discover new music through the community
- **Smart Recommendations**: AI-powered music discovery based on listening habits
### Social Features
- **Real-time Collaboration**: Multiple users can edit playlists simultaneously
- **Comments & Likes**: Engage with community content
- **Following System**: Follow favorite playlist creators

- **Activity Feeds**: See what friends are listening to and creating
- **Music Discovery**: Explore trending and recommended playlists
### Advanced Features
- **Cross-platform Sync**: Sync playlists across different music services
- **Offline Mode**: Download playlists for offline listening
- **Audio Analysis**: BPM detection, key matching, and mood analysis

- **Party Mode**: Real-time collaborative listening sessions
- **Music Events**: Organize and discover music events and listening parties
## Technical Implementation
### Models
#### Playlist::Set Model
```ruby

module Playlist

  class Set < ApplicationRecord

    belongs_to :user
    has_many :tracks, -> { order(:position) }, dependent: :destroy
    has_many :collaborations, dependent: :destroy
    has_many :collaborators, through: :collaborations, source: :user
    has_many :likes, dependent: :destroy
    has_many :comments, dependent: :destroy
    validates :name, presence: true
    validates :privacy, inclusion: { in: %w[public private unlisted] }
    enum privacy: { public: 0, private: 1, unlisted: 2 }
    def total_duration

      tracks.sum(:duration)
    end

    def can_edit?(user)

      return false unless user
      return true if self.user == user
      collaborations.where(user: user, role: ['editor', 'admin']).exists?

    end
    def like_count
      likes.count
    end
  end

end
```
#### Track Model with Music Service Integration
```ruby
module Playlist
  class Track < ApplicationRecord

    belongs_to :set, class_name: 'Playlist::Set'
    validates :name, :artist, presence: true
    validates :position, presence: true, uniqueness: { scope: :set_id }
    before_validation :set_position, if: :new_record?
    after_create :fetch_metadata_async

    def formatted_duration
      return '0:00' unless duration

      minutes = duration / 60
      seconds = duration % 60

      format('%d:%02d', minutes, seconds)
    end
    def fetch_from_spotify(spotify_id)
      # Integration with Spotify Web API
      spotify_client = SpotifyWebApiSdk::Client.new
      track_data = spotify_client.track(spotify_id)

      update!(
        name: track_data.name,
        artist: track_data.artists.first.name,
        duration: track_data.duration_ms / 1000,

        audio_url: track_data.preview_url,
        external_id: spotify_id,
        service: 'spotify'
      )
    end
    def fetch_from_youtube(youtube_id)
      # Integration with YouTube API
      youtube_client = YoutubeApiV3::Client.new(api_key: ENV['YOUTUBE_API_KEY'])
      video_data = youtube_client.video(youtube_id)

      update!(
        name: video_data.snippet.title,
        artist: video_data.snippet.channel_title,
        duration: parse_duration(video_data.content_details.duration),

        audio_url: "https://youtube.com/watch?v=#{youtube_id}",
        external_id: youtube_id,
        service: 'youtube'
      )
    end
    private
    def set_position
      self.position ||= (set.tracks.maximum(:position) || 0) + 1
    end

    def fetch_metadata_async

      TrackMetadataJob.perform_later(self) if audio_url.present?
    end
  end

end
```
### Controllers
#### Enhanced Playlist Controller
```ruby
module Playlist

  class SetsController < ApplicationController

    before_action :authenticate_user!, except: [:index, :show]
    before_action :set_playlist_set, only: [:show, :edit, :update, :destroy, :like, :collaborate]
    def index
      @sets = Playlist::Set.public_playlists.includes(:user, :tracks, :likes)
      apply_filters
      apply_sorting

      @pagy, @sets = pagy(@sets) unless @stimulus_reflex
    end
    def show
      @tracks = @set.tracks.ordered
      @comments = @set.comments.includes(:user).recent.limit(10)
      @similar_playlists = PlaylistRecommendationService.new(@set).similar_playlists

      respond_to do |format|
        format.html
        format.json { render json: serialize_playlist(@set) }
        format.m3u { render plain: generate_m3u(@set) }

      end
    end
    def create
      @set = current_user.playlist_sets.build(set_params)
      if @set.save
        redirect_to playlist_set_path(@set), notice: 'Playlist created successfully!'

      else
        render :new, status: :unprocessable_entity

      end
    end
    def collaborate
      collaboration_service = PlaylistCollaborationService.new(@set, current_user)
      result = collaboration_service.add_collaborator(params[:user_id], params[:role])
      respond_to do |format|

        format.json { render json: result }
        format.turbo_stream do
          if result[:success]

            render turbo_stream: turbo_stream.append(
              "collaborators",
              partial: "playlist/sets/collaborator",
              locals: { collaboration: result[:collaboration] }
            )
          end
        end
      end
    end
    def import_from_service
      service = params[:service] # 'spotify', 'youtube', 'soundcloud'
      external_id = params[:external_id]
      import_service = MusicServiceImporter.new(service, external_id, current_user)

      result = import_service.import_playlist
      if result[:success]
        redirect_to playlist_set_path(result[:playlist]), notice: 'Playlist imported successfully!'

      else
        redirect_back fallback_location: playlist_sets_path, alert: result[:error]

      end
    end
    private
    def apply_filters
      @sets = @sets.where("name ILIKE ?", "%#{params[:search]}%") if params[:search].present?
      @sets = @sets.joins(:user).where(users: { id: params[:user_id] }) if params[:user_id].present?

      @sets = @sets.where(collaborative: true) if params[:collaborative] == 'true'

    end
    def apply_sorting
      case params[:sort]
      when 'popular'
        @sets = @sets.joins(:likes).group('playlist_sets.id').order('COUNT(playlist_likes.id) DESC')

      when 'recent'
        @sets = @sets.order(created_at: :desc)
      when 'duration'
        @sets = @sets.joins(:tracks).group('playlist_sets.id').order('SUM(playlist_tracks.duration) DESC')
      else
        @sets = @sets.order(:name)
      end
    end
    def generate_m3u(playlist)
      m3u_content = "#EXTM3U\n"
      m3u_content += "#PLAYLIST:#{playlist.name}\n"
      playlist.tracks.ordered.each do |track|

        m3u_content += "#EXTINF:#{track.duration},#{track.artist} - #{track.name}\n"
        m3u_content += "#{track.audio_url}\n"
      end

      m3u_content
    end
    def serialize_playlist(set)
      {

        id: set.id,
        name: set.name,

        description: set.description,
        duration: set.formatted_duration,
        track_count: set.tracks.count,
        like_count: set.like_count,
        collaborative: set.collaborative?,
        privacy: set.privacy,
        creator: {
          id: set.user.id,
          username: set.user.email.split('@').first
        },
        tracks: set.tracks.map do |track|
          {
            id: track.id,
            name: track.name,
            artist: track.artist,
            duration: track.formatted_duration,
            position: track.position,
            service: track.service,
            external_id: track.external_id
          }
        end
      }
    end
  end
end
```
### Services
#### Music Service Integration
```ruby
class MusicServiceImporter

  def initialize(service, external_id, user)

    @service = service
    @external_id = external_id
    @user = user
  end
  def import_playlist
    case @service
    when 'spotify'
      import_from_spotify

    when 'youtube'
      import_from_youtube
    when 'soundcloud'
      import_from_soundcloud
    else
      { success: false, error: 'Unsupported service' }
    end
  end
  private
  def import_from_spotify
    spotify_client = SpotifyWebApiSdk::Client.new
    begin

      playlist_data = spotify_client.playlist(@external_id)

      playlist = Playlist::Set.create!(
        name: playlist_data.name,

        description: playlist_data.description,
        user: @user,

        privacy: :public
      )
      playlist_data.tracks.items.each_with_index do |track_item, index|
        track_data = track_item.track
        Playlist::Track.create!(
          set: playlist,

          name: track_data.name,
          artist: track_data.artists.first.name,

          duration: track_data.duration_ms / 1000,
          position: index + 1,
          external_id: track_data.id,
          service: 'spotify',
          audio_url: track_data.preview_url
        )
      end
      { success: true, playlist: playlist }
    rescue => e
      { success: false, error: e.message }
    end

  end
  def import_from_youtube
    youtube_client = YoutubeApiV3::Client.new(api_key: ENV['YOUTUBE_API_KEY'])
    begin
      playlist_data = youtube_client.playlist(@external_id)

      playlist_items = youtube_client.playlist_items(@external_id)
      playlist = Playlist::Set.create!(

        name: playlist_data.snippet.title,
        description: playlist_data.snippet.description,
        user: @user,

        privacy: :public
      )
      playlist_items.each_with_index do |item, index|
        video_data = youtube_client.video(item.snippet.resource_id.video_id)
        Playlist::Track.create!(
          set: playlist,

          name: video_data.snippet.title,
          artist: video_data.snippet.channel_title,

          duration: parse_youtube_duration(video_data.content_details.duration),
          position: index + 1,
          external_id: item.snippet.resource_id.video_id,
          service: 'youtube',
          audio_url: "https://youtube.com/watch?v=#{item.snippet.resource_id.video_id}"
        )
      end
      { success: true, playlist: playlist }
    rescue => e
      { success: false, error: e.message }
    end

  end
  def parse_youtube_duration(duration)
    # Parse ISO 8601 duration format (PT4M13S) to seconds
    match = duration.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/)
    return 0 unless match

    hours = match[1].to_i
    minutes = match[2].to_i
    seconds = match[3].to_i
    (hours * 3600) + (minutes * 60) + seconds

  end
end
```

#### Playlist Recommendation Service
```ruby
class PlaylistRecommendationService
  def initialize(playlist)

    @playlist = playlist
  end
  def similar_playlists(limit: 6)
    # Find playlists with similar tracks or genres
    track_names = @playlist.tracks.pluck(:name, :artist).map { |name, artist| "#{name} #{artist}" }
    similar_sets = Playlist::Set.public_playlists

                               .where.not(id: @playlist.id)
                               .joins(:tracks)
                               .where(

                                 'CONCAT(playlist_tracks.name, \' \', playlist_tracks.artist) IN (?)',
                                 track_names
                               )
                               .group('playlist_sets.id')
                               .having('COUNT(playlist_tracks.id) >= ?', [track_names.length * 0.2, 1].max)
                               .order('COUNT(playlist_tracks.id) DESC')
                               .limit(limit)
    # If not enough similar playlists, add popular ones
    if similar_sets.length < limit
      popular_sets = Playlist::Set.public_playlists
                                 .where.not(id: [@playlist.id] + similar_sets.pluck(:id))

                                 .joins(:likes)
                                 .group('playlist_sets.id')
                                 .order('COUNT(playlist_likes.id) DESC')
                                 .limit(limit - similar_sets.length)
      similar_sets = similar_sets.to_a + popular_sets.to_a
    end
    similar_sets
  end

  def recommended_tracks(limit: 10)
    # Get tracks from similar playlists that aren't in the current playlist

    current_track_ids = @playlist.tracks.pluck(:external_id).compact
    similar_playlists.flat_map(&:tracks)

                    .reject { |track| current_track_ids.include?(track.external_id) }
                    .uniq { |track| [track.name.downcase, track.artist.downcase] }
                    .sample(limit)

  end
end
```
### Frontend Components
#### Playlist Player (Stimulus)
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  static targets = ["playlist", "currentTrack", "progress", "playButton", "previousButton", "nextButton"]
  static values = {
    tracks: Array,

    currentIndex: { type: Number, default: 0 },
    autoplay: { type: Boolean, default: false }
  }
  connect() {
    this.audio = new Audio()
    this.setupAudioEvents()
    this.loadCurrentTrack()

    if (this.autoplayValue) {
      this.play()
    }
  }

  disconnect() {
    if (this.audio) {
      this.audio.pause()
      this.audio = null

    }
  }
  setupAudioEvents() {
    this.audio.addEventListener('loadedmetadata', () => {
      this.updateProgressBar()
    })

    this.audio.addEventListener('timeupdate', () => {
      this.updateProgressBar()
    })
    this.audio.addEventListener('ended', () => {

      this.next()
    })
    this.audio.addEventListener('error', (e) => {

      console.error('Audio error:', e)
      this.showError('Failed to load track')
      this.next()

    })
  }
  loadCurrentTrack() {
    const track = this.tracksValue[this.currentIndexValue]
    if (!track) return
    this.audio.src = track.audio_url

    this.updateTrackDisplay(track)
    this.updateButtons()
  }

  play() {
    if (this.audio.paused) {
      this.audio.play()
        .then(() => {

          this.playButtonTarget.textContent = '⏸️'
          this.broadcastNowPlaying()
        })
        .catch(error => {
          console.error('Play error:', error)
          this.showError('Failed to play track')
        })
    } else {
      this.pause()
    }
  }
  pause() {
    this.audio.pause()
    this.playButtonTarget.textContent = '▶️'
  }

  previous() {
    if (this.currentIndexValue > 0) {
      this.currentIndexValue--
      this.loadCurrentTrack()

      if (!this.audio.paused) {
        this.play()
      }
    }
  }
  next() {
    if (this.currentIndexValue < this.tracksValue.length - 1) {
      this.currentIndexValue++
      this.loadCurrentTrack()

      if (!this.audio.paused) {
        this.play()
      }
    } else {
      // End of playlist
      this.pause()
      this.currentIndexValue = 0
      this.loadCurrentTrack()
    }
  }
  seek(event) {
    if (!this.audio.duration) return
    const progressBar = event.currentTarget
    const rect = progressBar.getBoundingClientRect()

    const pos = (event.clientX - rect.left) / rect.width
    this.audio.currentTime = pos * this.audio.duration

  }
  updateProgressBar() {
    if (!this.audio.duration) return

    const progress = (this.audio.currentTime / this.audio.duration) * 100
    const progressBar = this.progressTarget.querySelector('.progress-fill')

    if (progressBar) {
      progressBar.style.width = `${progress}%`

    }
    // Update time display

    const currentTime = this.formatTime(this.audio.currentTime)
    const totalTime = this.formatTime(this.audio.duration)
    const timeDisplay = this.progressTarget.querySelector('.time-display')

    if (timeDisplay) {
      timeDisplay.textContent = `${currentTime} / ${totalTime}`
    }

  }
  updateTrackDisplay(track) {
    if (this.hasCurrentTrackTarget) {
      this.currentTrackTarget.innerHTML = `
        <div class="current-track">

          <h3>${track.name}</h3>
          <p>by ${track.artist}</p>
          <span class="duration">${track.duration}</span>
        </div>
      `
    }
  }
  updateButtons() {
    this.previousButtonTarget.disabled = this.currentIndexValue === 0
    this.nextButtonTarget.disabled = this.currentIndexValue >= this.tracksValue.length - 1
  }

  broadcastNowPlaying() {
    // Broadcast current track to other connected users
    const track = this.tracksValue[this.currentIndexValue]
    fetch('/playlist/now_playing', {

      method: 'POST',
      headers: {
        'Content-Type': 'application/json',

        'X-CSRF-Token': this.getCSRFToken()
      },
      body: JSON.stringify({
        track_id: track.id,
        playlist_id: this.element.dataset.playlistId,
        position: this.audio.currentTime
      })
    })
  }
  formatTime(seconds) {
    const mins = Math.floor(seconds / 60)
    const secs = Math.floor(seconds % 60)
    return `${mins}:${secs.toString().padStart(2, '0')}`

  }
  showError(message) {
    // Show error notification
    const notification = document.createElement('div')
    notification.className = 'notification error'

    notification.textContent = message
    document.body.appendChild(notification)
    setTimeout(() => notification.remove(), 3000)
  }
  getCSRFToken() {
    return document.querySelector('meta[name="csrf-token"]').content

  }
}

```
## Installation & Setup
### Requirements
- Rails 8.0+
- PostgreSQL 12+

- Redis 6+

- Node.js 18+
- FFmpeg (for audio processing)
### Setup Instructions
```bash
# Run the playlist setup script
./rails/brgen/playlist.sh

# Configure music service APIs
export SPOTIFY_CLIENT_ID=your_spotify_client_id
export SPOTIFY_CLIENT_SECRET=your_spotify_secret
export YOUTUBE_API_KEY=your_youtube_api_key

export SOUNDCLOUD_CLIENT_ID=your_soundcloud_client_id
# Install audio processing dependencies
sudo apt-get install ffmpeg  # Ubuntu/Debian
# or
brew install ffmpeg  # macOS

# Run migrations and setup
bin/rails db:migrate
bin/rails db:seed:playlists
# Start the application

bin/rails server
```
### Configuration

#### Music Service Integration
```ruby
# config/initializers/music_services.rb

Playlist.configure do |config|

  config.spotify_client_id = ENV['SPOTIFY_CLIENT_ID']
  config.spotify_client_secret = ENV['SPOTIFY_CLIENT_SECRET']
  config.youtube_api_key = ENV['YOUTUBE_API_KEY']
  config.soundcloud_client_id = ENV['SOUNDCLOUD_CLIENT_ID']
  config.max_playlist_size = 500
  config.max_track_duration = 3600 # 1 hour
  config.allowed_audio_formats = %w[mp3 mp4 wav ogg]
end

```
## API Documentation
### Playlist Management
```
GET /api/v1/playlists - List public playlists

POST /api/v1/playlists - Create new playlist

GET /api/v1/playlists/:id - Get playlist details
PUT /api/v1/playlists/:id - Update playlist
DELETE /api/v1/playlists/:id - Delete playlist
```
### Track Management
```
POST /api/v1/playlists/:id/tracks - Add track to playlist
PUT /api/v1/playlists/:id/tracks/:track_id - Update track

DELETE /api/v1/playlists/:id/tracks/:track_id - Remove track
POST /api/v1/tracks/search - Search tracks across services
```
### Music Service Import
```
POST /api/v1/import/spotify/:playlist_id - Import from Spotify
POST /api/v1/import/youtube/:playlist_id - Import from YouTube

POST /api/v1/import/soundcloud/:playlist_id - Import from SoundCloud
```
### Real-time Features
```
WebSocket /cable/playlist/:id - Real-time collaboration
POST /api/v1/playlists/:id/collaborators - Add collaborator

DELETE /api/v1/playlists/:id/collaborators/:user_id - Remove collaborator
```
## Testing
### Test Coverage
```bash
# Run playlist tests

bin/rails test test/models/playlist/

bin/rails test test/controllers/playlist/
bin/rails test test/services/music_service_importer_test.rb
# Test music service integrations
bin/rails test test/integration/spotify_integration_test.rb
bin/rails test test/integration/youtube_integration_test.rb
```

### Performance Testing
```bash
# Test playlist loading performance
bin/rails runner "

  playlist = Playlist::Set.joins(:tracks).first
  Benchmark.measure { playlist.tracks.ordered.load }
"
# Load test streaming endpoints
ab -n 100 -c 10 http://localhost:3000/api/v1/playlists
```
## Deployment Considerations

### Scaling
- **CDN integration** for audio file delivery
- **Redis caching** for frequently accessed playlists

- **Background jobs** for music service API calls

- **Database indexing** on search fields
### Performance
- **Audio file optimization** with different bitrates
- **Lazy loading** for large playlists
- **API rate limiting** for music services

- **Caching strategies** for track metadata
## Future Enhancements
### Planned Features
- **AI-powered recommendations** based on listening history
- **Live listening parties** with synchronized playback

- **Podcast integration** for mixed content playlists

- **Advanced audio analysis** for smart mixing and transitions
- **Mobile apps** for iOS and Android
### Integration Opportunities
- **Music festivals** and event integration
- **Artist collaboration** tools
- **Social media** sharing enhancements

- **Smart home** device integration
- **Car audio** system compatibility
