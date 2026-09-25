# frozen_string_literal: true

class Marketplace::WebhookDelivery < ApplicationRecord
  self.table_name = "marketplace_webhook_deliveries"

  STATUSES = %w[processing succeeded failed].freeze

  validates :provider, :event_delivery, :event, :received_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :event_delivery, uniqueness: { scope: :provider }

  scope :successful, -> { where(status: "succeeded") }

  def succeeded? = status == "succeeded"

  def active?
    status == "processing" && received_at > 120.seconds.ago
  end

  def finish!
    update!(status: "succeeded", succeeded_at: Time.current, last_error: nil)
  end

  def fail!(error)
    update!(
      status: "failed",
      attempts: attempts.to_i + 1,
      last_error: "#{error.class}: #{error.message}".truncate(500)
    )
  end

  def retryable!(error)
    update!(
      status: "processing",
      attempts: attempts.to_i + 1,
      last_error: "#{error.class}: #{error.message}".truncate(500)
    )
  end
end
