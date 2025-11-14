# PRIVCAM - Private Video Sharing Platform
## Overview

Privcam is a privacy-focused video sharing platform built with Rails 8, designed for secure, private video sharing with advanced privacy controls, end-to-end encryption options, and anonymous features. The platform prioritizes user privacy while providing modern video sharing capabilities.
## Features
### Privacy-First Video Sharing
- **Private Video Uploads**: Secure video storage with granular privacy controls
- **Encrypted Storage**: Client-side encryption options for sensitive content
- **Anonymous Sharing**: Share videos without revealing identity

- **Access Control**: Fine-grained permissions for video access

- **Temporary Sharing**: Self-destructing video links with expiration

### Advanced Privacy Features

- **Zero-Knowledge Architecture**: Server cannot access encrypted video content

- **Anonymous Comments**: Comment on videos without user identification
- **Privacy Zones**: Blur or mask sensitive areas in videos

- **Metadata Stripping**: Automatic removal of EXIF and location data

- **Secure Viewing**: View-once options and screenshot prevention

### Social Features (Privacy-Aware)

- **Private Groups**: Create invite-only video sharing groups

- **Secure Messaging**: End-to-end encrypted comments and discussions
- **Trust Networks**: Build networks of trusted viewers

- **Anonymous Feedback**: Rate and comment while maintaining anonymity

- **Privacy Reports**: Users can report privacy violations

## Technical Implementation

### Models & Database Schema

#### Video Model
```ruby
class Video < ApplicationRecord
  belongs_to :user, optional: true # Allow anonymous uploads

  has_many :comments, dependent: :destroy

  has_many :video_views, dependent: :destroy

  has_many :access_grants, dependent: :destroy

  has_one_attached :video_file

  has_one_attached :thumbnail

  validates :title, presence: true, length: { maximum: 200 }

  validates :description, length: { maximum: 2000 }

  enum privacy_level: {
    private_video: 0,

    trusted_users: 1,
    group_only: 2,

    anonymous_link: 3

  }

  enum encryption_level: {

    none: 0,

    server_side: 1,
    client_side: 2

  }

  before_create :generate_secure_id, :strip_metadata

  after_create :process_privacy_settings

  def viewable_by?(viewer_user = nil)
    case privacy_level

    when 'private_video'
      return false if user.nil? # Anonymous videos can't be private to specific user

      viewer_user == user

    when 'trusted_users'

      return false unless user && viewer_user

      user.trusts?(viewer_user)

    when 'group_only'

      return false unless viewer_user

      access_grants.exists?(user: viewer_user, granted: true)

    when 'anonymous_link'

      true # Anyone with link can view

    else

      false

    end

  end

  def secure_url

    Rails.application.routes.url_helpers.secure_video_path(secure_id: secure_id)

  end
  private

  def generate_secure_id

    self.secure_id = SecureRandom.urlsafe_base64(32)
  end
  def strip_metadata

    return unless video_file.attached?

    # Strip EXIF data and metadata in background job
    VideoMetadataStripperJob.perform_later(id)

  end

end

```

#### Privacy-Aware User Model

```ruby

class User < ApplicationRecord
  has_many :videos, dependent: :destroy

  has_many :comments, dependent: :destroy

  has_many :trust_relationships, dependent: :destroy

  has_many :trusted_users, through: :trust_relationships, source: :trusted_user

  has_many :privacy_settings, dependent: :destroy

  validates :username, presence: true, uniqueness: true

  validates :privacy_level, inclusion: { in: %w[public private anonymous] }

  enum privacy_level: { public_user: 0, private_user: 1, anonymous_user: 2 }
  def trusts?(other_user)

    trust_relationships.exists?(trusted_user: other_user, active: true)
  end
  def grant_trust(other_user)

    trust_relationships.find_or_create_by(trusted_user: other_user) do |trust|

      trust.active = true
      trust.granted_at = Time.current

    end

  end

  def revoke_trust(other_user)

    trust_relationships.where(trusted_user: other_user).update_all(active: false)

  end
  def anonymous_identifier

    # Generate consistent but unlinkable identifier for anonymous features

    Digest::SHA256.hexdigest("#{id}-#{Rails.application.secret_key_base}")[0..8]
  end

  def can_view_video?(video)

    video.viewable_by?(self)

  end
end

```

#### Anonymous Comment Model

```ruby

class Comment < ApplicationRecord
  belongs_to :video

  belongs_to :user, optional: true # Allow anonymous comments

  has_many :comment_reports, dependent: :destroy

  validates :content, presence: true, length: { maximum: 1000 }

  validates :anonymous_id, presence: true, if: -> { user.nil? }

  before_validation :generate_anonymous_id, if: -> { user.nil? }
  def author_display_name

    if user.present?
      case user.privacy_level
      when 'public_user'

        user.username

      when 'private_user'

        "Private User"

      when 'anonymous_user'

        user.anonymous_identifier

      end

    else

      "Anonymous-#{anonymous_id}"

    end

  end

  def author_is_anonymous?

    user.nil? || user.anonymous_user?

  end
  private

  def generate_anonymous_id

    self.anonymous_id = SecureRandom.hex(4) if anonymous_id.blank?
  end
end

```

### Client-Side Encryption

#### Video Encryption Service

```javascript
// app/javascript/encryption/video_encryptor.js
class VideoEncryptor {

  constructor() {

    this.algorithm = 'AES-GCM';

    this.keyLength = 256;

  }

  async generateKey() {

    return await crypto.subtle.generateKey(

      { name: this.algorithm, length: this.keyLength },
      true,

      ['encrypt', 'decrypt']

    );

  }

  async encryptVideo(videoFile, key) {

    const iv = crypto.getRandomValues(new Uint8Array(12));

    const videoBuffer = await videoFile.arrayBuffer();
    const encryptedBuffer = await crypto.subtle.encrypt(

      { name: this.algorithm, iv: iv },

      key,
      videoBuffer

    );

    return {

      encryptedData: encryptedBuffer,

      iv: iv,
      keyHash: await this.hashKey(key)

    };

  }

  async decryptVideo(encryptedData, key, iv) {

    return await crypto.subtle.decrypt(

      { name: this.algorithm, iv: iv },
      key,

      encryptedData

    );

  }

  async exportKey(key) {

    const exported = await crypto.subtle.exportKey('raw', key);

    return Array.from(new Uint8Array(exported));
  }

  async importKey(keyArray) {

    const keyBuffer = new Uint8Array(keyArray).buffer;

    return await crypto.subtle.importKey(
      'raw',

      keyBuffer,

      { name: this.algorithm },

      true,

      ['encrypt', 'decrypt']

    );

  }

  async hashKey(key) {

    const exported = await crypto.subtle.exportKey('raw', key);

    const hashBuffer = await crypto.subtle.digest('SHA-256', exported);
    return Array.from(new Uint8Array(hashBuffer));

  }

}

```

### Privacy Controls

#### Privacy Settings Manager

```ruby
class PrivacySettingsService
  def initialize(user)

    @user = user

  end

  def apply_video_privacy(video, settings)

    video.update!(

      privacy_level: settings[:privacy_level],
      encryption_level: settings[:encryption_level],

      allow_anonymous_comments: settings[:allow_anonymous_comments],

      metadata_stripped: settings[:strip_metadata],

      view_limit: settings[:view_limit],

      expires_at: settings[:expires_at]

    )

    if settings[:trusted_users].present?

      create_access_grants(video, settings[:trusted_users])

    end
    if settings[:client_side_encrypted]

      video.update!(

        encryption_key_hash: settings[:key_hash],
        server_cannot_decrypt: true

      )

    end

  end

  def create_secure_link(video, options = {})

    link = SecureLink.create!(

      video: video,
      token: SecureRandom.urlsafe_base64(32),

      expires_at: options[:expires_at] || 24.hours.from_now,

      view_limit: options[:view_limit] || nil,

      password_protected: options[:password].present?,

      password_hash: options[:password] ? BCrypt::Password.create(options[:password]) : nil

    )

    link.secure_url

  end

  def grant_video_access(video, target_user, permissions = {})
    AccessGrant.create!(

      video: video,
      user: target_user,

      granted_by: @user,

      granted: true,

      can_comment: permissions[:can_comment] || false,

      can_share: permissions[:can_share] || false,

      expires_at: permissions[:expires_at]

    )

  end

  private

  def create_access_grants(video, user_list)

    user_list.each do |username|
      user = User.find_by(username: username)
      next unless user

      grant_video_access(video, user, { can_comment: true })

    end

  end

end

```

### Anonymous Features

#### Anonymous Upload System

```ruby
class AnonymousUploadService
  def self.create_upload(video_params, session_id)

    # Create temporary anonymous user tied to session

    anonymous_user = AnonymousUser.find_or_create_by(

      session_identifier: anonymize_session(session_id)

    )

    video = Video.create!(

      title: video_params[:title],

      description: video_params[:description],
      privacy_level: 'anonymous_link',

      anonymous_uploader: anonymous_user,

      uploaded_by_ip: anonymize_ip(video_params[:ip]),

      metadata_stripped: true

    )

    if video_params[:video_file].present?

      video.video_file.attach(video_params[:video_file])

      VideoProcessingJob.perform_later(video.id, anonymous: true)
    end

    {

      video: video,

      secure_url: video.secure_url,
      management_token: generate_management_token(video, anonymous_user)

    }

  end

  def self.verify_management_access(video, token)

    expected_token = generate_management_token(video, video.anonymous_uploader)

    ActiveSupport::SecurityUtils.secure_compare(token, expected_token)
  end

  private

  def self.anonymize_session(session_id)

    Digest::SHA256.hexdigest("#{session_id}-#{Rails.application.secret_key_base}")[0..16]
  end
  def self.anonymize_ip(ip_address)

    # Keep only first 3 octets for IPv4, first 48 bits for IPv6

    return nil if ip_address.blank?
    if ip_address.include?('.')

      parts = ip_address.split('.')

      "#{parts[0]}.#{parts[1]}.#{parts[2]}.xxx"
    else

      # IPv6

      parts = ip_address.split(':')

      "#{parts[0..2].join(':')}::xxxx"

    end

  end

  def self.generate_management_token(video, anonymous_user)

    data = "#{video.id}-#{anonymous_user.id}-#{video.created_at.to_i}"

    Digest::SHA256.hexdigest("#{data}-#{Rails.application.secret_key_base}")
  end

end

```

### Video Processing with Privacy

#### Privacy-Aware Video Processing

```ruby
class VideoProcessingJob < ApplicationJob
  queue_as :video_processing

  def perform(video_id, options = {})

    video = Video.find(video_id)

    if options[:anonymous]
      # Extra privacy measures for anonymous uploads

      process_with_privacy(video)
    else

      process_standard(video)

    end

    # Always strip metadata regardless

    strip_metadata(video)

    # Generate thumbnail without storing original
    generate_privacy_safe_thumbnail(video)

    video.update!(processing_completed_at: Time.current)
  end

  private
  def process_with_privacy(video)

    # Process video without logging identifying information
    Rails.logger.info "Processing anonymous video #{video.secure_id}"
    # Use temporary file paths that don't reveal user info

    temp_path = Rails.root.join('tmp', 'anonymous_processing', video.secure_id)

    FileUtils.mkdir_p(temp_path)
    begin

      # Video processing logic here

      process_video_formats(video, temp_path)
    ensure

      # Always clean up temporary files

      FileUtils.rm_rf(temp_path)

    end

  end

  def strip_metadata(video)

    return unless video.video_file.attached?

    # Use FFmpeg to strip all metadata
    video.video_file.blob.open do |tempfile|

      stripped_path = "#{tempfile.path}.stripped"
      system("ffmpeg -i #{tempfile.path} -map_metadata -1 -c copy #{stripped_path}")

      if File.exist?(stripped_path)

        video.video_file.attach(
          io: File.open(stripped_path),
          filename: video.video_file.filename,

          content_type: video.video_file.content_type

        )

        File.delete(stripped_path)

      end

    end

  end

end

```

## Installation & Setup

### Prerequisites

- Ruby 3.3.0+
- Rails 8.0.0+
- PostgreSQL 15+

- Redis 7.0+

- FFmpeg (for video processing and metadata stripping)

- Node.js 18+ (for client-side encryption)

### Setup Commands

```bash

# Install dependencies
bundle install

yarn install

# Setup database

bin/rails db:create db:migrate db:seed

# Configure Active Storage with encryption
bin/rails active_storage:install

# Generate application secrets for encryption
bin/rails secret

# Add to credentials:
EDITOR=vim bin/rails credentials:edit

# Start services

bin/rails server

redis-server
```

### Privacy Configuration

```bash

# Environment variables for privacy features
export PRIVCAM_ENCRYPTION_ENABLED=true

export PRIVCAM_METADATA_STRIPPING=true

export PRIVCAM_ANONYMOUS_UPLOADS=true

export PRIVCAM_MAX_VIDEO_SIZE=500MB

export PRIVCAM_AUTO_DELETE_AFTER=30days

```

## Security Features

### Data Protection

- **Metadata Stripping**: Automatic removal of EXIF, GPS, and device information
- **IP Anonymization**: Partial IP masking for anonymous uploads
- **Session Management**: Secure session handling without persistent tracking

- **Secure File Storage**: Encrypted storage with access controls

- **Regular Cleanup**: Automatic deletion of expired content

### Privacy Controls

- **Granular Permissions**: Fine-grained control over who can view content

- **Anonymous Mode**: Complete anonymity for uploads and comments
- **Trust Networks**: Build networks of trusted viewers

- **Self-Destructing Content**: Automatic expiration of sensitive videos

- **Privacy Reports**: User-driven privacy violation reporting

## Usage Examples

### Creating a Private Video

```ruby
# Upload with client-side encryption
video = current_user.videos.create!(

  title: "Private Family Video",

  description: "Personal family content",

  privacy_level: 'trusted_users',

  encryption_level: 'client_side'

)

# Grant access to trusted users

privacy_service = PrivacySettingsService.new(current_user)

privacy_service.grant_video_access(video, trusted_friend, {
  can_comment: true,

  expires_at: 1.week.from_now

})

```

### Anonymous Upload

```ruby

# Create anonymous upload
upload_result = AnonymousUploadService.create_upload({

  title: "Anonymous Tip",

  description: "Sensitive information sharing",

  video_file: params[:video_file],

  ip: request.remote_ip

}, session.id)

# Return secure viewing and management URLs

{

  view_url: upload_result[:secure_url],
  manage_url: "#{upload_result[:secure_url]}?token=#{upload_result[:management_token]}"

}

```

### Creating Secure Sharing Link

```ruby

# Generate time-limited, password-protected link
privacy_service = PrivacySettingsService.new(current_user)

secure_url = privacy_service.create_secure_link(video, {

  expires_at: 24.hours.from_now,

  view_limit: 5,

  password: "secret123"

})

```

## Performance Considerations

- **Lazy Loading**: Load video content only when authorized

- **CDN Integration**: Serve public content through CDN while preserving privacy
- **Background Processing**: Asynchronous video processing and metadata stripping
- **Database Encryption**: Sensitive data encrypted at rest

- **Memory Management**: Careful handling of video data in memory

## Framework Compliance

### Master.json v146.1.0 Alignment

- **Idempotency**: All privacy operations are safely repeatable
- **Reversibility**: Privacy settings can be changed and content can be deleted
- **Security_by_design**: Privacy-first architecture with multiple protection layers

- **Composability**: Modular privacy components that work together

### Code Style

- **Privacy by Default**: All features default to maximum privacy

- **Explicit Consent**: Users must explicitly grant permissions
- **Transparency**: Clear communication about what data is collected and how

- **Minimal Data**: Collect only data necessary for functionality

---

*Built with Rails 8, client-side encryption, and privacy-first principles for OpenBSD 7.5*

