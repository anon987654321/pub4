#!/usr/bin/env zsh
# brgen_dating.sh — Brgen Dating platform (Rails 8)
# Usage: zsh brgen_dating.sh
set -euo pipefail

APP_NAME=brgen_dating
APP_DIR=/home/${APP_NAME}/app
APP_PORT=10008
SCRIPT_DIR=${0:a:h}

. "${SCRIPT_DIR:h}/@shared_functions.sh"

need_cmd ruby34 bundle rails doas

already_done "${APP_DIR}/app/models/profile.rb" && exit 0

log "Brgen Dating — Location-Based Matchmaking"

# ── Create app ─────────────────────────────────────────────────────────────
create_rails_app "$APP_DIR"

# ── Gems ────────────────────────────────────────────────────────────────────
add_gem pagy
add_gem image_processing
add_gem geocoder
install_solid_stack
install_security_tools

# ── Auth ───────────────────────────────────────────────────────────────────
install_auth
install_active_storage

# ── Models ─────────────────────────────────────────────────────────────────
bin/rails generate migration AddProfileFieldsToUsers \
  username:string birth_date:date gender:string \
  latitude:float longitude:float city:string country:string \
  --no-test-framework

bin/rails generate model Profile \
  user:references bio:text \
  looking_for:string \
  min_age:integer max_age:integer \
  max_distance_km:integer \
  show_distance:boolean:default[true] \
  show_age:boolean:default[true] \
  --no-test-framework

bin/rails generate model Photo \
  user:references position:integer primary:boolean:default[false] \
  --no-test-framework

bin/rails generate model Swipe \
  swiper:references{User} swiped:references{User} \
  direction:string \
  --no-test-framework

bin/rails generate model Match \
  user1:references{User} user2:references{User} \
  matched_at:datetime unmatched_at:datetime \
  --no-test-framework

bin/rails generate model Conversation \
  match:references last_message_at:datetime \
  --no-test-framework

bin/rails generate model Message \
  conversation:references user:references \
  content:text read_at:datetime \
  --no-test-framework

bin/rails generate model Interest name:string icon:string \
  --no-test-framework

bin/rails generate model UserInterest user:references interest:references \
  --no-test-framework

bin/rails db:migrate

# ── Model logic ─────────────────────────────────────────────────────────────
cat > app/models/user.rb << 'RUBY'
class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_one  :profile,  dependent: :destroy
  has_many :photos,   dependent: :destroy
  has_many :user_interests, dependent: :destroy
  has_many :interests, through: :user_interests
  has_many :sent_swipes, class_name: "Swipe", foreign_key: :swiper_id, dependent: :destroy
  has_many :received_swipes, class_name: "Swipe", foreign_key: :swiped_id, dependent: :destroy
  has_many :matches_as_user1, class_name: "Match", foreign_key: :user1_id, dependent: :destroy
  has_many :matches_as_user2, class_name: "Match", foreign_key: :user2_id, dependent: :destroy

  has_one_attached :avatar

  validates :email_address, presence: true, uniqueness: true
  validates :username, presence: true, uniqueness: true

  normalizes :email_address, with: -> e { e.strip.downcase }

  geocoded_by :city
  after_validation :geocode, if: :city_changed?

  def age
    return unless birth_date
    ((Date.today - birth_date) / 365).floor
  end

  def matches
    Match.active.where("user1_id = ? OR user2_id = ?", id, id)
  end

  def matched_with?(other)
    matches.where("user1_id = ? OR user2_id = ?", other.id, other.id).exists?
  end

  def primary_photo
    photos.find_by(primary: true) || photos.first
  end

  def discover(limit: 20)
    swiped_ids = sent_swipes.select(:swiped_id)
    User.where.not(id: swiped_ids + [id])
      .where.not(latitude: nil)
      .order(Arel.sql("((latitude - #{latitude || 0}) * (latitude - #{latitude || 0}) + (longitude - #{longitude || 0}) * (longitude - #{longitude || 0}))"))
      .limit(limit)
  end
end
RUBY

cat > app/models/swipe.rb << 'RUBY'
class Swipe < ApplicationRecord
  belongs_to :swiper, class_name: "User"
  belongs_to :swiped, class_name: "User"

  DIRECTIONS = %w[like dislike superlike].freeze

  validates :direction, inclusion: { in: DIRECTIONS }
  validates :swiper_id, uniqueness: { scope: :swiped_id }

  after_create :check_for_match

  private

  def check_for_match
    return unless direction.in?(%w[like superlike])
    mutual = Swipe.find_by(swiper: swiped, swiped: swiper, direction: ["like", "superlike"])
    return unless mutual
    Match.find_or_create_by!(
      user1: [swiper, swiped].min_by(&:id),
      user2: [swiper, swiped].max_by(&:id)
    ) do |m|
      m.matched_at = Time.current
    end
  end
end
RUBY

cat > app/models/match.rb << 'RUBY'
class Match < ApplicationRecord
  belongs_to :user1, class_name: "User"
  belongs_to :user2, class_name: "User"
  has_one :conversation, dependent: :destroy

  scope :active, -> { where(unmatched_at: nil) }

  after_create :create_conversation

  def other_user(user)
    user == user1 ? user2 : user1
  end

  def unmatch!
    update!(unmatched_at: Time.current)
  end

  private

  def create_conversation
    self.build_conversation.save!
  end
end
RUBY

cat > app/models/message.rb << 'RUBY'
class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :user

  validates :content, presence: true

  after_create_commit :broadcast_to_conversation

  def read_by!(reader)
    update!(read_at: Time.current) if user != reader && read_at.nil?
  end

  private

  def broadcast_to_conversation
    broadcast_append_to [conversation, "messages"],
      partial: "messages/message",
      locals: { message: self }
    conversation.match.user1.broadcast_render_later_to(
      [conversation.match.user1, "notifications"],
      partial: "shared/match_notification"
    ) rescue nil
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

cat > app/controllers/discover_controller.rb << 'RUBY'
class DiscoverController < ApplicationController
  before_action :require_authentication

  def index
    @users = Current.user.discover(limit: 10)
  end
end
RUBY

cat > app/controllers/swipes_controller.rb << 'RUBY'
class SwipesController < ApplicationController
  before_action :require_authentication

  def create
    swiped = User.find(params[:user_id])
    direction = params[:direction].presence_in(Swipe::DIRECTIONS) || "like"

    swipe = Current.user.sent_swipes.find_or_initialize_by(swiped: swiped)
    swipe.update!(direction: direction)

    if Current.user.matched_with?(swiped)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("swipe_#{swiped.id}", partial: "discover/match", locals: { user: swiped }) }
        format.json { render json: { matched: true } }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.remove("profile_#{swiped.id}") }
        format.json { render json: { matched: false } }
      end
    end
  end
end
RUBY

cat > app/controllers/matches_controller.rb << 'RUBY'
class MatchesController < ApplicationController
  before_action :require_authentication

  def index
    @matches = Current.user.matches.active.includes(:user1, :user2, :conversation)
  end

  def destroy
    match = Current.user.matches.find(params[:id])
    match.unmatch!
    redirect_to matches_path, notice: "Unmatched"
  end
end
RUBY

cat > app/controllers/conversations_controller.rb << 'RUBY'
class ConversationsController < ApplicationController
  before_action :require_authentication

  def show
    match = Current.user.matches.active.find_by!(id: params[:match_id])
    @conversation = match.conversation
    @messages     = @conversation.messages.order(:created_at)
    @messages.each { |m| m.read_by!(Current.user) }
    @message = Message.new
  end
end
RUBY

cat > app/controllers/messages_controller.rb << 'RUBY'
class MessagesController < ApplicationController
  before_action :require_authentication

  def create
    match        = Current.user.matches.active.find_by!(id: params[:match_id])
    @conversation = match.conversation
    @message = @conversation.messages.build(content: params[:message][:content], user: Current.user)
    if @message.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to match_conversation_path(match) }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end
end
RUBY

cat > app/controllers/profiles_controller.rb << 'RUBY'
class ProfilesController < ApplicationController
  before_action :require_authentication

  def edit
    @profile = Current.user.profile || Current.user.build_profile
  end

  def update
    @profile = Current.user.profile || Current.user.build_profile
    if @profile.update(profile_params)
      Current.user.update(user_params) if params[:user]
      redirect_to discover_path, notice: "Profile updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.require(:profile).permit(:bio, :looking_for, :min_age, :max_age, :max_distance_km, :show_distance, :show_age)
  end

  def user_params
    params.require(:user).permit(:username, :birth_date, :gender, :city)
  end
end
RUBY

# ── Routes ─────────────────────────────────────────────────────────────────
cat > config/routes.rb << 'RUBY'
Rails.application.routes.draw do
  resource  :session
  resources :passwords, param: :token
  resource  :profile, only: %i[edit update]

  root "discover#index"

  get  "discover",     to: "discover#index",  as: :discover
  post "swipe/:user_id", to: "swipes#create", as: :swipe

  resources :matches, only: %i[index destroy] do
    resource :conversation, only: %i[show] do
      resources :messages, only: %i[create]
    end
  end

  resources :users, only: %i[show]

  get "up", to: "rails/health#show", as: :rails_health_check
end
RUBY

# ── Assets + Infrastructure ─────────────────────────────────────────────────
mkdir -p app/assets/stylesheets
cat > app/assets/stylesheets/application.css << 'CSS'
:root {
  --bg: #0a0a0a; --surface: #1a1a1a; --text: #e8eaed;
  --primary: #e91e63; --primary-dim: #880e4f;
  --radius: 16px; --space: 8px;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: system-ui, sans-serif; background: var(--bg); color: var(--text); }
main { max-width: 480px; margin: 0 auto; padding: var(--space); }
.card { background: var(--surface); border-radius: var(--radius); overflow: hidden; margin-bottom: 1rem; }
.profile-photo { width: 100%; aspect-ratio: 3/4; object-fit: cover; }
.swipe-actions { display: flex; justify-content: space-around; padding: 1rem; }
.btn-like    { background: #4caf50; color: #fff; border: none; border-radius: 50%; width: 64px; height: 64px; font-size: 1.5rem; cursor: pointer; }
.btn-dislike { background: #f44336; color: #fff; border: none; border-radius: 50%; width: 64px; height: 64px; font-size: 1.5rem; cursor: pointer; }
.btn-super   { background: #2196f3; color: #fff; border: none; border-radius: 50%; width: 64px; height: 64px; font-size: 1.5rem; cursor: pointer; }
.flash-notice { background: #1a3a1a; color: #81c784; padding: .75rem 1rem; border-radius: 8px; margin-bottom: 1rem; }
.flash-alert  { background: #3a1a1a; color: #e57373; padding: .75rem 1rem; border-radius: 8px; margin-bottom: 1rem; }
CSS

write_layout "Brgen Dating"
write_puma_config "$APP_PORT"
configure_production
install_rcd brgen_dating "$APP_DIR" "$APP_PORT" brgen_dating

log_ok "Brgen Dating setup complete — start: doas rcctl start brgen_dating"
