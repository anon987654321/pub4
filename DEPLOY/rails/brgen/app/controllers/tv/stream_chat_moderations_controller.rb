# frozen_string_literal: true

module Tv
  class StreamChatModerationsController < BaseController
    before_action :require_user_session
    before_action :set_live_stream

    def index
      @entries = @live_stream.stream_chats.includes(:user).order(created_at: :desc).limit(500)
      @hidden_count = @entries.where(moderation_status: "hidden").count
    end

    def update
      entry = @live_stream.stream_chats.find(params[:id])
      entry.update!(
        moderation_status: params[:status].presence_in(%w[visible hidden]) || "hidden",
        moderated_at: Time.current,
        moderated_by_id: Current.user.id
      )
      ActivityEventRecorder.call(
        actor: Current.user,
        event_name: "StreamChatModerated",
        object: entry,
        source_vertical: "tv"
      ) if defined?(ActivityEventRecorder)

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to tv_live_stream_stream_chat_moderations_path(@live_stream), notice: "Message moderated" }
      end
    end

    private

    def set_live_stream
      @live_stream = Tv::LiveStream.find(params[:live_stream_id])
    end
  end
end