# frozen_string_literal: true

class Tv::VideosController < Tv::BaseController
  allow_unauthenticated_access only: %i[show]
  before_action :set_video, only: %i[show destroy]

  def show
    @video.view_events.create!(user: Current.user) if authenticated?
    @video.increment!(:views_count)
    respond_to_cached_show(@video, only: %i[id title description views_count comments_count tv_channel_id])
  end

  def new  = (@video = Tv::Video.new)

  def create
    channel = Current.user.tv_channels.find(params[:tv_channel_id])
    @video  = channel.videos.build(video_params.merge(user: Current.user, status: "ready"))
    @video.save ? redirect_to(tv_video_path(@video), notice: "Video uploaded") : render(:new, status: :unprocessable_entity)
  end

  def destroy = (@video.destroy and redirect_to tv_root_path)

  private
  def set_video    = (@video = Tv::Video.find(params[:id]))
  def video_params = params.expect(:tv_video => [:title, :description, :video_file, :thumbnail, :tv_channel_id])
end
