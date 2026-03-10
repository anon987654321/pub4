# frozen_string_literal: true

module MASTER
  # Persistent violation event hooks.
  # Appends to .constitutional_violations.jsonl on each violation found.
  module ViolationHooks
    LOG_PATH = File.join(Dir.pwd, ".constitutional_violations.jsonl").freeze

    module_function

    def on_violation_found(violation, file: nil, session_id: nil)
      entry = {
        t: Time.now.utc.iso8601,
        session: session_id,
        file: file,
        principle_id: violation[:principle_id],
        severity: violation[:severity],
        smell: violation[:smell],
        line: violation[:line],
        message: violation[:explanation] || violation[:message],
      }.compact
      File.open(LOG_PATH, "a") { |f| f.puts(JSON.generate(entry)) }
    rescue StandardError
      nil # never crash on hook failure
    end

    def on_cost_threshold(current:, limit:, warn_at:)
      return unless current >= warn_at
      pct = (current / limit * 100).round
      UI.warn("Cost warning: $#{format("%.3f", current)} (#{pct}% of $#{format("%.2f", limit)} limit)")
    end
  end
end
