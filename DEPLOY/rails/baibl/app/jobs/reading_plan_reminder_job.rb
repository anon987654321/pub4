# frozen_string_literal: true

class ReadingPlanReminderJob < ApplicationJob
  queue_as :default

  def perform
    ReadingPlan.includes(:reading_plan_days).find_each do |plan|
      day = plan.reading_plan_days.find_by(completed_at: nil, scheduled_on: Date.current)
      next unless day

      Shared::EventEmitter.call(
        "baibl.reading_plan.reminder",
        plan_id: plan.id,
        day_id: day.id
      ) if defined?(Shared::EventEmitter)
    end
  end
end