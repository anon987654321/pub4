# frozen_string_literal: true

class TrendingVideosInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @videos = pagy(videos_scope, page: page, request:)
    super
  end

  private

  def page_html
    @videos.map { |tv_video| render(partial: "tv/videos/tv_video", locals: { tv_video: }) }.join
  end

  def videos_scope
    Tv::Video.trending.includes(:channel)
  end
end