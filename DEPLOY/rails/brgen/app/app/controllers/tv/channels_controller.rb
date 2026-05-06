class Tv::ChannelsController < Tv::BaseController
  allow_unauthenticated_access only: %i[index show]
  before_action :set_channel, only: %i[show edit update destroy subscribe unsubscribe]

  def index    = (@pagy, @channels = pagy(Tv::Channel.popular.includes(:user)))
  def show     = (@pagy, @videos = pagy(@channel.videos.published))
  def new      = (@channel = Tv::Channel.new)
  def edit;    end

  def create
    @channel = Current.user.tv_channels.build(channel_params)
    @channel.save ? redirect_to(tv_channel_path(@channel), notice: "Channel created") : render(:new, status: :unprocessable_entity)
  end

  def update
    @channel.update(channel_params) ? redirect_to(tv_channel_path(@channel)) : render(:edit, status: :unprocessable_entity)
  end

  def destroy = (@channel.destroy and redirect_to tv_channels_path)

  def subscribe
    Tv::Subscription.find_or_create_by!(user: Current.user, tv_channel: @channel)
    redirect_back fallback_location: tv_channel_path(@channel)
  end

  def unsubscribe
    Tv::Subscription.find_by(user: Current.user, tv_channel: @channel)&.destroy
    redirect_back fallback_location: tv_channel_path(@channel)
  end

  private
  def set_channel    = (@channel = Tv::Channel.find_by!(slug: params[:id]))
  def channel_params = params.require(:tv_channel).permit(:name, :description, :banner, :avatar)
end
