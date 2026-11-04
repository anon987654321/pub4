# frozen_string_literal: true

# RSVP is a three-way answer, so this sets a status rather than toggling a
# boolean — except that pressing the status you already hold withdraws it, which
# is the only way to take back "going" without a fourth button.
class EventRsvpsController < ApplicationController
  include Shared::FindableBySlug

  before_action :require_user_session
  # Each RSVP writes a row and notifies the organiser.
  rate_limit to: 30, within: 10.minutes, only: :create, name: "rsvps",
    with: -> { redirect_back fallback_location: root_path, alert: t("shared.flash.rate_limited") }

  def create
    # A member route on resources :events, so the segment is :id — not
    # :event_id, which is what a nested resource would have given.
    event = find_by_slug_or_id(Event.published, params[:id])
    status = params[:status].to_s
    return head :unprocessable_entity unless EventRsvp::STATUSES.include?(status)

    # The capacity check and the write share one lock on the event row: two
    # "going" presses at once each read places_left 1 and both took the seat.
    full = event.with_lock { answer(event, status) == :full }
    if full
      redirect_back fallback_location: event_path(event), alert: t("flash.event_full")
      return
    end

    @event = event.reload
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: event_path(@event) }
    end
  end

  private

  # Pressing the status you already hold withdraws it. A full event still takes
  # "interested" (the waiting list is the point), and "interested" → "going" is
  # checked too, since full? once ran only on insert.
  def answer(event, status)
    rsvp = event.rsvps.find_by(user_id: Current.user.id)
    if rsvp&.status == status
      rsvp.destroy
      return
    end
    return :full if status == "going" && rsvp&.status != "going" && event.full?

    rsvp ? rsvp.update!(status:) : event.rsvps.create!(user: Current.user, status:)
    nil
  end
end
