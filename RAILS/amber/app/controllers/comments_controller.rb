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
    # A bare `return` fell through to the same implicit render as success, so
    # the owner and a stranger got the identical missing-template error.
    unless Current.user && @comment.user_id == Current.user.id
      return respond_to do |format|
        format.turbo_stream { head :forbidden }
        format.html { redirect_to @post, alert: t("flash.comment_not_yours") }
      end
    end

    @comment.record_activity!("AmberCommentRemoved", source_vertical: "amber")
    # The id is captured before the row goes: dom_id on a destroyed record
    # still works, but reading it first is what makes that obvious.
    removed = ActionView::RecordIdentifier.dom_id(@comment)
    @comment.destroy!
    respond_to do |format|
      # Rendered inline: there is no destroy.turbo_stream template in this
      # app, so every Turbo deletion ended in a missing-template error and the
      # comment stayed on the page.
      format.turbo_stream { render turbo_stream: turbo_stream.remove(removed) }
      format.html { redirect_to @post }
    end
  end

  private

  def set_post = @post = Post.find(params[:post_id])

  def comment_params = params.require(:comment).permit(:content)
end
