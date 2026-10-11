# frozen_string_literal: true

require "json"
require_relative "outcome_model"

module Master
  module Cognition
    # Turns /fix's terminal event into a trained observation, and only when the
    # event points at a durable receipt whose bytes hash to the digest it names
    # and whose run, state and target agree with the event. Provider prose and
    # ordinary bus events never qualify as task outcomes.
    module FixOutcome
      FAILED_STATES = %w[failed crash validation_failed delivery_failed plateau timeout].freeze

      private

      def capture_fix_outcome(payload)
        envelope = payload[:outcome_receipt] || payload["outcome_receipt"]
        return unless envelope.is_a?(Hash)

        receipt = OutcomeModel.validate_evidence!(
          { source: (envelope[:source] || envelope["source"]).to_s,
            sha256: (envelope[:sha256] || envelope["sha256"]).to_s },
          root: @repo_root,
        )
        data = JSON.parse(receipt.fetch("content").dup.force_encoding(Encoding::UTF_8))
        details = data["details"].is_a?(Hash) ? data["details"] : {}
        state = (payload[:state] || payload["state"]).to_s
        return unless data["command"] == "/fix" && data["state"].to_s == state
        return unless details["run_id"].to_s == (payload[:run_id] || payload["run_id"]).to_s

        target = details["target"].to_s
        return if target.empty? || (payload[:target] || payload["target"]).to_s != target

        record_task_result(
          context: "target=#{target}", action: "/fix", outcome: fix_outcome_for(state),
          evidence: receipt, predicted_probability: recorded_prior(details["outcome_prior"], target)
        )
      rescue StandardError => e
        Ground::Swallow.log(e, context: "cognition.fix_outcome", event_bus: @bus)
        nil
      end

      def fix_outcome_for(state)
        return "success" if state == "done"

        FAILED_STATES.include?(state) ? "failure" : "inconclusive"
      end

      # The probability the loop stated before the run, so the model scores its
      # own prediction against what happened.
      def recorded_prior(prior, target)
        return unless prior.is_a?(Hash) && prior["context"].to_s == "target=#{target}" && prior["action"].to_s == "/fix"

        value = prior["success_probability"]
        value.to_f if value.is_a?(Numeric) && value.between?(0.0, 1.0)
      end
    end
  end
end
