# frozen_string_literal: true

class Tv::VideosController < Tv::BaseController
  allow_unauthenticated_access only: %i[show]
  before_action :set_video, only: %i[show destroy]
  before_action :require_video_owner!, only: :destroy

  def show
    # Kept in an ivar so the player can PATCH watch time onto this exact row.
    # Before that it was created and abandoned: watch_time_seconds and completed
    # were never written by anything, so the table recorded that a signed-in
    # user opened the page and nothing about whether they watched it.
    @view_event = @video.view_events.create!(user: Current.user) if authenticated?
    @video.increment!(:views_count)
  end

  # Both actions are routed under a channel; scoping the lookup to the current
  # user's own channels is the ownership check. create read params[:tv_channel_id],
  # which no route or form ever set. The parent resource declares `param: :slug`,
  # so the segment arrives as :channel_slug and carries a slug, not an id --
  # the same trap ChannelsController#set_channel documents.
  def new
    @channel = own_channel
    @video = Tv::Video.new
  end

  def create
    channel = own_channel
    @channel = channel
    @video  = channel.videos.build(video_params.merge(user: Current.user, status: "published", published_at: Time.current))
    if @video.save
      preset = video_params[:preset].presence
      PostproJob.perform_later(@video.to_gid.to_s, preset, "thumbnail") if preset && @video.thumbnail.attached?
      redirect_to video_path(@video), notice: t("flash.tv.video_uploaded")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy = (@video.destroy and redirect_to root_path)

  private
  def own_channel  = Current.user.tv_channels.find_by!(slug: params[:channel_slug])
  # ApplicationRecord sets strict_loading_by_default, and the show view reads
  # channel, comments and notes off the record -- unpreloaded that raises
  # everywhere violations are not downgraded to a log line (i.e. outside
  # development), so the video page was a 500 in production.
  # `channel: :user` because the subscribe control reads
  # `Current.user != @video.channel.user`, which is only reached when
  # authenticated -- so the page rendered for guests and raised for every
  # signed-in viewer, which is why a guest-only smoke test never saw it.
  def set_video = (@video = find_by_slug_or_id(Tv::Video.includes(:user, comments: :user, video_notes: :user, channel: :user), params[:id]))
  # No :tv_channel_id -- the channel comes from the route and is ownership
  # checked. Permitting it let a submitted id override that check by
  # reassigning the foreign key on the built record.
  def video_params = params.require(:tv_video).permit(:title, :description, :video_file, :thumbnail, :preset)

  def require_video_owner!
    return if @video.user == Current.user

    redirect_to video_path(@video), alert: t("shared.flash.not_authorized")
  end
end
