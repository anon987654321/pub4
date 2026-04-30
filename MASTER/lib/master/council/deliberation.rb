# frozen_string_literal: true

module Master
  module Council
    class Deliberation
      Result = Master::Result

      def initialize(personas:, agent:, event_bus: nil)
        @personas = personas
        @agent    = agent
        @bus      = event_bus
        validate_dependencies!
      end

      def review(code, context: nil)
        return Result.err('council: no personas configured', category: :validation) if @personas.empty?

        threads = @personas.map do |persona|
          Thread.new do
            response = @agent.ask(build_prompt(persona, code, context))
            entry = { persona: persona.name, role: persona.role,
                      veto_role: veto_role?(persona), feedback: response }
            @bus&.publish(:council_feedback, entry)
            entry
          end
        end
        feedback = threads.map { |t| t.join(20) ? t.value : nil }.compact

        vetoes = feedback.select { |f| f[:veto_role] && veto_text?(f[:feedback]) }
        unless vetoes.empty?
          veto = vetoes.first
          @bus&.publish(:council_veto, veto)
          return Result.err("council: veto from #{veto[:persona]}\n#{veto[:feedback]}", category: :validation)
        end

        Result.ok(feedback)
      rescue StandardError => e
        Result.err("council: #{e.message}", category: :unknown)
      end

      private

      def validate_dependencies!
        raise ArgumentError, 'personas must be an array' unless @personas.is_a?(Array)
        raise ArgumentError, 'agent must respond to :ask' unless @agent.respond_to?(:ask)
      end

      def veto_role?(persona)
        if persona.respond_to?(:veto?)
          persona.veto?
        else
          persona.respond_to?(:veto_role) && !!persona.veto_role
        end
      end

      def build_prompt(persona, code, context)
        ctx = context ? "\nContext: #{context}\n" : ''
        veto_hint = veto_role?(persona) ? ' You may prefix VETO: if this must not ship.' : ''
        <<~PROMPT
          You are #{persona.name} (#{persona.role}, bias: #{persona.bias}).#{ctx}
          #{persona.prompt}

          Code:
          #{code}

          Provide terse, actionable feedback.#{veto_hint}
        PROMPT
      end

      def veto_text?(feedback)
        feedback.to_s.strip.start_with?('VETO:')
      end
    end
  end
end