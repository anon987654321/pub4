# MASTER Snapshot — lib/master/council/
Generated: 2026-05-04T10:21:42Z

## lib/master/council/deliberation.rb
```ruby
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
              slots.synchronize { available += 1; ready.signal }
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
```

## lib/master/council/ideation.rb
```ruby
# frozen_string_literal: true

module Master
  module Council
    class Ideation
      DEFAULT_CYCLES = 2

      def initialize(agent:, event_bus: nil)
        @agent = agent
        @bus   = event_bus
      end

      def ideate(prompt, constraints: [], cycles: DEFAULT_CYCLES)
        ideas     = []
        critiques = []

        cycles.times do |cycle|
          result = brainstorm(prompt, ideas, constraints)
          return result if result.err?
          ideas += result.value
          @bus&.publish("ideation:cycle", cycle: cycle + 1, ideas: ideas.size)

          result = critique(ideas)
          return result if result.err?
          critiques << result.value
        end

        result = synthesize(prompt:, ideas:, critiques:, constraints:)
        return result if result.err?

        Master::Result.ok(ideas: ideas, critiques: critiques, final: result.value)
      end

      private

      def brainstorm(prompt, prior, constraints)
        context           = prior.any? ? "Prior ideas (avoid repeating): #{prior.join('; ')}\n\n" : ""
        constraint_prefix = constraints.any? ? "Constraints: #{constraints.join(', ')}\n\n" : ""
        raw     = @agent.ask_once(<<~PROMPT, system: "Generate 3-5 novel, bold ideas. One idea per bullet (- prefix).")
          #{constraint_prefix}#{context}Generate ideas for: #{prompt}
        PROMPT
        return Master::Result.err("ideation: brainstorm failed") if raw.to_s.strip.empty?

        parsed = raw.scan(/^[-*]\s*(.+)/).flatten
        parsed = [raw.strip] if parsed.empty?
        Master::Result.ok(parsed)
      end

      def critique(ideas)
        list = ideas.map { |idea| "- #{idea}" }.join("\n")
        raw  = @agent.ask_once(<<~PROMPT, system: "Critique these ideas. Identify weaknesses, blind spots, risks. Be direct.")
          #{list}
        PROMPT
        return Master::Result.err("ideation: critique failed") if raw.to_s.strip.empty?

        Master::Result.ok(raw.strip)
      end

      def synthesize(prompt:, ideas:, critiques:, constraints:)
        constraint_prefix = constraints.any? ? "Constraints: #{constraints.join(', ')}\n\n" : ""
        list              = ideas.map { |idea| "- #{idea}" }.join("\n")
        crits = critiques.join("\n---\n")
        raw   = @agent.ask_once(<<~PROMPT, system: "Synthesize the best elements into a concrete, practical recommendation. Preserve innovation. Address valid critiques.")
          Goal: #{prompt}
          #{constraint_prefix}
          Ideas:
          #{list}

          Critiques:
          #{crits}
        PROMPT
        return Master::Result.err("ideation: synthesis failed") if raw.to_s.strip.empty?

        Master::Result.ok(raw.strip)
      end
    end
  end
end

```

## lib/master/council/personas.rb
```ruby
# frozen_string_literal: true

module Master
  module Council
    module Personas
      Persona = Data.define(:name, :role, :bias, :prompt, :veto_role) do
        def veto? = veto_role == true
      end

      DEFAULTS = [
        Persona.new(name: "Architect",  role: "System design",   bias: "Structure",
                    prompt: "Review for architectural soundness, coupling, and interface design.", veto_role: false),
        Persona.new(name: "Skeptic",    role: "Devil's advocate", bias: "Caution",
                    prompt: "Find what could go wrong. Challenge every assumption.", veto_role: false),
        Persona.new(name: "Pragmatist", role: "Implementation",  bias: "Shipping",
                    prompt: "Is this shippable? Flag over-engineering.", veto_role: false),
        Persona.new(name: "Security",   role: "Security review", bias: "Safety",
                    prompt: "Find injection vectors, auth bypasses, path traversals. Prefix VETO: if must not ship.", veto_role: true),
        Persona.new(name: "User",       role: "UX advocate",     bias: "Usability",
                    prompt: "Does this serve the user? Are error messages actionable?", veto_role: false),
        Persona.new(name: "Mentor",     role: "Code review",     bias: "Clarity",
                    prompt: "Is this code readable? Do names reveal intent?", veto_role: false)
      ].freeze

      @cache = {}

      def self.load(data_path = nil)
        return DEFAULTS if data_path.nil? || !File.exist?(data_path)

        @cache[data_path] ||= begin
          raw = Master.load_yaml(data_path, symbolize_names: true)
          raise "Invalid persona data" unless raw.is_a?(Array)

          raw.map do |attrs|
            raise "Persona must be a hash" unless attrs.is_a?(Hash)

            attrs = { veto_role: false }.merge(attrs)
            Persona.new(**attrs)
          end.freeze
        rescue StandardError => _e
          DEFAULTS
        end
      end
    end
  end
end
```
