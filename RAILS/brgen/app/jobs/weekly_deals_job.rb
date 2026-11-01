# frozen_string_literal: true

class WeeklyDealsJob < ApplicationJob
  queue_as :bulk

  def perform
    unless NewsletterEdition.for_today.exists?(kind: "weekly_deals")
      ComposeNewsletterEditionJob.perform_now("weekly_deals")
    end

    NewsletterEdition.for_today.where(kind: "weekly_deals").find_each do |edition|
      enqueue_subscribers_for(edition)
      edition.update!(sent_at: Time.current)
    end
  end

  private

  def enqueue_subscribers_for(edition)
    subscribers_for(edition.city).select(:id).find_in_batches(batch_size: 200) do |batch|
      NewsletterEditionDeliveryJob.perform_later(edition.id, batch.map(&:id))
    end
  end

  def subscribers_for(city)
    scope = EmailSubscription.delivery_eligible
    city.present? ? scope.where(city:) : scope
  end
end
