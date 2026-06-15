# frozen_string_literal: true
# AN310: Dead letter queue daily digest

module Shared
  class DeadLetterDigestJob < ApplicationJob
    queue_as :bulk

    def perform
      return unless defined?(SolidQueue::FailedExecution)

      failures = SolidQueue::FailedExecution.where("created_at > ?", 24.hours.ago).limit(100)
      return if failures.empty?

      AdminMailer.failed_jobs_digest(failures.map(&:attributes)).deliver_later
    rescue NameError
      Rails.logger.info("[dead_letter] demo mode — SolidQueue not available")
    end
  end
end