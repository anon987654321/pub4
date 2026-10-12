# frozen_string_literal: true

require_relative "test_helper"

class TestFaceLawField < Minitest::Test
  def test_glyphs_come_from_ranked_constitutional_laws
    laws = Master::Face::LawField.laws

    assert_equal 8, laws.size
    assert_equal %w[
      CAPABILITY_STATUS_MUST_BE_TRUTHFUL ROBUSTNESS SINGULARITY LINEARITY
      PROXIMITY ABSTRACTION DENSITY RENDERED_VALUES
    ], laws.map { |row| row.fetch("id") }
    assert_equal Master::Face::LawField.config.fetch("law_glyphs"), laws.map { |row| row.fetch("glyph") }
    assert laws.all? { |row| row.fetch("priority").is_a?(Numeric) && !row.fetch("statement").empty? }
  end

  def test_browser_scene_uses_bounded_head_points_and_laws
    scene = Master::Face::AsciiScene.browser_payload

    assert_equal 1, scene.fetch(:schema)
    assert_equal true, scene.fetch(:available)
    assert_operator scene.fetch(:points).size, :>, 300
    assert_operator scene.fetch(:points).size, :<=, Master::Face::AsciiScene::MAX_POINTS
    assert_equal 8, scene.fetch(:laws).size
    assert_match(/\A[0-9a-f]{64}\z/, scene.fetch(:point_digest))
    assert_equal scene.fetch(:laws), Master::Face::LawField.laws
  end

  def test_terminal_law_ring_is_plain_ascii
    laws = Master::Face::LawField.laws
    renderer = Master::CLI::Face::Ascii.new(Master::CLI::Face::Head.for(20, 40), 20, 40)
    frame = renderer.render(Master::CLI::Face::Motion.rest, laws:).to_s

    assert laws.any? { |law| frame.include?(law.fetch("glyph")) }
    assert_match(/\A[\x20-\x7e\n]+\z/, frame)
  end
end
