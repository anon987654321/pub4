# frozen_string_literal: true
# AN305/AN306: Solid Cache TTLs and size limits

Rails.application.config.after_initialize do
  next unless defined?(SolidCache::Store)

  SolidCache::Store::DEFAULT_MAX_SIZE = 512.megabytes if SolidCache::Store.const_defined?(:DEFAULT_MAX_SIZE)
end

module Shared
  module CacheTtl
    FEED_FRAGMENT = 5.minutes
    USER_PROFILE = 1.hour
    SEARCH_RESULTS = 15.minutes
    STATIC_PAGE = 24.hours

    def self.fetch(key, type: :default, **options, &block)
      ttl = case type
            when :feed_fragment then FEED_FRAGMENT
            when :user_profile then USER_PROFILE
            when :search_results then SEARCH_RESULTS
            when :static_page then STATIC_PAGE
            else options.delete(:expires_in) || 1.hour
            end
      Rails.cache.fetch(key, expires_in: ttl, **options, &block)
    end

    def self.stats_alert_threshold
      stats = Rails.cache.stats rescue {}
      return unless stats[:size] && stats[:max_size]

      usage = stats[:size].to_f / stats[:max_size]
      Rails.logger.warn("[solid_cache] usage at #{(usage * 100).round}%") if usage > 0.8
    end
  end
end