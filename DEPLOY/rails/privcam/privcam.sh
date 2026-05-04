#!/usr/bin/env zsh
# privcam.sh — Privcam private live camera/event sharing platform (Rails 8)
# Usage: zsh privcam.sh
set -euo pipefail

APP_NAME=privcam
APP_DIR=/home/${APP_NAME}/app
APP_PORT=10005
SCRIPT_DIR=${0:a:h}

. "${SCRIPT_DIR:h}/@shared_functions.sh"

need_cmd ruby34 bundle rails doas

already_done "${APP_DIR}/app/models/room.rb" && exit 0

log "Privcam — Private Live Camera and Event Sharing"

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
bin/rails generate model Room \
  user:references name:string description:text \
  access_code:string:uniq \
  status:string max_viewers:integer:default[50] \
  viewer_count:integer:default[0] \
  started_at:datetime ended_at:datetime \
  recording_enabled:boolean:default[false] \
  --no-test-framework

bin/rails generate model RoomParticipant \
  room:references user:references \
  role:string joined_at:datetime left_at:datetime \
  display_name:string \
  --no-test-framework

bin/rails generate model Message \
  room:references user:references \
  content:text message_type:string \
  deleted_at:datetime \
  --no-test-framework

bin/rails generate model RoomInvite \
  room:references inviter:references{User} \
  email:string token:string:uniq \
  accepted_at:datetime expires_at:datetime \
  --no-test-framework

bin/rails generate model Recording \
  room:references \
  duration_seconds:integer \
  status:string \
  --no-test-framework

bin/rails generate model ViewerEvent \
  room:references user:references \
  event_type:string occurred_at:datetime \
  --no-test-framework

bin/rails db:migrate

# ── Model logic ─────────────────────────────────────────────────────────────
cat > app/models/room.rb << 'RUBY'
class Room < ApplicationRecord
  belongs_to :user
  has_many :room_participants, dependent: :destroy
  has_many :participants, through: :room_participants, source: :user
  has_many :messages, dependent: :destroy
  has_many :room_invites, dependent: :destroy
  has_many :recordings, dependent: :destroy
  has_many :viewer_events, dependent: :destroy

  STATUSES = %w[idle live ended].freeze

  validates :name, presence: true, length: { maximum: 100 }
  validates :status, inclusion: { in: STATUSES }
  validates :max_viewers, numericality: { only_integer: true, greater_than: 0 }

  default_value_for :status, "idle"

  before_create :generate_access_code

  scope :live,    -> { where(status: "live") }
  scope :public_rooms, -> { joins(:room_participants).distinct }

  def go_live!
    update!(status: "live", started_at: Time.current)
    broadcast_replace_to "rooms", target: "room_#{id}", partial: "rooms/room", locals: { room: self }
  end

  def end_room!
    update!(status: "ended", ended_at: Time.current)
  end

  def accessible_by?(user)
    self.user == user ||
      room_invites.where(email: user.email_address).where("expires_at > ?", Time.current).exists? ||
      room_participants.exists?(user: user)
  end

  def full?
    viewer_count >= max_viewers
  end

  private

  def generate_access_code
    self.access_code = SecureRandom.alphanumeric(8).upcase
  end
end
RUBY

cat > app/models/room_participant.rb << 'RUBY'
class RoomParticipant < ApplicationRecord
  belongs_to :room
  belongs_to :user

  ROLES = %w[host moderator viewer].freeze

  validates :role, inclusion: { in: ROLES }

  after_create_commit  :increment_viewer_count
  after_destroy        :decrement_viewer_count

  scope :active, -> { where(left_at: nil) }

  def leave!
    update!(left_at: Time.current)
    room.decrement!(:viewer_count)
  end

  private

  def increment_viewer_count
    room.increment!(:viewer_count)
    ViewerEvent.create!(room: room, user: user, event_type: "join", occurred_at: Time.current)
  end

  def decrement_viewer_count
    room.decrement!(:viewer_count) if room.viewer_count > 0
    ViewerEvent.create!(room: room, user: user, event_type: "leave", occurred_at: Time.current)
  end
end
RUBY

cat > app/models/message.rb << 'RUBY'
class Message < ApplicationRecord
  belongs_to :room
  belongs_to :user

  MESSAGE_TYPES = %w[chat system reaction].freeze

  validates :content, presence: true, unless: -> { message_type == "reaction" }
  validates :message_type, inclusion: { in: MESSAGE_TYPES }

  default_scope -> { where(deleted_at: nil).order(:created_at) }

  after_create_commit :broadcast_to_room

  def soft_delete!
    update!(deleted_at: Time.current, content: "[message deleted]")
  end

  private

  def broadcast_to_room
    broadcast_append_to [room, "messages"],
      partial: "messages/message",
      locals: { message: self }
  end
end
RUBY

cat > app/models/room_invite.rb << 'RUBY'
class RoomInvite < ApplicationRecord
  belongs_to :room
  belongs_to :inviter, class_name: "User"

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token, uniqueness: true

  before_create :generate_token
  before_create :set_expiry

  scope :valid, -> { where("expires_at > ?", Time.current).where(accepted_at: nil) }

  def accept!(user)
    update!(accepted_at: Time.current)
    room.room_participants.find_or_create_by!(user: user) { |p| p.role = "viewer" }
  end

  private

  def generate_token
    self.token = SecureRandom.urlsafe_base64(24)
  end

  def set_expiry
    self.expires_at ||= 7.days.from_now
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

cat > app/controllers/rooms_controller.rb << 'RUBY'
class RoomsController < ApplicationController
  before_action :require_authentication, except: %i[join_with_code]
  before_action :set_room, only: %i[show go_live end_room destroy invite]
  before_action :authorize!, only: %i[go_live end_room destroy]

  def index
    @pagy, @rooms = pagy(Current.user.rooms.order(created_at: :desc))
    @live_rooms   = Room.live.includes(:user).limit(10)
  end

  def show
    unless @room.accessible_by?(Current.user)
      redirect_to rooms_path, alert: "Access denied"
      return
    end
    @participant = @room.room_participants.find_or_create_by!(user: Current.user) do |p|
      p.role       = @room.user == Current.user ? "host" : "viewer"
      p.joined_at  = Time.current
      p.display_name = Current.user.email_address.split("@").first
    end
    @messages = @room.messages.includes(:user).last(100)
    @message  = Message.new
  end

  def new
    @room = Current.user.rooms.build
  end

  def create
    @room = Current.user.rooms.build(room_params)
    @room.save ? redirect_to(@room, notice: "Room created — share code: #{@room.access_code}") : render(:new, status: :unprocessable_entity)
  end

  def go_live
    @room.go_live!
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @room }
    end
  end

  def end_room
    @room.end_room!
    redirect_to rooms_path, notice: "Room ended"
  end

  def destroy
    @room.destroy
    redirect_to rooms_path, notice: "Room deleted"
  end

  def invite
    invite = @room.room_invites.create!(inviter: Current.user, email: params[:email])
    # TODO: send email with invite.token
    redirect_to @room, notice: "Invite sent to #{invite.email}"
  end

  def join_with_code
    @room = Room.find_by!(access_code: params[:code].to_s.upcase)
    if authenticated?
      redirect_to @room
    else
      redirect_to new_session_path, notice: "Sign in to join room #{@room.name}"
    end
  end

  private

  def set_room   = @room = Room.find(params[:id])
  def authorize! = redirect_to(rooms_path, alert: "Unauthorized") unless @room.user == Current.user
  def room_params = params.require(:room).permit(:name, :description, :max_viewers, :recording_enabled)
end
RUBY

cat > app/controllers/messages_controller.rb << 'RUBY'
class MessagesController < ApplicationController
  before_action :require_authentication
  before_action :set_room

  def create
    unless @room.room_participants.exists?(user: Current.user)
      render json: { error: "Not a participant" }, status: :forbidden
      return
    end
    @message = @room.messages.build(message_params.merge(user: Current.user))
    if @message.save
      respond_to do |format|
        format.turbo_stream
        format.json { render json: { status: "ok" } }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @message = @room.messages.find(params[:id])
    if @message.user == Current.user || @room.user == Current.user
      @message.soft_delete!
    end
    respond_to do |format|
      format.turbo_stream
      format.json { render json: { status: "ok" } }
    end
  end

  private

  def set_room = @room = Room.find(params[:room_id])
  def message_params = params.require(:message).permit(:content, :message_type)
end
RUBY

cat > app/controllers/invites_controller.rb << 'RUBY'
class InvitesController < ApplicationController
  before_action :require_authentication

  def show
    @invite = RoomInvite.valid.find_by!(token: params[:token])
    @invite.accept!(Current.user)
    redirect_to @invite.room, notice: "Welcome to #{@invite.room.name}"
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Invalid or expired invite"
  end
end
RUBY

# ── Routes ─────────────────────────────────────────────────────────────────
cat > config/routes.rb << 'RUBY'
Rails.application.routes.draw do
  resource  :session
  resources :passwords, param: :token

  root "rooms#index"

  resources :rooms do
    member do
      post   :go_live
      post   :end_room
      post   :invite
    end
    resources :messages, only: %i[create destroy]
  end

  get "join/:code", to: "rooms#join_with_code", as: :join_room
  get "invite/:token", to: "invites#show",      as: :accept_invite

  get "up", to: "rails/health#show", as: :rails_health_check
end
RUBY

# ── Assets + Infrastructure ─────────────────────────────────────────────────
mkdir -p app/assets/stylesheets
cat > app/assets/stylesheets/application.css << 'CSS'
:root {
  --bg: #0a0a0a; --surface: #111; --surface-alt: #1a1a1a;
  --text: #e8eaed; --text-dim: #9aa0a6;
  --primary: #4285f4; --red: #ea4335; --green: #34a853;
  --radius: 8px; --space: 8px;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: system-ui, sans-serif; background: var(--bg); color: var(--text); }
main { max-width: 1400px; margin: 0 auto; padding: var(--space); }
a { color: var(--primary); text-decoration: none; }
a:hover { text-decoration: underline; }
.room-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 1rem; }
.room-card { background: var(--surface); border-radius: var(--radius); overflow: hidden; }
.room-preview { aspect-ratio: 16/9; background: #222; display: flex; align-items: center; justify-content: center; }
.room-info { padding: 1rem; }
.live-dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%; background: var(--red); margin-right: .35rem; animation: pulse 1.5s infinite; }
@keyframes pulse { 0%,100% { opacity: 1; } 50% { opacity: .4; } }
.chat-panel { height: 400px; display: flex; flex-direction: column; }
.chat-messages { flex: 1; overflow-y: auto; padding: .5rem; }
.chat-message { padding: .3rem 0; font-size: .9rem; }
.chat-author { font-weight: 600; color: var(--primary); margin-right: .35rem; }
.access-code { font-family: monospace; font-size: 1.4rem; font-weight: 700; letter-spacing: .2em; background: var(--surface-alt); padding: .5rem 1rem; border-radius: 6px; display: inline-block; }
.btn { display: inline-block; padding: .4rem 1rem; border-radius: var(--radius); border: none; cursor: pointer; font-size: .9rem; }
.btn-primary { background: var(--primary); color: #fff; }
.btn-live    { background: var(--red);     color: #fff; }
.btn-end     { background: #555;           color: #fff; }
.flash-notice { background: #1a3a1a; color: #81c784; padding: .75rem 1rem; border-radius: var(--radius); margin-bottom: 1rem; }
.flash-alert  { background: #3a1a1a; color: #e57373; padding: .75rem 1rem; border-radius: var(--radius); margin-bottom: 1rem; }
CSS

# ── Views ───────────────────────────────────────────────────────────────────
mkdir -p app/views/rooms app/views/messages

write_shared_partials
write_auth_views

cat > app/views/rooms/index.html.erb << 'ERB'
<% content_for :title, "Rooms" %>
<header>
  <h1>Rooms</h1>
  <%= link_to "New room", new_room_path, class: "btn-primary btn" %>
  <%= form_with url: join_room_path(code: ""), method: :get, class: "join-form" do |f| %>
    <%= f.text_field :code, placeholder: "Enter access code", maxlength: 8, class: "code-input" %>
    <%= f.submit "Join", class: "btn btn-primary" %>
  <% end %>
</header>
<% if @live_rooms.any? %>
  <h2>Live now</h2>
  <div class="room-grid" id="live_rooms">
    <%= render @live_rooms %>
  </div>
<% end %>
<% if @rooms.any? %>
  <h2>My rooms</h2>
  <div class="room-grid"><%= render @rooms %></div>
  <%= pagy_nav(@pagy) if @pagy.pages > 1 %>
<% else %>
  <p>No rooms yet. <%= link_to "Create one", new_room_path %>.</p>
<% end %>
ERB

cat > app/views/rooms/_room.html.erb << 'ERB'
<article class="room-card" id="<%= dom_id(room) %>">
  <div class="room-preview">
    <% if room.status == "live" %>
      <span><span class="live-dot"></span>LIVE</span>
    <% else %>
      <span class="dim"><%= room.status.upcase %></span>
    <% end %>
  </div>
  <div class="room-info">
    <%= link_to room.name, room %>
    <span class="dim"><%= room.viewer_count %> / <%= room.max_viewers %> viewers</span>
    <p class="dim"><%= room.description %></p>
    <span class="access-code"><%= room.access_code %></span>
  </div>
</article>
ERB

cat > app/views/rooms/show.html.erb << 'ERB'
<% content_for :title, @room.name %>
<div class="room-layout" data-controller="chat">
  <section class="room-main">
    <header>
      <h1>
        <% if @room.status == "live" %><span class="live-dot"></span><% end %>
        <%= @room.name %>
      </h1>
      <span class="access-code"><%= @room.access_code %></span>
      <% if @room.user == Current.user %>
        <% if @room.status != "live" %>
          <%= button_to "Go live", go_live_room_path(@room), method: :post, class: "btn btn-live" %>
        <% else %>
          <%= button_to "End", end_room_room_path(@room), method: :post, class: "btn btn-end", data: { turbo_confirm: "End this room?" } %>
        <% end %>
      <% end %>
    </header>
    <p class="dim"><%= @room.description %></p>
    <p class="dim"><%= @room.viewer_count %> viewer<%= "s" if @room.viewer_count != 1 %></p>
    <% if @room.user == Current.user %>
      <%= form_with url: invite_room_path(@room), method: :post, class: "invite-form" do |f| %>
        <%= f.email_field :email, placeholder: "Invite by email" %>
        <%= f.submit "Invite", class: "btn btn-primary" %>
      <% end %>
    <% end %>
  </section>
  <aside class="chat-panel">
    <div class="chat-messages" id="messages" data-chat-target="messages">
      <%= render @messages %>
    </div>
    <%= form_with url: room_messages_path(@room), data: { action: "turbo:submit-end->chat#reset", controller: "chat" } do |f| %>
      <%= f.text_field :content, placeholder: "Message…", data: { chat_target: "input" }, autocomplete: "off" %>
      <%= f.hidden_field :message_type, value: "chat" %>
      <%= f.submit "Send", class: "btn btn-primary" %>
    <% end %>
  </aside>
</div>
ERB

cat > app/views/rooms/go_live.turbo_stream.erb << 'ERB'
<%= turbo_stream.replace dom_id(@room), partial: "rooms/room", locals: { room: @room } %>
<%= turbo_stream.replace "live_rooms", partial: "rooms/room", locals: { room: @room } %>
ERB

cat > app/views/rooms/new.html.erb << 'ERB'
<% content_for :title, "New room" %>
<h1>New room</h1>
<%= form_with model: @room, class: "form" do |f| %>
  <%= render "shared/errors", object: @room %>
  <div class="field"><%= f.label :name %><%= f.text_field :name, autofocus: true %></div>
  <div class="field"><%= f.label :description %><%= f.text_area :description, rows: 3 %></div>
  <div class="field"><%= f.label :max_viewers %><%= f.number_field :max_viewers, min: 1, max: 1000 %></div>
  <div class="field"><%= f.label :recording_enabled %><%= f.check_box :recording_enabled %></div>
  <div class="actions"><%= f.submit "Create room", class: "btn btn-primary" %> <%= link_to "Cancel", rooms_path %></div>
<% end %>
ERB

cat > app/views/messages/_message.html.erb << 'ERB'
<p class="chat-message" id="<%= dom_id(message) %>">
  <span class="chat-author"><%= message.user.email_address.split("@").first %></span>
  <%= message.content %>
  <% if message.user == Current.user %>
    <%= button_to "×", room_message_path(message.room, message), method: :delete, class: "btn-del" %>
  <% end %>
</p>
ERB

cat > app/views/messages/create.turbo_stream.erb << 'ERB'
<%= turbo_stream.append "messages", partial: "messages/message", locals: { message: @message } %>
ERB

cat > app/views/messages/destroy.turbo_stream.erb << 'ERB'
<%= turbo_stream.remove dom_id(@message) %>
ERB

# ── Stimulus ────────────────────────────────────────────────────────────────
setup_stimulus

mkdir -p app/javascript/controllers
cat > app/javascript/controllers/chat_controller.js << 'JS'
import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["messages", "input"]
  connect() { this.scroll() }
  messageTargetConnected() { this.scroll() }
  scroll() { this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight }
  reset() { this.inputTarget.value = "" }
}
JS

write_layout "Privcam"
write_falcon_config "$APP_PORT"
configure_production
install_rcd privcam "$APP_DIR" "$APP_PORT" privcam

log_ok "Privcam setup complete — start: doas rcctl start privcam"
