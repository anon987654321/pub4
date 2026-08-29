# frozen_string_literal: true

module Pub4
  module CheckBrief
    HINTS = {
      "selftest" => {
        category: "known_debt",
        debt_tag: "agent-ignore",
        suggested_action: "skip unless the task targets scan rules; see TODO.md Self-Test Debt",
      },
      "lint:data_singularity" => {
        category: "true_violation",
        debt_tag: nil,
        suggested_action: "fix YAML alias/duplicate keys or restore shard singularity",
      },
      "test:core" => {
        category: "true_violation",
        debt_tag: nil,
        suggested_action: "fix core/ fold spine regression; run rake test:core",
      },
      "test" => {
        category: "true_violation",
        debt_tag: nil,
        suggested_action: "fix failing unit test or revert behavioral change",
      },
      "spec" => {
        category: "true_violation",
        debt_tag: nil,
        suggested_action: "fix failing spec or revert behavioral change",
      },
      "security_sweep" => {
        category: "true_violation",
        debt_tag: nil,
        suggested_action: "resolve security sweep finding before merge",
      },
      "web ui static" => {
        category: "true_violation",
        debt_tag: nil,
        suggested_action: "fix web UI static gate; see web/CLAUDE.md for face boot",
      },
      "test:web" => {
        category: "true_violation",
        debt_tag: nil,
        suggested_action: "fix live web test (MASTER_WEB_LIVE=1)",
      },
      "test:integration_web" => {
        category: "true_violation",
        debt_tag: nil,
        suggested_action: "fix integration web test (MASTER_WEB_LIVE=1)",
      },
      "bin/ci" => {
        category: "operator_gate",
        debt_tag: "operator-priority",
        suggested_action: "run bin/ci locally and fix first failure class",
      },
      "bin/probe all" => {
        category: "operator_gate",
        debt_tag: "operator-priority",
        suggested_action: "run bin/probe all and fix readiness matrix gap",
      },
      "audit" => {
        category: "operator_gate",
        debt_tag: "operator-priority",
        suggested_action: "resolve rake audit finding",
      },
    }.freeze

    module_function

    def hint_for(step_name)
      key = step_name.to_s.strip
      return HINTS[key] if HINTS.key?(key)

      HINTS.each { |pattern, hint| return hint if key.start_with?(pattern) }
      {
        category: "unknown",
        debt_tag: nil,
        suggested_action: "read step output; rerun with CHECK_VERBOSE=1",
      }
    end

    def render(profile:, results:)
      total = results.size
      passed = results.count(&:success)
      failed = results.reject(&:success)
      lines = ["profile: #{profile}", "status: #{failed.empty? ? 'clean' : 'fail'}", "checks_passed: #{passed}/#{total}"]

      return lines.join("\n") if failed.empty?

      first = failed.first
      hint = hint_for(first.name)
      lines << "first_failure: #{first.name}"
      lines << "category: #{hint[:category]}"
      lines << "debt_tag: #{hint[:debt_tag]}" if hint[:debt_tag]
      lines << "suggested_action: #{hint[:suggested_action]}"
      lines << "checks_remaining: #{failed.size}/#{total}"
      snippet = output_snippet(first.output)
      lines << "output_snippet: #{snippet}" if snippet
      lines.join("\n")
    end

    def output_snippet(output)
      line = output.to_s.lines.map(&:strip).reject(&:empty?).find { |l| !l.start_with?("check:") }
      return unless line

      line.length > 120 ? "#{line[0, 117]}..." : line
    end
  end
end
