# frozen_string_literal: true

module Tv
  class LiveStreamsController < ApplicationController
    before_action :set_live_stream, only: %i[show update destroy go_live end_live]

    def index
      @live_streams = Tv::LiveStream.recent.limit(50)
    end

    def show
      @stream_chats = @live_stream.stream_chats.visible.chronological.limit(200)
    end

    def new
      @channel = Tv::Channel.find(params[:channel_id]) if params[:channel_id].present?
      @live_stream = Tv::LiveStream.new(channel: @channel)
    end

    def create
      @channel = Tv::Channel.find(params[:channel_id]) if params[:channel_id].present?
      @live_stream = Tv::LiveStream.new(live_stream_params)
      @live_stream.channel ||= @channel
      @live_stream.user = current_user if respond_to?(:current_user, true)

      if @live_stream.save
        redirect_to tv_live_stream_path(@live_stream), notice: t("tv.live_stream_created", default: "Live stream created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @live_stream.update(live_stream_params)
        redirect_to tv_live_stream_path(@live_stream), notice: t("tv.live_stream_updated", default: "Live stream updated")
      else
        render :show, status: :unprocessable_entity
      end
    end

    def destroy
      @live_stream.destroy
      redirect_to tv_live_streams_path, notice: t("tv.live_stream_deleted", default: "Live stream removed")
    end

    def go_live
      @live_stream.go_live!
      redirect_to tv_live_stream_path(@live_stream)
    end

    def end_live
      @live_stream.end_live!
      redirect_to tv_live_stream_path(@live_stream)
    end

    private

    def set_live_stream
      @live_stream = Tv::LiveStream.find(params[:id])
    end

    def live_stream_params
      params.expect(:live_stream => [:title, :description, :status, :stream_key])
    end
  end
end
