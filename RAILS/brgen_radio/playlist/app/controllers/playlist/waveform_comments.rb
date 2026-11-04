# frozen_string_literal: true

# Every track's timestamped comments in one query, grouped for the waveform;
# reading track.timestamped_comments per row was one query per track.
module Playlist::WaveformComments
  private

  def waveform_comments_for(tracks)
    rows = Playlist::TimestampedComment.where(track_id: tracks.map(&:id)).chronological
                                       .pluck(:track_id, :timestamp_seconds, :body)
    grouped = rows.group_by(&:first)
    tracks.to_h do |track|
      [ track.id, grouped.fetch(track.id, []).map { |_id, time, body| { time: time.to_f, text: body } } ]
    end
  end
end
