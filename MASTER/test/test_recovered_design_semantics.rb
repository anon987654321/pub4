# frozen_string_literal: true

require_relative "test_helper"
require File.join(Master::ROOT, "law", "law") unless defined?(::Law)
::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.rules.empty?

class TestRecoveredDesignSemantics < Minitest::Test
  EXPECTED = %i[
    README_VISION
    INTERACTION_SEMANTICS
    HTML_HEADING_HIERARCHY
    CONFIGURATION_SHAPE
    STYLE_FOLLOWS_STRUCTURE
  ].freeze

  def test_recovered_laws_are_registered_once
    EXPECTED.each { |id| assert Law.rules.key?(id), "missing recovered law #{id}" }
    assert_equal EXPECTED.length, EXPECTED.uniq.length
  end

  def test_readme_vision_rejects_long_setup_first_paragraph
    rule = Law.rules.fetch(:README_VISION)
    bad = "# title\n\nSetup. Details. More details. More details.\n"
    good = "# title\n\nThe vision is first. The rest follows.\n"

    refute_empty rule.scan(bad)
    assert_empty rule.scan(good)
  end

  def test_configuration_shape_rejects_excessive_nesting
    rule = Law.rules.fetch(:CONFIGURATION_SHAPE)
    bad = <<~YAML
      a:
        b:
          c:
            d:
              e: true
    YAML
    good = <<~YAML
      retries: 3
      timeout: 30
      logging:
        level: info
    YAML

    refute_empty rule.scan(bad, file: "config.yml")
    assert_empty rule.scan(good, file: "config.yml")
    refute_empty rule.scan(bad, file: "config.json")
    assert_empty rule.scan(good, file: "config.json")
  end

  def test_semantic_laws_are_questions_not_fake_lexical_detectors
    assert Law.rules.fetch(:INTERACTION_SEMANTICS).semantic?
    assert Law.rules.fetch(:HTML_HEADING_HIERARCHY).semantic?
    assert Law.rules.fetch(:STYLE_FOLLOWS_STRUCTURE).semantic?
    refute Law.rules.fetch(:INTERACTION_SEMANTICS).scannable?
    refute Law.rules.fetch(:STYLE_FOLLOWS_STRUCTURE).scannable?
  end

  def test_each_recovered_law_has_worked_examples
    EXPECTED.each do |id|
      rule = Law.rules.fetch(id)
      assert_operator rule.bad.to_s.length, :>, 0, "#{id} missing bad example"
      assert_operator rule.good.to_s.length, :>, 0, "#{id} missing good example"
      assert_operator rule.fix.to_s.length, :>, 0, "#{id} missing fix"
    end
  end
end
