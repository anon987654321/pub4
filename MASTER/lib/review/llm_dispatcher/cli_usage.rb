# frozen_string_literal: true

require "json"
require_relative "../../ground/swallow"

module Master
  module Review
    class LLMDispatcher
      # What a command-line lane's call spent, into the session's costs ledger that RunBudget#spend reads.
      # Before this every claude-cli call billed nothing: the /fix heartbeat read "tokens = 0 (0)" for a
      # whole run, and no spend cap could trip on the lane the run used most.
      module CliUsage
        USAGE_KEYS = %w[input_tokens cache_read_input_tokens cache_creation_input_tokens output_tokens].freeze

        private

        # The final `result` event of a json or stream-json run, or nil when stdout carried none.
        def claude_result_event(out)
          out.lines.reverse_each do |line|
            next unless line.lstrip.start_with?("{")

            event = JSON.parse(line)
            return event if event.is_a?(Hash) && event["type"] == "result"
          rescue JSON::ParserError
            next
          end
          nil
        end

        # Every run ends in a json result: its usage goes to the ledger, its text is the reply.
        def claude_answer(out, model)
          event = claude_result_event(out)
          record_claude_usage(event, model)
          claude_cli_reply(claude_stream_reply(out, event).to_s, json: true)
        end

        # The reply of a json or stream-json run: the result event's text. An error event is no reply, except
        # the subscription's limit, which claude_cli_reply must still see to stand the lane down as a quota.
        # Stdout holding no JSON line at all is read as the reply itself, the way a plain-text run answered.
        def claude_stream_reply(out, event = claude_result_event(out))
          return (out.lines.none? { |line| line.lstrip.start_with?("{") } ? out : nil) unless event

          text = event["result"].to_s
          !event["is_error"] || text.match?(CliSender::CLAUDE_CLI_LIMIT) ? text : nil
        end

        # The amount is the CLI's own total_cost_usd, what the same tokens cost at API prices: a
        # subscription bills none of it in money but spends its quota in proportion, so the run's dollar
        # cap is the quota's proxy for this lane.
        def record_claude_usage(event, model)
          return unless @session && event.is_a?(Hash)

          input, cached, cache_write, output = claude_usage_counts(event)
          tokens = input + cached + cache_write + output
          cost = event["total_cost_usd"].is_a?(Numeric) ? event["total_cost_usd"].to_f : 0.0
          return if tokens.zero? && cost.zero?

          @session.record_cost(cost, model:, tokens:)
          publish_llm_cost(model:, cost:, tokens:, tokens_in: tokens - output, tokens_out: output,
                           cached:, cache_write:)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "CliUsage.record_claude_usage", model:)
        end

        def claude_usage_counts(event)
          usage = event["usage"].is_a?(Hash) ? event["usage"] : {}
          USAGE_KEYS.map { |key| usage[key].to_i }
        end

        # A lane that reports no usage is billed an estimate from the characters it was sent and gave back,
        # marked approximate in the ledger, so its calls still count against the run's budgets.
        def record_estimated_cli_usage(model:, prompt:, reply:)
          return unless @session

          tokens = Master::Trace::Session.estimate_tokens(prompt) + Master::Trace::Session.estimate_tokens(reply)
          return if tokens.zero?

          @session.record_cost(0.0, model:, tokens:, approximate: true)
          publish_llm_cost(model:, cost: 0.0, tokens:, estimated: true, approximate: true)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "CliUsage.record_estimated_cli_usage", model:)
        end
      end
    end
  end
end
