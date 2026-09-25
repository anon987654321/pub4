# frozen_string_literal: true

module Eritel
  class RegistrySimulator
    RESERVED = %w[admin dns mail ns registry www].freeze

    def initialize(endpoint: nil)
      @endpoint = endpoint
    end

    def check(domain)
      name = domain.to_s.downcase
      available = valid?(name) && !RESERVED.include?(name.split(".").first)

      { domain: name, available: available, source: "simulator" }
    end

    def create(domain:, registrant:)
      {
        domain: domain.to_s.downcase,
        registrant: registrant,
        status: "pending-authorized-registry",
        source: "simulator"
      }
    end

    def renew(domain:, years:)
      {
        domain: domain.to_s.downcase,
        years: Integer(years),
        status: "pending-authorized-registry",
        source: "simulator"
      }
    end

    private

    def valid?(domain)
      domain.match?(/\A[a-z0-9-]+\.er\z/)
    end
  end
end
