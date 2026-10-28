# frozen_string_literal: true

require_relative "test_helper"

# data/limits.yml has two halves: top-level keys a named file reads, and the
# unread remainder under `guidance:`. Reading `limits` still serves the file
# whole; this test is what stops the two halves blurring back together, and it
# is the same shape as test_security_defaults.rb.
class TestLimitsSplit < Minitest::Test
  PATH = Master.limits_path

  # enforced key => [file that reads it, the expression it reads it with]
  READERS = {
    "autoloop" => ["lib/fix/supervisor.rb", "autoloop"],
    "convergence_discipline" => ["lib/fix/convergence_discipline.rb", "convergence_discipline"],
    # Named with its unit (body lines), the mechanism lint:spine uses so a stale
    # number cannot pass quietly.
    "loc_body_budgets" => %w[Rakefile loc_body_budgets],
    "dmesg" => ["lib/trace/dmesg.rb", "dmesg"],
    "fix_budget" => ["lib/fix/run_budget.rb", "fix_budget"],
    "fix_time" => ["lib/fix/run_ledger.rb", "fix_time"],
    "governor" => ["lib/fix/governor.rb", "governor"],
    "law_groups" => ["lib/cli/scan/request.rb", "law_groups"],
    "orientation" => ["lib/ai/orientation.rb", "orientation"],
    "process" => ["lib/ops.rb", "process"],
    "scan_profiles" => ["lib/cli/scan/request.rb", "scan_profiles"],
    "scan_workers" => ["lib/fix/scan/transport.rb", "scan_workers"],
    "session_modes" => ["lib/ground/mode_posture.rb", "session_modes"],
    "zeitwerk" => ["lib/master.rb", "zeitwerk"],
  }.freeze

  def limits = @limits ||= Master.load_yaml(PATH)

  def source(relative) = File.read(File.join(Master::ROOT, relative))

  def test_enforced_keys_are_exactly_the_documented_readers
    enforced = limits.keys - %w[schema guidance]

    assert_equal READERS.keys.sort, enforced.sort,
                 "a top-level key changed. Every enforced key needs an entry in READERS; " \
                 "anything without a reader belongs under guidance:"
  end

  def test_every_enforced_key_is_read_by_the_file_that_claims_to_read_it
    READERS.each do |key, (relative, expression)|
      refute_nil limits[key], "#{key} is gone from #{PATH}"
      src = source(relative)
      assert_includes src, expression,
                      "#{relative} no longer reads #{key} — move it under guidance: or fix the reader"
      # The name alone is not evidence: `zeitwerk` also matches the gem's own
      # require line. The named file must at least open limits.
      assert_match(/limits/i, src,
                   "#{relative} contains the word #{key} but never opens #{PATH} — " \
                   "the claim is a coincidence, not a reader")
    end
  end

  def test_guidance_holds_the_unread_remainder
    guidance = limits.fetch("guidance")

    assert_operator guidance.size, :>=, 25, "guidance: should still hold the unread bulk of the file"
    assert_empty guidance.keys & READERS.keys, "a key cannot be both enforced and guidance"
  end

  # The direction that matters. A guidance key that grows a reader is not guidance
  # any more, and leaving it below the line hides an enforced rule.
  def test_nothing_under_guidance_has_grown_a_reader
    sources = Dir.glob(File.join(Master::ROOT, "{lib,bin,../RAILS/master/app}", "**", "*.rb"))
                 .reject { |path| path.end_with?("law_accessors.rb", "laws.rb") }
    bodies = sources.to_h { |path| [path.sub("#{Master::ROOT}/", ""), File.read(path)] }

    # Both halves, or this is the same coincidence in the other direction: a
    # file must open limits AND name the key. limits.yml is string-keyed, so
    # only a quoted key is a read; a `:phases` symbol is some other hash.
    promoted = limits.fetch("guidance").keys.filter_map do |key|
      readers = bodies.select do |_, body|
        body.match?(/["']#{Regexp.escape(key)}\b/) && body.match?(/limits/i)
      end.keys
      "#{key} → #{readers.first(2).join(", ")}" if readers.any?
    end

    assert_empty promoted,
                 "these guidance keys now have readers — promote them to the top level and add them " \
                 "to READERS:\n  #{promoted.join("\n  ")}"
  end

  # Both accessors that made the unread keys look reachable.
  def test_the_generic_accessors_are_gone
    laws = Master::Ground::Laws.new

    refute_respond_to laws, :workflow_law, "a generic reader over limits.yml defeats the split"
    refute_respond_to laws, :workflow
  end

  # The split relabels the guidance; it does not delete it from limits.yml.
  def test_limits_file_still_contains_guidance
    assert_includes File.read(PATH), "guidance:"
  end
end
