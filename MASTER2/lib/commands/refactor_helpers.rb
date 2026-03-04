# frozen_string_literal: true

module Commands
  module RefactorHelpers
    PROPOSALS_LINE_TEMPLATE = "\n  Proposals: %<proposals>s"
    COST_LINE_TEMPLATE = "  Cost: %<cost>s"

    Result = Struct.new(:success?, :value, :error, keyword_init: true) do
      def self.ok(value = nil) = new(success?: true, value: value, error: nil)
      def self.err(error) = new(success?: false, value: nil, error: error)
    end

    def apply_refactor(refactor_context:, execute: false)
      proposals = Array(refactor_context.fetch(:proposals, []))
      return Result.err(:no_proposals) if proposals.empty?

      cost_value = refactor_context.fetch(:cost, nil)
      summary_lines = build_refactor_summary_lines(
        proposals: proposals,
        cost_value: cost_value,
        currency_formatter: refactor_context.fetch(:currency_formatter, method(:default_currency_formatter))
      )

      return Result.ok(summary_lines: summary_lines, applied: false) unless execute

      executor = refactor_context.fetch(:executor, nil)
      return Result.err(:missing_executor) unless executor

      apply_result = executor.call(proposals: proposals)
      Result.ok(summary_lines: summary_lines, applied: true, apply_result: apply_result)
    end

    def build_refactor_summary_lines(proposals:, cost_value:, currency_formatter:)
      lines = [format(PROPOSALS_LINE_TEMPLATE, proposals: proposals.count)]
      lines << format(COST_LINE_TEMPLATE, cost: currency_formatter.call(cost_value)) unless cost_value.nil?
      lines
    end

    def default_currency_formatter(cost_value)
      return "" if cost_value.nil?

      if defined?(UI) && UI.respond_to?(:currency_precise)
        UI.currency_precise(cost_value)
      else
        cost_value.to_s
      end
    end

    private :build_refactor_summary_lines, :default_currency_formatter
  end
end