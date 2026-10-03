# frozen_string_literal: true

# Enqueue after marketplace order is paid.
#
# Wire from payment success, e.g.:
#
#   after_commit :enqueue_google_conversion, on: :update, if: :just_became_paid?
#
#   def just_became_paid?
#     saved_change_to_payment_status? && payment_status == "paid"
#   end
#
#   def enqueue_google_conversion
#     GoogleEnhancedConversionsJob.perform_later(id)
#   end
#
class GoogleEnhancedConversionsJob < ApplicationJob
  queue_as :default

  discard_on GoogleEnhancedConversions::NotConfigured

  retry_on GoogleEnhancedConversions::ApiError, wait: :polynomially_longer, attempts: 5

  def perform(order_id, validate_only: false)
    return unless GoogleEnhancedConversions.configured?

    order = find_order(order_id)
    return if order.nil?
    return unless order_paid?(order)

    # Idempotency: skip if we already recorded a successful upload for this order.
    if order.respond_to?(:google_conversion_uploaded_at) && order.google_conversion_uploaded_at.present?
      return
    end

    GoogleEnhancedConversions.upload_purchase!(order, validate_only: validate_only)

    if !validate_only && order.respond_to?(:update_column)
      order.update_column(:google_conversion_uploaded_at, Time.current)
    end
  end

  private

  def find_order(order_id)
    if defined?(Marketplace::Order)
      Marketplace::Order.find_by(id: order_id)
    else
      # Fallback: caller passes a duck-typed object in tests
      nil
    end
  end

  def order_paid?(order)
    return true if order.try(:paid_at).present?
    return true if order.try(:payment_status).to_s == "paid"
    return true if order.try(:paid?)

    false
  end
end
