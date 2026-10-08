# frozen_string_literal: true

# One recovery email for an explicitly opted-in shopper after an open basket
# has gone quiet. The account email must be verified and the same address must
# have a confirmed marketing subscription before a message is queued.
class AbandonedCartReminderJob < ApplicationJob
  queue_as :bulk

  limits_concurrency to: 1, key: "abandoned-cart-reminders", duration: 30.minutes, on_conflict: :discard

  def perform(now: Time.current)
    reminded = 0

    Marketplace::Checkout.open_baskets
                          .where("marketplace_checkouts.created_at <= ?", now - Marketplace::Checkout::ABANDONED_CART_AFTER)
                          .where("marketplace_checkouts.updated_at <= ?", now - Marketplace::Checkout::ABANDONED_CART_AFTER)
                          .where(abandoned_cart_reminded_at: nil)
                          .includes(:user)
                          .find_each do |checkout|
      next unless checkout.abandoned_cart_reminder_due?(now:)
      next unless eligible_user?(checkout.user)
      next unless Marketplace::Order.where(marketplace_checkout_id: checkout.id).exists?

      AbandonedCartMailer.reminder(checkout).deliver_later
      checkout.update!(abandoned_cart_reminded_at: now)
      reminded += 1
    rescue StandardError => e
      Ground::Swallow.log(e, context: "AbandonedCartReminderJob##{checkout.id}") if defined?(Ground::Swallow)
    end

    reminded
  end

  private

  def eligible_user?(user)
    return false unless user
    return false unless user.respond_to?(:email_verified?) && user.email_verified?
    return false unless user.respond_to?(:email_address) && user.email_address.present?
    return false if user.respond_to?(:deleted_at) && user.deleted_at.present?
    return false if user.respond_to?(:deletion_scheduled_at) && user.deletion_scheduled_at.present?

    EmailSubscription.delivery_eligible.exists?(email: user.email_address)
  end
end
