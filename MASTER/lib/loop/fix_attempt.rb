# frozen_string_literal: true

module Master
  module Loop
    # O205: shared fix attempt flow for council_fix and genetic_fix.
    class FixAttempt
      RATE_LIMIT_SLEEP = 10

      def initialize(agent:, scanner:, rule_loop:)
        @agent = agent
        @scanner = scanner
        @rule_loop = rule_loop
      end

      def council(violation, prompt:)
        path = violation[:file]
        src = File.read(path, encoding: "UTF-8")
        RuleLoop::MAX_FIX_RETRIES.times do |attempt|
          sleep RATE_LIMIT_SLEEP * attempt if attempt.positive?
          response = @agent.ask(prompt).to_s
          return nil if response.strip == "UNCHANGED"
          code = @rule_loop.send(:extract_code, response, File.extname(path).downcase)
          return code if code && code.strip != src.strip
        rescue StandardError => e
          action = @rule_loop.send(:handle_fix_exception, e, violation, event: "rule_loop:council_error")
          next if action == :retry
          return nil
        end
        nil
      end

      def genetic(violation, prompt:, path:, src:)
        ext = File.extname(path).downcase
        candidates = RuleLoop.candidate_count.times.filter_map do |attempt|
          sleep RATE_LIMIT_SLEEP if attempt.positive?
          code = @rule_loop.send(:extract_code, @agent.ask(prompt).to_s, ext)
          code if code && code.strip != src.strip
        rescue StandardError => e
          action = @rule_loop.send(:handle_fix_exception, e, violation, event: "rule_loop:fix_error")
          next if action == :retry
          break nil
        end
        @rule_loop.send(:best_candidate, candidates || [], path)
      end
    end
  end
end