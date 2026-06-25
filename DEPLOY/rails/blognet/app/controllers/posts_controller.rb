# frozen_string_literal: true

class PostsController < ApplicationController
  include Shared::LiveSearchable

  before_action :require_authentication, except: %i[index show]
  before_action :set_blog, except: %i[share]
  before_action :set_post, only: %i[show edit update destroy]
  before_action :authorize!, only: %i[edit update destroy]
  skip_before_action :verify_authenticity_token, only: [ :share ]

  def index
    scope = @blog.posts.published.includes(:user, :tags)
    scope = apply_live_search(scope, columns: %w[title], vertical: "posts") if live_search_query.present?
    @pagy, @posts = pagy(scope)
    finish_live_search(partial: "posts/live_search_results")
  end

  def show
    @post.increment!(:views_count)
    @post.record_activity!("BlogPostViewed", source_vertical: "blognet")
    @comments = @post.comments.approved.roots.includes(:user, :replies)
    @comment  = Comment.new
  end

  def new
    @post = @blog.posts.build
  end

  def create
    @post = @blog.posts.build(post_params.merge(user: Current.user))
    if @post.save
      Shared::DomainEvent.record!(actor: Current.user, action: "post.created", subject: @post, source_vertical: "blognet")
      redirect_to([ @blog, @post ], notice: "Post created")
    else
      render(:new, status: :unprocessable_entity)
    end
  end

  def edit; end

  def update
    if @post.update(post_params)
      Shared::DomainEvent.record!(actor: Current.user, action: "post.updated", subject: @post, source_vertical: "blognet")
      redirect_to([ @blog, @post ], notice: "Updated")
    else
      render(:edit, status: :unprocessable_entity)
    end
  end

  def destroy
    @post.record_activity!("BlogPostRemoved", source_vertical: "blognet")
    @post.destroy
    redirect_to @blog, notice: "Post deleted"
  end

  def share
    blog = Current.user.blogs.first || Current.user.blogs.create!(name: "Shared Drafts", description: "Imported shares")
    post = blog.posts.build(
      title: share_title,
      body: share_body,
      published: false,
      user: Current.user
    )

    if post.save
      post.record_activity!("BlogPostShared", source_vertical: "blognet")
      redirect_to edit_blog_post_path(blog, post), notice: "Shared into a draft"
    else
      redirect_to blog_path(blog), alert: "Could not create draft"
    end
  end

  private

  def set_blog   = @blog = Blog.find_by!(slug: params[:blog_id])
  def set_post   = @post = @blog.posts.find_by!(slug: params[:id])
  def authorize!
    redirect_to(@blog, alert: "Unauthorized") unless @post.user == Current.user
  end

  def post_params
    params.require(:post).permit(:title, :body, :published, :slug, images: [])
  end

  def share_title
    params[:title].presence || params[:text].presence || params[:url].presence || "Shared draft"
  end

  def share_body
    [ params[:text].presence, params[:url].presence ].compact.join("\n\n")
  end
end
