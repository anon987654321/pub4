# frozen_string_literal: true

module Tv
  class ShowsController < BaseController
    def index
      @channel = Tv::Channel.find_by!(slug: params[:channel_slug]) if params[:channel_slug]
      scope = (@channel ? @channel.shows : Tv::Show.all).published
@pagy, @shows = pagy(scope)
# One grouped count for the page. The card asked each show for
# episodes.count, so a page of twenty cards was twenty COUNTs.
@episode_counts = Tv::Episode.where(show_id: @shows.map(&:id)).group(:show_id).count
    end

    def show
      @channel = Tv::Channel.find_by!(slug: params[:channel_slug])
      @show = @channel.shows.find_by!(slug: params[:slug])
      @episodes = @show.episodes.order(:number)
      @show.record_activity!("TvShowViewed", source_vertical: "tv", locality: @channel&.slug) # wired via shared concern
    end
  end
end
