# frozen_string_literal: true

class CommentsController < ApplicationController
  include Shared::FindableBySlug
  rate_limit to: 20, within: 1.minute, only: :create,
             by: -> { Current.user&.id ? "u#{Current.user.id}" : request.remote_ip }
  before_action :require_verified_email, only: :create
  before_action :require_real_user, only: [ :destroy, :generate_summary ]
  before_action :set_commentable

  def create
    @comment = @commentable.comments.build(comment_params)
    @comment.user      = Current.user
    @comment.parent_id = params[:parent_id] if params[:parent_id]

    if @comment.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: root_path }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("comment_form", partial: "comments/form", locals: { comment: @comment, commentable: @commentable }) }
        format.html         { redirect_back fallback_location: root_path, alert: @comment.errors.full_messages.to_sentence }
      end
    end
  end

  def destroy
    @comment = Comment.find(params[:id])
    # user_id, not user. ApplicationRecord sets strict_loading_by_default in
    # every environment, so reading `@comment.user` on a record found by id with
    # nothing preloaded raises StrictLoadingViolationError — production included.
    # Deleting a comment has therefore been failing for everyone, its author
    # included, and the response is a redirect either way so nothing said so.
    # Comparing the foreign key answers the same question without a query.
    @comment.destroy if Current.user && @comment.user_id == Current.user.id
    respond_to do |format|
      format.turbo_stream
      format.html         { redirect_back fallback_location: root_path }
    end
  end

  def generate_summary
    @comment = Comment.find(params[:id])
    return unless @comment.long_thread?
    ThreadSummarizer.call(@comment)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace(dom_id(@comment), partial: "comments/comment", locals: { comment: @comment }) }
      format.html { redirect_back fallback_location: root_path }
    end
  end

  private

  def set_commentable
    # Posts and events are slug-routed. Post.find("konsert-pa-landmark") 404s
    # the comment form on every post show; Event was never even looked up, so
    # events#show's form_with [@event, @comment] 500'd on comments.build.
    if params[:event_id]
      @commentable = find_by_slug_or_id(Event, params[:event_id])
    elsif params[:post_id]
      @commentable = find_by_slug_or_id(Post.includes(:community), params[:post_id])
    elsif params[:comment_id]
      @commentable = Comment.find(params[:comment_id])
    end
    return unless @commentable.respond_to?(:readable_by?)
    raise ActiveRecord::RecordNotFound unless @commentable.readable_by?(Current.user)
  end

  def comment_params
    params.require(:comment).permit(:content)
  end
end
