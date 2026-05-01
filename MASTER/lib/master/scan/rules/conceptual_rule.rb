# frozen_string_literal: true


module Master
  module Scan
    module Rules
      # ConceptualRule — LLM-based rule violation detection.
      #
      # Checks rules that resist lexical detection via detect_conceptual prompts.
      # Runs only at :deep depth. Makes one LLM call per file and parses
      # structured findings. Skips if no agent is set.
      class ConceptualRule < Rule
        RULES_PATH = File.join(Master::ROOT, "data", "rules.yml").freeze
        CODE_SNIPPET_LIMIT = 2000

        def initialize(agent: nil)
          super()
          @agent       = agent
          @id          = "conceptual"
          @description = "LLM-based rule review (runs at :deep depth only)"
          @severity    = :warning
          @axioms      = load_conceptual_rules
          @axiom_tags  = @axioms.keys.map(&:to_sym)
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
        rescue StandardError => e
          [finding(line: 1, message: "conceptual: scan error — #{e.message}")]
        end

        private

        def load_conceptual_rules
          data = Master.load_yaml(RULES_PATH)
          all_rules = (data["rules"] || {}).values.flatten
          all_rules
            .select { |r| r["detect_conceptual"] }
            .each_with_object({}) { |r, h| h[r["id"]] = r["detect_conceptual"] }
        end

        def build_prompt(code, path)
          axiom_list = @axioms.map { |id, stmt| "#{id}: #{stmt}" }.join("\n")
          <<~PROMPT
            Review #{File.basename(path)} against these rules. List ONLY clear violations.
            Format each as: RULE_ID:LINE:description (one per line)
            If clean, respond with exactly: CLEAN

            Rules:
            #{axiom_list}

            Code (first #{CODE_SNIPPET_LIMIT} chars):
            #{code[0, CODE_SNIPPET_LIMIT]}
          PROMPT
        end

        def parse_findings(response)
          return [] if response.strip.upcase == "CLEAN"

          response.lines.filter_map do |line|
            match_data = line.strip.match(/\A([A-Z_]+):(\d+):(.+)\z/)
            next unless match_data && @axioms.key?(match_data[1])
            finding(line: match_data[2].to_i, message: "#{match_data[1]}: #{match_data[3].strip}")
          end
        end
      end
    end
  end
end
