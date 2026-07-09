# frozen_string_literal: true

class VideosInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @videos = pagy(Video.includes(:user).order(created_at: :desc), page: page, request:)
    super
  end

  private

  def page_html
    @videos.map { |video| render(partial: "videos/row", locals: { video: }) }.join
  end
end