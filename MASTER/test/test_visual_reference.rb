# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/fix/visual_reference"

class TestVisualReference < Minitest::Test
  def test_profiles_are_descriptive_lenses
    profiles = Master::Fix::VisualReference.profiles

    assert_equal %w[joi kaufland x], profiles.keys.sort
    profiles.each_value do |profile|
      assert profile[:name]
      assert_operator profile[:signals].length, :>, 0
    end
  end

  def test_context_keeps_master_as_authority
    context = Master::Fix::VisualReference.context

    assert_includes context, "MASTER laws remain authoritative"
    assert_includes context, "not a scorecard, ranking"
    assert_includes context, "x:"
    assert_includes context, "joi:"
    assert_includes context, "kaufland:"
  end
end
