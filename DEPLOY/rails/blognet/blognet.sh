#!/usr/bin/env zsh
# blognet.sh — Blognet multi-blog platform (Rails 8)
# Usage: zsh blognet.sh
set -euo pipefail

APP_NAME=blognet
APP_DIR=/home/${APP_NAME}/app
APP_PORT=10002
SCRIPT_DIR=${0:a:h}

. "${SCRIPT_DIR:h}/@shared_functions.sh"

need_cmd ruby34 bundle rails doas

already_done "${APP_DIR}/app/models/post.rb" && exit 0

log "Blognet — Multi-Blog Platform"

# ── Create app ─────────────────────────────────────────────────────────────
create_rails_app "$APP_DIR"

# ── Gems ────────────────────────────────────────────────────────────────────
add_gem pagy
add_gem image_processing
add_gem friendly_id
install_solid_stack
install_security_tools

# ── Auth ───────────────────────────────────────────────────────────────────
install_auth
install_active_storage
install_action_text

# ── Models ─────────────────────────────────────────────────────────────────
bin/rails generate model Blog \
  name:string description:text slug:string:uniq \
  user:references published:boolean:default[false] \
  posts_count:integer:default[0] \
  --no-test-framework

bin/rails generate model Post \
  title:string slug:string:uniq \
  blog:references user:references \
  published:boolean:default[false] \
  published_at:datetime \
  views_count:integer:default[0] \
  comments_count:integer:default[0] \
  --no-test-framework

bin/rails generate model Category name:string slug:string:uniq description:text \
  --no-test-framework

bin/rails generate model Categorization post:references category:references \
  --no-test-framework

bin/rails generate model Comment \
  post:references user:references \
  parent_id:integer content:text \
  approved:boolean:default[true] \
  --no-test-framework

bin/rails generate model Tag name:string:uniq posts_count:integer:default[0] \
  --no-test-framework

bin/rails generate model Tagging post:references tag:references \
  --no-test-framework

bin/rails db:migrate

# ── Model logic ─────────────────────────────────────────────────────────────
cat > app/models/blog.rb << 'RUBY'
class Blog < ApplicationRecord
  belongs_to :user
  has_many :posts, dependent: :destroy
  has_one_attached :banner

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/ }

  before_validation :generate_slug, on: :create

  scope :published, -> { where(published: true) }
  scope :recent,    -> { order(created_at: :desc) }

  def to_param = slug

  private

  def generate_slug
    self.slug ||= name.to_s.parameterize
  end
end
RUBY

cat > app/models/post.rb << 'RUBY'
class Post < ApplicationRecord
  belongs_to :blog
  belongs_to :user
  has_rich_text :body
  has_many_attached :images
  has_many :comments, dependent: :destroy
  has_many :categorizations, dependent: :destroy
  has_many :categories, through: :categorizations
  has_many :taggings, dependent: :destroy
  has_many :tags, through: :taggings

  validates :title, :slug, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/ }

  before_validation :generate_slug, on: :create
  before_save :set_published_at

  scope :published, -> { where(published: true).order(published_at: :desc) }
  scope :drafts,    -> { where(published: false) }
  scope :recent,    -> { order(created_at: :desc) }

  def to_param = slug

  def reading_time
    words = body.to_plain_text.split.size
    [(words / 200.0).ceil, 1].max
  end

  private

  def generate_slug
    self.slug ||= title.to_s.parameterize
  end

  def set_published_at
    self.published_at = Time.current if published? && published_at.nil?
  end
end
RUBY

cat > app/models/comment.rb << 'RUBY'
class Comment < ApplicationRecord
  belongs_to :post
  belongs_to :user
  belongs_to :parent, class_name: "Comment", optional: true
  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy

  validates :content, presence: true, length: { maximum: 5000 }

  scope :roots,    -> { where(parent_id: nil).order(created_at: :asc) }
  scope :approved, -> { where(approved: true) }

  after_create_commit :broadcast_comment

  private

  def broadcast_comment
    broadcast_append_to [post, "comments"], partial: "comments/comment", locals: { comment: self }
    post.increment!(:comments_count)
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

cat > app/controllers/blogs_controller.rb << 'RUBY'
class BlogsController < ApplicationController
  before_action :require_authentication, except: %i[index show]
  before_action :set_blog, only: %i[show edit update destroy]
  before_action :authorize!, only: %i[edit update destroy]

  def index
    @pagy, @blogs = pagy(Blog.published.includes(:user).recent)
  end

  def show
    @pagy, @posts = pagy(@blog.posts.published.includes(:user, :tags))
  end

  def new
    @blog = Current.user.blogs.build
  end

  def create
    @blog = Current.user.blogs.build(blog_params)
    @blog.save ? redirect_to(@blog, notice: "Blog created") : render(:new, status: :unprocessable_entity)
  end

  def edit; end

  def update
    @blog.update(blog_params) ? redirect_to(@blog, notice: "Updated") : render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @blog.destroy
    redirect_to blogs_path, notice: "Blog deleted"
  end

  private

  def set_blog   = @blog = Blog.find_by!(slug: params[:id])
  def authorize! = redirect_to(blogs_path, alert: "Unauthorized") unless @blog.user == Current.user
  def blog_params = params.require(:blog).permit(:name, :description, :published, :banner)
end
RUBY

cat > app/controllers/posts_controller.rb << 'RUBY'
class PostsController < ApplicationController
  before_action :require_authentication, except: %i[index show]
  before_action :set_blog
  before_action :set_post, only: %i[show edit update destroy]
  before_action :authorize!, only: %i[edit update destroy]

  def index
    @pagy, @posts = pagy(@blog.posts.published.includes(:user, :tags))
  end

  def show
    @post.increment!(:views_count)
    @comments = @post.comments.approved.roots.includes(:user, :replies)
    @comment  = Comment.new
  end

  def new
    @post = @blog.posts.build
  end

  def create
    @post = @blog.posts.build(post_params.merge(user: Current.user))
    @post.save ? redirect_to([@blog, @post], notice: "Post created") : render(:new, status: :unprocessable_entity)
  end

  def edit; end

  def update
    @post.update(post_params) ? redirect_to([@blog, @post], notice: "Updated") : render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @post.destroy
    redirect_to @blog, notice: "Post deleted"
  end

  private

  def set_blog   = @blog = Blog.find_by!(slug: params[:blog_id])
  def set_post   = @post = @blog.posts.find_by!(slug: params[:id])
  def authorize! = redirect_to(@blog, alert: "Unauthorized") unless @post.user == Current.user

  def post_params
    params.require(:post).permit(:title, :body, :published, :slug, images: [])
  end
end
RUBY

cat > app/controllers/comments_controller.rb << 'RUBY'
class CommentsController < ApplicationController
  before_action :require_authentication
  before_action :set_post

  def create
    @comment = @post.comments.build(comment_params.merge(user: Current.user))
    if @comment.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to [@post.blog, @post] }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @comment = @post.comments.find(params[:id])
    @comment.destroy! if @comment.user == Current.user
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to [@post.blog, @post] }
    end
  end

  private

  def set_post = @post = Post.find_by!(slug: params[:post_id])

  def comment_params
    params.require(:comment).permit(:content, :parent_id)
  end
end
RUBY

# ── Routes ─────────────────────────────────────────────────────────────────
cat > config/routes.rb << 'RUBY'
Rails.application.routes.draw do
  resource  :session
  resources :passwords, param: :token

  resources :blogs, path: "b" do
    resources :posts, path: "p" do
      resources :comments, only: %i[create destroy]
    end
  end

  root "blogs#index"
  get "up", to: "rails/health#show", as: :rails_health_check
end
RUBY

# ── Views ───────────────────────────────────────────────────────────────────
mkdir -p app/views/blogs app/views/posts app/views/comments

write_shared_partials
write_auth_views

cat > app/views/blogs/index.html.erb << 'ERB'
<% content_for :title, "Blogs" %>
<header>
  <h1>Blogs</h1>
  <% if authenticated? %><%= link_to "New blog", new_blog_path, class: "btn" %><% end %>
</header>
<div id="blogs">
  <% @blogs.each do |blog| %>
    <article>
      <%= link_to blog.name, blog_path(blog) %>
      <p class="dim"><%= blog.description %></p>
      <span class="dim"><%= blog.posts_count %> posts</span>
    </article>
  <% end %>
</div>
<%= pagy_nav(@pagy) if @pagy.pages > 1 %>
ERB

cat > app/views/blogs/show.html.erb << 'ERB'
<% content_for :title, @blog.name %>
<header>
  <h1><%= @blog.name %></h1>
  <p class="dim"><%= @blog.description %></p>
  <% if @blog.user == Current.user %>
    <%= link_to "New post", new_blog_post_path(@blog), class: "btn" %>
    <%= link_to "Edit", edit_blog_path(@blog), class: "btn" %>
  <% end %>
</header>
<div id="posts">
  <% @posts.each do |post| %>
    <article>
      <%= link_to post.title, blog_post_path(@blog, post) %>
      <span class="dim"><%= post.published_at&.strftime("%b %-d, %Y") %> · <%= post.views_count %> views · <%= post.comments_count %> comments</span>
    </article>
  <% end %>
</div>
<%= pagy_nav(@pagy) if @pagy.pages > 1 %>
ERB

cat > app/views/blogs/new.html.erb << 'ERB'
<% content_for :title, "New blog" %>
<h1>New blog</h1>
<%= render "form", blog: @blog %>
ERB

cat > app/views/blogs/edit.html.erb << 'ERB'
<% content_for :title, "Edit blog" %>
<h1>Edit <%= @blog.name %></h1>
<%= render "form", blog: @blog %>
ERB

cat > app/views/blogs/_form.html.erb << 'ERB'
<%= form_with model: blog, class: "form" do |f| %>
  <%= render "shared/errors", object: blog %>
  <div class="field"><%= f.label :name %><%= f.text_field :name, autofocus: true %></div>
  <div class="field"><%= f.label :description %><%= f.text_area :description, rows: 2 %></div>
  <div class="field field--check"><%= f.label :published %><%= f.check_box :published %></div>
  <div class="actions"><%= f.submit class: "btn" %> <%= link_to "Cancel", blogs_path %></div>
<% end %>
ERB

cat > app/views/posts/show.html.erb << 'ERB'
<% content_for :title, @post.title %>
<article class="post">
  <header>
    <h1><%= @post.title %></h1>
    <span class="dim"><%= @post.user.email_address.split("@").first %> · <%= @post.published_at&.strftime("%b %-d, %Y") %> · <%= @post.views_count %> views</span>
    <% if @post.user == Current.user %>
      <%= link_to "Edit", edit_blog_post_path(@blog, @post), class: "btn" %>
      <%= button_to "Delete", blog_post_path(@blog, @post), method: :delete, data: { turbo_confirm: "Delete post?" }, class: "btn btn-danger" %>
    <% end %>
  </header>
  <%= @post.body %>
</article>
<section id="comments">
  <h2>Comments (<%= @post.comments_count %>)</h2>
  <%= render @comments %>
  <% if authenticated? %>
    <%= form_with url: blog_post_comments_path(@blog, @post), class: "form" do |f| %>
      <div class="field"><%= f.text_area :content, rows: 3, placeholder: "Add a comment…" %></div>
      <div class="actions"><%= f.submit "Comment", class: "btn" %></div>
    <% end %>
  <% end %>
</section>
ERB

cat > app/views/posts/new.html.erb << 'ERB'
<% content_for :title, "New post" %>
<h1>New post</h1>
<%= render "form", blog: @blog, post: @post %>
ERB

cat > app/views/posts/edit.html.erb << 'ERB'
<% content_for :title, "Edit post" %>
<h1>Edit post</h1>
<%= render "form", blog: @blog, post: @post %>
ERB

cat > app/views/posts/_form.html.erb << 'ERB'
<%= form_with model: [@blog, post], class: "form" do |f| %>
  <%= render "shared/errors", object: post %>
  <div class="field"><%= f.label :title %><%= f.text_field :title, autofocus: true %></div>
  <div class="field"><%= f.label :body %><%= f.rich_text_area :body %></div>
  <div class="field field--check"><%= f.label :published %><%= f.check_box :published %></div>
  <div class="actions"><%= f.submit class: "btn" %> <%= link_to "Cancel", blog_path(@blog) %></div>
<% end %>
ERB

cat > app/views/comments/_comment.html.erb << 'ERB'
<article class="comment" id="<%= dom_id(comment) %>">
  <span class="dim"><%= comment.user.email_address.split("@").first %></span>
  <p><%= comment.content %></p>
  <% if authenticated? && (comment.user == Current.user || @blog.user == Current.user) %>
    <%= button_to "Delete", blog_post_comment_path(@blog, @post, comment), method: :delete, class: "btn-sm btn-danger" %>
  <% end %>
</article>
ERB

# ── Assets + Layout + Infrastructure ────────────────────────────────────────
install_dartsass
write_base_scss

cat >> app/assets/stylesheets/application.scss << 'SCSS'

.post { max-width: 720px; }
.post header { margin-bottom: var(--space-lg); }
article { margin-bottom: var(--space-md); padding-bottom: var(--space-md); border-bottom: 1px solid var(--color-extra-light-grey); }
article:last-child { border-bottom: none; }
.comment { padding: var(--space-sm) 0; border-bottom: 1px solid var(--color-extra-light-grey); }
.btn { display: inline-block; padding: .3rem .8rem; background: var(--color-black); color: var(--color-white); border: none; border-radius: 3px; cursor: pointer; font-size: .85rem; text-decoration: none; }
.btn-sm { padding: .2rem .5rem; font-size: .75rem; background: #444; color: #fff; border: none; border-radius: 3px; cursor: pointer; }
.btn-danger { background: #c00; }
.dim { color: #666; font-size: .85rem; }
.form { max-width: 680px; }
.form .field { display: flex; flex-direction: column; gap: .2rem; margin-bottom: var(--space-sm); }
.form .field--check { flex-direction: row; align-items: center; gap: var(--space-sm); }
.form input, .form textarea { border: 1px solid #ccc; border-radius: 3px; padding: .4rem .6rem; font: inherit; }
.form .actions { display: flex; gap: var(--space-sm); align-items: center; margin-top: var(--space-md); }
h1, h2 { margin-bottom: var(--space-sm); }
SCSS

write_layout "Blognet"
write_falcon_config "$APP_PORT"
configure_production
install_rcd blognet "$APP_DIR" "$APP_PORT" blognet

# ── Seed ───────────────────────────────────────────────────────────────────
cat > db/seeds.rb << 'RUBY'
user = User.find_or_create_by!(email_address: "admin@blognet.example") do |u|
  u.password = u.password_confirmation = "password123"
end

blog = Blog.find_or_create_by!(slug: "demo-blog") do |b|
  b.name        = "Demo Blog"
  b.description = "A demonstration blog"
  b.user        = user
  b.published   = true
end

5.times do |i|
  Post.find_or_create_by!(slug: "post-#{i + 1}") do |p|
    p.title     = "Post #{i + 1}: Getting Started with Rails 8"
    p.body      = "Rails 8 ships with Solid Cache, Solid Queue, and Solid Cable out of the box. This post covers what changed."
    p.blog      = blog
    p.user      = user
    p.published = true
  end
end
puts "Seeded #{Post.count} posts"
RUBY

bin/rails db:seed

log_ok "Blognet setup complete — start: doas rcctl start blognet"
