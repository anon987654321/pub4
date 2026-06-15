# frozen_string_literal: true

class PostsController < ApplicationController
  before_action :require_authentication, except: %i[index show]
  before_action :set_blog
  before_action :set_post, only: %i[show edit update destroy]
  before_action :authorize!, only: %i[edit update destroy]

  def index
    @pagy, @posts = pagy(@blog.posts.published.includes(:user, :tags))
  end

  def show
    @paywall_allowed = PaywallService.can_read?(post: @post, viewer_token: viewer_token, user: Current.user)
    @post.increment!(:views_count) if @paywall_allowed
    @comments = @post.comments.approved.roots.includes(:user, :replies) if @paywall_allowed
    @comment  = Comment.new
    respond_to_cached_show(@post, only: %i[id title body slug published_at views_count comments_count])
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
    params.expect(post: [:title, :body, :published, :slug, :paywalled, { images: [] }])
  end

  def viewer_token
    cookies.permanent[:blognet_viewer] ||= SecureRandom.urlsafe_base64(16)
  end
end
