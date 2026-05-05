#!/usr/bin/env zsh
# brgen.sh — Brgen social network (Reddit-style, Rails 8)
# Usage: zsh brgen.sh
set -euo pipefail

APP_NAME=brgen
APP_DIR=/home/${APP_NAME}/app
APP_PORT=11006
SCRIPT_DIR=${0:a:h}

. "${SCRIPT_DIR:h}/@shared_functions.sh"
. "${SCRIPT_DIR:h}/__shared/@reddit_features.sh"

need_cmd ruby34 bundle rails doas

already_done "${APP_DIR}/app/models/community.rb" && exit 0

log "Brgen — Social Network"

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

# ── Core models ─────────────────────────────────────────────────────────────
bin/rails generate migration AddUsernameAndKarmaToUsers \
  username:string:uniq karma:integer \
  --no-test-framework

bin/rails generate model Community \
  name:string description:text slug:string:uniq \
  subscribers_count:integer \
  user:references \
  --no-test-framework

bin/rails generate model CommunityMembership \
  community:references user:references role:string \
  --no-test-framework

bin/rails generate model Post \
  title:string content:text url:string \
  community:references user:references \
  score:integer \
  upvotes:integer downvotes:integer \
  comments_count:integer \
  post_type:string \
  --no-test-framework

bin/rails generate model Follow \
  follower:references{User} followee:references{User} \
  --no-test-framework

bin/rails generate model Story \
  user:references caption:string expires_at:datetime \
  views_count:integer \
  --no-test-framework

bin/rails db:migrate

# ── Reddit features ─────────────────────────────────────────────────────────
setup_reddit_models
write_reddit_model_logic
write_vote_controller

# ── Model overrides ─────────────────────────────────────────────────────────
cat > app/models/user.rb << 'RUBY'
class User < ApplicationRecord
  has_secure_password

  has_many :sessions, dependent: :destroy
  has_many :posts, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :votes, dependent: :destroy
  has_many :community_memberships, dependent: :destroy
  has_many :communities, through: :community_memberships
  has_many :stories, dependent: :destroy

  has_many :follows_as_follower, class_name: "Follow", foreign_key: :follower_id, dependent: :destroy
  has_many :follows_as_followee, class_name: "Follow", foreign_key: :followee_id, dependent: :destroy
  has_many :following, through: :follows_as_follower, source: :followee
  has_many :followers, through: :follows_as_followee, source: :follower

  has_one_attached :avatar

  validates :email_address, presence: true, uniqueness: true
  validates :username, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9_]+\z/ }, length: { in: 3..30 }

  normalizes :email_address, with: -> e { e.strip.downcase }
  normalizes :username,      with: -> u { u.strip.downcase }

  def following?(other) = follows_as_follower.exists?(followee: other)

  def timeline_posts
    Post.where(user: [self] + following).order(created_at: :desc)
  end

  def recalculate_karma!
    k = posts.sum(:score) + comments.sum(:score)
    update_column(:karma, k)
  end
end
RUBY

cat > app/models/community.rb << 'RUBY'
class Community < ApplicationRecord
  belongs_to :user
  has_many :community_memberships, dependent: :destroy
  has_many :members, through: :community_memberships, source: :user
  has_many :posts, dependent: :destroy
  has_one_attached :banner
  has_one_attached :icon

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }, length: { in: 3..21 }

  before_validation :generate_slug, on: :create

  scope :popular, -> { order(subscribers_count: :desc) }
  scope :recent,  -> { order(created_at: :desc) }

  def to_param = slug

  private

  def generate_slug
    self.slug ||= name.to_s.downcase.gsub(/\W+/, "_").delete_prefix("_").delete_suffix("_")
  end
end
RUBY

cat > app/models/post.rb << 'RUBY'
class Post < ApplicationRecord
  include Votable
  include Commentable

  belongs_to :community
  belongs_to :user
  has_many_attached :images

  POST_TYPES = %w[text link image].freeze

  validates :title, presence: true, length: { maximum: 300 }
  validates :post_type, inclusion: { in: POST_TYPES }
  validates :content, presence: true, if: -> { post_type == "text" }
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }, if: -> { post_type == "link" }

  attribute :post_type, :string, default: "text"

  scope :hot, -> {
    order(Arel.sql("(upvotes - downvotes) / POWER(((julianday('now') - julianday(created_at)) * 24 + 2), 1.5) DESC"))
  }
  scope :top,      -> { order(score: :desc) }
  scope :new_first,-> { order(created_at: :desc) }
  scope :rising,   -> {
    where("created_at > ?", 24.hours.ago).order(score: :desc)
  }
end
RUBY

cat > app/models/follow.rb << 'RUBY'
class Follow < ApplicationRecord
  belongs_to :follower, class_name: "User"
  belongs_to :followee, class_name: "User"

  validates :follower_id, uniqueness: { scope: :followee_id }
  validate :no_self_follow

  private

  def no_self_follow
    errors.add(:base, "cannot follow yourself") if follower_id == followee_id
  end
end
RUBY

cat > app/models/story.rb << 'RUBY'
class Story < ApplicationRecord
  belongs_to :user
  has_one_attached :media

  validates :media, presence: true

  scope :active, -> { where("expires_at > ?", Time.current).order(created_at: :desc) }

  before_create -> { self.expires_at = 24.hours.from_now }
end
RUBY

# ── Controllers ─────────────────────────────────────────────────────────────
cat > app/controllers/application_controller.rb << 'RUBY'
class ApplicationController < ActionController::Base
  include Pagy::Method
  allow_browser versions: :modern
end
RUBY

cat > app/controllers/communities_controller.rb << 'RUBY'
class CommunitiesController < ApplicationController
  before_action :require_authentication, only: %i[new create subscribe unsubscribe]
  before_action :set_community, only: %i[show subscribe unsubscribe]

  def index
    @pagy, @communities = pagy(Community.popular.includes(:user))
  end

  def show
    @sort = params[:sort] || "hot"
    @pagy, @posts = pagy(@community.posts.includes(:user).public_send(@sort.in?(%w[hot top new_first rising]) ? @sort : "hot"))
  end

  def new
    @community = Current.user.communities.build
  end

  def create
    @community = Current.user.communities.build(community_params)
    if @community.save
      @community.community_memberships.create!(user: Current.user, role: "moderator")
      redirect_to @community, notice: "Community created"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def subscribe
    m = @community.community_memberships.find_or_create_by!(user: Current.user)
    m.update!(role: "member")
    @community.increment!(:subscribers_count)
    redirect_to @community
  end

  def unsubscribe
    @community.community_memberships.find_by(user: Current.user)&.destroy!
    @community.decrement!(:subscribers_count)
    redirect_to @community
  end

  private

  def set_community = @community = Community.find_by!(slug: params[:id])
  def community_params = params.require(:community).permit(:name, :description)
end
RUBY

cat > app/controllers/posts_controller.rb << 'RUBY'
class PostsController < ApplicationController
  before_action :require_authentication, except: %i[index show]
  before_action :set_community, only: %i[new create]
  before_action :set_post,      only: %i[show edit update destroy]
  before_action :authorize!,    only: %i[edit update destroy]

  def index
    @sort = params[:sort] || "hot"
    @pagy, @posts = pagy(Post.includes(:user, :community).public_send(@sort.in?(%w[hot top new_first rising]) ? @sort : "hot"))
  end

  def feed
    require_authentication
    @pagy, @posts = pagy(Current.user.timeline_posts.includes(:user, :community))
    render :index
  end

  def show
    @comments = @post.comments.roots.top.includes(:user, replies: :user)
    @comment  = Comment.new
  end

  def new
    @post = @community.posts.build
  end

  def create
    @post = @community.posts.build(post_params.merge(user: Current.user))
    @post.save ? redirect_to([@community, @post], notice: "Posted") : render(:new, status: :unprocessable_entity)
  end

  def edit; end

  def update
    @post.update(post_params) ? redirect_to(@post, notice: "Updated") : render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @post.destroy
    redirect_to @post.community, notice: "Deleted"
  end

  private

  def set_community = @community = Community.find_by!(slug: params[:community_id])
  def set_post      = @post = Post.find(params[:id])
  def authorize!    = redirect_to(root_path, alert: "Unauthorized") unless @post.user == Current.user

  def post_params
    params.require(:post).permit(:title, :content, :url, :post_type, images: [])
  end
end
RUBY

cat > app/controllers/comments_controller.rb << 'RUBY'
class CommentsController < ApplicationController
  before_action :require_authentication

  def create
    @post    = Post.find(params[:post_id])
    @comment = @post.comments.build(comment_params.merge(user: Current.user))
    if @comment.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @post }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @comment = Comment.find(params[:id])
    @comment.destroy! if @comment.user == Current.user
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @comment.commentable }
    end
  end

  private

  def comment_params
    params.require(:comment).permit(:content, :parent_id)
  end
end
RUBY

cat > app/controllers/users_controller.rb << 'RUBY'
class UsersController < ApplicationController
  def show
    @user = User.find_by!(username: params[:id])
    @pagy, @posts = pagy(@user.posts.includes(:community).order(created_at: :desc))
  end
end
RUBY

cat > app/controllers/follows_controller.rb << 'RUBY'
class FollowsController < ApplicationController
  before_action :require_authentication

  def create
    user = User.find(params[:user_id])
    Current.user.follows_as_follower.find_or_create_by!(followee: user)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to user_path(user) }
    end
  end

  def destroy
    user = User.find(params[:user_id])
    Current.user.follows_as_follower.find_by!(followee: user).destroy!
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to user_path(user) }
    end
  end
end
RUBY

cat > app/controllers/stories_controller.rb << 'RUBY'
class StoriesController < ApplicationController
  before_action :require_authentication, except: :index

  def index
    @stories = Story.active.includes(:user).where(user: Current.user&.following).limit(50)
  end

  def new = (@story = Story.new)

  def create
    @story = Current.user.stories.build(story_params)
    @story.save ? redirect_to(stories_path, notice: "Story posted") : render(:new, status: :unprocessable_entity)
  end

  def destroy
    Current.user.stories.find(params[:id]).destroy!
    redirect_to stories_path
  end

  private

  def story_params = params.require(:story).permit(:caption, :media)
end
RUBY

# ── Routes ─────────────────────────────────────────────────────────────────
cat > config/routes.rb << 'RUBY'
Rails.application.routes.draw do
  resource  :session
  resource  :registration, only: %i[new create]
  resources :passwords, param: :token

  root "communities#index"

  get "feed", to: "posts#feed", as: :feed

  resources :communities, path: "r" do
    member do
      post :subscribe
      post :unsubscribe
    end
    resources :posts, shallow: true do
      resources :comments, only: %i[create destroy]
    end
  end

  resources :users, only: %i[show], param: :id do
    resource :follow, only: %i[create destroy], controller: :follows
  end

  resources :stories, only: %i[index new create destroy]
  resources :votes, only: %i[create]

  get "up", to: "rails/health#show", as: :rails_health_check
end
RUBY

# ── Views ───────────────────────────────────────────────────────────────────
write_shared_partials
write_auth_views
write_registration

mkdir -p app/views/communities app/views/posts app/views/comments app/views/votes app/views/users app/views/stories

cat > app/views/communities/index.html.erb << 'ERB'
<div class="page-header">
  <h1>Communities</h1>
  <%= link_to "New community", new_community_path, class: "btn btn--primary" if authenticated? %>
</div>
<div class="community-list">
  <% @communities.each do |c| %>
    <%= render "communities/community", community: c %>
  <% end %>
</div>
<%= render "shared/pagination", pagy: @pagy %>
ERB

cat > app/views/communities/_community.html.erb << 'ERB'
<div class="community-card" id="<%= dom_id(community) %>">
  <div class="community-card__icon">
    <% if community.icon.attached? %>
      <%= image_tag community.icon, class: "community-icon" %>
    <% else %>
      <span class="community-icon--placeholder"><%= community.name[0].upcase %></span>
    <% end %>
  </div>
  <div class="community-card__body">
    <h3><%= link_to community.name, community_path(community) %></h3>
    <p class="text-dim"><%= community.description&.truncate(120) %></p>
    <span class="badge"><%= community.subscribers_count %> members</span>
  </div>
</div>
ERB

cat > app/views/communities/show.html.erb << 'ERB'
<div class="community-header">
  <% if @community.banner.attached? %>
    <%= image_tag @community.banner, class: "community-banner" %>
  <% end %>
  <div class="community-header__body">
    <h1>r/<%= @community.name %></h1>
    <p><%= @community.description %></p>
    <div class="community-header__actions">
      <%= link_to "New post", new_community_post_path(@community), class: "btn btn--primary" if authenticated? %>
      <% if authenticated? %>
        <% if @community.members.include?(Current.user) %>
          <%= button_to "Leave", unsubscribe_community_path(@community), class: "btn" %>
        <% else %>
          <%= button_to "Join", subscribe_community_path(@community), class: "btn btn--primary" %>
        <% end %>
      <% end %>
    </div>
  </div>
</div>
<div class="sort-bar">
  <% %w[hot top new_first rising].each do |s| %>
    <%= link_to s.humanize, community_path(@community, sort: s), class: "sort-link #{@sort == s ? 'active' : ''}" %>
  <% end %>
</div>
<div class="post-list">
  <% @posts.each do |post| %>
    <%= render "posts/post", post: post %>
  <% end %>
</div>
<%= render "shared/pagination", pagy: @pagy %>
ERB

cat > app/views/communities/new.html.erb << 'ERB'
<div class="form-page">
  <h1>New community</h1>
  <%= form_with model: @community, url: communities_path do |f| %>
    <%= render "shared/errors", object: @community %>
    <div class="field">
      <%= f.label :name %>
      <%= f.text_field :name, autofocus: true %>
    </div>
    <div class="field">
      <%= f.label :description %>
      <%= f.text_area :description, rows: 4 %>
    </div>
    <div class="actions">
      <%= f.submit "Create community", class: "btn btn--primary" %>
    </div>
  <% end %>
</div>
ERB

cat > app/views/posts/index.html.erb << 'ERB'
<div class="sort-bar">
  <% %w[hot top new_first rising].each do |s| %>
    <%= link_to s.humanize, posts_path(sort: s), class: "sort-link #{@sort == s ? 'active' : ''}" %>
  <% end %>
</div>
<div class="post-list">
  <% @posts.each do |post| %>
    <%= render "posts/post", post: post %>
  <% end %>
</div>
<%= render "shared/pagination", pagy: @pagy %>
ERB

cat > app/views/posts/_post.html.erb << 'ERB'
<article class="post-card" id="<%= dom_id(post) %>">
  <div class="vote-col" data-controller="vote" data-vote-score-value="<%= post.score %>">
    <% if authenticated? %>
      <button class="vote-btn vote-btn--up" data-action="click->vote#upvote"
              data-vote-votable-type-param="Post" data-vote-votable-id-param="<%= post.id %>">▲</button>
    <% else %>
      <span class="vote-btn vote-btn--up">▲</span>
    <% end %>
    <span class="vote-score" data-vote-target="score"><%= post.score %></span>
    <% if authenticated? %>
      <button class="vote-btn vote-btn--down" data-action="click->vote#downvote"
              data-vote-votable-type-param="Post" data-vote-votable-id-param="<%= post.id %>">▼</button>
    <% else %>
      <span class="vote-btn vote-btn--down">▼</span>
    <% end %>
  </div>
  <div class="post-card__body">
    <div class="post-card__meta">
      r/<%= link_to post.community.name, community_path(post.community) %> ·
      u/<%= post.user.username %> · <%= time_ago_in_words(post.created_at) %> ago
    </div>
    <h2 class="post-card__title"><%= link_to post.title, post_path(post) %></h2>
    <% if post.post_type == "link" && post.url.present? %>
      <a href="<%= post.url %>" class="post-link" target="_blank" rel="noopener">
        <%= URI.parse(post.url).host rescue post.url %>
      </a>
    <% end %>
    <% if post.post_type == "text" && post.content.present? %>
      <p class="post-card__excerpt"><%= truncate(post.content, length: 200) %></p>
    <% end %>
    <div class="post-card__actions">
      <%= link_to "#{post.comments_count} comments", post_path(post), class: "action-link" %>
    </div>
  </div>
</article>
ERB

cat > app/views/posts/show.html.erb << 'ERB'
<%= render "posts/post", post: @post %>
<% if @post.post_type == "text" && @post.content.present? %>
  <div class="post-body"><%= @post.content %></div>
<% end %>

<section class="comments-section">
  <h2><%= @post.comments_count %> Comments</h2>
  <% if authenticated? %>
    <%= form_with model: [@post, @comment], url: post_comments_path(@post) do |f| %>
      <div class="field">
        <%= f.text_area :content, placeholder: "Add a comment...", rows: 4 %>
      </div>
      <div class="actions">
        <%= f.submit "Comment", class: "btn btn--primary" %>
      </div>
    <% end %>
  <% end %>
  <div id="comments">
    <% @comments.each do |comment| %>
      <%= render "comments/comment", comment: comment, depth: 0 %>
    <% end %>
  </div>
</section>
ERB

cat > app/views/posts/new.html.erb << 'ERB'
<div class="form-page">
  <h1>New post in r/<%= @community.name %></h1>
  <%= form_with model: [@community, @post] do |f| %>
    <%= render "shared/errors", object: @post %>
    <div class="post-type-tabs">
      <%= f.radio_button :post_type, "text", id: "type_text" %>
      <label for="type_text">Text</label>
      <%= f.radio_button :post_type, "link", id: "type_link" %>
      <label for="type_link">Link</label>
    </div>
    <div class="field">
      <%= f.label :title %>
      <%= f.text_field :title, autofocus: true, maxlength: 300 %>
    </div>
    <div class="field" id="field-content">
      <%= f.label :content %>
      <%= f.text_area :content, rows: 6 %>
    </div>
    <div class="field" id="field-url" style="display:none">
      <%= f.label :url, "URL" %>
      <%= f.url_field :url %>
    </div>
    <div class="actions">
      <%= f.submit "Post", class: "btn btn--primary" %>
      <%= link_to "Cancel", community_path(@community), class: "btn" %>
    </div>
  <% end %>
</div>
ERB

cat > app/views/posts/edit.html.erb << 'ERB'
<div class="form-page">
  <h1>Edit post</h1>
  <%= form_with model: @post do |f| %>
    <%= render "shared/errors", object: @post %>
    <div class="field">
      <%= f.label :title %>
      <%= f.text_field :title %>
    </div>
    <div class="field">
      <%= f.label :content %>
      <%= f.text_area :content, rows: 6 %>
    </div>
    <div class="actions">
      <%= f.submit "Update", class: "btn btn--primary" %>
    </div>
  <% end %>
</div>
ERB

cat > app/views/comments/_comment.html.erb << 'ERB'
<div class="comment" id="<%= dom_id(comment) %>" style="margin-left:<%= depth * 1.5 %>rem">
  <div class="comment__meta">
    u/<%= comment.user.username %> · <%= time_ago_in_words(comment.created_at) %> ago ·
    <span data-controller="vote" data-vote-score-value="<%= comment.score %>">
      <% if authenticated? %>
        <button class="vote-btn--inline" data-action="click->vote#upvote"
                data-vote-votable-type-param="Comment" data-vote-votable-id-param="<%= comment.id %>">▲</button>
      <% end %>
      <span data-vote-target="score"><%= comment.score %></span>
      <% if authenticated? %>
        <button class="vote-btn--inline" data-action="click->vote#downvote"
                data-vote-votable-type-param="Comment" data-vote-votable-id-param="<%= comment.id %>">▼</button>
      <% end %>
    </span>
    <% if authenticated? && comment.user == Current.user %>
      <%= button_to "delete", post_comment_path(comment.commentable_id, comment),
            method: :delete, class: "btn-link", data: { turbo_confirm: "Delete?" } %>
    <% end %>
  </div>
  <div class="comment__body"><%= simple_format comment.content %></div>
  <% if depth < 6 %>
    <% comment.replies.top.each do |reply| %>
      <%= render "comments/comment", comment: reply, depth: depth + 1 %>
    <% end %>
  <% end %>
</div>
ERB

cat > app/views/comments/create.turbo_stream.erb << 'ERB'
<%= turbo_stream.prepend "comments", partial: "comments/comment",
      locals: { comment: @comment, depth: 0 } %>
ERB

cat > app/views/comments/destroy.turbo_stream.erb << 'ERB'
<%= turbo_stream.remove dom_id(@comment) %>
ERB

cat > app/views/votes/create.turbo_stream.erb << 'ERB'
<%= turbo_stream.replace "vote-score-#{params[:votable_type].downcase}-#{params[:votable_id]}",
      "<span id='vote-score-#{params[:votable_type].downcase}-#{params[:votable_id]}'></span>" %>
ERB

cat > app/views/users/show.html.erb << 'ERB'
<% content_for :title, "@#{@user.username}" %>
<div class="profile-header">
  <% if @user.avatar.attached? %>
    <%= image_tag @user.avatar, class: "avatar avatar--lg" %>
  <% else %>
    <div class="avatar avatar--lg avatar--placeholder"><%= @user.username[0].upcase %></div>
  <% end %>
  <div class="profile-header__body">
    <h1>@<%= @user.username %></h1>
    <p class="text-dim"><%= pluralize(@user.followers.count, "follower") %> · <%= @user.following.count %> following · <%= @user.karma %> karma</p>
    <% if authenticated? && Current.user != @user %>
      <% if Current.user.following?(@user) %>
        <%= button_to "Unfollow", user_follow_path(@user), method: :delete, class: "btn" %>
      <% else %>
        <%= button_to "Follow", user_follow_path(@user), method: :post, class: "btn btn--primary" %>
      <% end %>
    <% end %>
  </div>
</div>
<div class="post-list">
  <% @posts.each do |post| %>
    <%= render "posts/post", post: post %>
  <% end %>
</div>
<%= render "shared/pagination", pagy: @pagy %>
ERB

cat > app/views/stories/index.html.erb << 'ERB'
<% content_for :title, "Stories" %>
<div class="stories-bar">
  <% @stories.group_by(&:user).each do |user, stories| %>
    <div class="story-avatar" title="<%= user.username %>">
      <%= link_to stories_path do %>
        <% if user.avatar.attached? %>
          <%= image_tag user.avatar, class: "avatar" %>
        <% else %>
          <div class="avatar avatar--placeholder"><%= user.username[0].upcase %></div>
        <% end %>
        <span class="story-username">@<%= user.username %></span>
      <% end %>
    </div>
  <% end %>
  <% if authenticated? %>
    <div class="story-avatar story-avatar--add">
      <%= link_to new_story_path do %>
        <div class="avatar avatar--add">+</div>
        <span class="story-username">Add</span>
      <% end %>
    </div>
  <% end %>
</div>
<% if @stories.empty? %>
  <p class="text-dim">No stories from people you follow.</p>
<% end %>
ERB

cat > app/views/stories/new.html.erb << 'ERB'
<% content_for :title, "New Story" %>
<div class="form-page">
  <h1>New Story</h1>
  <%= form_with model: @story, url: stories_path do |f| %>
    <div class="field">
      <%= f.label :media, "Photo or Video" %>
      <%= f.file_field :media, accept: "image/*,video/*" %>
    </div>
    <div class="field">
      <%= f.label :caption %>
      <%= f.text_field :caption, maxlength: 200 %>
    </div>
    <div class="actions">
      <%= f.submit "Post Story", class: "btn btn--primary" %>
    </div>
  <% end %>
</div>
ERB

# ── Stimulus controllers ─────────────────────────────────────────────────────
setup_stimulus

write_stimulus_controller vote << 'JS'
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { score: Number }
  static targets = ["score"]

  upvote(event) { this.#vote(event, 1) }
  downvote(event) { this.#vote(event, -1) }

  #vote(event, value) {
    const { votableType, votableId } = event.params
    fetch("/votes", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("[name='csrf-token']")?.content,
        "Accept": "text/vnd.turbo-stream.html"
      },
      body: JSON.stringify({ votable_type: votableType, votable_id: votableId, value })
    })
    .then(r => r.text())
    .then(html => Turbo.renderStreamMessage(html))
  }
}
JS

write_stimulus_controller post_type << 'JS'
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.querySelectorAll("input[name='post[post_type]']").forEach(radio => {
      radio.addEventListener("change", () => this.#toggle(radio.value))
    })
    const checked = this.element.querySelector("input[name='post[post_type]']:checked")
    if (checked) this.#toggle(checked.value)
  }

  #toggle(type) {
    document.getElementById("field-content").style.display = type === "text" ? "" : "none"
    document.getElementById("field-url").style.display     = type === "link" ? "" : "none"
  }
}
JS

# ── CSS ─────────────────────────────────────────────────────────────────────
install_dartsass
mkdir -p app/assets/stylesheets
cat > app/assets/stylesheets/application.scss << 'SCSS'
:root {
  --bg: #dae0e6; --surface: #fff; --border: #edeff1;
  --text: #1c1c1c; --text-dim: #878a8c; --primary: #ff4500;
  --primary-hover: #e03d00; --upvote: #ff4500; --downvote: #7193ff;
  --radius: 4px; --nav-h: 48px;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { background: var(--bg); color: var(--text); font: 14px/1.5 -apple-system, sans-serif; }
a { color: var(--primary); text-decoration: none; }
a:hover { text-decoration: underline; }
nav { background: #fff; border-bottom: 1px solid var(--border); display: flex; align-items: center; height: var(--nav-h); padding: 0 1rem; gap: 1rem; position: sticky; top: 0; z-index: 100; }
nav a { color: var(--text); }
nav .brand { font-weight: 700; font-size: 1.1rem; color: var(--primary); margin-right: auto; }
.main { max-width: 1200px; margin: 0 auto; padding: 1rem; display: grid; grid-template-columns: 1fr 312px; gap: 1.5rem; }
@media (max-width: 960px) { .main { grid-template-columns: 1fr; } }
.btn { display: inline-block; padding: .4rem .9rem; border-radius: 99px; border: 1px solid var(--primary); color: var(--primary); font-size: .8rem; font-weight: 600; cursor: pointer; background: transparent; }
.btn--primary { background: var(--primary); color: #fff; border-color: var(--primary); }
.btn--primary:hover { background: var(--primary-hover); }
.btn-link { background: none; border: none; color: var(--text-dim); font-size: .75rem; cursor: pointer; padding: 0; }
.flash { padding: .6rem 1rem; margin: .5rem 0; border-radius: var(--radius); }
.flash--notice { background: #e8f5e9; color: #2e7d32; }
.flash--alert  { background: #ffebee; color: #c62828; }
.errors { background: #ffebee; border: 1px solid #ef9a9a; border-radius: var(--radius); padding: .75rem 1rem; margin-bottom: 1rem; }
.error-msg { color: #c62828; font-size: .875rem; }
.field { margin-bottom: 1rem; }
.field label { display: block; font-weight: 600; margin-bottom: .25rem; font-size: .875rem; }
.field input, .field textarea, .field select { width: 100%; border: 1px solid #edeff1; border-radius: var(--radius); padding: .5rem .75rem; font: inherit; }
.field textarea { resize: vertical; }
.actions { margin-top: 1rem; display: flex; gap: .5rem; align-items: center; }
.page-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem; }
.community-list { display: flex; flex-direction: column; gap: .5rem; }
.community-card { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); padding: .75rem 1rem; display: flex; gap: 1rem; align-items: center; }
.community-icon { width: 40px; height: 40px; border-radius: 50%; }
.community-icon--placeholder { display: flex; align-items: center; justify-content: center; width: 40px; height: 40px; border-radius: 50%; background: var(--primary); color: #fff; font-weight: 700; }
.community-header { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); margin-bottom: 1rem; overflow: hidden; }
.community-banner { width: 100%; height: 160px; object-fit: cover; }
.community-header__body { padding: 1rem; }
.community-header__actions { display: flex; gap: .5rem; margin-top: .75rem; }
.sort-bar { display: flex; gap: .25rem; margin-bottom: .75rem; }
.sort-link { padding: .4rem .75rem; border-radius: 99px; color: var(--text-dim); font-weight: 600; font-size: .85rem; }
.sort-link.active { background: var(--surface); border: 1px solid var(--border); color: var(--text); }
.post-list { display: flex; flex-direction: column; gap: .5rem; }
.post-card { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); display: flex; overflow: hidden; }
.vote-col { display: flex; flex-direction: column; align-items: center; padding: .5rem .4rem; background: #f8f9fa; gap: .1rem; min-width: 40px; }
.vote-btn { background: none; border: none; cursor: pointer; color: var(--text-dim); font-size: 1rem; padding: 2px; line-height: 1; }
.vote-btn--up:hover, .vote-btn--up.active { color: var(--upvote); }
.vote-btn--down:hover, .vote-btn--down.active { color: var(--downvote); }
.vote-btn--inline { background: none; border: none; cursor: pointer; color: var(--text-dim); font-size: .7rem; padding: 0 2px; }
.vote-score { font-size: .75rem; font-weight: 700; color: var(--text); }
.post-card__body { flex: 1; padding: .5rem .75rem; }
.post-card__meta { font-size: .75rem; color: var(--text-dim); margin-bottom: .25rem; }
.post-card__title { font-size: 1.05rem; font-weight: 500; margin-bottom: .3rem; }
.post-card__title a { color: var(--text); }
.post-link { font-size: .75rem; color: var(--primary); }
.post-card__excerpt { font-size: .875rem; color: var(--text-dim); margin-bottom: .3rem; }
.post-card__actions { display: flex; gap: .75rem; }
.action-link { font-size: .75rem; color: var(--text-dim); font-weight: 600; }
.post-body { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); padding: 1rem; margin: .5rem 0; white-space: pre-wrap; }
.post-type-tabs { display: flex; gap: .5rem; margin-bottom: 1rem; }
.comments-section { margin-top: 1rem; background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); padding: 1rem; }
.comment { border-top: 1px solid var(--border); padding: .75rem 0; }
.comment__meta { font-size: .75rem; color: var(--text-dim); display: flex; gap: .5rem; align-items: center; margin-bottom: .3rem; flex-wrap: wrap; }
.comment__body { font-size: .9rem; white-space: pre-wrap; }
.badge { font-size: .7rem; color: var(--text-dim); background: #f6f7f8; border-radius: 99px; padding: 2px 6px; }
.text-dim { color: var(--text-dim); }
.form-page { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); padding: 1.5rem; max-width: 600px; }
.form-page h1 { margin-bottom: 1rem; }
.auth-form { max-width: 400px; margin: 3rem auto; background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); padding: 1.5rem; }
.auth-form h1 { margin-bottom: 1.5rem; }
.avatar { width: 40px; height: 40px; border-radius: 50%; object-fit: cover; }
.avatar--lg { width: 80px; height: 80px; }
.avatar--placeholder, .avatar--add { display: flex; align-items: center; justify-content: center; background: var(--primary); color: #fff; font-weight: 700; font-size: 1.1rem; }
.avatar--add { background: #edeff1; color: var(--text); font-size: 1.4rem; }
.profile-header { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); padding: 1rem; display: flex; gap: 1rem; align-items: flex-start; margin-bottom: 1rem; }
.profile-header__body { flex: 1; }
.stories-bar { display: flex; gap: 1rem; overflow-x: auto; padding: .5rem 0 1rem; margin-bottom: .5rem; }
.story-avatar { display: flex; flex-direction: column; align-items: center; gap: .25rem; text-decoration: none; }
.story-avatar .avatar { border: 2px solid var(--primary); }
.story-username { font-size: .65rem; color: var(--text-dim); max-width: 50px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
SCSS

# ── Assets + Infrastructure ─────────────────────────────────────────────────
write_full_layout "Brgen" '<%= link_to "Communities", root_path %><%= link_to "Feed", feed_path if authenticated? %><%= link_to "Stories", stories_path %>'
write_falcon_config "$APP_PORT"
configure_production
install_rcd brgen "$APP_DIR" "$APP_PORT" brgen
relayd_add_relay brgen.no "$APP_PORT"

# ── Seed ───────────────────────────────────────────────────────────────────
cat > db/seeds.rb << 'RUBY'
admin = User.find_or_create_by!(email_address: "admin@brgen.no") do |u|
  u.username = "admin"
  u.password = u.password_confirmation = "password123"
end

["news", "tech", "bergen", "norge", "kultur"].each do |slug|
  Community.find_or_create_by!(slug: slug) do |c|
    c.name        = slug.capitalize
    c.description = "#{slug.capitalize} community"
    c.user        = admin
  end
end

puts "Seeded #{Community.count} communities"
RUBY

bin/rails db:seed

log_ok "Brgen setup complete — start: doas rcctl start brgen"
