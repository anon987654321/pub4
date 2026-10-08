# frozen_string_literal: true

module Shared
  module CacheHealth
    ALERT_RATIO = 0.8

    def self.alert?(bytes_used:, max_size_bytes:)
      return false if max_size_bytes.to_i <= 0

      bytes_used.to_f / max_size_bytes.to_f >= ALERT_RATIO
    end

    def self.usage_percent(bytes_used:, max_size_bytes:)
      return 0.0 if max_size_bytes.to_i <= 0

      ((bytes_used.to_f / max_size_bytes.to_f) * 100).round(1)
    end

    def self.message(app:, bytes_used:, max_size_bytes:)
      "#{app} cache at #{usage_percent(bytes_used:,
max_size_bytes:)}% (#{bytes_used}/#{max_size_bytes} bytes)"
    end
  end
end
