# frozen_string_literal: true

class LiveStreamsController < ApplicationController
  # Anonymous parity with brgen (allow all for anonymous): anyone may watch a
  # stream and read its chat; owning a broadcast still needs an account.
  before_action :require_real_user, except: %i[index show]
  before_action :set_public_live_stream, only: :show
  before_action :set_live_stream, only: %i[update destroy]

  def index
    @pagy, @live_streams = pagy(
      LiveStream.publicly_visible.where(status: %w[scheduled live]).includes(:user).order(:scheduled_at, :created_at)
    )
    # The next full hour, the time a session is most often planned for. A
    # guest watches but does not schedule - the composer is an owner's tool.
    @live_stream = Current.user.live_streams.build(scheduled_at: Time.current.beginning_of_hour + 1.hour) unless guest?
  end

  def show; end

  def create
    @live_stream = Current.user.live_streams.build(live_stream_params)
    if @live_stream.save
      redirect_to live_streams_path, notice: t("flash.live_stream_scheduled")
    else
      @live_streams = LiveStream.publicly_visible.where(status: %w[scheduled live]).includes(:user).order(:scheduled_at, :created_at)
      render :index, status: :unprocessable_entity
    end
  end

  def update
    @live_stream.start! if params[:start] && owns_stream?
    @live_stream.end! if params[:end] && owns_stream?
    @live_stream.cancel! if params[:cancel] && owns_stream?
    respond_to do |format|
      format.turbo_stream { load_streams }
      format.html { redirect_to live_streams_path }
    end
  end

  def destroy
    @live_stream.destroy if owns_stream?
    redirect_to live_streams_path
  end

  private

  def set_public_live_stream = @live_stream = LiveStream.publicly_visible.find(params[:id])
  def set_live_stream = @live_stream = LiveStream.find(params[:id])
  # user_id, not user — @live_stream is found by id with nothing preloaded and
  # strict_loading_by_default raises on the association read.
  def owns_stream? = Current.user.present? && Current.user.id == @live_stream.user_id
  def live_stream_params = params.require(:live_stream).permit(:title, :description, :scheduled_at)

  def load_streams
    @pagy, @live_streams = pagy(
      LiveStream.where(status: %w[scheduled live]).includes(:user).order(:scheduled_at, :created_at)
    )
  end
end
