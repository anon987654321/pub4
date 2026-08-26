# frozen_string_literal: true

# Scheduled and live style sessions, in the order the page shows them.
class LiveStreamsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "live_streams/stream_row", as: :live_stream, wrap_in: :li

  private

  def scope
    LiveStream.where(status: %w[scheduled live])
              .includes(:user)
              .order(:scheduled_at, :created_at)
  end
end
