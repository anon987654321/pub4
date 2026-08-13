# frozen_string_literal: true

class Tv::ViewEvent < ApplicationRecord
  tracks_activity created: "TvVideoViewed", source_vertical: "tv", visibility: "private", actor: :user

  belongs_to :user
  belongs_to :video, class_name: "Tv::Video", foreign_key: :tv_video_id

  # A view counts as watched-through at 90%. Players rarely reach the final
  # frame — the last timeupdate fires short of duration, and trailing silence
  # gets skipped — so requiring 100% would mark almost nothing complete.
  COMPLETION_THRESHOLD = 0.9

  validates :watch_time_seconds, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :watched, -> { where.not(watch_time_seconds: nil) }

  # Fold a progress report from the player into this row.
  #
  # Monotonic: the player reports on pause, on tab hide and on unload, and those
  # arrive out of order — a beacon queued at 0:40 can land after one sent at
  # 1:10. Taking the max means a late small report cannot erase real watch time.
  #
  # Clamped to the video's own duration, because seconds arrive from the client
  # and nothing stops a caller posting an hour against a 40-second clip. Without
  # the clamp the ranking below is trivially forgeable.
  def record_progress!(seconds)
    seconds = seconds.to_f
    return false if seconds.negative?

    limit = video_duration_seconds
    seconds = [ seconds, limit ].min if limit
    seconds = [ seconds, watch_time_seconds.to_i ].max

    update!(
      watch_time_seconds: seconds.round,
      completed: limit ? seconds >= limit * COMPLETION_THRESHOLD : completed
    )
  end

  def progress_fraction
    limit = video_duration_seconds
    return nil unless limit&.positive?

    [ watch_time_seconds.to_f / limit, 1.0 ].min
  end

  private

  # strict_safe: an event found by id in the update action has nothing preloaded,
  # and ApplicationRecord is strict_loading by default.
  def video_duration_seconds
    duration = strict_safe_attribute(:video, :duration_seconds)
    duration&.positive? ? duration : nil
  end
end
