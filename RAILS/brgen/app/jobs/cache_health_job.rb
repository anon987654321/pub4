# frozen_string_literal: true

class CacheHealthJob < ApplicationJob
  queue_as :bulk

  MAX_SIZE_BYTES = 512.megabytes

  def perform
    used = cache_bytes_used
    return unless Shared::CacheHealth.alert?(bytes_used: used, max_size_bytes: MAX_SIZE_BYTES)

    message = Shared::CacheHealth.message(app: "brgen", bytes_used: used, max_size_bytes: MAX_SIZE_BYTES)
    Rails.logger.warn(message)
    Shared::EventEmitter.call("brgen.cache.health", message:, bytes_used: used, max_size_bytes: MAX_SIZE_BYTES) if defined?(Shared::EventEmitter)
  end

  private

  def cache_bytes_used
    return SolidCache::Entry.sum(:byte_size) if defined?(SolidCache::Entry)
    return Rails.cache.stats[:byte_size].to_i if Rails.cache.respond_to?(:stats) && Rails.cache.stats.respond_to?(:[])

    0
  rescue StandardError => e
    Ground::Swallow.log(e, context: "CacheHealthJob.cache_bytes_used")
    0
  end
end
