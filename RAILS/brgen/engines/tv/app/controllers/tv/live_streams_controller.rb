# frozen_string_literal: true

module Tv
  class LiveStreamsController < ApplicationController
    before_action :require_user_session, only: %i[new create]
    before_action :set_live_stream, only: %i[show update destroy go_live end_live]
    before_action :require_live_stream_owner!, only: %i[update destroy go_live end_live]

    def index
      @live_streams = Tv::LiveStream.recent.limit(50)
    end

    def show
      @stream_chats = @live_stream.stream_chats.chronological.limit(200)
    end

    def new
      @channel = resolve_channel(params[:channel_slug]) if params[:channel_slug].present?
      @live_stream = Tv::LiveStream.new(channel: @channel)
    end

    def create
      @channel = resolve_channel(params[:channel_slug]) if params[:channel_slug].present?
      if @channel && @channel.user_id != Current.user&.id
        redirect_to live_streams_path, alert: t("shared.flash.not_authorized")
        return
      end
      @live_stream = Tv::LiveStream.new(live_stream_params)
      @live_stream.channel ||= @channel
      @live_stream.user = Current.user
      @live_stream.status = "scheduled"
      @live_stream.stream_key ||= SecureRandom.hex(16)

      if @live_stream.save
        redirect_to live_stream_path(@live_stream), notice: t("tv.live_stream_created", default: "Live stream created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @live_stream.update(live_stream_params)
        redirect_to live_stream_path(@live_stream), notice: t("tv.live_stream_updated", default: "Live stream updated")
      else
        render :show, status: :unprocessable_entity
      end
    end

    def destroy
      @live_stream.destroy
      redirect_to live_streams_path, notice: t("tv.live_stream_deleted", default: "Live stream removed")
    end

    def go_live
      @live_stream.go_live!
      redirect_to live_stream_path(@live_stream)
    end

    def end_live
      @live_stream.end_live!
      redirect_to live_stream_path(@live_stream)
    end

    private

    def set_live_stream
      @live_stream = Tv::LiveStream.includes(:user).find(params[:id])
    end

    def resolve_channel(id_or_slug)
      Tv::Channel.find_by(slug: id_or_slug) || Tv::Channel.find(id_or_slug)
    end

    def require_live_stream_owner!
      return if @live_stream.user_id == Current.user&.id

      redirect_to live_stream_path(@live_stream), alert: t("shared.flash.not_authorized")
    end

    # form_with model: @live_stream scopes fields under the model's param_key.
    def live_stream_params
      params.require(:live_stream).permit(:title, :description)
    end
  end
end
