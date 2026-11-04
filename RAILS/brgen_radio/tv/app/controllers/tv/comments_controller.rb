# frozen_string_literal: true

class Tv::CommentsController < Tv::BaseController
  before_action :require_user_session
  before_action :set_video

  def create
    @comment = @video.comments.build(comment_params.merge(user: Current.user))
    if @comment.save
      redirect_to video_path(@video), notice: t("flash.tv.comment_added")
    else
      redirect_to video_path(@video), alert: @comment.errors.full_messages.to_sentence
    end
  end

  private

  def set_video
    # Only a video the public can see takes comments: not a draft, and not one
    # whose account is leaving.
    @video = find_by_slug_or_id(Tv::Video.publicly_visible, params[:video_id])
  end

  def comment_params
    params.require(:tv_comment).permit(:body)
  end
end
