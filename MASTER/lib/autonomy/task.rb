# frozen_string_literal: true

require "securerandom"

module Master
  module Autonomy
    Task = Data.define(:id, :goal_id, :parent_id, :title, :state, :position, :attempts, :payload) do
      STATES = %i[pending ready running blocked succeeded failed].freeze

      def self.create(goal_id:, title:, parent_id: nil, position: 0, payload: {})
        new(
          id: "task-#{SecureRandom.hex(6)}",
          goal_id:,
          parent_id:,
          title: title.to_s.strip,
          state: :pending,
          position:,
          attempts: 0,
          payload:
        )
      end

      def runnable?
        %i[pending ready].include?(state)
      end

      def with_state(value, attempts: self.attempts, payload: self.payload)
        with(state: value.to_sym, attempts:, payload:)
      end

      def to_h
        { id:, goal_id:, parent_id:, title:, state:, position:, attempts:, payload: }
      end
    end
  end
end
