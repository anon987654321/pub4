# frozen_string_literal: true

# Watch-time reports from the player.
#
# tv_view_events has carried watch_time_seconds and completed since the table
# was created, and videos#show wrote a row with neither — so the table recorded
# that a signed-in user opened the page, never how much of it they watched.
# This is the endpoint that fills those two columns in.
class Tv::ViewEventsController < Tv::BaseController
  before_action :require_user_session

  # POST /videos/:video_id/view_events
  #
  # The vertical feed needs a row per video as each one scrolls into view;
  # videos#show creates its own on page load, so only the feed calls this.
  # Answers the id the player then reports progress against.
  def create
    # Tv::Video includes Shared::Sluggable, so the nested path carries a slug
    # and find_by(id:) answers nil for every real request. Tv::BaseController
    # includes Shared::FindableBySlug for exactly this.
    video = Tv::Video.published.find_by(slug: params[:video_id]) ||
            Tv::Video.published.find_by(id: params[:video_id])
    return head :not_found unless video

    event = video.view_events.create!(user: Current.user)
    video.increment!(:views_count)
    render json: { id: event.id, url: video_view_event_path(video, event) }
  end

  # PATCH /videos/:video_id/view_events/:id
  #
  # Scoped to Current.user's own events, so the id in the URL cannot be used to
  # inflate someone else's watch time. Beacons fire during page unload and
  # nothing is listening for the response, so this answers :no_content either
  # way rather than rendering anything.
  def update
    event = Current.user.tv_view_events.find_by(id: params[:id])
    return head :not_found unless event

    event.record_progress!(params[:watch_time_seconds])
    head :no_content
  end
end
