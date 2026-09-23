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

      def first_code(prompt:, ext:, source:, wait_context:, image: nil)
        # codes returns nil when on_error stops the run (`break nil`). Calling
        # .first on that nil is the NoMethodError /fix RAILS hit on NO_GOD_CLASS.
        codes(prompt:, ext:, source:, wait_context:, image:)&.first
      end

      def codes(prompt:, ext:, source:, wait_context:, image: nil)
        @attempts.times.filter_map do |attempt|
          @wait.call(attempt, wait_context)
          code = @extractor.call(ask_agent(prompt, image:).to_s, ext)
          code if code && code.strip != source.strip
        rescue StandardError => e
          action = @on_error.call(e)
          next if action == :retry
          break nil
        end
      end

      private

      def ask_agent(prompt, image:)
        image ? @agent.ask(prompt, image:) : @agent.ask(prompt)
      end
    end
  end
end
