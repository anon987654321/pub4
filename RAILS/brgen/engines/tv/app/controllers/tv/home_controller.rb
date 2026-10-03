# frozen_string_literal: true

class Tv::HomeController < Tv::BaseController
  allow_unauthenticated_access

  def index
    # with_attached_thumbnail: the card checks thumbnail.attached?, which costs
    # one active_storage_attachments query per video without it — 20 on this page.
    @pagy_trending, @trending = pagy(Tv::Video.trending.includes(:channel).with_attached_thumbnail, limit: 12)
    @live = Tv::Broadcast.live.includes(:channel).limit(6)
    @recent = Tv::Video.recent.includes(:channel).with_attached_thumbnail.limit(8)
  end
end
