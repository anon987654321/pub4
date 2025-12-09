#!/usr/bin/env zsh
set -euo pipefail

# BRGEN v3.0.0 - Rails 8 Complete Social Network
# Updated for Rails 8.0, PWA, Propshaft, modern patterns
# Per master.yml v13.16.0

readonly VERSION="3.0.0"
readonly APP_NAME="brgen"
readonly BASE_DIR="/home/brgen"
readonly APP_DIR="${BASE_DIR}/app"
readonly BRGEN_IP="185.52.176.18"
readonly BRGEN_PORT="11006"

SCRIPT_DIR="${0:a:h}"
source "${SCRIPT_DIR}/__shared/load_modules.sh"

log "BRGEN v${VERSION} - Rails 8 Complete Setup"

if [[ ! -d "$APP_DIR" ]]; then
  log "ERROR: $APP_DIR missing. Run: doas zsh openbsd.sh --pre-point"
  exit 1
fi

cd "$APP_DIR"
log "Working in: $APP_DIR"

if [[ ! -f "config/application.rb" ]]; then
  log "Creating Rails 8 application"
  rails new . --database=postgresql --skip-git --css=tailwind --javascript=esbuild
fi

log "Installing Rails 8 + PWA stack"
cat > Gemfile << 'GEMFILE'
source "https://rubygems.org"
ruby "3.3.0"

gem "rails", "~> 8.0"
gem "pg", "~> 1.5"
gem "puma", "~> 6.0"

# Rails 8 Solid Stack (Redis-free)
gem "solid_queue"
gem "solid_cache"
gem "solid_cable"

# Rails 8 Authentication
gem "bcrypt", "~> 3.1"

# Assets (Propshaft is default in Rails 8)
gem "propshaft"
gem "tailwindcss-rails"
gem "importmap-rails"

# Hotwire
gem "turbo-rails"
gem "stimulus-rails"

# StimulusReflex for real-time
gem "stimulus_reflex", "~> 3.5"
gem "cable_ready", "~> 5.0"

# Core features
gem "devise"
gem "devise-guests"
gem "acts_as_tenant"
gem "pagy"
gem "image_processing"

# Location
gem "geocoder"

# AI
gem "langchainrb"
gem "ruby-openai"

# PWA support
gem "serviceworker-rails"

gem "bootsnap", require: false

group :development, :test do
  gem "debug"
  gem "brakeman"
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "web-console"
end
GEMFILE

bundle install

end
GEMFILE
bundle install

# Setup Rails 8 Solid Stack
log "Configuring Rails 8 Solid Stack"
setup_rails8_solid_stack

# Setup Rails 8 authentication (built-in)
log "Installing Rails 8 authentication"
if [[ ! -f "app/models/session.rb" ]]; then
  bin/rails generate authentication
fi

# Configure database
log "Configuring PostgreSQL"
content=$(<config/database.yml)
content="${content//database: app_/database: brgen_}"
content="${content//username: brgen/username: brgen_user}"
print -r -- "$content" > config/database.yml

# Setup PWA
log "Setting up Progressive Web App"
setup_full_pwa "BRGEN"

# Setup StimulusReflex
log "Installing StimulusReflex"
bin/rails generate stimulus_reflex:install

# Generate models
log "Generating Rails 8 models"

# Community (multi-tenant parent)
bin/rails generate model Community name:string description:text subdomain:string:uniq slug:string:uniq

# User enhancements (Devise already created by setup_rails8_authentication)
bin/rails generate migration AddFieldsToUsers username:string karma:integer location:point

# Posts with karma
bin/rails generate model Post title:string content:text user:references community:references karma:integer:default[0] anonymous:boolean:default[false]

# Comments with threading
bin/rails generate model Comment content:text user:references commentable:references{polymorphic}:index parent_id:integer

# Votes (Reddit-style)
bin/rails generate model Vote value:integer user:references votable:references{polymorphic}:index

# Reactions (emoji-style)
bin/rails generate model Reaction kind:string user:references post:references

# Media streams (video/stories TikTok-style)
bin/rails generate model Stream content_type:string url:string user:references post:references duration:integer

# Run migrations
bin/rails db:migrate

# Configure models with concerns
log "Configuring models with concerns"

cat > app/models/community.rb << 'EOF'
class Community < ApplicationRecord

  has_many :posts, dependent: :destroy
  has_many :users
  validates :name, :subdomain, :slug, presence: true
  validates :subdomain, :slug, uniqueness: true

  before_validation :generate_slug
  private

  def generate_slug

    self.slug ||= name.parameterize if name.present?

  end
end
EOF
cat > app/models/post.rb << 'EOF'
class Post < ApplicationRecord

  include Votable
  include Commentable
  acts_as_tenant :community
  belongs_to :user

  belongs_to :community

  has_many :reactions, dependent: :destroy
  has_many :streams, dependent: :destroy
  has_many_attached :photos
  validates :content, presence: true
  validates :title, presence: true, length: { maximum: 300 }

  scope :hot, -> {
    left_joins(:votes)

      .group(:id)
      .order("SUM(COALESCE(votes.value, 0)) / POW(EXTRACT(EPOCH FROM (NOW() - posts.created_at)) / 3600 + 2, 1.5) DESC")
  }
  scope :top, -> { left_joins(:votes).group(:id).order("SUM(COALESCE(votes.value, 0)) DESC") }
  scope :new, -> { order(created_at: :desc) }
  def update_karma
    update_column(:karma, votes.sum(:value))

  end
end
EOF
cat > app/models/comment.rb << 'EOF'
class Comment < ApplicationRecord

  include Votable
  belongs_to :user
  belongs_to :commentable, polymorphic: true

  belongs_to :parent, class_name: "Comment", optional: true
  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy
  validates :content, presence: true, length: { minimum: 1, maximum: 10000 }
  def root?

    parent_id.nil?

  end
  def depth
    parent ? parent.depth + 1 : 0

  end
  scope :best, -> { left_joins(:votes).group(:id).order("SUM(COALESCE(votes.value, 0)) DESC") }
  scope :new, -> { order(created_at: :desc) }

end
EOF
cat > app/models/vote.rb << 'EOF'
class Vote < ApplicationRecord

  belongs_to :user
  belongs_to :votable, polymorphic: true
  validates :value, inclusion: { in: [-1, 1] }
  validates :user_id, uniqueness: { scope: [:votable_type, :votable_id] }

  after_commit :update_votable_karma
  private

  def update_votable_karma

    votable.update_karma if votable.respond_to?(:update_karma)

  end
end
EOF
# Create concerns
mkdir -p app/models/concerns

cat > app/models/concerns/votable.rb << 'EOF'
module Votable

  extend ActiveSupport::Concern
  included do
    has_many :votes, as: :votable, dependent: :destroy

  end
  def score
    votes.sum(:value)

  end
  def upvotes
    votes.where(value: 1).count

  end
  def downvotes
    votes.where(value: -1).count

  end
  def update_karma
    # Override in models that need it

  end
end
EOF
cat > app/models/concerns/commentable.rb << 'EOF'
module Commentable

  extend ActiveSupport::Concern
  included do
    has_many :comments, as: :commentable, dependent: :destroy

  end
  def comment_count
    comments.count

  end
end
EOF
# Generate controllers
log "Generating controllers"

bin/rails generate controller Communities index show
bin/rails generate controller Posts index show new create edit update destroy

bin/rails generate controller Comments create destroy
bin/rails generate controller Votes create destroy
# Generate StimulusReflex reflexes
log "Generating reflexes"

mkdir -p app/reflexes
cat > app/reflexes/posts_reflex.rb << 'EOF'

class PostsReflex < ApplicationReflex

  def upvote
    post = Post.find(element.dataset[:post_id])
    vote = post.votes.find_or_initialize_by(user: current_user)
    vote.value = 1
    vote.save
    morph :nothing
  end
  def downvote
    post = Post.find(element.dataset[:post_id])

    vote = post.votes.find_or_initialize_by(user: current_user)
    vote.value = -1
    vote.save
    morph :nothing
  end
end
EOF
# Setup InfiniteScroll for posts
generate_model_reflex "Post" "posts"

# Generate views with pure zsh heredocs
log "Generating views"

mkdir -p app/views/communities app/views/posts app/views/comments app/views/shared
cat > app/views/communities/index.html.erb << 'EOF'

<%= tag.section class: "communities" do %>

  <%= tag.header do %>
    <%= tag.h1 t("brgen.communities") %>
  <% end %>
  <%= tag.div class: "community-grid" do %>
    <% @communities.each do |community| %>

      <%= tag.article class: "community-card" do %>
        <%= link_to community_path(community) do %>
          <%= tag.h2 community.name %>
          <%= tag.p community.description %>
        <% end %>
      <% end %>
    <% end %>
  <% end %>
<% end %>
EOF
generate_crud_views "post" "posts"
# Routes

log "Configuring routes"

cat > config/routes.rb << 'EOF'
Rails.application.routes.draw do

  devise_for :users
  resources :communities, only: [:index, :show] do
    resources :posts, shallow: true

  end
  resources :posts do
    resources :comments, only: [:create, :destroy]

    member do
      post :upvote
      post :downvote
    end
  end
  resources :votes, only: [:create, :destroy]
  root "communities#index"

end

EOF
# Styles (single application.scss)
log "Generating styles"

cat > app/assets/stylesheets/application.scss << 'SCSS'
/* BRGEN - Minimalist Dark Theme */

/* Per master.json design principles */
:root {
  --color-bg: #0a0a0a;

  --color-surface: #1a1a1a;
  --color-text: #e8eaed;
  --color-text-dim: #9aa0a6;
  --color-primary: #8ab4f8;
  --color-upvote: #ff4500;
  --color-downvote: #7193ff;
  --spacing-unit: 8px;
  --border-radius: 8px;
}
* {
  box-sizing: border-box;

  margin: 0;
  padding: 0;
}
body {
  font-family: system-ui, -apple-system, sans-serif;

  background-color: var(--color-bg);
  color: var(--color-text);
  line-height: 1.6;
}
section {
  max-width: 1200px;

  margin: 0 auto;
  padding: calc(var(--spacing-unit) * 2);
}
header {
  margin-bottom: calc(var(--spacing-unit) * 3);

}
h1 {
  font-size: 2rem;

  margin-bottom: calc(var(--spacing-unit) * 2);
}
h2 {
  font-size: 1.5rem;

  margin-bottom: var(--spacing-unit);
}
article.post {
  background: var(--color-surface);

  border-radius: var(--border-radius);
  padding: calc(var(--spacing-unit) * 2);
  margin-bottom: calc(var(--spacing-unit) * 2);
  transition: transform 0.2s;
  &:hover {
    transform: translateY(-2px);

  }
  header {
    margin-bottom: var(--spacing-unit);

  }
  p {
    color: var(--color-text-dim);

    margin-bottom: var(--spacing-unit);
  }
}
.vote-buttons {
  display: flex;

  gap: calc(var(--spacing-unit) * 2);
  align-items: center;
  button {
    background: transparent;

    border: 1px solid var(--color-text-dim);
    color: var(--color-text);
    padding: var(--spacing-unit) calc(var(--spacing-unit) * 2);
    border-radius: calc(var(--border-radius) / 2);
    cursor: pointer;
    transition: all 0.2s;
    &.upvote:hover {
      border-color: var(--color-upvote);

      color: var(--color-upvote);
    }
    &.downvote:hover {
      border-color: var(--color-downvote);

      color: var(--color-downvote);
    }
  }
}
.community-grid {
  display: grid;

  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: calc(var(--spacing-unit) * 2);
}
.community-card {
  background: var(--color-surface);

  border-radius: var(--border-radius);
  padding: calc(var(--spacing-unit) * 2);
  transition: transform 0.2s;
  &:hover {
    transform: scale(1.02);

  }
  a {
    color: var(--color-text);

    text-decoration: none;
  }
}
form {
  background: var(--color-surface);

  padding: calc(var(--spacing-unit) * 2);
  border-radius: var(--border-radius);
  label {
    display: block;

    margin-bottom: var(--spacing-unit);
    font-weight: 600;
  }
  input[type="text"],
  textarea {

    width: 100%;
    padding: var(--spacing-unit);
    background: var(--color-bg);
    border: 1px solid var(--color-text-dim);
    border-radius: calc(var(--border-radius) / 2);
    color: var(--color-text);
    margin-bottom: calc(var(--spacing-unit) * 2);
  }
  textarea {
    min-height: 150px;

    resize: vertical;
  }
  button[type="submit"] {
    background: var(--color-primary);

    color: var(--color-bg);
    border: none;
    padding: calc(var(--spacing-unit) * 1.5) calc(var(--spacing-unit) * 3);
    border-radius: calc(var(--border-radius) / 2);
    font-weight: 600;
    cursor: pointer;
    transition: opacity 0.2s;
    &:hover {
      opacity: 0.9;

    }
  }
}
/* Mobile responsive */
@media (max-width: 768px) {

  section {
    padding: var(--spacing-unit);
  }
  .community-grid {
    grid-template-columns: 1fr;

  }
}
SCSS
# Generate Stimulus controllers
log "Generating Stimulus controllers"

generate_all_stimulus_controllers
mkdir -p app/javascript/controllers

cat > app/javascript/controllers/geo_controller.js << 'EOF'

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {

    if (!navigator.geolocation) return
    navigator.geolocation.getCurrentPosition(
      (position) => {

        const { latitude, longitude } = position.coords
        this.sendLocation(latitude, longitude)
      },
      (error) => console.error("Geolocation error:", error)
    )
  }
  sendLocation(lat, lon) {
    fetch(`/geo?lat=${lat}&lon=${lon}`, {

      headers: { "Accept": "application/json" }
    })
      .then(response => response.json())
      .then(data => console.log("Location set:", data))
  }
  disconnect() {
    // Cleanup

  }
}
EOF
# PWA setup
log "Setting up PWA"

setup_full_pwa "BRGEN"
# Seeds
log "Creating seed data"

cat > db/seeds.rb << 'EOF'
# BRGEN seed data

return unless Rails.env.development?
print "Creating communities...\n"

cities = ["Oslo", "Bergen", "Trondheim", "Stavanger", "Tromsø"]

cities.each do |city_name|

  Community.find_or_create_by!(

    name: "#{city_name} Community",
    subdomain: city_name.downcase,
    slug: city_name.parameterize
  ) do |community|
    community.description = "Local community for #{city_name}"
  end
end
print "Creating users...\n"
10.times do

  User.create!(

    email: Faker::Internet.email,
    password: "password123",
    password_confirmation: "password123",
    username: Faker::Internet.username,
    karma: rand(0..1000)
  )
end
print "Creating posts...\n"
Community.all.each do |community|

  20.times do

    post = community.posts.create!(
      title: Faker::Lorem.sentence(word_count: 5),
      content: Faker::Lorem.paragraphs(number: 3).join("\n\n"),
      user: User.all.sample,
      karma: rand(-50..500)
    )
    # Add random votes
    User.all.sample(rand(3..15)).each do |user|

      post.votes.create!(user: user, value: [-1, 1].sample)
    end
  end
end
print "Seed data created successfully!\n"
EOF

bin/rails db:seed
# I18n (Norwegian)

log "Setting up Norwegian locales"

cat > config/locales/nb.yml << 'EOF'
nb:

  brgen:
    app_name: "BRGEN"
    communities: "Lokalsamfunn"
    posts: "Innlegg"
    new_post: "Nytt innlegg"
    upvote: "Stem opp"
    downvote: "Stem ned"
    karma: "Karma"
    comments: "Kommentarer"
    add_comment: "Legg til kommentar"
    posted_by: "Postet av %{user}"
    edit: "Rediger"
    delete: "Slett"
    confirm_delete: "Er du sikker?"
EOF
# Create rc.d service for OpenBSD
log "Creating rc.d service script"

cat > /tmp/brgen_rc.sh << 'EOF'
#!/bin/ksh

# OpenBSD rc.d script for BRGEN
# Will be moved to /etc/rc.d/brgen by openbsd.sh
daemon_user="brgen"
daemon_execdir="/home/brgen/app"

daemon="/home/brgen/app/bin/rails"
daemon_flags="server -b 0.0.0.0 -p 11006 -e production"
daemon_timeout="60"
. /etc/rc.d/rc.subr
pexp="ruby.*bin/rails server.*-p 11006"

rc_bg=YES
rc_reload=NO
rc_cmd $1
EOF

log "BRGEN setup complete!"
log "Next steps:"

log "  1. Review config/database.yml"
log "  2. Test: bin/rails server -b 0.0.0.0 -p 11006"
log "  3. Deploy: doas zsh openbsd.sh --post-point"
