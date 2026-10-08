# frozen_string_literal: true

class ComposeNewsletterEditionJob < ApplicationJob
  queue_as :bulk
  # One composition per kind and city at a time; two would build the same edition.
  limits_concurrency to: 1, key: ->(kind = "daily", city = nil) { "newsletter-#{kind}-#{city}" }, duration: 30.minutes, on_conflict: :discard

  def perform(kind = "daily", city = nil)
    case kind.to_s
    when "daily"
      NewsletterEditionBuilder.compose_daily!(city:)
    when "weekly_deals"
      NewsletterEditionBuilder.compose_weekly_deals!(city:)
    else
      raise ArgumentError, "unknown newsletter kind: #{kind}"
    end
  end
end
