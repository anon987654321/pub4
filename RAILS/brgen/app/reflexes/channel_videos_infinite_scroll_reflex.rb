# frozen_string_literal: true

class ChannelVideosInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "tv/videos/tv_video", as: :tv_video

  private

  def scope
    channel = Tv::Channel.find_by!(slug: element.dataset["channelSlug"])
    channel.videos.published.includes(:channel)
  end
end
