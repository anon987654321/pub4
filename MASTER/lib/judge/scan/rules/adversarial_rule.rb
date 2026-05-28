# frozen_string_literal: true

module Master
  module Judge
  module Scan
    module Rules
      # Steelman-first red-team: the model must defend the code before it can attack it.
      # This suppresses false positives by forcing consideration of legitimate reasons
      # before a violation can survive. Deep depth only; one LLM call per file.
      class AdversarialRule < Rule
        PROMPT_TEMPLATE = <<~PROMPT.freeze
          Red-team review of %<path>s.

          Step 1 — Steelman (internal, do not output): write the three strongest
          arguments that this code is correct and should not be changed.

          Step 2 — Answer each question silently; only include findings below
          if they survive the steelman:
            1. What is wrong with this design that I have not spotted?
            2. What would an attacker do with this code?
            3. What assumption is this built on that could be false?
            4. What breaks at scale or under failure?
            5. Is this wired to anything? Could it be deleted without loss?
            6. Is there a simpler approach that was not taken?
            7. What should be relocated or transformed to a different format?

          Step 3 — Output only surviving violations.
          Format: ISSUE:LINE:description (one per line).
          If nothing survives, respond with exactly: CLEAN

          Focus on: broken contracts, hidden coupling, axiom violations (CQS,
          ONE_JOB, GUARD_EXPENSIVE, FAIL_VISIBLY), security, and logic errors.
          Ignore style. Do not hallucinate method names.

          Code (%<lang>s):
          %<code>s
        PROMPT

        def initialize(agent: nil)
          super()
          @agent = agent
          @id = "adversarial"
          @description = "Red-team scan: steelman then challenge — suppresses false positives"
          @severity = :error
          @rule_tags = %i[ONE_JOB CQS GUARD_EXPENSIVE FAIL_VISIBLY COMPOSABLE]
        end

        def self.auto_build? = false

        def set_agent(agent)
          @agent = agent
          self
        end

        def check(code, path:)
          return [] unless (lang = language(path))
          return [] unless @agent

          prompt = format(PROMPT_TEMPLATE, path: File.basename(path),
                                           lang: lang,
                                           code: code[0, 3_000])
          response = @agent.ask(prompt, operation: :scan_adversarial).to_s
          parse_findings(response)
        rescue StandardError => e
          return [] if e.message.to_s =~ /missing configuration|api.?key|unauthorized|no.*provider/i
          [finding(line: 1, message: "adversarial: scan error — #{e.message}")]
        end

        private

        def parse_findings(response)
          response_normalized = response.strip.upcase
          return [] if response_normalized.start_with?("CLEAN")

          response.lines.filter_map do |line|
            match = line.strip.match(/\AISSUE:(\d+):(.+)\z/)
            next unless match
            finding(line: match[1].to_i, message: "adversarial: #{match[2].strip}")
          end
        end
      end
    end
  end
  end
end
