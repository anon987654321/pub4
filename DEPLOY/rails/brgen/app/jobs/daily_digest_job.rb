# frozen_string_literal: true

class DailyDigestJob < ApplicationJob
  queue_as :bulk

  def perform
    EmailSubscription.marketing_opted_in.find_each do |subscription|
      NewsletterMailer.daily_digest(subscription).deliver_now
    end
  end
end
