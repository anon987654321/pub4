# frozen_string_literal: true

class CommentsController < ApplicationController
  before_action :require_authentication
  before_action :set_port

  def create
    @comment = @port.comments.build(comment_params.merge(user: Current.user))
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
    if Current.user && @comment.user_id == Current.user.id
      @comment.destroy!
      @comment.record_activity!("PortCommentRemoved", source_vertical: "bsdports")
    end
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @port }
    end
  end

  private

  def set_port = @port = Port.find(params[:port_id])
  def comment_params = params.require(:comment).permit(:content, :parent_id)
end
