# frozen_string_literal: true

class WeeklyDealsJob < ApplicationJob
  queue_as :bulk

  def perform
    ComposeNewsletterEditionJob.perform_now("weekly_deals") unless NewsletterEdition.for_today.exists?(kind: "weekly_deals")

    NewsletterEdition.for_today.where(kind: "weekly_deals").find_each do |edition|
      subscribers_for(edition.city).find_each do |subscription|
        NewsletterMailer.edition(subscription, edition).deliver_now
      end
      edition.update!(sent_at: Time.current)
    end
  end

  private

  def subscribers_for(city)
    scope = EmailSubscription.marketing_opted_in
    city.present? ? scope.where(city:) : scope
  end
end
