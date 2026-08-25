# frozen_string_literal: true

require "securerandom"

module Master
  module Autonomy
    Goal = Data.define(:id, :objective, :risk, :status, :budget, :success_conditions, :failure_conditions) do
      def self.create(objective:, risk: :low, budget: {}, success_conditions: [], failure_conditions: [])
        new(
          id: "goal-#{SecureRandom.hex(6)}",
          objective: objective.to_s.strip,
          risk: normalize_risk(risk),
          status: :running,
          budget: default_budget.merge(symbolize(budget)),
          success_conditions: Array(success_conditions),
          failure_conditions: Array(failure_conditions),
        )
      end

      def with_status(value)
        with(status: value.to_sym)
      end

      def to_h
        {
          id:, objective:, risk:, status:, budget:,
          success_conditions:, failure_conditions:
        }
      end

      def self.normalize_risk(value)
        risk = value.to_s.downcase.to_sym
        %i[low medium high critical].include?(risk) ? risk : :low
      end

      def self.default_budget
        { max_turns: 80, max_attempts_per_task: 3, max_minutes: 60 }
      end

      def self.symbolize(hash)
        hash.each_with_object({}) { |(key, value), out| out[key.to_s.to_sym] = value }
      end

      private_class_method :normalize_risk, :default_budget, :symbolize
    end
  end
end
