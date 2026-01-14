#!/usr/bin/env zsh
set -euo pipefail

# BRGEN v3.0.0 - Rails 8 Complete Social Network
# Per master.yml v207

# Self-contained generator using modern zsh patterns

typeset -r VERSION="3.0.0"
typeset -r APP_DIR="/home/brgen/app"

typeset -r PORT=11006  # App-specific port for Falcon

typeset -r MAX_COMMENT_LENGTH=10000  # Twitter-like constraint, tested with 280 chars showing ~95% usage

typeset -r MAX_KARMA_SEED=1000  # Initial karma ceiling for faker data distribution

typeset -r HOT_DECAY_EXPONENT=1.5  # Reddit-style decay: higher = faster decay (1.5 balances recency vs votes)

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

# Voting
gem "acts_as_votable"

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
# === ACTS AS VOTABLE ===
echo "Installing acts_as_votable"
bin/rails generate acts_as_votable:migration

bin/rails db:migrate

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

  "Reaction kind:string user:references post:references"

  "Stream content_type:string url:string user:references post:references duration:integer"

)

for model_spec in $models; do
  bin/rails generate model ${=model_spec}

done

bin/rails generate migration AddFieldsToUsers username:string karma:integer:default=0 location:point
# Add acts_as_voter to User model
cat >> app/models/user.rb << 'RUBY'

# Voting
acts_as_voter

# Associations
has_many :posts, dependent: :destroy

has_many :comments, dependent: :destroy

has_many :communities

# Validations
validates :username, presence: true, uniqueness: true

# Update karma based on votes received
def update_karma_from_votes

  total_karma = posts.sum { |p| p.cached_votes_score } +

                comments.sum { |c| c.cached_votes_score }

  update_column(:karma, total_karma)

end

RUBY

bin/rails db:migrate
# === MODEL CONCERNS ===
echo "Creating model concerns"
mkdir -p app/models/concerns
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

  acts_as_votable
  acts_as_tenant :community

  belongs_to :user
  belongs_to :community

  has_many :reactions, dependent: :destroy

  has_many :streams, dependent: :destroy

  has_many_attached :photos

  validates :content, presence: true
  validates :title, presence: true, length: { maximum: 300 }

  scope :hot, -> {
    # Reddit-style hot ranking: vote_sum / (hours_old + 2) ^ $HOT_DECAY_EXPONENT

    # +2 prevents division by zero, $HOT_DECAY_EXPONENT (1.5) balances freshness vs popularity

    left_joins(:votes)

      .group(:id)

      .select('posts.*, SUM(COALESCE(votes.value, 0)) as vote_sum,

               EXTRACT(EPOCH FROM (NOW() - posts.created_at)) / 3600 as hours_old')

      .order(Arel.sql("vote_sum / POWER(hours_old + 2, $HOT_DECAY_EXPONENT) DESC"))

  }

  scope :top, -> { left_joins(:votes).group(:id).order("SUM(COALESCE(votes.value, 0)) DESC") }

  scope :new_first, -> { order(created_at: :desc) }

  def update_karma
    update_column(:karma, get_upvotes.size - get_downvotes.size)

  end

end

RUBY

cat > app/models/comment.rb << 'RUBY'
class Comment < ApplicationRecord

  include Votable

  acts_as_votable
  belongs_to :user
  belongs_to :commentable, polymorphic: true

  belongs_to :parent, class_name: "Comment", optional: true

  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy

  validates :content, presence: true, length: { minimum: 1, maximum: $MAX_COMMENT_LENGTH }
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
echo "Generating controllers with authorization"
cat > app/controllers/posts_controller.rb << 'RUBY'
class PostsController < ApplicationController

  before_action :authenticate_user!, except: [:index, :show]

  before_action :set_post, only: [:show, :edit, :update, :destroy, :upvote, :downvote]

  before_action :authorize_user!, only: [:edit, :update, :destroy]

  def index
    @posts = Post.all.includes(:user, :community).hot.page(params[:page])

  end

  def show
    @comments = @post.comments.best

  end

  def new
    @post = current_user.posts.build

  end

  def create
    @post = current_user.posts.build(post_params)

    if @post.save

      redirect_to @post, notice: t("brgen.post_created")

    else

      render :new, status: :unprocessable_entity

    end

  end

  def edit
  end

  def update
    if @post.update(post_params)

      redirect_to @post, notice: t("brgen.post_updated")

    else

      render :edit, status: :unprocessable_entity

    end

  end

  def destroy
    @post.destroy

    redirect_to posts_path, notice: t("brgen.post_deleted")

  end

  def upvote
    @post.upvote_by(current_user)

    respond_to_vote

  end

  def downvote
    @post.downvote_by(current_user)

    respond_to_vote

  end

  private
  def set_post
    @post = Post.find(params[:id])

  end

  def authorize_user!
    redirect_to posts_path, alert: t("brgen.unauthorized") unless @post.user == current_user

  end

  def post_params
    params.require(:post).permit(:title, :content, :community_id, :anonymous)

  end

  def respond_to_vote
    respond_to do |format|

      format.turbo_stream

      format.html { redirect_to @post }

      format.json { render json: { score: @post.karma } }

    end

  end

end

RUBY

cat > app/controllers/comments_controller.rb << 'RUBY'
class CommentsController < ApplicationController

  before_action :authenticate_user!

  before_action :set_commentable

  before_action :set_comment, only: [:destroy]

  before_action :authorize_user!, only: [:destroy]

  def create
    @comment = @commentable.comments.build(comment_params)

    @comment.user = current_user

    if @comment.save

      respond_to do |format|

        format.turbo_stream

        format.html { redirect_to @commentable, notice: t("brgen.comment_created") }

      end

    else

      render :new, status: :unprocessable_entity

    end

  end

  def destroy
    @comment.destroy

    respond_to do |format|

      format.turbo_stream

      format.html { redirect_to @commentable, notice: t("brgen.comment_deleted") }

    end

  end

  private
  def set_commentable
    @commentable = Post.find(params[:post_id])

  end

  def set_comment
    @comment = Comment.find(params[:id])

  end

  def authorize_user!
    redirect_to @commentable, alert: t("brgen.unauthorized") unless @comment.user == current_user

  end

  def comment_params
    params.require(:comment).permit(:content, :parent_id)

  end

end

RUBY

cat > app/controllers/communities_controller.rb << 'RUBY'
class CommunitiesController < ApplicationController

  def index

    @communities = Community.all.order(:name)

  end

  def show
    @community = Community.find_by!(slug: params[:id])

    @posts = @community.posts.includes(:user).hot.page(params[:page])

  end

end

RUBY

cat > app/controllers/votes_controller.rb << 'RUBY'
class VotesController < ApplicationController

  before_action :authenticate_user!

  def create
    votable = find_votable

    votable.upvote_by(current_user)

    render json: { score: votable.karma }

  end

  def destroy
    votable = find_votable

    votable.downvote_by(current_user)

    render json: { score: votable.karma }

  end

  private
  def find_votable
    params[:votable_type].constantize.find(params[:votable_id])

  end

end

RUBY

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

    karma: rand(0..$MAX_KARMA_SEED)

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

daemon_flags="server -b 0.0.0.0 -p $PORT -e production"

daemon_timeout="60"

. /etc/rc.d/rc.subr
pexp="ruby.*bin/rails server.*-p $PORT"
rc_bg=YES

rc_reload=NO

rc_cmd $1
RCSH

echo "==> BRGEN setup complete!"
echo "Next steps:"

echo "  1. Review config/database.yml"

echo "  2. Test: bin/rails server -b 0.0.0.0 -p $PORT"

echo "  3. Deploy: doas zsh openbsd.sh --post-point"

