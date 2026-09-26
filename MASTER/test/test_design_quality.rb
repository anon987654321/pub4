# frozen_string_literal: true

require_relative "test_helper"
require_relative "../gates/support/design_quality"

class TestDesignQuality < Minitest::Test
  def element(x:, y:, w: 100, h: 44, font_size: 16, font_weight: 400, text: "text", is_control: false, is_image: false)
    Deploy::DesignQuality::Element.new(
      tag: is_control ? "button" : "p",
      role: is_control ? "button" : nil,
      text: text,
      x:, y:, w:, h:,
      font_size:, font_weight:,
      color: "#ffffff",
      bg_color: "#000000",
      is_text: !text.empty?,
      is_control:,
      is_image:
    )
  end

  def test_hard_floor_rejects_small_controls
    vector = Deploy::DesignQuality.calculate(
      elements: [element(x: 0, y: 0, w: 40, h: 40, is_control: true)],
      viewport: { w: 390, h: 844 },
      dialect: :social
    )

    refute vector.hard_ok?
    refute vector.tap_ok
  end

  def test_hard_floor_rejects_contrast_failure
    vector = Deploy::DesignQuality.calculate(
      elements: [element(x: 0, y: 0)],
      viewport: { w: 390, h: 844 },
      dialect: :social,
      contrast_ok: false
    )

    refute vector.hard_ok?
    refute vector.contrast_ok
  end

  def test_soft_vector_is_bounded
    vector = Deploy::DesignQuality.calculate(
      elements: [element(x: 0, y: 0), element(x: 100, y: 27, font_size: 24, font_weight: 700)],
      viewport: { w: 390, h: 844 },
      dialect: :social
    )

    vector.soft_axes.values.each do |value|
      assert_operator value, :>=, 0.0
      assert_operator value, :<=, 1.0
    end
    assert vector.contrast_ok
  end

  def test_regression_detects_soft_drop_but_not_within_epsilon
    before = Deploy::DesignQuality::Vector.new(
      rhythm: 1.0, hierarchy: 1.0, density: 1.0, alignment: 1.0, balance: 1.0,
      tap_ok: true, contrast_ok: true
    )
    after = before.dup
    after.rhythm = 0.90
    assert after.regresses?(before)

    after.rhythm = 0.98
    refute after.regresses?(before)
  end
end
