# frozen_string_literal: true

class EmailSubscriptionConfirmationJob < ApplicationJob
  queue_as :critical
  run_inline!

  def perform(subscription_id)
    subscription = EmailSubscription.find_by(id: subscription_id)
    return unless subscription

    EmailSubscriptionMailer.confirm(subscription).deliver_now
  end
end
