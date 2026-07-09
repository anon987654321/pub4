# frozen_string_literal: true

class ShiftReminderJob < ApplicationJob
  queue_as :critical

  def perform
    window = 24.hours.from_now
    Shift.where(state: %w[open assigned]).where(starts_at: Time.current..window).find_each do |shift|
      recipient = shift.volunteer&.user
      next unless recipient

      shift.deliver_notification(
        recipient,
        title: "Upcoming #{shift.kind} shift",
        body: "Your shift starts #{shift.starts_at.strftime('%Y-%m-%d %H:%M')}.",
        source: shift,
        kind: "shift_reminder"
      )
    end
  end
end