# frozen_string_literal: true

class ComposeNewsletterEditionJob < ApplicationJob
  queue_as :bulk

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
