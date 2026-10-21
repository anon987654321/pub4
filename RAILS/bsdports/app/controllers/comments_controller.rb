# frozen_string_literal: true

class CommentsController < ApplicationController
  before_action :require_authentication
  before_action :set_port

  def create
    comment_input = params[:comment]
    return head(:unprocessable_entity) unless comment_input.is_a?(ActionController::Parameters)

    parent_id = comment_input[:parent_id]
    parent = nil
    if parent_id.present?
      valid_id = parent_id.is_a?(Integer) && parent_id.positive? ||
                 parent_id.is_a?(String) && parent_id.match?(/\A[1-9]\d*\z/)
      return head(:unprocessable_entity) unless valid_id

      parent = @port.comments.find_by(id: parent_id)
      return head(:unprocessable_entity) unless parent
    end

    @comment = @port.comments.build(comment_params.merge(user: Current.user, parent: parent))
    if @comment.save
      Shared::DomainEvent.record!(actor: Current.user, action: "comment.created", subject: @comment, source_vertical: "bsdports")
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @port }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @comment = @port.comments.find(params[:id])
    removed = nil
    if Current.user && @comment.user_id == Current.user.id
      # Recorded before the row goes, not after: the activity was being written
      # against a deleted primary key. amber's twin already did it in this
      # order, so the two apps disagreed.
      @comment.record_activity!("PortCommentRemoved", source_vertical: "bsdports")
      removed = ActionView::RecordIdentifier.dom_id(@comment)
      @comment.destroy!
    end
    respond_to do |format|
      # Rendered inline: app/views/comments/ has no destroy.turbo_stream, so
      # every Turbo deletion ended in a missing-template error.
      format.turbo_stream do
        removed ? render(turbo_stream: turbo_stream.remove(removed)) : head(:forbidden)
      end
      format.html { redirect_to @port }
    end
  end

  private

  def set_port = @port = Port.find(params[:port_id])
  def comment_params = params.require(:comment).permit(:content)
end
