# frozen_string_literal: true

class NewsletterEditionDeliveryJob < ApplicationJob
  queue_as :bulk

  retry_on ActiveRecord::RecordNotFound, wait: :exponentially_longer, attempts: 5
  retry_on StandardError, wait: :exponentially_longer, attempts: 5
  discard_on ActiveJob::DeserializationError

  def perform(edition_id, subscription_ids)
    edition = NewsletterEdition.find_by(id: edition_id)
    return if edition.blank?

    subscription_ids = Array(subscription_ids)
    return if subscription_ids.empty?

    EmailSubscription.where(id: subscription_ids).find_each do |subscription|
      next unless subscription.delivery_eligible?

      NewsletterMailer.edition(subscription, edition).deliver_now
    end
  end
end
