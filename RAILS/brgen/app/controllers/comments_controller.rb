# frozen_string_literal: true

class CommentsController < ApplicationController
  include Shared::FindableBySlug
  # Named, because unnamed limits in one controller share one counter: the key is
  # ["rate-limit", controller_path, name, by], so every signed-out commenter's
  # comments and summaries counted against each other. Burst plus sustained, as
  # posts and messages carry. See RAILS/test/rate_limit_naming_test.rb.
  rate_limit to: 20, within: 1.minute, only: :create, name: "burst",
             by: -> { Current.user&.id ? "u#{Current.user.id}" : request.remote_ip }
  rate_limit to: 40, within: 3.minutes, only: :create, name: "sustained",
             by: -> { Current.user&.id ? "u#{Current.user.id}" : request.remote_ip },
             with: -> { redirect_back fallback_location: root_path, alert: t("shared.flash.rate_limited") }
  before_action :require_verified_email, only: :create
  before_action :require_real_user, only: [ :destroy, :generate_summary ]
  rate_limit to: 5, within: 1.minute, only: :generate_summary, name: "summary",
             by: -> { Current.user&.id ? "u#{Current.user.id}" : request.remote_ip }
  before_action :set_commentable, only: :create
  before_action :set_own_comment, only: :destroy
  before_action :set_summary_comment, :authorize_summary_comment, only: :generate_summary

  def create
    @comment = @commentable.comments.build(comment_params)
    @comment.user = Current.user
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
    @comment.destroy
    respond_to do |format|
      format.turbo_stream
      format.html         { redirect_back fallback_location: root_path }
    end
  end

  def generate_summary
    return unless @comment.long_thread?
    ThreadSummarizer.call(@comment)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace(dom_id(@comment), partial: "comments/comment", locals: { comment: @comment }) }
      format.html { redirect_back fallback_location: root_path }
    end
  end

  private

  # user_id, not user. ApplicationRecord sets strict_loading_by_default in
  # every environment, so reading `@comment.user` on a record found by id with
  # nothing preloaded raises StrictLoadingViolationError — production included.
  # Comparing the foreign key answers the same question without a query.
  # Someone else's comment is refused out loud: a redirect read as if the
  # delete had worked.
  def set_own_comment
    @comment = Comment.find(params[:id])
    head :forbidden unless Current.user && @comment.user_id == Current.user.id
  end

  def set_summary_comment
    @comment = Comment.includes(:user, :votes, replies: :user).find(params[:id])
  end

  def authorize_summary_comment
    readable = case @comment.commentable_type
    when "Post"
                 Post.includes(:community).find(@comment.commentable_id).readable_by?(Current.user)
    when "Event"
                 Event.find(@comment.commentable_id).readable_by?(Current.user)
    else
                 false
    end
    raise ActiveRecord::RecordNotFound unless readable
  end

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
    # POST /comments names no parent at all; that is a missing record, not a 500.
    raise ActiveRecord::RecordNotFound unless @commentable
    return unless @commentable.respond_to?(:readable_by?)
    raise ActiveRecord::RecordNotFound unless @commentable.readable_by?(Current.user)
  end

  def comment_params
    params.require(:comment).permit(:content)
  end
end
