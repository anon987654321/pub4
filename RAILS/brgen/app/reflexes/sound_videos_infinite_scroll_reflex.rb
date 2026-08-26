# frozen_string_literal: true

# The clips made with one sound. Ranked by watch time, like every other tv
# surface — a sound page ordered by page opens would rank a sound by how many
# people bounced off it.
class SoundVideosInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "tv/videos/tv_video", as: :tv_video, wrap_in: :li

  private

  def scope
    sound = Tv::Sound.find_by(id: element.dataset["sound_id"])
    return Tv::Video.none unless sound

    sound.videos_by_watch_time.includes(:channel, :user)
  end
end
