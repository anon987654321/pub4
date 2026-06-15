# frozen_string_literal: true
# AN205: Rate limiting on auth via Solid Cache

module Shared
  module AuthRateLimiting
    extend ActiveSupport::Concern

    MAX_ATTEMPTS = 10
    LOCKOUT_DURATION = 15.minutes

    private

    def auth_rate_limited?(ip: request.remote_ip)
      Rails.cache.read(auth_attempt_key(ip)).to_i >= MAX_ATTEMPTS
    end

    def record_failed_auth_attempt(ip: request.remote_ip)
      key = auth_attempt_key(ip)
      count = Rails.cache.increment(key, 1, expires_in: LOCKOUT_DURATION, initial: 0)
      count.to_i >= MAX_ATTEMPTS
    end

    def clear_auth_attempts(ip: request.remote_ip)
      Rails.cache.delete(auth_attempt_key(ip))
    end

    def auth_attempt_key(ip)
      "auth:failed:#{ip}"
    end
  end
end