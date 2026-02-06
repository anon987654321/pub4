#!/usr/bin/env zsh
set -euo pipefail

# Blognet: Multi-blog platform with AI content generation

APP_NAME="blognet"

BASE_DIR="/home/dev/rails"

SERVER_IP="185.52.176.18"

APP_PORT=$((10000 + RANDOM % 10000))

SCRIPT_DIR="${0:a:h}"

source "${SCRIPT_DIR}/@shared_functions.sh"

# Idempotency: skip if already generated

check_app_exists "$APP_NAME" "app/models/blog.rb" && exit 0

setup_full_app "$APP_NAME"

cat >> Gemfile << 'GEMFILE'
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

  before_action :authorize_user!, only: [:edit, :update, :destroy]

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

  def authorize_user!
    redirect_to posts_path, alert: 'Unauthorized' unless @post.user == current_user || current_user&.admin?

  end

  def post_params
    params.require(:post).permit(:blog_id, :title, :content, :published_at)

  end

end

RUBY

# Additional controllers
cat > app/controllers/comments_controller.rb << 'RUBY'

class CommentsController < ApplicationController

  before_action :authenticate_user!

  before_action :set_post

  before_action :set_comment, only: [:destroy]

  before_action :authorize_user!, only: [:destroy]

  def create
    @comment = @post.comments.build(comment_params)

    @comment.user = current_user

    if @comment.save

      redirect_to @post, notice: 'Comment added'

    else

      redirect_to @post, alert: 'Could not add comment'

    end

  end

  def destroy
    @comment.destroy

    redirect_to @post, notice: 'Comment deleted'

  end

  private
  def set_post
    @post = Post.find(params[:post_id])

  end

  def set_comment
    @comment = Comment.find(params[:id])

  end

  def authorize_user!
    redirect_to @post, alert: 'Unauthorized' unless @comment.user == current_user

  end

  def comment_params
    params.require(:comment).permit(:content)

  end

end

RUBY

cat > app/controllers/likes_controller.rb << 'RUBY'
class LikesController < ApplicationController

  before_action :authenticate_user!

  def create
    @likeable = find_likeable

    @like = @likeable.likes.build(user: current_user)

    if @like.save

      @likeable.calculate_engagement! if @likeable.respond_to?(:calculate_engagement!)

      redirect_back fallback_location: root_path, notice: 'Liked'

    else

      redirect_back fallback_location: root_path, alert: 'Could not like'

    end

  end

  private
  def find_likeable
    params[:likeable_type].constantize.find(params[:likeable_id])

  end

end

RUBY

cat > app/controllers/shares_controller.rb << 'RUBY'
class SharesController < ApplicationController

  before_action :authenticate_user!

  def create
    @shareable = find_shareable

    @share = @shareable.shares.build(user: current_user, platform: params[:platform])

    if @share.save

      @shareable.calculate_engagement! if @shareable.respond_to?(:calculate_engagement!)

      redirect_back fallback_location: root_path, notice: 'Shared'

    else

      redirect_back fallback_location: root_path, alert: 'Could not share'

    end

  end

  private
  def find_shareable
    params[:shareable_type].constantize.find(params[:shareable_id])

  end

end

RUBY

cat > app/controllers/blogs_controller.rb << 'RUBY'
class BlogsController < ApplicationController

  before_action :authenticate_user!, except: [:index, :show]

  before_action :set_blog, only: [:show, :edit, :update, :destroy]

  before_action :authorize_user!, only: [:edit, :update, :destroy]

  def index
    @blogs = Blog.all.order(created_at: :desc)

  end

  def show
    @posts = @blog.posts.where('published_at <= ?', Time.current).order(published_at: :desc)

  end

  def new
    @blog = current_user.blogs.build

  end

  def create
    @blog = current_user.blogs.build(blog_params)

    if @blog.save

      redirect_to @blog, notice: 'Blog created'

    else

      render :new, status: :unprocessable_entity

    end

  end

  def edit
  end

  def update
    if @blog.update(blog_params)

      redirect_to @blog, notice: 'Blog updated'

    else

      render :edit, status: :unprocessable_entity

    end

  end

  def destroy
    @blog.destroy

    redirect_to blogs_path, notice: 'Blog deleted'

  end

  private
  def set_blog
    @blog = Blog.find_by!(slug: params[:id]) || Blog.find(params[:id])

  end

  def authorize_user!
    redirect_to blogs_path, alert: 'Unauthorized' unless @blog.user == current_user

  end

  def blog_params
    params.require(:blog).permit(:title, :description)

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

  end

  resources :likes, only: [:create]
  resources :shares, only: [:create]

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

# === VIEWS ===
log "Creating views"
mkdir -p app/views/{posts,feed,shared,layouts}

# Application layout
cat > app/views/layouts/application.html.erb << 'LAYOUT_EOF'

<!DOCTYPE html>

<html lang="en">

<head>

  <meta charset="utf-8">

  <meta name="viewport" content="width=device-width,initial-scale=1">

  <title><%= content_for?(:title) ? yield(:title) + " - Blognet" : "Blognet - Multi-Blog Platform" %></title>

  <%= csrf_meta_tags %>

  <%= csp_meta_tag %>

  <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>

  <%= javascript_importmap_tags %>

</head>

<body>

  <%= render "shared/header" %>

  <% if notice.present? %>

    <div class="notice"><%= notice %></div>

  <% end %>

  <% if alert.present? %>

    <div class="alert"><%= alert %></div>

  <% end %>

  <main>

    <%= yield %>

  </main>

  <%= render "shared/footer" %>

</body>

</html>

LAYOUT_EOF

# Shared header
cat > app/views/shared/_header.html.erb << 'HEADER_EOF'

<header class="site-header">

  <div class="container">

    <%= link_to "Blognet", root_path, class: "logo" %>

    <nav>

      <%= link_to "Feed", feed_index_path, class: "nav-link" %>

      <%= link_to "Trending", trending_feed_index_path, class: "nav-link" %>

      <% if user_signed_in? %>

        <%= link_to "My Posts", posts_path, class: "nav-link" %>

        <%= link_to "New Post", new_post_path, class: "btn btn-primary" %>

        <%= link_to "Sign Out", destroy_user_session_path, method: :delete, class: "nav-link" %>

      <% else %>

        <%= link_to "Sign In", new_user_session_path, class: "nav-link" %>

        <%= link_to "Sign Up", new_user_registration_path, class: "btn btn-primary" %>

      <% end %>

    </nav>

  </div>

</header>

HEADER_EOF

# Shared footer
cat > app/views/shared/_footer.html.erb << 'FOOTER_EOF'

<footer class="site-footer">

  <div class="container">

    <p>&copy; <%= Time.current.year %> Blognet. Multi-blog platform with AI content generation.</p>

  </div>

</footer>

FOOTER_EOF

# Feed index
cat > app/views/feed/index.html.erb << 'FEED_INDEX_EOF'

<div class="container">

  <h1>Feed</h1>

  <div class="posts-feed">

    <% @posts.each do |post| %>

      <%= render "posts/post_card", post: post %>

    <% end %>

  </div>

  <%= render "shared/pagination", pagy: @pagy if defined?(@pagy) %>

</div>

FEED_INDEX_EOF

# Feed trending
cat > app/views/feed/trending.html.erb << 'FEED_TRENDING_EOF'

<div class="container">

  <h1>Trending Posts</h1>

  <div class="posts-feed">

    <% @posts.each do |post| %>

      <%= render "posts/post_card", post: post %>

    <% end %>

  </div>

  <%= render "shared/pagination", pagy: @pagy if defined?(@pagy) %>

</div>

FEED_TRENDING_EOF

# Posts index
cat > app/views/posts/index.html.erb << 'POSTS_INDEX_EOF'

<div class="container">

  <div class="page-header">

    <h1>My Posts</h1>

    <%= link_to "New Post", new_post_path, class: "btn btn-primary" %>

  </div>

  <div class="posts-list">

    <% @posts.each do |post| %>

      <div class="post-item">

        <h3><%= link_to post.title, post_path(post) %></h3>

        <div class="post-meta">

          <span>Blog: <%= post.blog.title %></span>

          <span>Engagement: <%= post.engagement_score %></span>

          <span>Published: <%= post.published_at&.strftime("%B %d, %Y") || "Draft" %></span>

        </div>

        <div class="post-actions">

          <%= link_to "Edit", edit_post_path(post), class: "btn-link" %>

          <%= button_to "Delete", post_path(post), method: :delete,

              data: { confirm: "Delete this post?" }, class: "btn-link danger" %>

        </div>

      </div>

    <% end %>

  </div>

</div>

POSTS_INDEX_EOF

# Posts show
cat > app/views/posts/show.html.erb << 'POSTS_SHOW_EOF'

<article class="post-detail">

  <div class="container">

    <header class="post-header">

      <h1><%= @post.title %></h1>

      <div class="post-meta">

        <span class="author">By <%= @post.user.email %></span>

        <span class="blog">in <%= link_to @post.blog.title, blog_path(@post.blog) %></span>

        <span class="date"><%= @post.published_at&.strftime("%B %d, %Y") %></span>

        <span class="engagement">💬 <%= @post.comments.count %> 👍 <%= @post.likes.count %> 🔗 <%= @post.shares.count %></span>

      </div>

    </header>

    <div class="post-content">
      <%= simple_format(@post.content) %>

    </div>

    <div class="post-actions">
      <%= button_to "👍 Like", likes_path(likeable_type: "Post", likeable_id: @post.id), method: :post, class: "btn btn-icon" %>

      <%= button_to "🔗 Share", shares_path(shareable_type: "Post", shareable_id: @post.id, platform: "twitter"), method: :post, class: "btn btn-icon" %>

      <% if current_user == @post.user %>

        <%= link_to "Edit", edit_post_path(@post), class: "btn btn-secondary" %>

        <%= button_to "Delete", post_path(@post), method: :delete,

            data: { confirm: "Delete this post?" }, class: "btn btn-danger" %>

      <% end %>

    </div>

    <section class="comments">
      <h2>Comments (<%= @post.comments.count %>)</h2>

      <% if user_signed_in? %>

        <%= render "comments/form", post: @post %>

      <% else %>

        <p><%= link_to "Sign in", new_user_session_path %> to comment</p>

      <% end %>

      <div class="comments-list">
        <% @post.comments.order(created_at: :desc).each do |comment| %>

          <%= render "comments/comment", comment: comment %>

        <% end %>

      </div>

    </section>

  </div>

</article>

POSTS_SHOW_EOF

# Posts new
cat > app/views/posts/new.html.erb << 'POSTS_NEW_EOF'

<div class="container">

  <h1>New Post</h1>

  <%= render "form", post: @post %>

</div>

POSTS_NEW_EOF

# Posts edit
cat > app/views/posts/edit.html.erb << 'POSTS_EDIT_EOF'

<div class="container">

  <h1>Edit Post</h1>

  <%= render "form", post: @post %>

</div>

POSTS_EDIT_EOF

# Posts form
cat > app/views/posts/_form.html.erb << 'POSTS_FORM_EOF'

<%= form_with(model: post, local: true, class: "post-form") do |f| %>

  <% if post.errors.any? %>

    <div class="error-messages">

      <h3><%= pluralize(post.errors.count, "error") %> prevented this post from being saved:</h3>

      <ul>

        <% post.errors.full_messages.each do |message| %>

          <li><%= message %></li>

        <% end %>

      </ul>

    </div>

  <% end %>

  <div class="form-group">
    <%= f.label :blog_id, "Blog" %>

    <%= f.collection_select :blog_id, current_user.blogs, :id, :title,

        { prompt: "Select a blog" }, class: "form-select", required: true %>

    <%= link_to "Create new blog", new_blog_path, class: "btn-link" %>

  </div>

  <div class="form-group">
    <%= f.label :title %>

    <%= f.text_field :title, class: "form-control", placeholder: "Enter post title", required: true %>

  </div>

  <div class="form-group">
    <%= f.label :content %>

    <%= f.text_area :content, rows: 15, class: "form-control", placeholder: "Write your post...", required: true %>

  </div>

  <div class="form-group">
    <%= f.label :published_at, "Publish Date (leave blank for draft)" %>

    <%= f.datetime_field :published_at, class: "form-control" %>

  </div>

  <div class="form-actions">
    <%= f.submit "Save Post", class: "btn btn-primary" %>

    <%= link_to "Cancel", posts_path, class: "btn btn-secondary" %>

  </div>

<% end %>

POSTS_FORM_EOF

# Post card partial
cat > app/views/posts/_post_card.html.erb << 'POST_CARD_EOF'

<article class="post-card">

  <header>

    <h2><%= link_to post.title, post_path(post) %></h2>

    <div class="post-meta">

      <span class="author"><%= post.user.email %></span>

      <span class="blog"><%= link_to post.blog.title, blog_path(post.blog) %></span>

      <span class="date"><%= post.published_at&.strftime("%B %d, %Y") %></span>

    </div>

  </header>

  <div class="post-excerpt">

    <%= truncate(post.content, length: 200) %>

  </div>

  <footer>

    <div class="post-stats">

      <span>💬 <%= post.comments.count %></span>

      <span>👍 <%= post.likes.count %></span>

      <span>📈 <%= post.engagement_score %></span>

      <% if post.trending_score > 0 %>

        <span class="trending">🔥 Trending</span>

      <% end %>

    </div>

    <%= link_to "Read more →", post_path(post), class: "read-more" %>

  </footer>

</article>

POST_CARD_EOF

# Comments partial
mkdir -p app/views/comments

cat > app/views/comments/_form.html.erb << 'COMMENT_FORM_EOF'

<%= form_with(model: [post, Comment.new], local: true, class: "comment-form") do |f| %>

  <div class="form-group">

    <%= f.text_area :content, rows: 3, class: "form-control",

        placeholder: "Add a comment...", required: true %>

  </div>

  <%= f.submit "Post Comment", class: "btn btn-primary" %>

<% end %>

COMMENT_FORM_EOF

cat > app/views/comments/_comment.html.erb << 'COMMENT_EOF'
<div class="comment">

  <div class="comment-author"><%= comment.user.email %></div>

  <div class="comment-content"><%= simple_format(comment.content) %></div>

  <div class="comment-meta">

    <%= comment.created_at.strftime("%B %d, %Y at %I:%M %p") %>

    <% if current_user == comment.user %>

      <%= button_to "Delete", comment_path(comment), method: :delete,

          data: { confirm: "Delete this comment?" }, class: "btn-link danger" %>

    <% end %>

  </div>

</div>

COMMENT_EOF

# Pagination partial
cat > app/views/shared/_pagination.html.erb << 'PAGINATION_EOF'

<% if defined?(pagy) && pagy.pages > 1 %>

  <nav class="pagination">

    <% if pagy.prev %>

      <%= link_to "← Previous", url_for(page: pagy.prev), class: "btn" %>

    <% end %>

    <span class="page-info">Page <%= pagy.page %> of <%= pagy.pages %></span>

    <% if pagy.next %>

      <%= link_to "Next →", url_for(page: pagy.next), class: "btn" %>

    <% end %>

  </nav>

<% end %>

PAGINATION_EOF

log "✓ Blognet v${VERSION} complete: social feed + PWA + container queries + engagement scoring"
