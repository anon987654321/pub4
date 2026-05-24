# frozen_string_literal: true

module Tv
  class StreamChatsController < ApplicationController
    before_action :set_live_stream

    def create
      entry = @live_stream.stream_chats.build(stream_chat_params)
      entry.user = current_user if respond_to?(:current_user, true)
      entry.save!

      respond_to do |format|
        format.html { redirect_to tv_live_stream_path(@live_stream) }
        format.turbo_stream
        format.json { render json: { id: entry.id }, status: :created }
      end
    end

    private

    def set_live_stream
      @live_stream = Tv::LiveStream.find(params[:live_stream_id])
    end

    def stream_chat_params
      params.require(:stream_chat).permit(:message)
    end
  end
end
