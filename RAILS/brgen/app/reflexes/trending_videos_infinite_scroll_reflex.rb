# frozen_string_literal: true

class TrendingVideosInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "tv/videos/tv_video", as: :tv_video

  private

  def scope
    Tv::Video.trending.includes(:channel)
  end
end
