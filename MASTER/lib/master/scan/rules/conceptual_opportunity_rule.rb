# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Mirror of ConceptualRule for refactor opportunities, not violations. Asks the
      # LLM what pattern this file is 80% of the way to (Strategy, Decorator, Pipeline,
      # Visitor, Builder) and where extraction would pay off. Severity :info — deep
      # depth only — opportunities are aspirational, not failing checks.
      class ConceptualOpportunityRule < Rule
        CODE_SNIPPET_LIMIT = 2000
        PATTERNS = %w[Strategy Decorator Pipeline Visitor Builder Observer Command
                      State Adapter NullObject].freeze

        def initialize(agent: nil)
          super()
          @agent       = agent
          @id          = "conceptual_opportunity"
          @description = "Refactor opportunity — pattern this file is 80% of the way to"
          @severity    = :info
          @axiom_tags  = %i[SIMPLEST_WORKS DECOUPLE ABSTRACTION]
        end

        def self.auto_build? = false

        def set_agent(agent)
          @agent = agent
          self
        end

        def check(code, path:)
          return [] unless language(path) && @agent
          response = @agent.ask(build_prompt(code, path), operation: :scan_conceptual_opportunity).to_s
          parse_findings(response)
        rescue StandardError
          []
        end

        private

        def build_prompt(code, path)
          <<~PROMPT
            Audit #{File.basename(path)} for refactor *opportunities* — not bugs.
            For each, name a pattern from this set: #{PATTERNS.join(', ')}.
            Only flag when the file is genuinely close to instantiating that pattern;
            do not propose patterns that would add complexity for its own sake.

            Format each opportunity: PATTERN:LINE:short reason (one per line).
            If none, respond with exactly: NONE.

            Code (first #{CODE_SNIPPET_LIMIT} chars):
            #{code[0, CODE_SNIPPET_LIMIT]}
          PROMPT
        end

        def parse_findings(response)
          return [] if response.strip.upcase == "NONE"
          response.lines.filter_map do |line|
            match = line.strip.match(/\A([A-Z][A-Za-z]+):(\d+):(.+)\z/)
            next unless match && PATTERNS.include?(match[1])
            { rule: "opportunity.#{match[1].downcase}", message: "#{match[1]}: #{match[3].strip}",
              line: match[2].to_i, severity: @severity, fix: nil, tags: [match[1].to_sym] }
          end
        end
      end
    end
  end
end
