# frozen_string_literal: true

class Tv::CommentsController < Tv::BaseController
  before_action :require_user_session
  before_action :set_video

  def create
    @comment = @video.comments.build(comment_params.merge(user: Current.user))
    if @comment.save
      redirect_to video_path(@video), notice: "Comment added."
    else
      redirect_to video_path(@video), alert: @comment.errors.full_messages.to_sentence
    end
  end

  private

  def set_video
    @video = Tv::Video.find(params[:video_id])
  end

  def comment_params
    params.require(:tv_comment).permit(:body)
  end
end
