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
    # Answering a clip is a link into this form; the sounds list is the other
    # way in, for a video that reuses audio without answering anybody.
    @duet_of = Tv::Video.published.find_by(id: params[:duet_of_id])
    @sounds = Tv::Sound.popular.limit(20) if @duet_of.nil?
  end

  def create
    channel = own_channel
    @channel = channel
    @video = channel.videos.build(video_params.merge(user: Current.user, status: "published", published_at: Time.current))
    apply_sound_and_duet(@video)
    if @video.save
      # After save, because a sound named after a clip needs the clip to exist.
      # A video carrying somebody else's sound keeps it; one that carries none
      # becomes the origin of its own.
      # update!, not update_column: the counter cache on Tv::Sound#videos_count
      # is what the sounds list ranks by, and a column write does not touch it.
      @video.update!(sound: Tv::Sound.original_for(@video)) if @video.sound_id.nil?
      preset = video_params[:preset].presence
      PostproJob.perform_later(@video.to_gid.to_s, preset, "thumbnail") if preset && @video.thumbnail.attached?
      redirect_to video_path(@video), notice: t("flash.tv.video_uploaded")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy = (@video.destroy and redirect_to root_path)

  private
  def own_channel = Current.user.tv_channels.find_by!(slug: params[:channel_slug])
  # ApplicationRecord sets strict_loading_by_default, and the show view reads
  # channel, comments and notes off the record -- unpreloaded that raises
  # everywhere violations are not downgraded to a log line (i.e. outside
  # development), so the video page was a 500 in production.
  # `channel: :user` because the subscribe control reads
  # `Current.user != @video.channel.user`, which is only reached when
  # authenticated -- so the page rendered for guests and raised for every
  # signed-in viewer, which is why a guest-only smoke test never saw it.
  def set_video = (@video = find_by_slug_or_id(Tv::Video.includes(:user, :sound, :duet_of, :duets, comments: :user, video_notes: :user, channel: :user), params[:id]))
  # No :tv_channel_id -- the channel comes from the route and is ownership
  # checked. Permitting it let a submitted id override that check by
  # reassigning the foreign key on the built record.
  def video_params = params.require(:video).permit(:title, :description, :video_file, :thumbnail, :preset, :allow_duets)

  # A duet answers a published video that allows being answered, and inherits
  # its sound — which is what makes it a duet rather than a second clip that
  # happens to mention the first. A sound can also be reused on its own.
  def apply_sound_and_duet(video)
    original = Tv::Video.published.find_by(id: params.dig(:video, :duet_of_id))
    if original&.allow_duets?
      video.duet_of = original
      video.sound_id = original.sound_id
      return
    end

    reused = Tv::Sound.find_by(id: params.dig(:video, :sound_id))
    video.sound_id = reused.id if reused
  end

  def require_video_owner!
    return if @video.user == Current.user

    redirect_to video_path(@video), alert: t("shared.flash.not_authorized")
  end
end
