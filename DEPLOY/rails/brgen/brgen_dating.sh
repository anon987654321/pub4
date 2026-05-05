#!/usr/bin/env zsh
# brgen_dating.sh — Add Dating:: namespace to the main brgen Rails app
set -euo pipefail

APP_DIR=/home/brgen/app
SCRIPT_DIR=${0:a:h}

. "${SCRIPT_DIR}/@shared_functions.sh" 2>/dev/null || . /tmp/shared_functions.sh

need_cmd ruby34 bundle rails doas

already_done "${APP_DIR}/app/models/dating/profile.rb" && exit 0

log "Brgen Dating — adding Dating namespace to brgen app"
cd "$APP_DIR"

# ── Models ─────────────────────────────────────────────────────────────────
bin/rails generate model Dating::Profile \
  user:references bio:text gender:string looking_for:string \
  age:integer location:string latitude:decimal longitude:decimal \
  visible:boolean \
  --no-test-framework

bin/rails generate model Dating::Like \
  liker:references likee:references \
  --no-test-framework

bin/rails generate model Dating::Dislike \
  disliker:references dislikee:references \
  --no-test-framework

bin/rails generate model Dating::Match \
  initiator:references receiver:references status:string \
  --no-test-framework

RAILS_ENV=production bin/rails db:migrate

# ── Model logic ─────────────────────────────────────────────────────────────
mkdir -p app/models/dating

cat > app/models/dating/profile.rb << 'RUBY'
class Dating::Profile < ApplicationRecord
  belongs_to :user
  has_many_attached :photos

  GENDERS     = %w[man woman nonbinary other].freeze
  LOOKING_FOR = %w[man woman everyone].freeze

  validates :bio,         length: { maximum: 500 }
  validates :age,         numericality: { greater_than: 17, less_than: 100 }, allow_nil: true
  validates :gender,      inclusion: { in: GENDERS },     allow_nil: true
  validates :looking_for, inclusion: { in: LOOKING_FOR }, allow_nil: true

  scope :visible, -> { where(visible: true) }
  scope :nearby, ->(lat, lng, km = 50) {
    where("ABS(latitude - ?) < ? AND ABS(longitude - ?) < ?", lat, km / 111.0, lng, km / 111.0)
  }

  def liked_by?(user)    = Dating::Like.exists?(liker: user, likee: self.user)
  def disliked_by?(user) = Dating::Dislike.exists?(disliker: user, dislikee: self.user)
  def matched_with?(user)
    Dating::Match.where(status: "matched")
      .where("(initiator_id = ? AND receiver_id = ?) OR (initiator_id = ? AND receiver_id = ?)",
             self.user_id, user.id, user.id, self.user_id).exists?
  end
end
RUBY

cat > app/models/dating/like.rb << 'RUBY'
class Dating::Like < ApplicationRecord
  belongs_to :liker, class_name: "User"
  belongs_to :likee, class_name: "User"
  validates :liker_id, uniqueness: { scope: :likee_id }
  validate  :no_self_like
  after_create :check_mutual_match

  private

  def no_self_like
    errors.add(:likee, "can't like yourself") if liker_id == likee_id
  end

  def check_mutual_match
    return unless Dating::Like.exists?(liker_id: likee_id, likee_id: liker_id)
    Dating::Match.find_or_create_by!(initiator_id: liker_id, receiver_id: likee_id) do |m|
      m.status = "matched"
    end
  end
end
RUBY

cat > app/models/dating/dislike.rb << 'RUBY'
class Dating::Dislike < ApplicationRecord
  belongs_to :disliker, class_name: "User"
  belongs_to :dislikee, class_name: "User"
  validates :disliker_id, uniqueness: { scope: :dislikee_id }
  validate  :no_self_dislike

  private
  def no_self_dislike
    errors.add(:dislikee, "can't dislike yourself") if disliker_id == dislikee_id
  end
end
RUBY

cat > app/models/dating/match.rb << 'RUBY'
class Dating::Match < ApplicationRecord
  belongs_to :initiator, class_name: "User"
  belongs_to :receiver,  class_name: "User"
  validates :initiator_id, uniqueness: { scope: :receiver_id }
  validates :status, inclusion: { in: %w[pending matched unmatched] }

  scope :active, -> { where(status: "matched") }

  def other_user(user)
    initiator_id == user.id ? receiver : initiator
  end
end
RUBY

# ── Controllers ─────────────────────────────────────────────────────────────
mkdir -p app/controllers/dating

cat > app/controllers/dating/base_controller.rb << 'RUBY'
class Dating::BaseController < ApplicationController

end
RUBY

cat > app/controllers/dating/home_controller.rb << 'RUBY'
class Dating::HomeController < Dating::BaseController
  def index
    profile = Current.user.dating_profile
    unless profile&.visible?
      redirect_to edit_dating_profile_path and return
    end
    liked_ids    = Dating::Like.where(liker: Current.user).pluck(:likee_id)
    disliked_ids = Dating::Dislike.where(disliker: Current.user).pluck(:dislikee_id)
    excluded     = (liked_ids + disliked_ids + [Current.user.id]).uniq
    @pagy, @profiles = pagy(
      Dating::Profile.visible
        .where.not(user_id: excluded)
        .includes(:user)
        .order(Arel.sql("RANDOM()"))
    )
  end
end
RUBY

cat > app/controllers/dating/profiles_controller.rb << 'RUBY'
class Dating::ProfilesController < Dating::BaseController
  before_action :set_profile, only: %i[show edit update]

  def show; end
  def edit; end

  def new
    @profile = Current.user.build_dating_profile
  end

  def create
    @profile = Current.user.build_dating_profile(profile_params)
    @profile.save ?
      redirect_to(dating_root_path, notice: "Profile created") :
      render(:new, status: :unprocessable_entity)
  end

  def update
    @profile.update(profile_params) ?
      redirect_to(dating_root_path, notice: "Profile updated") :
      render(:edit, status: :unprocessable_entity)
  end

  private
  def set_profile    = (@profile = Current.user.dating_profile || redirect_to(new_dating_profile_path))
  def profile_params = params.require(:dating_profile).permit(:bio, :gender, :looking_for, :age, :location, :latitude, :longitude, :visible, photos: [])
end
RUBY

cat > app/controllers/dating/likes_controller.rb << 'RUBY'
class Dating::LikesController < Dating::BaseController
  def create
    user = User.find(params[:user_id])
    Dating::Like.find_or_create_by!(liker: Current.user, likee: user)
    redirect_to dating_root_path
  end
end
RUBY

cat > app/controllers/dating/dislikes_controller.rb << 'RUBY'
class Dating::DislikesController < Dating::BaseController
  def create
    user = User.find(params[:user_id])
    Dating::Dislike.find_or_create_by!(disliker: Current.user, dislikee: user)
    redirect_to dating_root_path
  end
end
RUBY

cat > app/controllers/dating/matches_controller.rb << 'RUBY'
class Dating::MatchesController < Dating::BaseController
  def index
    @pagy, @matches = pagy(
      Dating::Match.active
        .where("initiator_id = ? OR receiver_id = ?", Current.user.id, Current.user.id)
        .includes(:initiator, :receiver)
    )
  end
end
RUBY

# ── Views ────────────────────────────────────────────────────────────────────
mkdir -p app/views/dating/home app/views/dating/profiles app/views/dating/matches

cat > app/views/dating/home/index.html.erb << 'ERB'
<% content_for :title, "Dating" %>
<h1>Discover</h1>
<nav>
  <%= link_to "Matches", dating_matches_path, class: "btn" %>
  <%= link_to "Edit profile", edit_dating_profile_path, class: "btn" %>
</nav>
<div class="profile-deck">
  <% @profiles.each do |p| %>
    <article class="profile-card">
      <% if p.photos.attached? %>
        <%= image_tag p.photos.first, class: "profile-photo" %>
      <% end %>
      <h2><%= p.user.email_address.split("@").first %><% if p.age %>, <%= p.age %><% end %></h2>
      <% if p.location.present? %><p><%= p.location %></p><% end %>
      <p><%= p.bio %></p>
      <div>
        <%= button_to "Like", dating_likes_path(user_id: p.user_id), method: :post, class: "btn btn--primary" %>
        <%= button_to "Pass", dating_dislikes_path(user_id: p.user_id), method: :post, class: "btn" %>
      </div>
    </article>
  <% end %>
</div>
<%= @pagy.series_nav if @pagy.pages > 1 %>
ERB

cat > app/views/dating/profiles/new.html.erb << 'ERB'
<h1>Create your profile</h1>
<%= form_with model: @profile, url: dating_profile_path do |f| %>
  <%= render "shared/errors", object: @profile %>
  <div class="field">
    <%= f.label :bio, "About you" %>
    <%= f.text_area :bio, rows: 4, maxlength: 500 %>
  </div>
  <div class="field">
    <%= f.label :gender %>
    <%= f.select :gender, Dating::Profile::GENDERS, { include_blank: "—" } %>
  </div>
  <div class="field">
    <%= f.label :looking_for, "Looking for" %>
    <%= f.select :looking_for, Dating::Profile::LOOKING_FOR, { include_blank: "—" } %>
  </div>
  <div class="field">
    <%= f.label :age %>
    <%= f.number_field :age, min: 18, max: 99 %>
  </div>
  <div class="field">
    <%= f.label :location %>
    <%= f.text_field :location %>
  </div>
  <div class="field">
    <%= f.label :photos, "Photos" %>
    <%= f.file_field :photos, multiple: true, accept: "image/*" %>
  </div>
  <div class="field">
    <%= f.check_box :visible %> <%= f.label :visible, "Make profile visible" %>
  </div>
  <div class="actions"><%= f.submit "Save", class: "btn btn--primary" %></div>
<% end %>
ERB

cat > app/views/dating/profiles/edit.html.erb << 'ERB'
<h1>Edit profile</h1>
<%= form_with model: @profile, url: dating_profile_path, method: :patch do |f| %>
  <%= render "shared/errors", object: @profile %>
  <div class="field">
    <%= f.label :bio, "About you" %>
    <%= f.text_area :bio, rows: 4, maxlength: 500 %>
  </div>
  <div class="field">
    <%= f.label :gender %>
    <%= f.select :gender, Dating::Profile::GENDERS, { include_blank: "—" } %>
  </div>
  <div class="field">
    <%= f.label :looking_for, "Looking for" %>
    <%= f.select :looking_for, Dating::Profile::LOOKING_FOR, { include_blank: "—" } %>
  </div>
  <div class="field">
    <%= f.label :age %>
    <%= f.number_field :age, min: 18, max: 99 %>
  </div>
  <div class="field">
    <%= f.label :location %>
    <%= f.text_field :location %>
  </div>
  <div class="field">
    <%= f.label :photos, "Photos" %>
    <%= f.file_field :photos, multiple: true, accept: "image/*" %>
  </div>
  <div class="field">
    <%= f.check_box :visible %> <%= f.label :visible, "Make profile visible" %>
  </div>
  <div class="actions"><%= f.submit "Save", class: "btn btn--primary" %></div>
<% end %>
ERB

cat > app/views/dating/matches/index.html.erb << 'ERB'
<% content_for :title, "Matches" %>
<h1>Matches</h1>
<%= link_to "Back to discover", dating_root_path, class: "btn" %>
<% if @matches.none? %>
  <p>No matches yet.</p>
<% else %>
  <div class="match-list">
    <% @matches.each do |m| %>
      <% other = m.other_user(Current.user) %>
      <article>
        <% if other.dating_profile&.photos&.attached? %>
          <%= image_tag other.dating_profile.photos.first %>
        <% end %>
        <p><%= other.email_address.split("@").first %></p>
      </article>
    <% end %>
  </div>
<% end %>
<%= @pagy.series_nav if @pagy.pages > 1 %>
ERB

# ── Route patch ─────────────────────────────────────────────────────────────
ruby34 -e "
r = File.read('config/routes.rb')
unless r.include?('namespace :dating')
  patch = %q(
  namespace :dating do
    root 'home#index'
    resource  :profile,  only: %i[new create edit update show]
    resources :likes,    only: :create
    resources :dislikes, only: :create
    resources :matches,  only: :index
  end
)
  r.sub!('root \"home#index\"', patch + '  root \"home#index\"')
  File.write('config/routes.rb', r)
  puts 'Routes patched'
end
"

# ── User association ─────────────────────────────────────────────────────────
ruby34 -e "
u = File.read('app/models/user.rb')
unless u.include?('dating_profile')
  u.sub!('has_secure_password', %Q(has_secure_password
  has_one  :dating_profile,              class_name: 'Dating::Profile',  dependent: :destroy
  has_many :dating_likes,                class_name: 'Dating::Like',     foreign_key: :liker_id,    dependent: :destroy
  has_many :dating_dislikes,             class_name: 'Dating::Dislike',  foreign_key: :disliker_id, dependent: :destroy
  has_many :dating_matches_as_initiator, class_name: 'Dating::Match',    foreign_key: :initiator_id, dependent: :destroy
  has_many :dating_matches_as_receiver,  class_name: 'Dating::Match',    foreign_key: :receiver_id,  dependent: :destroy))
  File.write('app/models/user.rb', u)
  puts 'User model patched'
end
"

doas rcctl restart brgen 2>/dev/null || true
log_ok "Brgen Dating namespace added — visit /dating"
