# frozen_string_literal: true

class NewsletterEditionDeliveryJob < ApplicationJob
  queue_as :bulk

  retry_on ActiveRecord::RecordNotFound, wait: :polynomially_longer, attempts: 5
  retry_on StandardError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveJob::DeserializationError

  def perform(edition_id, subscription_ids)
    edition = NewsletterEdition.find_by(id: edition_id)
    return if edition.blank?

    subscription_ids = Array(subscription_ids)
    return if subscription_ids.empty?

    # Eligibility is rechecked here, not only at enqueue: an address that opted
    # out or whose account began deletion since then must not get the mail.
    EmailSubscription.delivery_eligible.where(id: subscription_ids).find_each do |subscription|
      NewsletterMailer.edition(subscription, edition).deliver_now
    end
  end
end
