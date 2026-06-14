# frozen_string_literal: true

module Tv
  class EpisodesController < BaseController
    def show
      @channel = Tv::Channel.find_by!(slug: params[:channel_slug])
      @show = @channel.shows.find_by!(slug: params[:show_slug])
      @episode = @show.episodes.find_by!(number: params[:number])
      @video = @episode.video
    end
  end
end
