# frozen_string_literal: true

module Eritel
  class DomainPolicy
    Result = Data.define(:allowed, :name, :reason)

    RESERVED = %w[admin dns mail ns registry www].freeze

    def self.check(value)
      name = DomainName.normalize(value)
      label = name.delete_suffix(".er")

      return Result.new(false, name, "reserved label") if RESERVED.include?(label)

      Result.new(true, name, nil)
    rescue DomainName::Invalid => e
      Result.new(false, value.to_s.downcase.strip, e.message)
    end
  end
end
