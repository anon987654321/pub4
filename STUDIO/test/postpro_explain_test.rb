# frozen_string_literal: true

require "minitest/autorun"
require_relative "../postpro/explain"

class PostproExplainTest < Minitest::Test
  def test_effect_explanation_is_opt_in
    previous = ENV.delete("POSTPRO_EXPLAIN")

    refute PostproExplain.on?
    assert_nil PostproExplain.snapshot(Object.new)
    assert_equal "", PostproExplain.delta(nil, Object.new)
  ensure
    previous.nil? ? ENV.delete("POSTPRO_EXPLAIN") : ENV["POSTPRO_EXPLAIN"] = previous
  end

  def test_unreadable_image_diagnostics_degrade_to_no_measurement
    previous = ENV["POSTPRO_EXPLAIN"]
    ENV["POSTPRO_EXPLAIN"] = "1"

    assert PostproExplain.on?
    assert_nil PostproExplain.snapshot(Object.new)
    assert_equal "", PostproExplain.delta(nil, Object.new)
  ensure
    previous.nil? ? ENV.delete("POSTPRO_EXPLAIN") : ENV["POSTPRO_EXPLAIN"] = previous
  end
end
