# frozen_string_literal: true

require_relative "test_helper"

# data/attention_context.yml had exactly one reader — the schema test that
# checks its keys exist. The class that implements the protocol carried its own
# copy of the vocabulary, and the two had drifted apart in both directions.
# These tests pin the file as the single source, so the next edit to either one
# cannot silently disagree with the other.
class TestAttentionContext < Minitest::Test
  AC = Master::Ground::AttentionContext

  def test_vocabulary_comes_from_the_protocol_file
    protocol = YAML.safe_load_file(AC::DATA, aliases: true)

    assert_equal protocol.dig("fields", "zoom", "allowed"), AC.valid_zooms
    assert_equal protocol.dig("fields", "act", "allowed"), AC.valid_acts
  end

  # The three the class used to reject while the file allowed them.
  def test_zooms_the_old_constant_rejected_are_accepted
    %w[out lateral narrow_to_wide].each do |zoom|
      assert_equal zoom, AC.new(map: "x", zoom:).zoom, "#{zoom} is in the protocol"
    end
  end

  # The three the class used to allow while the file did not name them.
  def test_acts_the_protocol_does_not_name_fall_back
    %w[repair checkpoint review].each do |act|
      assert_equal AC.default_act, AC.new(map: "x", act:).act, "#{act} is not in the protocol"
    end
  end

  def test_unknown_values_fall_back_to_the_first_allowed
    context = AC.new(map: "x", zoom: "sideways", act: "juggle")

    assert_equal "wide", context.zoom
    assert_equal "scout", context.act
  end

  def test_rendering_uses_the_protocol_templates
    context = AC.new(map: "a/b", zoom: "deep", act: "patch")

    # No bracket tags and no enclosing glyphs: the breadcrumb is read by a
    # person at the top of a reply, and the decoration was the part they asked
    # to lose. NO_ASCII_DECORATION carries the same rule for everything else.
    assert_equal "a/b · zoom deep · act patch", context.to_s
    assert_equal "a/b — zoom deep, act patch", context.to_markdown
  end

  def test_scouting_is_not_complex
    refute AC.new(map: "x").complex?
    assert AC.new(map: "x", act: "patch").complex?
  end

  def test_to_h_round_trips_every_field
    context = AC.new(map: "a", zoom: "deep", act: "mine", target: %w[t], parent: %w[p])

    assert_equal({ map: "a", zoom: "deep", act: "mine", target: %w[t], parent: %w[p] }, context.to_h)
  end

  def test_from_yaml_returns_defaults_for_a_missing_path
    context = AC.from_yaml(File.join(Dir.tmpdir, "no-such-breadcrumb-#{Process.pid}.yml"))

    assert_equal "", context.map
    assert_equal AC.default_zoom, context.zoom
  end
end
