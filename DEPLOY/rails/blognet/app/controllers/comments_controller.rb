# frozen_string_literal: true

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
