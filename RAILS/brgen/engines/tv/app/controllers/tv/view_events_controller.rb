# frozen_string_literal: true

# Watch-time reports from the player.
#
# tv_view_events has carried watch_time_seconds and completed since the table
# was created, and videos#show wrote a row with neither — so the table recorded
# that a signed-in user opened the page, never how much of it they watched.
# This is the endpoint that fills those two columns in.
class Tv::ViewEventsController < Tv::BaseController
  before_action :require_user_session

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
