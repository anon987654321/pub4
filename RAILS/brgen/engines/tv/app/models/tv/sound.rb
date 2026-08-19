# frozen_string_literal: true

# The audio a clip is built on, as a thing in its own right.
#
# Without it a video has no audio identity: you can watch a clip and have no way
# to find the others built on the same thirty seconds, which is most of what
# makes a short-video feed a place rather than a queue.
class Tv::Sound < ApplicationRecord
  belongs_to :user
  # The clip it came from. Nullable and nullify: the sound outlives the video —
  # the clips that used it are the reason it is still a thing.
  belongs_to :source_video, class_name: "Tv::Video", optional: true
  has_many :videos, class_name: "Tv::Video", foreign_key: :sound_id, dependent: :nullify, inverse_of: :sound

  validates :title, presence: true, length: { maximum: 120 }

  scope :popular, -> { order(videos_count: :desc, id: :desc) }

  # Named after the clip that introduced it, which is what every app that has
  # this does — "original sound — kari" is a name people recognise before they
  # recognise a title.
  def self.original_for(video)
    find_or_create_by!(source_video_id: video.id) do |sound|
      sound.user_id = video.user_id
      sound.title = I18n.t("tv.original_sound", name: video.user&.display_name || video.title.to_s.truncate(40))
    end
  end

  # Ranked the way the feed is: by watch time, not by view count, which counts
  # accidental clicks.
  def videos_by_watch_time
    Tv::Video.published.where(sound_id: id).reorder(Arel.sql(Tv::Video::WATCH_TIME_SQL))
  end
end
