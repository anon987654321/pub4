# frozen_string_literal: true

class CommentsController < ApplicationController
  before_action :require_user_session
  before_action :set_post

  def create
    @comment = @post.comments.build(comment_params)
    @comment.user = Current.user
    @comment.parent_id = params[:parent_id] if params[:parent_id].present?

    if @comment.save
      @comment.record_activity!("AmberCommentCreated", source_vertical: "amber")
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @post }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("comment_form", partial: "comments/form", locals: { comment: @comment, commentable: @post }) }
        format.html { redirect_to @post, alert: @comment.errors.full_messages.to_sentence }
      end
    end
  end

  def destroy
    @comment = @post.comments.find(params[:id])
    return unless Current.user && @comment.user_id == Current.user.id

    @comment.record_activity!("AmberCommentRemoved", source_vertical: "amber")
    @comment.destroy!
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @post }
    end
  end

  private

  def set_post = @post = Post.find(params[:post_id])

  def comment_params = params.require(:comment).permit(:content)
end
