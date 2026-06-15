# frozen_string_literal: true

module Tv
  class ShowsController < BaseController
    def index
      @channel = Tv::Channel.find_by!(slug: params[:channel_slug]) if params[:channel_slug]
      @shows = (@channel ? @channel.shows : Tv::Show.all).published.page(params[:page])
    end

    def show
      @channel = Tv::Channel.find_by!(slug: params[:channel_slug])
      @show = @channel.shows.find_by!(slug: params[:slug])
      @episodes = @show.episodes.order(:number)
      @show.record_activity!("TvShowViewed", source_vertical: "tv", locality: @channel&.slug) # wired via shared concern
    end
  end
end
