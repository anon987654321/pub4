# frozen_string_literal: true

class ChannelVideosInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @videos = pagy(videos_scope, page: page, request:)
    super
  end

  private

  def page_html
    @videos.map { |tv_video| render(partial: "tv/videos/tv_video", locals: { tv_video: }) }.join
  end

  def videos_scope
    channel = Tv::Channel.find_by!(slug: element.dataset["channelSlug"])
    channel.videos.published.includes(:channel)
  end
end
