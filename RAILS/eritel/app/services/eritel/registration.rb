# frozen_string_literal: true

module Eritel
  class Registration
    class Rejected < StandardError; end

    def self.create(domain:, registrant:, participant: nil, mode: "direct", idempotency_key:, amount_cents: 0, currency: "EUR")
      policy = DomainPolicy.check(domain)
      raise Rejected, policy.reason unless policy.allowed

      raise Rejected, "registrant is not verified" unless registrant.verified?

      access = ParticipantAccess.check(participant:, mode:)
      raise Rejected, access.reason unless access.allowed

      record = Domain.find_or_create_by!(name: policy.name) do |item|
        item.state = "pending"
      end

      raise Rejected, "domain lifecycle disallows registration" unless record.pending?

      Order.create!(
        domain: record,
        registrant:,
        participant:,
        operation: "create",
        state: "pending",
        idempotency_key:,
        amount_cents:,
        currency: currency.to_s.upcase
      )
    end
  end
end
