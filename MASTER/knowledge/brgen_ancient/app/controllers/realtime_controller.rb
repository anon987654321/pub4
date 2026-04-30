class RealtimeController < ApplicationController
  def twitter_stream
    TwitterStreamer.perform_async
    head :ok
  end
end

