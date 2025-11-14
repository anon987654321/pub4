# BRGEN TV - Video Streaming and Live Broadcasting Platform
## Overview

BRGEN TV is a comprehensive video streaming and live broadcasting platform built with Rails 8, featuring live streaming capabilities, content management, social viewing features, and multi-channel broadcasting. The platform combines traditional video on-demand with live streaming and interactive social features.
## Features

### Core Video Features

- **Video Upload & Management**: Support for multiple video formats with automatic transcoding

- **Live Streaming**: Real-time broadcasting with WebRTC and streaming protocols

- **Channel System**: User-created channels with subscription and notification systems

- **Content Organization**: Categories, playlists, and recommendation algorithms
- **Video Processing**: Automatic thumbnail generation, quality optimization, and format conversion
### Live Broadcasting
- **Stream Management**: Create and manage live streams with custom stream keys
- **Real-time Chat**: Interactive chat during live broadcasts
- **Viewer Analytics**: Live viewer count, engagement metrics, and audience insights

- **Broadcasting Tools**: Stream health monitoring, bitrate adaptation, and quality controls
- **Scheduled Streams**: Pre-plan live broadcasts with notifications
### Social Features
- **Channel Subscriptions**: Follow favorite content creators and channels
- **Interactive Comments**: Time-stamped comments and video discussions
- **Social Sharing**: Share videos and streams across social media platforms

- **Community Features**: User ratings, favorites, and watch later lists
- **Live Chat Moderation**: Real-time chat moderation and user management
## Technical Implementation
### Models & Database Schema
#### Video Model
```ruby

class Video < ApplicationRecord

  belongs_to :user

  belongs_to :channel, optional: true
  has_many :video_comments, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_one_attached :video_file
  has_one_attached :thumbnail
  validates :title, presence: true, length: { maximum: 100 }
  validates :description, length: { maximum: 5000 }
  validates :category, inclusion: { in: %w[entertainment education news sports gaming music] }
  enum status: { draft: 0, published: 1, private: 2, unlisted: 3 }

  scope :published, -> { where(status: 'published') }
  scope :by_category, ->(cat) { where(category: cat) }
  scope :trending, -> { order(views: :desc, created_at: :desc) }

end

```
#### LiveStream Model
```ruby
class LiveStream < ApplicationRecord
  belongs_to :user

  belongs_to :channel
  has_many :stream_chats, dependent: :destroy
  has_many :viewers, class_name: 'User', through: :stream_views
  validates :title, presence: true
  validates :stream_key, presence: true, uniqueness: true
  enum status: { scheduled: 0, live: 1, ended: 2 }
  before_create :generate_stream_key

  def live?
    status == 'live' && viewer_count > 0

  end

  private

  def generate_stream_key
    self.stream_key = SecureRandom.hex(16)
  end

end

```
#### Channel Model
```ruby
class Channel < ApplicationRecord
  belongs_to :user

  has_many :videos, dependent: :destroy
  has_many :live_streams, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_many :subscribers, through: :subscriptions, source: :user
  has_one_attached :avatar
  has_one_attached :banner
  validates :name, presence: true, uniqueness: true
  validates :description, length: { maximum: 1000 }
  def subscriber_count
    subscriptions.count

  end
  def total_views

    videos.sum(:views)
  end
end

```
### Video Processing Pipeline
#### Video Upload Processing
```ruby
class VideoProcessingJob < ApplicationJob

  queue_as :video_processing

  def perform(video_id)
    video = Video.find(video_id)
    # Generate thumbnail
    VideoThumbnailService.new(video).generate

    # Process video formats
    VideoTranscodingService.new(video).transcode_formats

    # Extract metadata
    VideoMetadataService.new(video).extract_info

    video.update(status: 'published')
  end

end
```

### Live Streaming Integration
#### WebRTC Live Streaming
```javascript
// app/javascript/streaming/live_broadcaster.js

class LiveBroadcaster {

  constructor(streamKey) {
    this.streamKey = streamKey;
    this.mediaRecorder = null;
    this.stream = null;
  }
  async startBroadcast() {
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { width: 1280, height: 720 },

        audio: true
      });
      this.mediaRecorder = new MediaRecorder(this.stream, {
        mimeType: 'video/webm;codecs=vp8,opus'
      });
      this.mediaRecorder.ondataavailable = this.handleDataAvailable.bind(this);

      this.mediaRecorder.start(1000); // Send data every second
      this.updateStreamStatus('live');
    } catch (error) {

      console.error('Error starting broadcast:', error);
    }

  }
  handleDataAvailable(event) {
    if (event.data.size > 0) {
      this.sendToServer(event.data);
    }

  }
  sendToServer(data) {
    fetch('/api/v1/live_streams/upload_chunk', {
      method: 'POST',
      headers: {

        'Content-Type': 'application/octet-stream',
        'X-Stream-Key': this.streamKey
      },
      body: data
    });
  }
}
```
### Real-time Features
#### Live Chat Implementation
```ruby
# app/channels/stream_chat_channel.rb

class StreamChatChannel < ApplicationCable::Channel

  def subscribed
    @live_stream = LiveStream.find(params[:stream_id])
    stream_from "stream_chat_#{@live_stream.id}"
  end
  def speak(data)
    message = @live_stream.stream_chats.create!(
      user: current_user,
      message: data['message']

    )
    ActionCable.server.broadcast("stream_chat_#{@live_stream.id}", {
      id: message.id,
      user: current_user.username,
      message: message.message,

      timestamp: message.created_at
    })
  end
end
```
## Installation & Setup
### Prerequisites
- Ruby 3.3.0+
- Rails 8.0.0+

- PostgreSQL 15+

- Redis 7.0+
- FFmpeg (for video processing)
- Node.js 18+ (for frontend assets)
### Setup Commands
```bash
# Install dependencies
bundle install

yarn install
# Setup database
bin/rails db:create db:migrate db:seed
# Configure Active Storage
bin/rails active_storage:install

# Start services
bin/rails server

redis-server
```

### Video Processing Setup
```bash
# Install FFmpeg on OpenBSD
doas pkg_add ffmpeg

# Configure storage for video files
# Add to config/storage.yml:
production:
  service: S3

  access_key_id: <%= Rails.application.credentials.dig(:aws, :access_key_id) %>
  secret_access_key: <%= Rails.application.credentials.dig(:aws, :secret_access_key) %>
  region: us-east-1
  bucket: brgen-tv-production
```
## Architecture
### Video Streaming Architecture
- **Upload**: Direct to cloud storage with background processing
- **Transcoding**: Multiple format generation (MP4, WebM, HLS)

- **CDN**: Global content distribution for video delivery

- **Analytics**: View tracking, engagement metrics, performance monitoring
### Live Streaming Architecture
- **Ingestion**: RTMP/WebRTC stream ingestion
- **Processing**: Real-time transcoding and adaptation
- **Distribution**: HLS/DASH streaming to viewers

- **Chat**: WebSocket-based real-time messaging
### Security Features
- **Stream Keys**: Secure broadcasting authentication
- **Content Moderation**: Automated and manual content review
- **User Verification**: Channel verification and trust systems

- **Access Controls**: Privacy settings and viewing permissions
## Usage Examples
### Creating a Video Channel
```ruby
# Create a new channel

channel = current_user.create_channel(

  name: "Tech Reviews",
  description: "Latest technology reviews and tutorials"
)
# Upload a video
video = channel.videos.create!(
  title: "iPhone 15 Review",
  description: "Complete review of the iPhone 15",

  category: "technology"
)
video.video_file.attach(params[:video_file])
```
### Starting a Live Stream
```ruby
# Create a live stream
stream = current_user.live_streams.create!(

  title: "Live Coding Session",
  description: "Building a Rails application",
  scheduled_for: 1.hour.from_now
)
# Get stream URL for broadcasting software
stream_url = "rtmp://#{Rails.application.config.streaming_server}/live/#{stream.stream_key}"
```
## Performance Considerations

- **Video Storage**: Use object storage (S3) with CDN distribution
- **Database Optimization**: Proper indexing for search and recommendations
- **Caching**: Redis caching for popular content and user preferences

- **Background Jobs**: Asynchronous video processing and notifications

- **Monitoring**: Real-time metrics for streaming quality and user engagement
## Framework Compliance
### Master.json v146.1.0 Alignment
- **Idempotency**: All video operations are safely repeatable
- **Reversibility**: Video uploads and streams can be cancelled/deleted

- **Security_by_design**: Secure stream keys and content validation

- **Composability**: Modular architecture with reusable components
### Code Style
- Two-space indentation with double quotes
- Comprehensive error handling with detailed logging
- Test-driven development with RSpec and system tests

- Progressive enhancement with Hotwire and Stimulus
---
*Built with Rails 8, Hotwire, and modern streaming technologies for OpenBSD 7.5*
