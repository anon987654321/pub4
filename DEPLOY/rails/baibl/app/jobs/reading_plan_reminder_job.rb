# frozen_string_literal: true

class ReadingPlanReminderJob < ApplicationJob
  queue_as :default

  def perform
    ReadingPlan.includes(:user).find_each do |plan|
      next unless plan.user&.email_address.present?

      Rails.logger.info("baibl: reading plan reminder user=#{plan.user_id}")
    end
  end
end
