# frozen_string_literal: true

class LiveStreamsController < ApplicationController
  before_action :require_real_user
  before_action :set_live_stream, only: %i[show update destroy]

  def index
    @pagy, @live_streams = pagy(
      LiveStream.where(status: %w[scheduled live]).includes(:user).order(:scheduled_at, :created_at)
    )
    @live_stream = Current.user.live_streams.build
  end

  def show; end

  def create
    @live_stream = Current.user.live_streams.build(live_stream_params)
    if @live_stream.save
      redirect_to live_streams_path, notice: t("flash.live_stream_scheduled")
    else
      @live_streams = LiveStream.where(status: %w[scheduled live]).includes(:user).order(:scheduled_at, :created_at)
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
