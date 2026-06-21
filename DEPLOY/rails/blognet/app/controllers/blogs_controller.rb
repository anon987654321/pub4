# frozen_string_literal: true

class BlogsController < ApplicationController
  before_action :require_authentication, except: %i[index show]
  before_action :set_blog, only: %i[show edit update destroy]
  before_action :authorize!, only: %i[edit update destroy]

  def index
    @pagy, @blogs = pagy(Blog.published.includes(:user).recent)
  end

  def show
    @pagy, @posts = pagy(@blog.posts.published.includes(:user, :tags))
    @blog.record_activity!("BlogViewed", source_vertical: "blognet")
  end

  def new
    @blog = Current.user.blogs.build
  end

  def create
    @blog = Current.user.blogs.build(blog_params)
    if @blog.save
      @blog.record_activity!("BlogCreated", source_vertical: "blognet")
      redirect_to(@blog, notice: "Blog created")
    else
      render(:new, status: :unprocessable_entity)
    end
  end

  def edit; end

  def update
    if @blog.update(blog_params)
      @blog.record_activity!("BlogUpdated", source_vertical: "blognet")
      redirect_to(@blog, notice: "Updated")
    else
      render(:edit, status: :unprocessable_entity)
    end
  end

  def destroy
    @blog.record_activity!("BlogRemoved", source_vertical: "blognet")
    @blog.destroy
    redirect_to blogs_path, notice: "Blog deleted"
  end

  private

  def set_blog   = @blog = Blog.find_by!(slug: params[:id])
  def authorize!
    redirect_to(blogs_path, alert: "Unauthorized") unless @blog.user == Current.user
  end
  def blog_params = params.require(:blog).permit(:name, :description, :published, :banner)
end
