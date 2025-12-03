#!/usr/bin/env zsh
set -euo pipefail

# Brgen Dating - Location-based dating platform
# Per brgen_dating_README.md specifications

readonly VERSION="2.0.0"
readonly APP_NAME="brgen"

readonly BASE_DIR="/home/brgen"

readonly APP_DIR="${BASE_DIR}/app"

SCRIPT_DIR="${0:a:h}"
source "${SCRIPT_DIR}/__shared/@common.sh"

log "Setting up Brgen Dating"
if [[ ! -d "$APP_DIR" ]]; then
  log "ERROR: Brgen app not found at $APP_DIR. Run brgen.sh first."

  exit 1

fi

cd "$APP_DIR"
log "Generating dating models"
bin/rails generate model Dating::Profile user:references bio:text age:integer gender:string location:string lat:decimal lng:decimal max_distance:integer interests:text status:string last_active_at:datetime
bin/rails generate model Dating::Like user:references liked_user:references

bin/rails generate model Dating::Dislike user:references disliked_user:references

bin/rails generate model Dating::Match initiator:references receiver:references status:string matched_at:datetime

bin/rails db:migrate
log "Configuring dating models"
cat > app/models/dating/profile.rb << 'EOF'
class Dating::Profile < ApplicationRecord

  belongs_to :user

  has_many_attached :photos

  validates :bio, length: { maximum: 500 }
  validates :age, presence: true, numericality: { in: 18..100 }

  validates :gender, inclusion: { in: %w[male female non-binary] }

  geocoded_by :location
  after_validation :geocode, if: :location_changed?

  scope :within_radius, ->(lat, lng, radius) { near([lat, lng], radius) }
  scope :available, -> { where(status: 'active') }

  scope :recently_active, -> { where('last_active_at > ?', 7.days.ago) }

  def complete?
    bio.present? && age.present? && gender.present? && photos.attached?

  end

end

EOF

cat > app/models/dating/like.rb << 'EOF'
class Dating::Like < ApplicationRecord

  belongs_to :user

  belongs_to :liked_user, class_name: 'User'

  validates :user_id, uniqueness: { scope: :liked_user_id }
end

EOF

cat > app/models/dating/dislike.rb << 'EOF'
class Dating::Dislike < ApplicationRecord

  belongs_to :user

  belongs_to :disliked_user, class_name: 'User'

  validates :user_id, uniqueness: { scope: :disliked_user_id }
end

EOF

cat > app/models/dating/match.rb << 'EOF'
class Dating::Match < ApplicationRecord

  belongs_to :initiator, class_name: 'Dating::Profile'

  belongs_to :receiver, class_name: 'Dating::Profile'

  validates :initiator_id, uniqueness: { scope: :receiver_id }
  enum status: { pending: 'pending', matched: 'matched', expired: 'expired' }
  scope :active, -> { where(status: 'matched') }
end

EOF

log "Creating matchmaking service"
mkdir -p app/services/dating
cat > app/services/dating/matchmaking_service.rb << 'EOF'

module Dating

  class MatchmakingService

    def self.find_matches(user)

      return [] unless user.profile&.complete?

      excluded_ids = get_excluded_user_ids(user)
      potential_matches = Dating::Profile.joins(:user)
        .where.not(user_id: excluded_ids)

        .where(gender: compatible_genders(user.profile.gender))

        .available

        .recently_active

      if user.profile.lat.present? && user.profile.lng.present?
        potential_matches = potential_matches.within_radius(

          user.profile.lat,

          user.profile.lng,

          user.profile.max_distance || 50

        )

      end

      score_and_rank_matches(potential_matches, user)
    end

    private
    def self.get_excluded_user_ids(user)
      excluded = [user.id]

      excluded += Dating::Like.where(user: user).pluck(:liked_user_id)

      excluded += Dating::Dislike.where(user: user).pluck(:disliked_user_id)

      excluded += user.blocked_users.pluck(:blocked_user_id) if user.respond_to?(:blocked_users)

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

    def self.score_and_rank_matches(profiles, user)
      scored = profiles.map do |profile|

        score = calculate_compatibility_score(profile, user)

        { profile: profile, score: score }

      end

      scored.sort_by { |item| -item[:score] }
        .first(20)

        .map { |item| item[:profile] }

    end

    def self.calculate_compatibility_score(profile, user)
      score = 0

      if profile.lat && profile.lng && user.profile.lat && user.profile.lng
        distance = Geocoder::Calculations.distance_between(

          [user.profile.lat, user.profile.lng],

          [profile.lat, profile.lng]

        )

        score += [50 - distance, 0].max

      end

      if profile.interests.present? && user.profile.interests.present?
        user_interests = user.profile.interests.split(',').map(&:strip)

        profile_interests = profile.interests.split(',').map(&:strip)

        common = user_interests & profile_interests

        score += common.length * 10

      end

      age_diff = (profile.age - user.profile.age).abs
      score += [20 - age_diff, 0].max

      if profile.last_active_at && profile.last_active_at > 7.days.ago
        score += 15

      end

      score
    end

  end

end

EOF

log "Generating dating controllers"
bin/rails generate controller Dating::Profiles index show like dislike
bin/rails generate controller Dating::Matches index show

bin/rails generate controller Dating::MyProfile show edit update

log "Implementing controllers"
cat > app/controllers/dating/profiles_controller.rb << 'EOF'
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
      @match = Dating::Match.active

        .where('(initiator_id = ? AND receiver_id = ?) OR (initiator_id = ? AND receiver_id = ?)',

               current_user.profile.id, @profile.id, @profile.id, current_user.profile.id)

        .first

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
      @profile = Dating::Profile.find(params[:id])

    end

    def ensure_profile_exists
      redirect_to new_dating_my_profile_path unless current_user.profile&.complete?

    end

    def create_interaction(type)
      case type

      when :like

        Dating::Like.find_or_create_by(user: current_user, liked_user: @profile.user)

        if Dating::Like.exists?(user: @profile.user, liked_user: current_user)
          match = Dating::Match.create!(

            initiator: current_user.profile,

            receiver: @profile,

            status: 'matched',

            matched_at: Time.current

          )

          { success: true, matched: true, match: match }

        else

          { success: true, matched: false }

        end

      when :dislike
        Dating::Dislike.find_or_create_by(user: current_user, disliked_user: @profile.user)

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

EOF

log "Creating dating views"
mkdir -p app/views/dating/profiles
cat > app/views/dating/profiles/index.html.erb << 'EOF'

<%= tag.section class: "dating-discover", data: { controller: "swipe", "swipe-profile-id-value": @current_profile&.id } do %>

  <%= tag.header do %>

    <%= tag.h1 "Oppdag Personer" %>

    <%= tag.nav do %>

      <%= link_to "Meldinger", dating_matches_path %>

      <%= link_to "Min Profil", dating_my_profile_path %>

    <% end %>

  <% end %>

  <% if @current_profile %>
    <%= tag.article id: "profile-card-#{@current_profile.id}", class: "profile-card", data: { "swipe-target": "card" } do %>

      <% if @current_profile.photos.attached? %>

        <%= image_tag @current_profile.photos.first, alt: @current_profile.user.username, class: "profile-image" %>

      <% end %>

      <%= tag.div class: "profile-info" do %>
        <%= tag.h2 "#{@current_profile.user.username}, #{@current_profile.age}" %>

        <%= tag.p @current_profile.bio %>

        <% if @current_profile.location.present? %>
          <%= tag.p class: "location" do %>

            <%= tag.span "📍" %>

            <%= @current_profile.location %>

          <% end %>

        <% end %>

        <% if @current_profile.interests.present? %>
          <%= tag.div class: "interests" do %>

            <% @current_profile.interests.split(',').each do |interest| %>

              <%= tag.span interest.strip, class: "interest-tag" %>

            <% end %>

          <% end %>

        <% end %>

      <% end %>

      <%= tag.div class: "actions" do %>
        <%= button_tag "❌", data: { action: "click->swipe#dislike" }, class: "dislike-button", "aria-label": "Dislike" %>

        <%= button_tag "💚", data: { action: "click->swipe#like" }, class: "like-button", "aria-label": "Like" %>

      <% end %>

    <% end %>

  <% else %>

    <%= tag.p "Ingen flere profiler å vise for øyeblikket. Kom tilbake senere!" %>

  <% end %>

<% end %>

EOF

log "Creating Stimulus swipe controller"
mkdir -p app/javascript/controllers
cat > app/javascript/controllers/swipe_controller.js << 'EOF'

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["card"]

  static values = { profileId: Number }

  connect() {
    this.setupSwipeGestures()

    this.setupKeyboardControls()

  }

  setupSwipeGestures() {
    let startX = null

    this.cardTarget.addEventListener('touchstart', (e) => {
      startX = e.touches[0].clientX

    })

    this.cardTarget.addEventListener('touchend', (e) => {
      if (!startX) return

      const endX = e.changedTouches[0].clientX
      const deltaX = endX - startX

      if (Math.abs(deltaX) > 100) {
        if (deltaX > 0) {

          this.like()

        } else {

          this.dislike()

        }

      }

      startX = null
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

    setTimeout(() => card.remove(), 300)
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

  }

  showMatchCelebration() {
    const celebration = document.createElement('div')

    celebration.className = 'match-celebration'

    celebration.innerHTML = `

      <div class="celebration-content">

        <h2>Match! 🎉</h2>

        <p>Dere likte hverandre!</p>

        <button onclick="this.parentElement.parentElement.remove()">Start chat</button>

      </div>

    `

    document.body.appendChild(celebration)

  }

  loadNextProfile() {
    window.location.reload()

  }

  getCSRFToken() {
    return document.querySelector('meta[name="csrf-token"]').content

  }

}

EOF

log "Adding dating styles"
cat >> app/assets/stylesheets/application.scss << 'SCSS'
/* Dating styles */
.dating-discover {

  max-width: 500px;

  margin: 0 auto;

  padding: var(--spacing-unit);

  .profile-card {
    background: var(--color-surface);

    border-radius: var(--border-radius);

    overflow: hidden;

    box-shadow: 0 4px 12px rgba(0,0,0,0.1);

    .profile-image {
      width: 100%;

      height: 400px;

      object-fit: cover;

    }

    .profile-info {
      padding: calc(var(--spacing-unit) * 2);

      h2 {
        margin: 0 0 var(--spacing-unit) 0;

        font-size: 1.5rem;

      }

      .location {
        color: var(--color-text-dim);

        margin: var(--spacing-unit) 0;

      }

      .interests {
        display: flex;

        flex-wrap: wrap;

        gap: calc(var(--spacing-unit) / 2);

        margin-top: var(--spacing-unit);

        .interest-tag {
          background: var(--color-primary);

          color: var(--color-bg);

          padding: calc(var(--spacing-unit) / 2) var(--spacing-unit);

          border-radius: calc(var(--border-radius) / 2);

          font-size: 0.875rem;

        }

      }

    }

    .actions {
      display: flex;

      justify-content: space-around;

      padding: calc(var(--spacing-unit) * 2);

      gap: var(--spacing-unit);

      button {
        width: 80px;

        height: 80px;

        border: none;

        border-radius: 50%;

        font-size: 2rem;

        cursor: pointer;

        transition: transform 0.2s;

        &:hover {
          transform: scale(1.1);

        }

        &.dislike-button {
          background: #ff6b6b;

        }

        &.like-button {
          background: #51cf66;

        }

      }

    }

  }

}

.match-celebration {
  position: fixed;

  top: 0;

  left: 0;

  right: 0;

  bottom: 0;

  background: rgba(0,0,0,0.8);

  display: flex;

  align-items: center;

  justify-content: center;

  z-index: 9999;

  animation: fadeIn 0.3s;

  .celebration-content {
    background: var(--color-surface);

    padding: calc(var(--spacing-unit) * 4);

    border-radius: var(--border-radius);

    text-align: center;

    animation: scaleIn 0.3s;

    h2 {
      font-size: 2rem;

      margin-bottom: var(--spacing-unit);

    }

    button {
      margin-top: calc(var(--spacing-unit) * 2);

      padding: var(--spacing-unit) calc(var(--spacing-unit) * 3);

      background: var(--color-primary);

      color: var(--color-bg);

      border: none;

      border-radius: calc(var(--border-radius) / 2);

      font-size: 1rem;

      cursor: pointer;

      &:hover {
        opacity: 0.9;

      }

    }

  }

}

@keyframes fadeIn {
  from { opacity: 0; }

  to { opacity: 1; }

}

@keyframes scaleIn {
  from { transform: scale(0.8); }

  to { transform: scale(1); }

}

SCSS

log "Adding dating routes"
routes_block=$(cat << 'ROUTES'
  namespace :dating do

    resources :profiles, only: [:index, :show] do

      member do

        post :like

        post :dislike

      end

    end

    resources :matches, only: [:index, :show]

    resource :my_profile, controller: 'my_profile', only: [:show, :edit, :update, :new, :create]

  end

ROUTES

)

add_routes_block "$routes_block"
log "Creating dating seed data"
cat >> db/seeds.rb << 'EOF'
# Dating seed data
if Rails.env.development? && Dating::Profile.count.zero?

  print "Creating dating profiles...\n"

  User.limit(20).each do |user|
    next if user.profile.present?

    profile = Dating::Profile.create!(
      user: user,

      bio: Faker::Lorem.paragraph(sentence_count: 2),

      age: rand(22..45),

      gender: ['male', 'female', 'non-binary'].sample,

      location: ["Oslo", "Bergen", "Trondheim"].sample,

      lat: rand(58.0..63.0),

      lng: rand(5.0..11.0),

      max_distance: [25, 50, 100].sample,

      interests: ["hiking", "music", "travel", "food", "art", "sports"].sample(3).join(', '),

      status: 'active',

      last_active_at: rand(1..48).hours.ago

    )

    print "."
  end

  print "\nDating profiles created!\n"
end

EOF

log "Brgen Dating setup complete!"
log "Access dating at: http://localhost:11006/dating/profiles"

