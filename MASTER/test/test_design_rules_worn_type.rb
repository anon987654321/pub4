# frozen_string_literal: true

require_relative "test_helper"

# worn_type is law only if something reads it. A profile that exists only in
# design_rules.yml is the inert-config hole this tree keeps cutting.
class TestDesignRulesWornType < Minitest::Test
  PROFILES = %w[feed catalog chat immersive map legal auth].freeze

  def setup
    @data = Master::Design::Thresholds.load(root: Master::ROOT)
    @worn = @data.fetch("worn_type")
    # gates/support/, not gates/lib/. The reader moved and this was the only
    # reference that did not follow — AGENTS.md, DECISIONS.md, agent_map.yml,
    # design_rules.yml and rendered_gates_test.rb had all been updated. The test
    # errored on ENOENT rather than failing, so it reported a missing file where
    # its subject is "every profile has a reader".
    @reader = File.join(Master::ROOT, "..", "RAILS", "gates", "support", "geometry_type.rb")
  end

  def test_worn_type_profiles_exist
    profiles = @worn.fetch("profiles")
    PROFILES.each { |name| assert profiles[name], "worn_type.profiles.#{name} missing" }
  end

  def test_thresholds_worn_profile_merges_feed_defaults
    catalog = Master::Design::Thresholds.worn_profile("catalog", root: Master::ROOT)
    assert_equal "catalog", catalog["name"]
    assert catalog["require_tabular_nums"]
    assert catalog["measure_min_ch"]
  end

  def test_every_profile_has_a_reader
    src = File.read(@reader)
    PROFILES.each do |name|
      assert_includes src, name, "geometry_type.rb must name profile #{name}"
    end
    assert_includes src, "check_measure"
    assert_includes src, "check_type_scale"
    assert_includes src, "check_baseline"
    assert_includes src, "check_tabular"
    assert_includes src, "check_accents"
    assert_includes src, "check_empty"
    assert_includes src, "check_split"
    assert_includes src, "check_hanging"
  end

  def test_feed_measure_is_the_short_column
    feed = @worn.dig("profiles", "feed")
    assert_operator feed["measure_max_ch"].to_i, :<=, 55
    prose = @data.dig("typography", "line_length", "ideal_ch").to_i
    assert_operator prose, :>=, 60
    refute_equal feed["measure_max_ch"].to_i, prose,
                 "feed and legal/prose must stay different jobs"
  end
end
