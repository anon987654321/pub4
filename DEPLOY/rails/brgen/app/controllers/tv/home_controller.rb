# frozen_string_literal: true

class Tv::HomeController < Tv::BaseController
  include Shared::LiveSearchable

  allow_unauthenticated_access

  def index
    if live_search_query.present?
      video_scope = apply_live_search(Tv::Video.published.includes(:channel), columns: %w[title description], vertical: "tv")
      channel_scope = apply_live_search(Tv::Channel.all, columns: %w[name description], vertical: "tv")
      @pagy_trending, @trending = pagy(video_scope.trending, limit: 12)
      @pagy_channels, @channels = pagy(channel_scope.popular, limit: 8, page_param: :channels_page)
    else
      @pagy_trending, @trending = pagy(Tv::Video.trending.includes(:channel), limit: 12)
      @pagy_channels, @channels = nil
    end
    @live = Tv::Broadcast.live.includes(:channel).limit(6)
    @recent = Tv::Video.recent.includes(:channel).limit(8)
  end
end