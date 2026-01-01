#!/usr/bin/env zsh
set -euo pipefail

# BRGEN v3.0.0 - Rails 8 Complete Social Network
# Per master.yml v59.2.0
# Self-contained generator using modern zsh patterns

readonly VERSION="3.0.0"
readonly APP_DIR="/home/brgen/app"

echo "==> BRGEN v${VERSION} - Rails 8 Complete Setup"

# === VALIDATION ===

if [[ ! -d "$APP_DIR" ]]; then
  echo "ERROR: $APP_DIR missing. Run: doas zsh openbsd.sh --pre-point"
  exit 1
fi

cd "$APP_DIR"
echo "Working in: $APP_DIR"

# === RAILS APP CREATION ===

if [[ ! -f "config/application.rb" ]]; then
  echo "Creating Rails 8 application"
  rails new . --database=postgresql --skip-git --css=tailwind --javascript=esbuild
fi

echo "Appending gems to Gemfile"
cat >> Gemfile << 'GEMFILE'

# Rails 8 Solid Stack
gem "solid_queue"
gem "solid_cache"
gem "solid_cable"

# Authentication
gem "bcrypt", "~> 3.1"

# Real-time
gem "stimulus_reflex", "~> 3.5"
gem "cable_ready", "~> 5.0"

# Multi-tenancy
gem "devise"
gem "devise-guests"
gem "acts_as_tenant"

# Features
gem "pagy"
gem "image_processing"
gem "geocoder"
gem "langchainrb"
gem "ruby-openai"
gem "serviceworker-rails"

group :development, :test do
  gem "brakeman"
  gem "rubocop-rails-omakase"
  gem "faker"
end
GEMFILE

bundle install

# === SOLID STACK SETUP ===

echo "Installing Solid Stack"
bin/rails generate solid_queue:install
bin/rails generate solid_cache:install
bin/rails generate solid_cable:install

# === AUTHENTICATION ===

echo "Installing Rails 8 authentication"
[[ ! -f "app/models/session.rb" ]] && bin/rails generate authentication

# === DATABASE CONFIGURATION ===

echo "Configuring PostgreSQL"
config=$(<config/database.yml)
config=${config//database: app_/database: brgen_}
config=${config//username: brgen/username: brgen_user}
print -r -- "$config" > config/database.yml

# === CORE MODELS ===

echo "Generating models"

typeset -a models
models=(
  "Community name:string description:text subdomain:string:uniq slug:string:uniq"
  "Post title:string content:text user:references community:references karma:integer:default[0] anonymous:boolean:default[false]"
  "Comment content:text user:references commentable:references{polymorphic}:index parent_id:integer"
  "Vote value:integer user:references votable:references{polymorphic}:index"
  "Reaction kind:string user:references post:references"
  "Stream content_type:string url:string user:references post:references duration:integer"
)

for model_spec in $models; do
  bin/rails generate model ${=model_spec}
done

bin/rails generate migration AddFieldsToUsers username:string karma:integer location:point

bin/rails db:migrate

# === MODEL CONCERNS ===

echo "Creating model concerns"

mkdir -p app/models/concerns

cat > app/models/concerns/votable.rb << 'RUBY'
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
end
RUBY

cat > app/models/concerns/commentable.rb << 'RUBY'
module Commentable
  extend ActiveSupport::Concern
  
  included do
    has_many :comments, as: :commentable, dependent: :destroy
  end
  
  def comment_count
    comments.count
  end
end
RUBY

# === MODEL OVERRIDES ===

cat > app/models/community.rb << 'RUBY'
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
RUBY

cat > app/models/post.rb << 'RUBY'
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
  scope :new_first, -> { order(created_at: :desc) }
  
  def update_karma
    update_column(:karma, votes.sum(:value))
  end
end
RUBY

cat > app/models/comment.rb << 'RUBY'
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
  scope :new_first, -> { order(created_at: :desc) }
end
RUBY

cat > app/models/vote.rb << 'RUBY'
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
RUBY

# === ROUTES ===

echo "Configuring routes"

cat > config/routes.rb << 'RUBY'
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
RUBY

# === CONTROLLERS ===

echo "Generating controllers"

typeset -a controllers
controllers=(
  "Communities index show"
  "Posts index show new create edit update destroy"
  "Comments create destroy"
  "Votes create destroy"
)

for controller_spec in $controllers; do
  bin/rails generate controller ${=controller_spec}
done

# === VIEWS ===

echo "Creating views"

mkdir -p app/views/{communities,posts,comments,shared}

cat > app/views/communities/index.html.erb << 'ERB'
<section class="communities">
  <header>
    <h1><%= t("brgen.communities") %></h1>
  </header>
  
  <div class="community-grid">
    <% @communities.each do |community| %>
      <article class="community-card">
        <%= link_to community_path(community) do %>
          <h2><%= community.name %></h2>
          <p><%= community.description %></p>
        <% end %>
      </article>
    <% end %>
  </div>
</section>
ERB

# === STYLES ===

echo "Creating styles"

cat > app/assets/stylesheets/application.scss << 'SCSS'
/* BRGEN - Minimalist Dark Theme */

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
  
  &:hover {
    transform: translateY(-2px);
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

@media (max-width: 768px) {
  section {
    padding: var(--spacing-unit);
  }
  
  .community-grid {
    grid-template-columns: 1fr;
  }
}
SCSS

# === PWA MANIFEST ===

echo "Creating PWA manifest"

mkdir -p public
cat > public/manifest.json << 'JSON'
{
  "name": "BRGEN",
  "short_name": "BRGEN",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#0a0a0a",
  "theme_color": "#8ab4f8",
  "icons": []
}
JSON

# === SEEDS ===

echo "Creating seed data"

cat > db/seeds.rb << 'RUBY'
return unless Rails.env.development?

puts "Creating communities..."
%w[Oslo Bergen Trondheim Stavanger Tromsø].each do |city|
  Community.find_or_create_by!(
    name: "#{city} Community",
    subdomain: city.downcase,
    slug: city.parameterize
  ) do |c|
    c.description = "Local community for #{city}"
  end
end

puts "Creating users..."
10.times do
  User.create!(
    email: Faker::Internet.email,
    password: "password123",
    password_confirmation: "password123",
    username: Faker::Internet.username,
    karma: rand(0..1000)
  )
end

puts "Creating posts..."
Community.all.each do |community|
  20.times do
    post = community.posts.create!(
      title: Faker::Lorem.sentence(word_count: 5),
      content: Faker::Lorem.paragraphs(number: 3).join("\n\n"),
      user: User.all.sample,
      karma: rand(-50..500)
    )
    
    # Add votes
    User.all.sample(rand(3..15)).each do |user|
      post.votes.create!(user: user, value: [-1, 1].sample)
    end
  end
end

puts "Seed data created!"
RUBY

bin/rails db:seed

# === I18N ===

echo "Setting up Norwegian locales"

cat > config/locales/nb.yml << 'YAML'
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
YAML

# === DEPLOYMENT ===

echo "Creating OpenBSD rc.d service"

cat > /tmp/brgen_rc.sh << 'RCSH'
#!/bin/ksh
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
RCSH

echo "==> BRGEN setup complete!"
echo "Next steps:"
echo "  1. Review config/database.yml"
echo "  2. Test: bin/rails server -b 0.0.0.0 -p 11006"
echo "  3. Deploy: doas zsh openbsd.sh --post-point"
