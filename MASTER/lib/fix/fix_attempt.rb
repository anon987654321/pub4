# frozen_string_literal: true

module Master
  module Fix
    class FixAttempt
      def initialize(agent:, attempts:, wait:, extractor:, on_error:)
        @agent = agent
        @attempts = attempts
        @wait = wait
        @extractor = extractor
        @on_error = on_error
      end

      def first_code(prompt:, ext:, source:, wait_context:)
        codes(prompt: prompt, ext: ext, source: source, wait_context: wait_context).first
      end

      def codes(prompt:, ext:, source:, wait_context:)
        @attempts.times.filter_map do |attempt|
          @wait.call(attempt, wait_context)
          code = @extractor.call(@agent.ask(prompt).to_s, ext)
          code if code && code.strip != source.strip
        rescue StandardError => e
          action = @on_error.call(e)
          next if action == :retry
          break nil
        end
      end
    end
  end
end
