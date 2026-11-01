# frozen_string_literal: true

# The what's-on listing. `upcoming` means "has not finished", not "has not
# started" — a three-day festival is still on during day two — and the scope
# has to agree with the controller's or page two contradicts page one.
class EventsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "events/event", as: :event, wrap_in: :li

  private

  def scope
    scope = Event.upcoming.includes(:user, :place, :neighborhood).with_attached_cover
    neighborhood = element.dataset["neighborhood_id"]
    scope = scope.where(neighborhood_id: neighborhood) if neighborhood.present?
    scope
  end

  # The viewer's own answer for each event on this page: one pluck, not one
  # exists? per card. Same reason the controller batches it.
  def after_paginate
    @rsvps = if Current.user.blank? || @records.blank?
               {}
    else
               EventRsvp.where(user_id: Current.user.id, event_id: @records.map(&:id))
                        .pluck(:event_id, :status).to_h
    end
  end

  def row_locals(event) = { event: event, rsvp_status: @rsvps[event.id] }
end
