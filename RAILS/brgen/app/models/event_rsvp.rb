# frozen_string_literal: true

# One answer per person per event.
#
# "interested" is not decoration: on every event platform it is the majority
# answer, and collapsing it into going/not-going both overstates attendance and
# loses the signal that someone wants reminding.
class EventRsvp < ApplicationRecord
  include Shared::Notifiable

  STATUSES = %w[going interested not_going].freeze

  belongs_to :event
  belongs_to :user

  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :event_id }

  scope :going,     -> { where(status: "going") }
  scope :interested, -> { where(status: "interested") }

  after_commit :refresh_event_counts

  def going? = status == "going"

  private

  # Two counters, three statuses, and a status that can move between them — a
  # counter_cache per status would drift the moment someone changed their mind
  # from going to interested, because Rails only increments on create and
  # decrements on destroy. Recounting the two the UI shows is cheap and cannot
  # drift.
  #
  # update_columns rather than update!, so this does not fire Event's
  # tracks_activity(updated:) and emit an EventUpdated to the city feed every
  # time someone RSVPs. But updated_at is written by hand along with them:
  # update_columns skips it, and the event card is fragment-cached on [event],
  # so without it the counts would change in the database and the page would
  # keep rendering the old ones.
  def refresh_event_counts
    target = Event.find_by(id: event_id)
    return unless target

    target.update_columns(
      going_count: EventRsvp.where(event_id: event_id, status: "going").count,
      interested_count: EventRsvp.where(event_id: event_id, status: "interested").count,
      updated_at: Time.current
    )
  end
end
