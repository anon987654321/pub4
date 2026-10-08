# frozen_string_literal: true

require "set"

module Master
  module CLI
    class Pipeline
      module Proof
        # What a proof's output names: failed gates from runner.rb's verdict,
        # failed bin/check steps, minitest failures, killed steps, and the
        # ratchet rows selftest and measure print.
        SUITE_HEADER = /\Aproof suite (.+): (ok|FAIL)\z/
        GATE_VERDICT = /\b(\d+) of (\d+) passed in [^;]*autofix (?:on|off)/
        GATE_FAILED = /\A(.+?) (?:failed|errored)\z/
        CHECK_FAILURES = /\Acheck\[\w+\]: \d+ failure\(s\): (.+)\z/
        TEST_HEAD = /\A\s*(?:\d+\)\s+)?(?:Failure|Error):\s*\z/
        TEST_NAME = /\A\s*(\S+#\S+?)(?: \[[^\]]*\])?:?\s*\z/
        TIMEOUT = /step timed out after \d+s: (.+)\z/
        MINITEST_SUMMARY = /\A\d+ runs, \d+ assertions/
        ROWS = {
          /\A\s*\[([A-Z][A-Z_]*)\]\s+(\d+)\s*\z/ => "selftest %s",
          %r{\A\s*([a-z][\w.]*)\s+(\d+)\s*/\s*\d+\s+OVER\b} => "%s",
          /loc_budget: OVER (\S+) (\d+) >/ => "loc_budget %s",
        }.freeze

        # One run of a proof: per unit (the RAILS runner, or one suite) whether
        # it passed, the failures it named and how many checks it counted; the
        # ratchet rows it printed; and how many minitest runs reached a summary.
        Reading = Data.define(:ok, :units, :rows, :finished) do
          def self.parse(ok, out)
            lines = Array(out).map { |line| line.to_s.chomp }
            units = sections(lines).to_h { |name, unit_ok, body| [name, unit(unit_ok.nil? ? ok : unit_ok, body)] }
            new(ok:, units:, rows: rows(lines), finished: lines.count { |line| line.match?(MINITEST_SUMMARY) })
          end

          def self.sections(lines)
            lines.each_with_object([["gates", nil, []]]) do |line, out|
              header = line.match(SUITE_HEADER)
              header ? out << [header[1], header[2] == "ok", []] : out.last.last << line
            end.reject { |name, ok, body| name == "gates" && ok.nil? && body.empty? }
          end

          def self.unit(ok, lines)
            keys = Set.new
            counted = nil
            lines.each_with_index do |line, index|
              counted = gate_keys(line, keys) || counted
              other_keys(line, lines[index + 1].to_s, keys)
            end
            passed, total = counted || [ok ? 1 : 0, 1]
            { ok:, keys:, passed:, total: }
          end

          # A failed bin/check step, a step killed at its timeout, and a
          # minitest failure, whose name is on the line after its header.
          def self.other_keys(line, following, keys)
            line.match(CHECK_FAILURES) { |m| m[1].split(", ").each { |step| keys << "step #{step.strip}" } }
            line.match(TIMEOUT) { |m| keys << "timeout #{m[1]}" }
            following.match(TEST_NAME) { |m| keys << m[1] } if line.match?(TEST_HEAD)
          end

          def self.gate_keys(line, keys)
            verdict = line.match(GATE_VERDICT)
            return unless verdict

            line.split(";").drop(1).each do |part|
              part.strip.match(GATE_FAILED) { |m| m[1].split(", ").each { |gate| keys << gate.strip } }
            end
            [verdict[1].to_i, verdict[2].to_i]
          end

          def self.rows(lines)
            lines.product(ROWS.to_a).each_with_object({}) do |(line, (pattern, label)), found|
              row = line.match(pattern)
              found[format(label, row[1])] = row[2].to_i if row && row[2].to_i.positive?
            end
          end

          def failing = units.values.flat_map { |unit| unit[:keys].to_a }.to_set
          def passed = units.values.sum { |unit| unit[:passed] }
          def total = units.values.sum { |unit| unit[:total] }

          # A unit that failed and named nothing crashed before it could say
          # what failed, so nothing it would have named can be compared.
          def measured? = units.any? && units.values.none? { |unit| !unit[:ok] && unit[:keys].empty? }
        end
      end
    end
  end
end
