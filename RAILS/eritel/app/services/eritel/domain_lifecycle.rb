# frozen_string_literal: true

module Eritel
  class DomainLifecycle
    TRANSITIONS = {
      "pending" => %w[active warning deleted],
      "active" => %w[warning hold deleted],
      "warning" => %w[active hold],
      "hold" => %w[active parked deleted],
      "parked" => %w[active deleted],
      "deleted" => []
    }.freeze

    def self.allowed?(from, to)
      TRANSITIONS.fetch(from.to_s, []).include?(to.to_s)
    end

    def self.transition!(domain, to:, actor: "system", metadata: {})
      target = to.to_s
      from = domain.state.to_s
      raise ArgumentError, "invalid domain state: #{target}" unless TRANSITIONS.key?(target)
      raise ArgumentError, "invalid transition: #{from} -> #{target}" unless allowed?(from, target)

      domain.update!(state: target)
      AuditEvent.create!(
        domain: domain,
        event_type: "state_transition",
        actor: actor.to_s,
        data: metadata.merge(from:, to: target)
      )
      domain
    end
  end
end
