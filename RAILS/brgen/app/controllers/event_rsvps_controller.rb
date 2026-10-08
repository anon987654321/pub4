# frozen_string_literal: true

# RSVP is a three-way answer, so this sets a status rather than toggling a
# boolean — except that pressing the status you already hold withdraws it, which
# is the only way to take back "going" without a fourth button.
class EventRsvpsController < ApplicationController
  include Shared::FindableBySlug

  before_action :require_user_session

  def create
    # A member route on resources :events, so the segment is :id — not
    # :event_id, which is what a nested resource would have given.
    event = find_by_slug_or_id(Event.published, params[:id])
    status = params[:status].to_s
    return head :unprocessable_entity unless EventRsvp::STATUSES.include?(status)

    rsvp = event.rsvps.find_by(user_id: Current.user.id)

    if rsvp&.status == status
      rsvp.destroy
    elsif rsvp
      # full? used to run only on insert, so "interested" → "going" walked
      # onto a sold-out event.
      if status == "going" && rsvp.status != "going" && event.reload.full?
        redirect_back fallback_location: event_path(event), alert: t("flash.event_full")
        return
      end
      rsvp.update!(status: status)
    else
      # A full event still takes "interested" — the waiting list is the point.
      if status == "going" && event.reload.full?
        redirect_back fallback_location: event_path(event), alert: t("flash.event_full")
        return
      end
      event.rsvps.create!(user: Current.user, status: status)
    end

    @event = event.reload
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: event_path(@event) }
    end
  end
end
