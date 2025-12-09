#!/usr/bin/env zsh
set -euo pipefail

# Blognet: Multi-blog platform with AI content generation

APP_NAME="blognet"
BASE_DIR="/home/dev/rails"
SERVER_IP="185.52.176.18"
APP_PORT=$((10000 + RANDOM % 10000))
SCRIPT_DIR="${0:a:h}"

source "${SCRIPT_DIR}/__shared/@common.sh"

gem "solid_queue"

gem "solid_cache"

gem "solid_cable"

gem "propshaft"

gem "turbo-rails"

gem "stimulus-rails"

gem "devise"

gem "devise-guests"

gem "acts_as_tenant"

gem "pagy"

gem "langchainrb_rails"

gem "rhino-editor"

gem "chartkick"

gem "geocoder"

group :development do
  gem "debug"

end

GEMFILE

bundle install
# Database with engagement_score per innovation_research_2024
bin/rails generate model Blog user:references title:string slug:string description:text published:boolean:default[false]

bin/rails generate model Post blog:references user:references title:string content:text engagement_score:integer:default[0] trending_score:float:default[0.0] published_at:datetime

bin/rails generate model Comment post:references user:references content:text

bin/rails generate model Like likeable:references{polymorphic}:index user:references

bin/rails generate model Share shareable:references{polymorphic}:index user:references platform:string

bin/rails db:migrate
# Models with social algorithms
cat > app/models/post.rb << 'RUBY'

class Post < ApplicationRecord

  belongs_to :blog

  belongs_to :user

  has_many :comments, dependent: :destroy

  has_many :likes, as: :likeable

  has_many :shares, as: :shareable

  validates :title, :content, presence: true
  scope :feed, -> { where(published_at: ..Time.current).order(engagement_score: :desc, published_at: :desc) }
  scope :trending, -> { where('trending_score > ?', 0).order(trending_score: :desc) }

  def calculate_engagement!
    score = (likes.count * 2) + (comments.count * 5) + (shares.count * 10)

    recency = [(Time.current - published_at) / 1.hour, 168].min

    trending = score / (recency + 2.0)**1.5

    update_columns(engagement_score: score, trending_score: trending)
  end

end

RUBY

cat > app/models/blog.rb << 'RUBY'
class Blog < ApplicationRecord

  belongs_to :user

  has_many :posts, dependent: :destroy

  validates :title, :slug, presence: true
  validates :slug, uniqueness: true

  before_validation :generate_slug
  private
  def generate_slug

    self.slug ||= title&.parameterize

  end

end

RUBY

cat > app/models/comment.rb << 'RUBY'
class Comment < ApplicationRecord

  belongs_to :post

  belongs_to :user

  validates :content, presence: true
  after_create :bump_engagement
  private
  def bump_engagement

    post.calculate_engagement!

  end

end

RUBY

# Controllers with feed optimization
cat > app/controllers/feed_controller.rb << 'RUBY'

class FeedController < ApplicationController

  def index

    @posts = Post.feed.includes(:user, :blog, :likes, :comments)

                     .page(params[:page])

  end

  def trending
    @posts = Post.trending.includes(:user, :blog)

                          .page(params[:page])

  end

end

RUBY

cat > app/controllers/posts_controller.rb << 'RUBY'
class PostsController < ApplicationController

  before_action :authenticate_user!, except: [:index, :show]

  before_action :set_post, only: [:show, :edit, :update, :destroy]

  def index
    @posts = Post.feed.page(params[:page])

  end

  def show
  end

  def new
    @post = current_user.posts.build

  end

  def create
    @post = current_user.posts.build(post_params)

    if @post.save

      redirect_to @post, notice: 'Post created'

    else

      render :new, status: :unprocessable_entity

    end

  end

  def edit
  end

  def update
    if @post.update(post_params)

      redirect_to @post, notice: 'Post updated'

    else

      render :edit, status: :unprocessable_entity

    end

  end

  def destroy
    @post.destroy

    redirect_to posts_path, notice: 'Post deleted'

  end

  private
  def set_post

    @post = Post.find(params[:id])

  end

  def post_params
    params.require(:post).permit(:blog_id, :title, :content, :published_at)

  end

end

RUBY

# Modern CSS with container queries + typography
cat > app/assets/stylesheets/application.scss << 'SCSS'

@import url('https://fonts.googleapis.com/css2?family=Fugaz+One&family=Work+Sans:wght@300;400;600&display=swap');

:root {
  --font-heading: 'Fugaz One', sans-serif;

  --font-body: 'Work Sans', sans-serif;

  --color-primary: #0066ff;

  --color-bg: #ffffff;

  --color-text: #1a1a1a;

}

* {
  margin: 0;

  padding: 0;

  box-sizing: border-box;

}

body {
  font-family: var(--font-body);

  font-size: clamp(1rem, 2vw, 1.125rem);

  line-height: 1.6;

  color: var(--color-text);

  background: var(--color-bg);

}

h1, h2, h3, h4, h5, h6 {
  font-family: var(--font-heading);

  line-height: 1.2;

}

.feed {
  display: grid;

  grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));

  gap: 1.5rem;

  max-width: 1200px;

  margin: 0 auto;

  padding: 2rem 1rem;

}

.posts {
  container-type: inline-size;

  container-name: posts-grid;

}

.post-card {
  background: white;

  border-radius: 12px;

  padding: 1.5rem;

  box-shadow: 0 2px 8px rgba(0,0,0,0.08);

  transition: transform 0.2s, box-shadow 0.2s;

}

.post-card:hover {
  transform: translateY(-2px);

  box-shadow: 0 4px 16px rgba(0,0,0,0.12);

}

@container posts-grid (width > 60ch) {
  .post-card {

    display: flex;

    flex-direction: row;

    gap: 1.5rem;

  }

}

.post-card:has(.comment) {
  border-left: 4px solid var(--color-primary);

}

SCSS

# Sidekiq job for engagement calculation
cat > app/jobs/calculate_engagement_job.rb << 'RUBY'

class CalculateEngagementJob < ApplicationJob

  queue_as :default

  def perform
    Post.where('published_at < ?', 1.hour.ago).find_each do |post|

      post.calculate_engagement!

    end

  end

end

RUBY

# Routes
cat > config/routes.rb << 'RUBY'

Rails.application.routes.draw do

  devise_for :users

  root "feed#index"
  resources :feed, only: [:index] do
    collection do

      get :trending

    end

  end

  resources :blogs do
    resources :posts

  end

  resources :posts do
    resources :comments, only: [:create, :destroy]

    member do

      post :like

      post :share

    end

  end

end

RUBY

# PWA manifest
cat > public/manifest.json << 'JSON'

{

  "name": "Blognet",

  "short_name": "Blognet",

  "description": "AI-powered social blogging platform",

  "start_url": "/",

  "display": "standalone",

  "background_color": "#ffffff",

  "theme_color": "#0066ff",

  "icons": [

    {

      "src": "/icon-192.png",

      "sizes": "192x192",

      "type": "image/png"

    },

    {

      "src": "/icon-512.png",

      "sizes": "512x512",

      "type": "image/png"

    }

  ]

}

JSON

# Service worker
cat > public/service-worker.js << 'JS'

const CACHE_NAME = 'blognet-v1';

const urlsToCache = [

  '/',

  '/assets/application.css',

  '/assets/application.js',

  '/offline.html'

];

self.addEventListener('install', event => {
  event.waitUntil(

    caches.open(CACHE_NAME).then(cache => cache.addAll(urlsToCache))

  );

});

self.addEventListener('fetch', event => {
  event.respondWith(

    caches.match(event.request).then(response => {

      return response || fetch(event.request).then(networkResponse => {

        return caches.open('dynamic-cache').then(cache => {

          cache.put(event.request, networkResponse.clone());

          return networkResponse;

        });

      }).catch(() => caches.match('/offline.html'));

    })

  );

});

JS

log "✓ Blognet v${VERSION} complete: social feed + PWA + container queries + engagement scoring"
