# frozen_string_literal: true

module Master
  module Judge
    module Council
      # CV03: adversarial agent argues opposite position.
      class Dissent
        def initialize(agent:, event_bus: nil)
          @agent = agent
          @bus = event_bus
        end

        def challenge(proposal, context:)
          prompt = <<~PROMPT
            Argue against this proposal. Find flaws, risks, and counter-evidence.
            Proposal: #{proposal}
            Context: #{context}
          PROMPT
          result = { role: "dissent", feedback: @agent.ask(prompt).to_s.strip, confidence: 0.6 }
          @bus&.publish("council:dissent", length: result[:feedback].size)
          result
        rescue StandardError => e
          { role: "dissent", feedback: "dissent unavailable: #{e.message}", confidence: 0.0 }
        end
      end
    end
  end
end