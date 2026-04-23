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
          { persona: persona.name, role: persona.role, veto_role: veto_role?(persona), feedback: response }
        }

        # Check veto on any persona flagged with veto_role, not on name.
        # Multiple security-tier personas can now all hold veto power.
        vetoes = feedback.select { |f| f[:veto_role] && veto_text?(f[:feedback]) }
        return Result.err("council: veto from #{vetoes.first[:persona]}\n#{vetoes.first[:feedback]}", category: :validation) if vetoes.any?

        Result.ok(feedback)
      rescue => e
        Result.err("council: #{e.message}", category: :unknown)
      end

      private

      def veto_role?(persona)
        persona.respond_to?(:veto?) ? persona.veto? : persona.respond_to?(:veto_role) && persona.veto_role
      end

      def build_prompt(persona, code, context)
        ctx = context ? "\nContext: #{context}\n" : ""
        veto_hint = veto_role?(persona) ? " You may prefix VETO: if this must not ship." : ""
        "You are #{persona.name} (#{persona.role}, bias: #{persona.bias}).#{ctx}\n#{persona.prompt}\n\nCode:\n#{code}\n\nProvide terse, actionable feedback.#{veto_hint}"
      end

      def veto_text?(feedback)
        feedback.to_s.strip.start_with?("VETO:")
      end
    end
  end
end
