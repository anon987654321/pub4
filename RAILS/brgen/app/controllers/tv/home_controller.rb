# frozen_string_literal: true

class Tv::HomeController < Tv::BaseController
  allow_unauthenticated_access

  def index
    @pagy_trending, @trending = pagy(Tv::Video.trending.includes(:channel), limit: 12)
    @live   = Tv::Broadcast.live.includes(:channel).limit(6)
    @recent = Tv::Video.recent.includes(:channel).limit(8)
  end
end
