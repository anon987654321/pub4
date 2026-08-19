# frozen_string_literal: true

class Tv::ChannelsController < Tv::BaseController
  include Shared::LiveSearchable

  allow_unauthenticated_access only: %i[index show]
  before_action :set_channel, only: %i[show edit update destroy subscribe unsubscribe]
  before_action :require_channel_owner!, only: %i[edit update destroy]

  def index
    scope = Tv::Channel.all.with_attached_avatar.includes(:user)
    if live_search_query.present?
      channel_ids = apply_live_search(scope, columns: %w[name description], vertical: "tv").pluck(:id)
      video_ids = apply_live_search(Tv::Video.published, columns: %w[title description], vertical: "tv").pluck(:tv_channel_id)
      scope = scope.where(id: (channel_ids + video_ids).uniq)
    else
      scope = scope.popular
    end
    @pagy, @channels = pagy(scope)
    finish_live_search(partial: "tv/channels/live_search_results")
  end
  def show     = (@pagy, @videos = pagy(@channel.videos.published))
  def new      = (@channel = Tv::Channel.new)
  def edit;    end

  def create
    @channel = Current.user.tv_channels.build(channel_params)
    @channel.save ? redirect_to(channel_path(@channel), notice: t("flash.tv.channel_created")) : render(:new, status: :unprocessable_entity)
  end

  def update
    @channel.update(channel_params) ? redirect_to(channel_path(@channel)) : render(:edit, status: :unprocessable_entity)
  end

  def destroy = (@channel.destroy and redirect_to channels_path)

  def subscribe
    Tv::Subscription.find_or_create_by!(user: Current.user, tv_channel: @channel)
    redirect_back fallback_location: channel_path(@channel)
  end

  def unsubscribe
    Tv::Subscription.find_by(user: Current.user, tv_channel: @channel)&.destroy
    redirect_back fallback_location: channel_path(@channel)
  end

  private
  # params[:slug], not params[:id]: the route declares `param: :slug`, so the
  # segment arrives under that name and params[:id] is nil. find_by!(slug: nil)
  # raises RecordNotFound every time, so every channel link on /channels 404'd
  # — including the ones the index itself renders. The sibling IRC
  # ChannelsController already reads params[:slug].
  def set_channel    = (@channel = Tv::Channel.find_by!(slug: params[:slug]))
  def channel_params = params.require(:channel).permit(:name, :description, :banner, :avatar)

  # user_id, not user: set_channel finds by slug with nothing preloaded, and
  # strict_loading_by_default raises on the association read before the
  # comparison — so channel edit and update failed for the owner too.
  def require_channel_owner!
    return if Current.user && @channel.user_id == Current.user.id

    redirect_to channel_path(@channel), alert: t("shared.flash.not_authorized")
  end
end
