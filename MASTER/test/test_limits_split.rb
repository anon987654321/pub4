# frozen_string_literal: true

require_relative "test_helper"

# DEBT.md, Inert law and config: "Roughly 28 of data/limits.yml's 39 top-level keys
# have no reader, and the generic accessor workflow_rule(key) has zero call sites —
# ~70% of 794 lines of Tier-1 'law' is decoration."
#
# Measured 2026-08-02: 29 of 38, 477 of 794 lines. Both generic accessors are gone
# and the unread keys moved under `guidance:`, which is a relabelling — reading
# limits` still serves the file whole. This test is what stops the two halves blurring
# back together, and it is the same shape as test_security_defaults.rb.
class TestLimitsSplit < Minitest::Test
  PATH = Master.limits_path

  # enforced key => [file that reads it, the expression it reads it with]
  # Four of these were false and passed anyway, because the check below was a
  # bare substring match on the file's text: `zeitwerk` matched the gem's own
  # `require "zeitwerk"` and `validation` matched `category: :validation`.
  # `conflicts` and `sweep` had no reader at all and now live under guidance:;
  # `dmesg` and `validation` were pointed at files that never open limits.yml.
  READERS = {
    "autoloop" => ["lib/fix/fix_loop/convergence_config.rb", "autoloop"],
    "loc_budgets" => ["Rakefile", "loc_budgets"],
    "dmesg" => ["lib/trace/dmesg.rb", "dmesg"],
    "principle_groups" => ["lib/cli/scan_request.rb", "principle_groups"],
    "process" => ["lib/ops/process_budget.rb", "process"],
    "scan_profiles" => ["lib/cli/scan_request.rb", "scan_profiles"],
    "session_modes" => ["lib/ground/mode_posture.rb", "session_modes"],
    "validation" => ["lib/ground/schema_check.rb", "validation"],
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
      # The name alone is not evidence: this file's whole purpose is keeping
      # unread law from blurring back into enforced law, and a bare
      # assert_includes passed on four false claims — `zeitwerk` matched the
      # gem's own require line. The named file must at least open limits.
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
  # any more, and leaving it below the line is how this file filled up with rules
  # nothing applied.
  def test_nothing_under_guidance_has_grown_a_reader
    sources = Dir.glob(File.join(Master::ROOT, "{lib,core,bin,web/app}", "**", "*.rb"))
                 .reject { |path| path.end_with?("rule_accessors.rb", "rules.rb") }
    bodies = sources.to_h { |path| [path.sub("#{Master::ROOT}/", ""), File.read(path)] }

    # Both halves, or this is the same coincidence in the other direction: a
    # file must open limits AND name the key. scan_report.rb contains the word
    # "conflicts" and has never read limits.yml, which is exactly how the
    # forward map came to carry four false claims.
    promoted = limits.fetch("guidance").keys.filter_map do |key|
      readers = bodies.select do |_, body|
        body.match?(/(["':])#{Regexp.escape(key)}\b/) && body.match?(/limits/i)
      end.keys
      "#{key} → #{readers.first(2).join(", ")}" if readers.any?
    end

    assert_empty promoted,
                 "these guidance keys now have readers — promote them to the top level and add them " \
                 "to READERS:\n  #{promoted.join("\n  ")}"
  end

  # Both accessors that made the unread keys look reachable.
  def test_the_generic_accessors_are_gone
    rules = Master::Ground::Rules.new

    refute_respond_to rules, :workflow_rule, "a generic reader over limits.yml defeats the split"
    refute_respond_to rules, :workflow
  end

  # limits.yml is still read whole, so the guidance is still served —
  # the split relabels it, it does not hide it.
  def test_limits_file_still_contains_guidance
    assert_includes Master::BOOTSTRAP_AUTHORITY_FILES.flatten, "data/limits.yml"
    assert_includes File.read(PATH), "guidance:"
  end

  # phases/code_principles are not merely unread — Ground::WorkflowPolicy hardcodes
  # the same concepts as Ruby constants and never consults this file. Recorded so the
  # next person to edit the YAML expecting an effect finds out here.
  def test_the_ruby_that_actually_governs_phases_is_named
    guidance = limits.fetch("guidance")

    assert guidance.key?("phases"), "phases belongs to guidance until WorkflowPolicy reads it"
    assert guidance.key?("code_principles")
    policy = source("lib/ground/workflow_policy.rb")
    assert_includes policy, "PHASES", "WorkflowPolicy is the enforced source for phases"
    refute_includes policy, "limits.yml", "if WorkflowPolicy starts reading limits.yml, promote the keys"
  end
end
