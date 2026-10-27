# frozen_string_literal: true

require "set"

module Master
  module CLI
    class Pipeline
      module Proof
        # What a proof's output names: failed checks from runner.rb's verdict,
        # failed bin/check steps, minitest failures, killed steps, and the
        # ratchet rows selftest and measure print.
        SUITE_HEADER = /\Aproof suite (.+): (ok|FAIL)\z/
        CHECK_VERDICT = /\b(\d+) pass, (\d+) fail, \d+ skip, (\d+) inconclusive, (\d+) error in [^;]*autofix (?:on|off)/
        CHECK_FAILED = /\A(?:failed|errored)=(.+)\z/
        CHECK_UNMEASURED = /\Ainconclusive=(.+)\z/
        CHECK_FAILURES = /\Acheck\d+ at \S+: \d+ failure\(s\), (.+)\z/
        TEST_HEAD = /\A\s*(?:\d+\)\s+)?(?:Failure|Error):\s*\z/
        TEST_NAME = /\A\s*(\S+#\S+?)(?: \[[^\]]*\])?:?\s*\z/
        TIMEOUT = /step timed out after \d+s: (.+)\z/
        MINITEST_SUMMARY = /\A\d+ runs, \d+ assertions/
        # bin/check prints a step's output under its own unit (check_ci30: ...), and the test
        # name and summary patterns above are anchored at the start of a bare line.
        UNIT_PREFIX = /\A[a-z][a-z0-9_]*\d+(?: at \S+)?: /
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
            finished = lines.count { |line| bare(line).match?(MINITEST_SUMMARY) }
            new(ok:, units:, rows: rows(lines), finished:)
          end

          def self.sections(lines)
            lines.each_with_object([["checks", nil, []]]) do |line, out|
              header = line.match(SUITE_HEADER)
              header ? out << [header[1], header[2] == "ok", []] : out.last.last << line
            end.reject { |name, ok, body| name == "checks" && ok.nil? && body.empty? }
          end

          def self.unit(ok, lines)
            keys = Set.new
            counted = nil
            lines.each_with_index do |line, index|
              counted = check_keys(line, keys) || counted
              other_keys(line, lines[index + 1].to_s, keys)
            end
            passed, total = counted || [ok ? 1 : 0, 1]
            { ok:, keys:, passed:, total:, unmeasured: unmeasured_checks(lines) }
          end

          # Checks the runner could not measure: neither passed nor failed, and never green.
          def self.unmeasured_checks(lines)
            parts = lines.flat_map { |line| line.split(";").drop(1) }
            named = parts.filter_map { |part| part.strip[CHECK_UNMEASURED, 1] }
            named.flat_map { |list| list.split(",").map(&:strip) }.to_set
          end

          # A failed bin/check step, a step killed at its timeout, and a
          # minitest failure, whose name is on the line after its header.
          def self.other_keys(line, following, keys)
            line.match(CHECK_FAILURES) { |m| m[1].split(", ").each { |step| keys << "step #{step.strip}" } }
            line.match(TIMEOUT) { |m| keys << "timeout #{m[1]}" }
            bare(following).match(TEST_NAME) { |m| keys << m[1] } if bare(line).match?(TEST_HEAD)
          end

          def self.bare(line) = line.sub(UNIT_PREFIX, "")

          def self.check_keys(line, keys)
            verdict = line.match(CHECK_VERDICT)
            return unless verdict

            named = line.split(";").drop(1).filter_map { |part| part.strip[CHECK_FAILED, 1] }
            keys.merge(named.flat_map { |list| list.split(",").map(&:strip) })
            passed = verdict[1].to_i
            [passed, passed + verdict[2].to_i + verdict[3].to_i + verdict[4].to_i]
          end

          def self.rows(lines)
            lines.product(ROWS.to_a).each_with_object({}) do |(line, (pattern, label)), found|
              row = line.match(pattern)
              found[format(label, row[1])] = row[2].to_i if row && row[2].to_i.positive?
            end
          end

          # The stored baseline is JSON, so reading it back runs no code.
          def self.from_stored(row)
            units = row.fetch("units").transform_values do |unit|
              { ok: unit.fetch("ok"), keys: unit.fetch("keys").to_set, passed: unit.fetch("passed"),
                total: unit.fetch("total"), unmeasured: unit.fetch("unmeasured").to_set }
            end
            new(ok: row.fetch("ok"), units:, rows: row.fetch("rows"), finished: row.fetch("finished"))
          end

          def to_stored
            stored_units = units.transform_values do |unit|
              unit.merge(keys: unit[:keys].to_a, unmeasured: unit[:unmeasured].to_a)
            end
            { "ok" => ok, "units" => stored_units, "rows" => rows, "finished" => finished }
          end

          def failing = units.values.flat_map { |unit| unit[:keys].to_a }.to_set
          def unmeasured = units.values.flat_map { |unit| unit[:unmeasured].to_a }.to_set
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
