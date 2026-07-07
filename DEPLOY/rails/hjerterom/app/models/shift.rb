# frozen_string_literal: true

class Shift < ApplicationRecord
  # Engine-ize Shared
  include Shared.concern(:Notifiable) rescue nil
  include Shared.concern(:Reactable) rescue nil
  enum :kind, { intake: 0, packing: 1, transport: 2, coordination: 3 }, default: :packing
  enum :state, { open: 0, assigned: 1, completed: 2, cancelled: 3 }, default: :open

  belongs_to :volunteer, optional: true

  validates :starts_at, presence: true
  validates :ends_at, presence: true
  validate :valid_time_range

  scope :future, -> { where("starts_at >= ?", Time.current).order(:starts_at) }

  after_create_commit { broadcast_append_later_to "hjerterom:shifts" }
  after_update_commit { broadcast_replace_later_to "hjerterom:shifts" }
  after_create_commit :notify_volunteer_assignment
  after_update_commit :notify_volunteer_assignment, if: :saved_change_to_state?

  def notify_volunteer_assignment
    recipient = volunteer&.user
    return unless recipient

    deliver_notification(
      recipient,
      title: "Shift #{state}",
      body: "#{kind} shift #{starts_at.strftime('%Y-%m-%d %H:%M')} — #{state}.",
      source: self,
      kind: "shift_update"
    )
  end

  private

  def valid_time_range
    return if starts_at.blank? || ends_at.blank? || ends_at > starts_at

    errors.add(:ends_at, "must be later than starts_at")
  end
end
