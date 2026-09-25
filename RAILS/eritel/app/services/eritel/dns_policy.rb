# frozen_string_literal: true

module Eritel
  class DnsPolicy
    MIN_NAMESERVERS = 2
    MAX_NAMESERVERS = 13
    HOSTNAME = /A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*z/i

    Result = Data.define(:allowed, :reason)

    def self.check(nameservers)
      names = Array(nameservers).map { |name| name.to_s.strip.downcase }.reject(&:empty?)

      return Result.new(false, "too few nameservers") if names.length < MIN_NAMESERVERS
      return Result.new(false, "too many nameservers") if names.length > MAX_NAMESERVERS
      return Result.new(false, "duplicate nameserver") unless names.uniq.length == names.length
      return Result.new(false, "invalid nameserver hostname") if names.any? { |name| !name.match?(HOSTNAME) }

      Result.new(true, nil)
    end
  end
end
