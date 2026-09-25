# frozen_string_literal: true

module Eritel
  class DomainName
    class Invalid < ArgumentError; end

    LABEL = /A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?z/
    SUFFIX = ".er"

    def self.normalize(value)
      name = value.to_s.strip.downcase
      raise Invalid, "domain is required" if name.empty?
      raise Invalid, "only .er names are accepted" unless name.end_with?(SUFFIX)

      labels = name.split(".")
      raise Invalid, "domain must contain one label before .er" unless labels.length == 2
      raise Invalid, "invalid .er label" unless labels.first.match?(LABEL)

      name
    end
  end
end
