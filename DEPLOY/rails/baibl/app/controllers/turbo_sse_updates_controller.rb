# frozen_string_literal: true
# AN413: Turbo Streams over SSE for low-traffic apps

class TurboSseUpdatesController < ApplicationController
  include ActionController::Live

  allow_unauthenticated_access only: :show if respond_to?(:allow_unauthenticated_access)

  def show
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"

    sse = SSE.new(response.stream, retry: 3000)
    channel = params[:channel] || "updates"

    Turbo::StreamsChannel.subscribe_to(channel) do |message|
      sse.write(message, event: "message")
    end
  rescue IOError
    # client disconnected
  ensure
    response.stream.close
  end
end