# frozen_string_literal: true

require "minitest/autorun"

# A threshold copied into prose goes stale the next time the box changes.
#
# OPENBSD/CLAUDE.md said "thresholds are now 8/14" for a month after
# resource_guard.sh moved MEM_RESTORE from 14 to 10 on 2026-08-14 — a
# recalibration the script records in full, with the 1550-tick dataset that
# justified it. Anyone reading the doc to decide whether the guard was tuned
# right was reading a number the running code had abandoned.
#
# The doc is allowed to name a threshold; it is not allowed to name a different
# one from the script. This checks the direction that matters: every number the
# prose attaches to a guard variable has to be the number the script sets.
class GuardThresholdsDocumentedTest < Minitest::Test
  OPENBSD = File.expand_path("..", __dir__)
  SCRIPT = File.join(OPENBSD, "resource_guard.sh")
  DOC = File.join(OPENBSD, "CLAUDE.md")

  # The gates the prose discusses by name.
  VARIABLES = %w[MEM_WARN MEM_RESTORE LOAD_WARN LOAD_RESTORE].freeze

  def script_values
    source = File.read(SCRIPT)
    VARIABLES.to_h do |name|
      # The assignment, not a mention of it in a comment.
      value = source[/^#{name}=([\d.]+)/, 1]
      [name, value]
    end
  end

  def test_the_script_sets_every_threshold_the_doc_discusses
    missing = script_values.select { |_, value| value.nil? }.keys

    assert_empty missing, "resource_guard.sh sets no value for: #{missing.join(', ')}"
  end

  # `MEM_RESTORE` is 10 — a backticked variable followed by a number is the
  # shape the stale sentence used, and the shape worth pinning.
  def test_no_documented_threshold_contradicts_the_script
    doc = File.read(DOC)
    wrong = []

    script_values.each do |name, value|
      doc.scan(/`#{name}`[^.\n]{0,40}?\*{0,2}(\d+(?:\.\d+)?)\*{0,2}/) do |(stated)|
        next if stated == value
        # A sentence recounting history says what a threshold WAS; those carry a
        # year and are not claims about today.
        next if Regexp.last_match.pre_match.lines.last.to_s.match?(/\b20\d\d-\d\d-\d\d\b/)

        wrong << "#{name}: doc says #{stated}, script sets #{value}"
      end
    end

    assert_empty wrong, "the doc names a threshold the script does not set: #{wrong.join('; ')}"
  end

  # The guard has to be reading something. If the assignment regex breaks, the
  # test above passes by comparing nothing.
  def test_the_guard_reads_real_values
    values = script_values.values.compact

    assert_equal VARIABLES.size, values.size
    assert(values.all? { |v| v.to_f.positive? }, "a threshold of zero means the scan broke: #{values.inspect}")
  end
end
