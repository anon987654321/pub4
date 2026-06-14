# frozen_string_literal: true

class WeeklyDealsJob < ApplicationJob
  queue_as :bulk

  def perform
    EmailSubscription.marketing_opted_in.find_each do |subscription|
      NewsletterMailer.weekly_deals(subscription).deliver_now
    end
  end
end
