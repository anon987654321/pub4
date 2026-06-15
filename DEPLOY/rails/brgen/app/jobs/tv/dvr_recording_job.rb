# frozen_string_literal: true
# AN617: DVR recording

module Tv
  class DvrRecordingJob < ApplicationJob
    queue_as :bulk

    def perform(live_stream_id)
      stream = LiveStream.find(live_stream_id)
      path = stream.record_to_storage!
      stream.update!(vod_path: path, thumbnail_at: 30)
    rescue StandardError => e
      Rails.logger.info("[tv_dvr] demo/fallback: #{e.message}")
    end
  end
end