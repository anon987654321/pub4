# frozen_string_literal: true

# Two files carrying the same dimension eventually disagree, and the gates pick
# different ones — a document prescribing a 16px step against design_tokens.yml's
# 0.75rem space_sm leaves no way to tell which scale governs.
#
# A document may mention a value. It may not prescribe one without naming where
# the value lives, because a reader who cannot find the source cannot tell which
# of the two is authoritative.

require "minitest/autorun"
require "yaml"
require_relative "../tools/doc_numbers"

class TestDocNumbers < Minitest::Test
  BASELINE = File.expand_path("../data/doc_baselines.yml", __dir__)

  def self.report = @report ||= Pub4::DocNumbers.run

  def setup
    @report = self.class.report
    @baseline = YAML.safe_load_file(BASELINE).fetch("doc_numbers")
  end

  def test_no_untraceable_dimensions
    unexpected = @report[:findings].filter_map do |doc, rows|
      allowed = (@baseline[doc] || []).map { |row| row.fetch("value") }
      extra = rows.map { |row| row.fetch("value") } - allowed
      "#{doc}: #{extra.join(', ')}" if extra.any?
    end

    assert_empty unexpected,
                 "dimensions prescribed in prose without naming the token that owns them. " \
                 "Name the token (`--tap-min`, design_tokens.yml), or add an entry with a reason " \
                 "to MASTER/data/doc_baselines.yml (doc_numbers:):\n  #{unexpected.join("\n  ")}"
  end

  def test_baseline_has_no_stale_entries
    stale = @baseline.filter_map do |doc, rows|
      found = (@report[:findings][doc] || []).map { |row| row.fetch("value") }
      gone = rows.map { |row| row.fetch("value") } - found
      "#{doc}: #{gone.join(', ')}" if gone.any?
    end

    assert_empty stale,
                 "baseline entries that are now traceable — remove them:\n  #{stale.join("\n  ")}"
  end

  def test_every_baseline_entry_states_a_reason
    missing = @baseline.flat_map do |doc, rows|
      rows.reject { |row| row["why"].to_s.strip.length > 20 }.map { |row| "#{doc}: #{row['value']}" }
    end

    assert_empty missing, "baseline entries without a reason: #{missing.join(', ')}"
  end

  # The checker reads design_tokens.yml. If that file moves or its shape changes,
  # the value set empties and every document passes having been checked against
  # nothing.
  def test_the_checker_measures_something
    assert_operator @report[:values], :>, 10,
                    "only #{@report[:values]} token values extracted — design_tokens.yml moved or changed shape"
    assert_operator @report[:docs], :>, 30,
                    "only #{@report[:docs]} documents scanned"
    refute Pub4::DocNumbers.traceable?("Minimum touch target: 44px.", ["shared_chrome.tap_min"])
    assert Pub4::DocNumbers.traceable?("Minimum touch target: 44px (`--tap-min`).", ["shared_chrome.tap_min"])
  end
end
