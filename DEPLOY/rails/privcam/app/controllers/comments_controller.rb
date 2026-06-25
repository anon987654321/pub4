# frozen_string_literal: true

class CommentsController < ApplicationController
  before_action :require_authentication

  def create
    @video = Video.find(params[:video_id])
    @comment = @video.comments.build(comment_params)
    @comment.user = Current.user

    if @comment.save
      redirect_to @video, notice: "Comment added."
    else
      redirect_to @video, alert: "Could not add comment."
    end
  end

  private

  def comment_params
    params.require(:comment).permit(:content)
  end
end