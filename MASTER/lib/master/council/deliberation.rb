# frozen_string_literal: true

module Master
  module Council
    class Deliberation
      MAX_CONCURRENT  = 4
      MAX_CODE_BYTES  = 8_192
      TRUNCATE_MARKER = "\n... [truncated to #{MAX_CODE_BYTES} bytes for review]".freeze

      def initialize(personas:, agent:, event_bus: nil)
        @personas = personas
        @agent    = agent
        @bus      = event_bus
        validate_dependencies!
      end

      def review(code, context: nil)
        return Master::Result.err("council: no personas configured", category: :validation) if @personas.empty?

        slots = Mutex.new
        available = MAX_CONCURRENT
        ready = ConditionVariable.new

        threads = @personas.map do |persona|
          Thread.new do
            slots.synchronize { ready.wait(slots) until available > 0; available -= 1 }
            begin
              response = @agent.ask(build_prompt(persona, code, context))
              entry = { persona: persona.name, role: persona.role,
                        veto_role: veto_role?(persona), feedback: response }
              @bus&.publish(:council_feedback, entry)
              entry
            rescue StandardError => e
              @bus&.publish("council:persona_error", persona: persona.name, error: e.message)
              nil
            ensure
              slots.synchronize { available += 1; ready.broadcast }
            end
          end
        end
        feedback = threads.map { |thread| thread.join(30) ? thread.value : nil }.compact
        if feedback.empty?
          @bus&.publish(:council_timeout, personas: @personas.map(&:name))
          return Master::Result.err("council: all personas timed out (#{@personas.size})", category: :timeout)
        end

        vetoes = feedback.select { |f| f[:veto_role] && veto_text?(f[:feedback]) }
        unless vetoes.empty?
          veto = vetoes.first
          @bus&.publish(:council_veto, veto)
          return Master::Result.err("council: veto from #{veto[:persona]}\n#{veto[:feedback]}", category: :validation)
        end

        Master::Result.ok(feedback)
      rescue StandardError => e
        Master::Result.err("council: #{e.message}", category: :unknown)
      end

      private

      def validate_dependencies!
        raise ArgumentError, "personas must be an array" unless @personas.is_a?(Array)
        raise ArgumentError, "agent must respond to :ask" unless @agent.respond_to?(:ask)
      end

      def veto_role?(persona)
        if persona.respond_to?(:veto?)
          persona.veto?
        else
          persona.respond_to?(:veto_role) && !!persona.veto_role
        end
      end

      def build_prompt(persona, code, context)
        ctx = context ? "\nContext: #{context}\n" : ""
        veto_hint = veto_role?(persona) ? " You may prefix VETO: if this must not ship." : ""
        safe_code = truncate_code(code.to_s)
        <<~PROMPT
          You are #{persona.name} (#{persona.role}, bias: #{persona.bias}).#{ctx}
          #{persona.prompt}

          Code:
          #{safe_code}

          Provide terse, actionable feedback.#{veto_hint}
        PROMPT
      end

      def truncate_code(code)
        return code if code.bytesize <= MAX_CODE_BYTES
        @bus&.publish(:council_code_truncated, bytes: code.bytesize, limit: MAX_CODE_BYTES)
        code.byteslice(0, MAX_CODE_BYTES) + TRUNCATE_MARKER
      end

      VETO_RE = /\AVETO:/i.freeze

      def veto_text?(feedback)
        VETO_RE.match?(feedback.to_s.strip)
      end
    end
  end
end