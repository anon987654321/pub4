# frozen_string_literal: true

class BlogsController < ApplicationController
  include Shared::LiveSearchable

  before_action :require_authentication, except: %i[index show]
  before_action :set_blog, only: %i[show edit update destroy]
  before_action :authorize!, only: %i[edit update destroy]

  def index
    @pagy, @blogs = pagy(Blog.published.includes(:user).recent)
  end

  def show
    scope = @blog.posts.published.includes(:user, :tags)
    scope = apply_live_search(scope, columns: %w[title], vertical: "posts") if live_search_query.present?
    @pagy, @posts = pagy(scope)
    respond_to_cached_show(@blog, only: %i[id name slug description published])
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
  def blog_params = params.expect(:blog => [:name, :description, :published, :banner])
end
