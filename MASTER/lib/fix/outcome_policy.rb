# frozen_string_literal: true

require_relative "../execution/contract"

module Master
  module Fix
    # The functional core for /fix terminal-state decisions.
    #
    # This is the single vocabulary and mapping shared by the repair loop,
    # its protocol document, and the review scorecard. Unknown states fail
    # closed; only a recognized DONE may claim successful repair.
    module OutcomePolicy
      TERMINAL_STATES = Master::Execution::Contract::TERMINAL_STATES

      PARTIAL_ENDINGS = %i[
        plateau timeout blocked human_decision inconclusive cancelled unknown_outcome recovery_failed
      ].freeze

      MEASURED_REPAIR_OUTCOMES = {
        done: true, plateau: false, crash: false, skip: false, blocked: false,
        validation_failed: false, delivery_failed: false, timeout: false,
        inconclusive: false, failed: false, reloading: false,
        cancelled: false, unknown_outcome: false, recovery_failed: false
      }.freeze

      ERROR_STATES = {
        timeout: :timeout,
        crash: :crash,
        skip: :skip,
        delivery_failed: :delivery_failed,
        policy: :blocked,
        human_decision: :human_decision,
        plateau: :plateau,
        reloading: :reloading,
        inconclusive: :inconclusive,
        validation: :validation_failed,
        cancelled: :cancelled,
        unknown_outcome: :unknown_outcome,
        recovery_failed: :recovery_failed,
        failed: :failed,
      }.freeze

      module_function

      # Translate a structured Result into a known terminal state.
      # Success alone is insufficient: the payload must name a known state.
      def terminal_state(result)
        return :failed unless result.respond_to?(:ok?) && result.respond_to?(:err?)
        return ERROR_STATES.fetch(result.category, :failed) if result.err?
        return :failed unless result.ok?

        value = result.value!
        candidate = value.is_a?(Symbol) ? value : extract_state(value)
        normalize_state(candidate) || :failed
      end

      # Read only a leading uppercase terminal marker; ordinary prose and
      # lowercase lookalikes are not authoritative workflow states.
      def extract_state(message)
        match = message.to_s.match(/\A([A-Z_]+)(?=:|\s|\z)/)
        match && match[1].downcase.to_sym
      end

      def normalize_state(value)
        Master::Execution::Contract.normalize_terminal_state(value)
      end

      # Classify the review's fix outcome without side effects. Missing or
      # unknown state is incomplete, never done; delivered commits can make a
      # recognized interrupted ending partial rather than failed.
      def workflow_outcome(ok:, msg:, delivered:, ending: nil)
        raw_ending = ending.nil? ? extract_state(msg) : ending
        state = normalize_state(raw_ending)

        return :done if ok && state == :done
        return :partial if delivered.to_i.positive? && PARTIAL_ENDINGS.include?(state)

        ok ? :incomplete : :failed
      end

      def halted?(ending)
        !ending.nil? && normalize_state(ending) != :done
      end
    end
  end
end
