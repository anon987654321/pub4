# BRGEN Dating - Location-Based Dating Platform
## Overview

BRGEN Dating is a modern, location-based dating platform built as part of the BRGEN ecosystem. It features intelligent matchmaking, real-time messaging, and location-aware discovery with privacy-focused design.
## Features

### Core Dating Features

- **Profile Management**: Comprehensive user profiles with photos, bio, interests, and preferences

- **Smart Matching**: ML-powered compatibility algorithm based on location, interests, and behavior

- **Swipe Interface**: Intuitive like/dislike system with instant feedback

- **Real-time Chat**: Secure messaging system for matched users
- **Location Services**: Radius-based discovery with privacy controls
### Privacy & Safety
- **Anonymous Browsing**: Browse profiles without revealing identity
- **Location Privacy**: Approximate location sharing with configurable radius
- **Block & Report**: Comprehensive safety tools

- **Verification System**: Photo and identity verification options
- **Safe Dating Tips**: Integrated safety resources
### Advanced Matching
- **Interest Compatibility**: Shared hobbies and lifestyle preferences
- **Geographic Filtering**: Distance-based matching with customizable range
- **Age Preferences**: Flexible age range settings

- **Activity Status**: Online/offline indicators and last seen
- **Mutual Friends**: Social network integration for safer connections
## Technical Implementation
### Models & Database Schema
#### Profile Model
```ruby

class Profile < ApplicationRecord

  belongs_to :user

  has_many_attached :photos
  validates :bio, length: { maximum: 500 }
  validates :age, presence: true, numericality: { in: 18..100 }
  validates :gender, inclusion: { in: %w[male female non-binary] }
  geocoded_by :location

  after_validation :geocode, if: :location_changed?
  scope :within_radius, ->(lat, lng, radius) { near([lat, lng], radius) }
  scope :available, -> { where(status: 'active') }

end
```

#### Matchmaking Service
```ruby
module Dating
  class MatchmakingService

    def self.find_matches(user)
      return [] unless user.profile&.active?
      # Exclude already interacted users
      excluded_ids = get_excluded_user_ids(user)
      # Base query for potential matches
      potential_matches = Profile.joins(:user)

                                .where.not(user_id: excluded_ids)
                                .where(gender: compatible_genders(user.profile.gender))

                                .available
      # Apply location filtering
      if user.profile.lat.present? && user.profile.lng.present?
        potential_matches = potential_matches.within_radius(
          user.profile.lat,

          user.profile.lng,
          user.profile.max_distance || 50
        )
      end
      # Apply interest matching
      potential_matches = apply_interest_filtering(potential_matches, user)
      # Score and sort by compatibility
      score_and_rank_matches(potential_matches, user)

    end
    private

    def self.get_excluded_user_ids(user)
      excluded = [user.id]
      excluded += user.dating_likes.pluck(:liked_user_id)

      excluded += user.dating_dislikes.pluck(:disliked_user_id)

      excluded += user.blocked_users.pluck(:blocked_user_id)
      excluded
    end
    def self.compatible_genders(user_gender)
      case user_gender
      when 'male' then ['female', 'non-binary']
      when 'female' then ['male', 'non-binary']

      when 'non-binary' then ['male', 'female', 'non-binary']
      else ['male', 'female', 'non-binary']
      end
    end
    def self.apply_interest_filtering(profiles, user)
      return profiles unless user.profile.interests.present?
      user_interests = user.profile.interests.split(',').map(&:strip)
      profiles.select do |profile|

        next true unless profile.interests.present?
        profile_interests = profile.interests.split(',').map(&:strip)

        common_interests = user_interests & profile_interests

        common_interests.length >= 1  # At least one shared interest
      end

    end
    def self.score_and_rank_matches(profiles, user)
      scored_profiles = profiles.map do |profile|
        score = calculate_compatibility_score(profile, user)
        { profile: profile, score: score }

      end
      scored_profiles.sort_by { |item| -item[:score] }
                    .first(20)
                    .map { |item| item[:profile] }
    end

    def self.calculate_compatibility_score(profile, user)
      score = 0
      # Distance factor (closer = higher score)
      if profile.lat && profile.lng && user.profile.lat && user.profile.lng

        distance = Geocoder::Calculations.distance_between(
          [user.profile.lat, user.profile.lng],

          [profile.lat, profile.lng]
        )
        score += [50 - distance, 0].max
      end
      # Interest compatibility
      if profile.interests.present? && user.profile.interests.present?
        user_interests = user.profile.interests.split(',').map(&:strip)
        profile_interests = profile.interests.split(',').map(&:strip)

        common_interests = user_interests & profile_interests
        score += common_interests.length * 10
      end
      # Age compatibility
      age_difference = (profile.age - user.profile.age).abs
      score += [20 - age_difference, 0].max
      # Activity factor (recently active users)

      if profile.user.last_sign_in_at && profile.user.last_sign_in_at > 7.days.ago
        score += 15
      end

      score
    end
  end
end

```
### Controllers
#### Profiles Controller
```ruby
module Dating

  class ProfilesController < ApplicationController

    before_action :authenticate_user!
    before_action :ensure_profile_exists
    before_action :set_profile, only: [:show, :like, :dislike]
    def index
      @profiles = MatchmakingService.find_matches(current_user)
      @current_profile = @profiles.first
      respond_to do |format|

        format.html
        format.json { render json: @profiles }
      end

    end
    def show
      @messages = Message.conversation_between(current_user, @profile.user)
                        .order(:created_at)
                        .limit(50)

    end
    def like
      result = create_interaction(:like)
      respond_to do |format|
        format.turbo_stream { render_interaction_response(result) }

        format.json { render json: result }
      end

    end
    def dislike
      result = create_interaction(:dislike)
      respond_to do |format|
        format.turbo_stream { render_interaction_response(result) }

        format.json { render json: result }
      end

    end
    private
    def set_profile
      @profile = Profile.find(params[:id])
    end

    def ensure_profile_exists

      redirect_to new_profile_path unless current_user.profile&.complete?
    end
    def create_interaction(type)

      case type
      when :like
        like = Dating::Like.find_or_create_by(

          user: current_user,
          liked_user: @profile.user
        )
        # Check for mutual like (match)
        if Dating::Like.exists?(user: @profile.user, liked_user: current_user)
          match = Match.create!(
            initiator: current_user.profile,

            receiver: @profile,
            status: 'matched',
            matched_at: Time.current
          )
          # Send match notifications
          MatchNotificationJob.perform_later(match)
          { success: true, matched: true, match: match }
        else

          { success: true, matched: false }
        end

      when :dislike
        Dating::Dislike.find_or_create_by(
          user: current_user,
          disliked_user: @profile.user

        )
        { success: true }
      end
    end
    def render_interaction_response(result)
      if result[:matched]
        render turbo_stream: [
          turbo_stream.replace("profile-card-#{@profile.id}",

            partial: "dating/shared/match_celebration",
            locals: { match: result[:match] }
          ),
          turbo_stream.append("notifications",
            partial: "dating/shared/match_notification",
            locals: { match: result[:match] }
          )
        ]
      else
        render turbo_stream: turbo_stream.remove("profile-card-#{@profile.id}")
      end
    end
  end
end
```
### Frontend Components
#### Swipe Controller (Stimulus)
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  static targets = ["card", "likeButton", "dislikeButton"]
  static values = { profileId: Number }
  connect() {

    this.setupSwipeGestures()
    this.setupKeyboardControls()
  }

  setupSwipeGestures() {
    let startX = null
    let startY = null
    this.cardTarget.addEventListener('touchstart', (e) => {

      startX = e.touches[0].clientX
      startY = e.touches[0].clientY
    })

    this.cardTarget.addEventListener('touchend', (e) => {
      if (!startX || !startY) return
      const endX = e.changedTouches[0].clientX
      const endY = e.changedTouches[0].clientY

      const deltaX = endX - startX
      const deltaY = endY - startY

      // Only process horizontal swipes
      if (Math.abs(deltaX) > Math.abs(deltaY) && Math.abs(deltaX) > 100) {

        if (deltaX > 0) {
          this.like()

        } else {
          this.dislike()
        }
      }
      startX = null
      startY = null
    })
  }

  setupKeyboardControls() {
    document.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowRight' || e.key === 'l') {
        this.like()

      } else if (e.key === 'ArrowLeft' || e.key === 'd') {
        this.dislike()
      }
    })
  }
  like() {
    this.animateCard('right')
    this.submitInteraction('like')
  }

  dislike() {
    this.animateCard('left')
    this.submitInteraction('dislike')
  }

  animateCard(direction) {
    const card = this.cardTarget
    const translateX = direction === 'right' ? '100vw' : '-100vw'
    const rotation = direction === 'right' ? '30deg' : '-30deg'

    card.style.transition = 'transform 0.3s ease-out'
    card.style.transform = `translateX(${translateX}) rotate(${rotation})`
    setTimeout(() => {
      card.remove()

    }, 300)
  }

  submitInteraction(action) {
    const url = `/dating/profiles/${this.profileIdValue}/${action}`
    fetch(url, {
      method: 'POST',

      headers: {
        'X-CSRF-Token': this.getCSRFToken(),

        'Accept': 'text/vnd.turbo-stream.html'
      }
    })
    .then(response => response.text())
    .then(html => {
      if (html.includes('match_celebration')) {
        this.showMatchCelebration()
      }
      this.loadNextProfile()
    })
    .catch(error => {
      console.error('Error submitting interaction:', error)
      this.showError('Network error. Please try again.')
    })
  }
  showMatchCelebration() {
    // Show match animation/modal
    const celebration = document.createElement('div')
    celebration.className = 'match-celebration'

    celebration.innerHTML = `
      <div class="celebration-content">
        <h2>It's a Match! 🎉</h2>
        <p>You both liked each other!</p>
        <button onclick="this.parentElement.parentElement.remove()">
          Start Chatting
        </button>
      </div>
    `
    document.body.appendChild(celebration)
  }
  loadNextProfile() {
    // Load the next profile in the stack
    fetch('/dating/profiles/next', {
      headers: {

        'Accept': 'text/html'
      }
    })
    .then(response => response.text())
    .then(html => {
      const parser = new DOMParser()
      const doc = parser.parseFromString(html, 'text/html')
      const nextCard = doc.querySelector('.profile-card')
      if (nextCard) {
        this.element.insertAdjacentHTML('beforeend', nextCard.outerHTML)
      }
    })

  }
  getCSRFToken() {
    return document.querySelector('meta[name="csrf-token"]').content
  }
  showError(message) {

    // Show error notification
    const error = document.createElement('div')
    error.className = 'error-notification'

    error.textContent = message
    document.body.appendChild(error)
    setTimeout(() => error.remove(), 3000)
  }
}
```

## Installation & Setup
### Requirements
- Rails 8.0+
- PostgreSQL 12+

- Redis 6+

- Node.js 18+
### Setup Instructions
```bash
# Run the dating setup script
./rails/brgen/dating.sh

# Configure environment variables
export MAPBOX_ACCESS_TOKEN=your_token
export MAX_DATING_DISTANCE=100
# Run migrations

bin/rails db:migrate
# Seed test data
bin/rails db:seed:dating

```
### Configuration Options

#### Dating Settings
```ruby
# config/initializers/dating.rb

Dating.configure do |config|

  config.max_distance = ENV.fetch('MAX_DATING_DISTANCE', 50).to_i
  config.min_age = 18
  config.max_age = 80
  config.max_photos = 10
  config.enable_video_profiles = true
  config.require_verification = false
end
```
## API Endpoints
### Profile Discovery
- `GET /dating/profiles` - Get potential matches
- `GET /dating/profiles/:id` - View specific profile

- `POST /dating/profiles/:id/like` - Like a profile

- `POST /dating/profiles/:id/dislike` - Dislike a profile
### Matches & Messaging
- `GET /dating/matches` - List current matches
- `GET /dating/matches/:id/messages` - Get conversation
- `POST /dating/matches/:id/messages` - Send message

### Profile Management
- `GET /dating/my_profile` - Current user's profile
- `PUT /dating/my_profile` - Update profile
- `POST /dating/my_profile/photos` - Upload photos

## Privacy & Safety Features
### Data Protection
- **GDPR Compliance**: Full data export and deletion capabilities
- **Location Privacy**: Only approximate locations shared

- **Photo Protection**: Watermarking and download prevention

- **Anonymous Mode**: Browse without being visible to others
### Safety Tools
- **Report System**: Easy reporting of inappropriate behavior
- **Block Users**: Immediate blocking with no further contact
- **Safe Meeting**: Tips and resources for safe dating

- **Emergency Contacts**: Integration with emergency services
## Testing
### Test Coverage
```bash
# Run dating-specific tests

bin/rails test:models test/models/dating/

bin/rails test:controllers test/controllers/dating/
bin/rails test:system test/system/dating/
# Run matching algorithm tests
bin/rails test test/services/dating/matchmaking_service_test.rb
```
### Performance Testing

```bash
# Test matching performance
bin/rails runner "

  user = User.first
  Benchmark.measure { Dating::MatchmakingService.find_matches(user) }
"
# Load test profile endpoints
ab -n 1000 -c 10 http://localhost:3000/dating/profiles
```
## Deployment Considerations

### Scaling
- **Database indexing** on location columns for performance
- **Redis caching** for frequently accessed profiles

- **CDN integration** for photo delivery

- **Background jobs** for match processing
### Monitoring
- **Match success rates** tracking
- **User engagement** metrics
- **Response time** monitoring

- **Error rate** alerting
## Future Enhancements
### Planned Features
- **Video chat** integration for virtual dates
- **Group dating** and double date coordination

- **Event-based** matching for shared activities

- **AI-powered** conversation starters
- **Virtual reality** profile experiences
### Integration Opportunities
- **Social media** profile importing
- **Calendar integration** for date scheduling
- **Restaurant APIs** for date suggestions

- **Transportation** booking integration
