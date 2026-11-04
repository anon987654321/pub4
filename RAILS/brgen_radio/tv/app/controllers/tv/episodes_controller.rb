# frozen_string_literal: true

module Tv
  class EpisodesController < BaseController
    # The page plays the episode, so the file and its poster come with it;
    # strict loading refuses either read lazily.
    EPISODE_VIDEO_LOADS = [ :channel, { thumbnail_attachment: :blob, video_file_attachment: :blob } ].freeze

    def show
      @channel = Tv::Channel.find_by!(slug: params[:channel_slug])
      @show = @channel.shows.find_by!(slug: params[:slug])
      episodes = @show.episodes.includes(video: EPISODE_VIDEO_LOADS)
      @episode = episodes.find_by!(number: params[:number])
      @video = @episode.video
    end
  end
end
