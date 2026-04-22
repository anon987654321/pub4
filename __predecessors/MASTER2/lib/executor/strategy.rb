# frozen_string_literal: true

module MASTER
  class Executor
    # Shared step-loop plumbing included by every executor strategy.
    #
    # Provides two private helpers so strategy modules contain only
    # config + logic, not repeated infrastructure:
    #
    #   timeout_error_for(start_time)          -> nil | Result.err
    #   injection_error_for(obs, source:)      -> nil | Result.err
    #
    # Typical usage in a step loop:
    #
    module Strategy
      private

      # Converts check_timeout!'s raise into a returnable Result so strategy
      # step loops can use a single-line guard instead of a 4-line begin/rescue.
      def timeout_error_for(start_time)
        check_timeout!(start_time)
        nil
      rescue Result::Error => err
        Result.err(err.message)
      end

      # Unified injection guard for all strategies.  Resolves whichever
      # security module is available (InjectionGuard preferred, Sanitizer
      # as fallback) and returns a Result.err when the observation is unsafe,
      # or nil when it is clean.
      def injection_error_for(observation, source:)
        sanitizer = if defined?(Security::InjectionGuard)
                      Security::InjectionGuard
                    elsif defined?(Security::Sanitizer)
                      Security::Sanitizer
                    end
        return nil unless sanitizer && !sanitizer.safe?(observation)

        Result.err(
          "Injection attempt detected in tool response from '#{source}'. Aborting.",
          category: :validation,
        )
      end
    end
  end
end
