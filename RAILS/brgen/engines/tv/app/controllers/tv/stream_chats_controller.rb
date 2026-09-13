# frozen_string_literal: true

module Tv
  class StreamChatsController < Tv::BaseController
    before_action :require_user_session
    before_action :set_live_stream

    def create
      @stream_chat = @live_stream.stream_chats.build(stream_chat_params.merge(user: Current.user))

      if @stream_chat.save
        respond_to do |format|
          format.html { redirect_to live_stream_path(@live_stream) }
          format.turbo_stream
          format.json { render json: { id: @stream_chat.id }, status: :created }
        end
      else
        alert = @stream_chat.errors.full_messages.to_sentence
        respond_to do |format|
          format.html { redirect_to live_stream_path(@live_stream), alert: }
          format.turbo_stream { head :unprocessable_entity }
          format.json { render json: { errors: @stream_chat.errors }, status: :unprocessable_entity }
        end
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
