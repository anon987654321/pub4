class CommentsController < ApplicationController
  before_action :require_authentication
  before_action :set_port

  def create
    @comment = @port.comments.build(comment_params.merge(user: Current.user))
    if @comment.save
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
    @comment.destroy! if @comment.user == Current.user
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @port }
    end
  end

  private

  def set_port = @port = Port.find(params[:port_id])
  def comment_params = params.require(:comment).permit(:content, :parent_id)
end
