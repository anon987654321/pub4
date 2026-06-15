# frozen_string_literal: true

class CommunityController < ApplicationController
  allow_unauthenticated_access only: %i[index show]

  def index
    @categories = Category.order(:name)
    @pagy, @posts = pagy(Post.recent.includes(:user, :category))
  end

  def show
    @post     = Post.find(params[:id])
    @post.increment!(:views_count)
    @comments = @post.comments.roots.includes(:user, replies: :user)
    @comment  = Comment.new
  end

  def new
    @post = Post.new
  end

  def create
    @post = Current.user.posts.build(post_params)
    @post.save ? redirect_to(community_show_path(@post), notice: "Posted") : render(:new, status: :unprocessable_entity)
  end

  private

  def post_params
    params.require(:post).permit(:title, :body, :category_id, :anonymous)
  end
end
