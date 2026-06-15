# frozen_string_literal: true
# AN616: HLS live stream (demo/fallback)

module Tv
  class HlsStream
    def initialize(stream)
      @stream = stream
    end

    def playlist_url
      ENV.fetch("HLS_RELAY_URL", "/tv/streams/#{@stream.id}/index.m3u8")
    end

    def viewer_count_channel
      "tv_stream_#{@stream.id}_viewers"
    end
  end
end