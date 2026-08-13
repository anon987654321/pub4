# frozen_string_literal: true

# The vertical feed: one video per screen, ranked by how much of each people
# actually watched.
#
# Tv::HomeController is the other shape — a trending/live/recent grid, which is
# the YouTube answer to "what is there". This is the TikTok one: no choosing,
# just the next thing. It is only possible because Tv::ViewEvent finally records
# watch time; before that, `trending` sorted views_count, which is incremented
# on page load, so a bounce ranked like a full view.
class Tv::FeedController < Tv::BaseController
  allow_unauthenticated_access

  # A screenful at a time. Ten is roughly a minute of short video, which is far
  # enough ahead that the next one is always ready and short enough that the
  # ranking is re-read while someone is still watching.
  PAGE = 10

  def index
    # joins(:video_file_attachment) rather than a with_attached preload: a
    # vertical feed with nothing to play in it is a blank screen you cannot
    # scroll past, so a video without a file is not in the feed at all.
    @videos = Tv::Video.trending
                       .joins(:video_file_attachment)
                       .includes(:channel, video_file_attachment: :blob)
                       .limit(PAGE)
                       .offset(offset)
    @next_offset = offset + PAGE
    @has_more = @videos.size == PAGE

    # Turbo appends the next screenful onto the same scroller rather than
    # replacing it, so the feed keeps its position.
    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  private

  def offset
    [ params[:offset].to_i, 0 ].max
  end
end
