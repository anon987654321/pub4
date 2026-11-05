# frozen_string_literal: true

class CommentsController < ApplicationController
  include Shared::FindableBySlug
  # dom_id for the streams and anchors below.
  include ActionView::RecordIdentifier
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
  before_action :require_real_user, only: [ :edit, :update, :destroy, :remove, :generate_summary ]
  rate_limit to: 5, within: 1.minute, only: :generate_summary, name: "summary",
             by: -> { Current.user&.id ? "u#{Current.user.id}" : request.remote_ip }
  before_action :set_commentable, :refuse_banned_commenter, only: :create
  before_action :set_own_comment, only: :destroy
  before_action :set_editable_comment, only: %i[edit update]
  before_action :set_moderated_comment, only: :remove
  helper_method :comment_return_path
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
        format.turbo_stream { render turbo_stream: failed_form_stream }
        format.html         { redirect_back fallback_location: root_path, alert: @comment.errors.full_messages.to_sentence }
      end
    end
  end

  # The editor opens in the comment's own frame, as messages edit in place.
  def edit; end

  def update
    if @comment.update(comment_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(dom_id(@comment), partial: "comments/comment",
                                                                      locals: { comment: @comment })
        end
        format.html { redirect_to comment_return_path }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # One with replies stays as a tombstone so the thread under it keeps its place.
  def destroy
    @comment.discard!
    respond_to do |format|
      format.turbo_stream
      format.html         { redirect_back fallback_location: root_path }
    end
  end

  # A moderator of the post's community takes the comment down from the
  # thread. It goes through ModerationWorkflow as a resolved report, so the
  # removal sits in the community's moderation queue with who made it, and is
  # undone the way any resolved report is.
  def remove
    report = ModerationWorkflow.report!(reporter: Current.user, target: @comment, reason: "other")
    ModerationWorkflow.transition!(report:, status: "resolved", decision_reason: "community_moderator")
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id(@comment)) }
      format.html { redirect_back fallback_location: root_path }
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
    # Preloaded: a tombstone renders back in place, thread and all.
    @comment = Comment.preload(:user, :commentable).find(params[:id])
    head :forbidden unless Current.user && @comment.user_id == Current.user.id && !@comment.tombstoned?
  end

  # Only the author, only inside Comment::EDIT_WINDOW, never a tombstone or a
  # removed comment. Preloaded: the comment renders back with its thread.
  def set_editable_comment
    @comment = Comment.preload(:user, :commentable).find(params[:id])
    head :forbidden unless @comment.editable_by?(Current.user)
  end

  def set_moderated_comment
    @comment = Comment.find(params[:id])
    allowed = @comment.removable_by_moderator_of_thread?(Current.user) &&
              Community.moderated_by?(@comment.thread_community_id, Current.user)
    head :forbidden unless allowed
  end

  def comment_return_path
    thread = @comment.commentable
    thread.is_a?(Comment) ? root_path : polymorphic_path(thread, anchor: dom_id(@comment))
  end

  # A failed reply goes back into its own disclosure with the typed text and
  # the errors. Replacing the root comment_form put a reply's errors at the top
  # of the thread and dropped what the person wrote under the comment.
  def failed_form_stream
    locals = { comment: @comment, commentable: @commentable }
    return turbo_stream.replace("comment_form", partial: "comments/form", locals:) unless @comment.parent_id

    form_id = "reply_form_#{@comment.parent_id}"
    reply = { parent_id: @comment.parent_id, form_id:, rows: 3,
              placeholder: t("comments.reply_placeholder"), submit: t("comments.reply") }
    turbo_stream.replace(form_id, partial: "comments/form", locals: locals.merge(reply))
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

  # postable_by? keeps a banned member from posting in the community; the same
  # ban has to keep them out of its comment threads.
  def refuse_banned_commenter
    head :forbidden if @commentable.is_a?(Post) && @commentable.community&.banned?(Current.user)
  end

  def comment_params
    params.require(:comment).permit(:content)
  end
end
