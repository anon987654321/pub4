# frozen_string_literal: true

class CommentsController < ApplicationController
  before_action :require_authentication
  before_action :set_post

  def create
    @comment = @post.comments.build(comment_params.merge(user: Current.user))
    if @comment.save
      @comment.record_activity!("CommunityCommentCreated", source_vertical: "hjerterom")
      redirect_to community_show_path(@post), notice: "Comment added"
    else
      redirect_to community_show_path(@post), alert: @comment.errors.full_messages.to_sentence
    end
  end

  def destroy
    @comment = @post.comments.find(params[:id])
    @comment.destroy! if @comment.user == Current.user
    redirect_to community_show_path(@post), notice: "Comment removed"
  end

  private

  def set_post = @post = Post.find(params[:post_id])

  def comment_params
    params.require(:comment).permit(:content, :parent_id, :anonymous)
  end
end
