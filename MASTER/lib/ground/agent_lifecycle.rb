# frozen_string_literal: true

module Master
  module Ground
    class AgentLifecycle
      STATES = %i[new planned running waiting verifying complete failed cancelled].freeze
      TRANSITIONS = {
        new: %i[planned running cancelled],
        planned: %i[running cancelled],
        running: %i[waiting verifying complete failed cancelled],
        waiting: %i[running cancelled],
        verifying: %i[running complete failed cancelled],
        complete: [],
        failed: %i[planned cancelled],
        cancelled: [],
      }.freeze

      Event = Struct.new(:from, :to, :reason, :at, keyword_init: true)

      attr_reader :state, :events, :metadata

      def initialize(initial: :new, metadata: {})
        @state = normalize(initial)
        @metadata = metadata
        @events = []
      end

      def transition(to, reason: nil)
        target = normalize(to)
        allowed = TRANSITIONS.fetch(state)
        raise ArgumentError, "invalid transition #{state} -> #{target}" unless allowed.include?(target)

        @events << Event.new(from: state, to: target, reason: reason, at: Time.now.utc)
        @state = target
        self
      end

      def terminal?
        TRANSITIONS.fetch(state).empty?
      end

      def running?
        state == :running
      end

      def failed?
        state == :failed
      end

      def complete?
        state == :complete
      end

      def self.valid_transition?(from, to)
        TRANSITIONS.fetch(normalize_static(from), []).include?(normalize_static(to))
      end

      def self.normalize_static(value)
        key = value.to_s.downcase.to_sym
        STATES.include?(key) ? key : :new
      end

      private

      def normalize(value)
        self.class.normalize_static(value)
      end
    end
  end
end
