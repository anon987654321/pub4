# frozen_string_literal: true

module Master
  module Council
    class Deliberation
      def initialize(personas:, agent:, event_bus: nil)
        @personas = personas
        @agent    = agent
        @bus      = event_bus
      end

      def review(code, context: nil)
        feedback = @personas.map { |persona|
          response = @agent.ask(build_prompt(persona, code, context))
          { persona: persona.name, role: persona.role, feedback: response }
        }

        vetoes = feedback.select { |f| f[:persona] == "Security" && veto?(f[:feedback]) }
        return Result.err("council: Security veto\n#{vetoes.first[:feedback]}", category: :validation) if vetoes.any?

        Result.ok(feedback)
      rescue => e
        Result.err("council: #{e.message}", category: :unknown)
      end

      private

      def build_prompt(persona, code, context)
        ctx = context ? "\nContext: #{context}\n" : ""
        "You are #{persona.name} (#{persona.role}, bias: #{persona.bias}).#{ctx}\n#{persona.prompt}\n\nCode:\n#{code}\n\nProvide terse, actionable feedback. Flag VETO: at the start if this must not ship."
      end

      def veto?(feedback)
        feedback.to_s.strip.start_with?("VETO:")
      end
    end
  end
end
