# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # ConceptualRule — LLM-based axiom violation detection.
      #
      # Checks all philosophy axioms that resist lexical detection:
      # NO_SURPRISES, COMPOSABLE, REVERSIBLE, IDEMPOTENT, JUST_ENOUGH, etc.
      # Runs only at :deep depth. Makes one LLM call per file and parses
      # structured findings. Skips if no agent is set.
      #
      # Meta-note: this rule itself must satisfy JUST_ENOUGH (one LLM call,
      # not one per axiom) and GUARD_EXPENSIVE (depth gate).
      class ConceptualRule < Rule
        PHILOSOPHY_AXIOMS = {
          "NO_SURPRISES"       => "Methods behave exactly as their names suggest. No hidden side effects.",
          "COMPOSABLE"         => "Small pieces that combine cleanly. No tight coupling.",
          "REVERSIBLE"         => "Operations are easy to rollback. Prefer non-destructive paths.",
          "ONE_CHANGE"         => "Each method/class has one focused intent. No shotgun surgery.",
          "IDEMPOTENT"         => "Repeated calls produce the same result. No accidental double-execution.",
          "CQS"                => "Queries don't mutate. Commands don't return meaningful values.",
          "JUST_ENOUGH"        => "No speculative features, premature abstractions, or over-engineering.",
          "CHESTERTONS_FENCE"  => "Nothing removed without understanding why it exists.",
          "GALLS_LAW"          => "Complexity evolved from a working simple system, not designed upfront.",
          "GUARD_EXPENSIVE"    => "Preconditions checked before costly operations (I/O, LLM, network).",
          "DEGRADE_GRACEFULLY" => "Partial failures handled. Fallbacks exist. No hard crashes on external deps.",
        }.freeze

        def initialize(agent: nil)
          super()
          @agent    = agent
          @id       = "conceptual"
          @description = "LLM-based philosophy axiom review (runs at :deep depth only)"
          @severity    = :warning
          @axiom_tags  = PHILOSOPHY_AXIOMS.keys.map(&:to_sym)
        end

        def set_agent(agent)
          @agent = agent
          self
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          return [] unless @agent

          prompt = build_prompt(code, path)
          response = @agent.ask(prompt).to_s
          parse_findings(response)
        rescue => e
          [finding(line: 1, message: "conceptual: scan error — #{e.message}")]
        end

        private

        def build_prompt(code, path)
          axiom_list = PHILOSOPHY_AXIOMS.map { |id, stmt| "#{id}: #{stmt}" }.join("\n")
          <<~PROMPT
            Review #{File.basename(path)} against these axioms. List ONLY clear violations.
            Format each as: AXIOM_ID:LINE:description (one per line)
            If clean, respond with exactly: CLEAN

            Axioms:
            #{axiom_list}

            Code (first 2000 chars):
            #{code[0, 2000]}
          PROMPT
        end

        def parse_findings(response)
          return [] if response.strip.upcase == "CLEAN"

          response.lines.filter_map do |line|
            m = line.strip.match(/\A([A-Z_]+):(\d+):(.+)\z/)
            next unless m && PHILOSOPHY_AXIOMS.key?(m[1])
            finding(line: m[2].to_i, message: "#{m[1]}: #{m[3].strip}")
          end
        end
      end
    end
  end
end
