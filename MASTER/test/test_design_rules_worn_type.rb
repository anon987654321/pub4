# frozen_string_literal: true

require_relative "test_helper"

# worn_type is law only if something reads it. A profile that exists only in
# rules.yml design_rules is the inert-config hole this tree keeps cutting.
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

  def test_line_height_scale_matches_rails_and_has_a_preferred_body
    allowed = Master::Design::Thresholds.allowed_line_heights(root: Master::ROOT)
    assert_equal [1.0, 1.25, 1.4, 1.5, 1.6], allowed
    assert_in_delta 1.5, Master::Design::Thresholds.body_line_height_preferred(root: Master::ROOT), 0.001
    assert_equal 66, Master::Design::Thresholds.measure_ideal_ch(root: Master::ROOT)
    assert_includes @data.dig("typography", "line_height", "allowed"), 1.25
  end

  def test_micro_typography_tokens_have_a_reader
    micro = Master::Design::Thresholds.micro_typography(root: Master::ROOT)
    assert_equal 3, micro.fetch("orphans")
    assert_equal 3, micro.fetch("widows")
    assert_equal [6, 3, 2], micro.fetch("hyphenate_limit_chars")
    assert_equal "oldstyle-nums", micro.fetch("body_numerals")
    assert_includes micro.fetch("default_features"), "kern"
    assert_in_delta 0.7, micro.fetch("void_target"), 0.001
    assert_includes File.read(File.join(Master::ROOT, "data", "rules.yml")),
                    "Design::Thresholds.micro_typography"
  end
end
