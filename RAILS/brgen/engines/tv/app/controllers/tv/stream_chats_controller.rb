# frozen_string_literal: true

module Tv
  class StreamChatsController < ApplicationController
    before_action :set_live_stream

    def create
      @stream_chat = @live_stream.stream_chats.build(stream_chat_params)
      @stream_chat.user = current_user if respond_to?(:current_user, true)
      @stream_chat.save!

      respond_to do |format|
        format.html { redirect_to live_stream_path(@live_stream) }
        format.turbo_stream
        format.json { render json: { id: @stream_chat.id }, status: :created }
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
