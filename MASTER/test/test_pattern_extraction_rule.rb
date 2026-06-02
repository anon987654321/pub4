# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/judge/scan/rules/structural_rules"

class TestPatternExtractionRule < Minitest::Test
  def setup
    @rule = Master::Judge::Scan::Rules::PatternExtractionRule.new
  end

  def test_detects_strategy_opportunity
    code = <<~RUBY
      def route(kind)
        case kind
        when :email
          send_email
        when :sms
          send_sms
        when :push
          send_push
        else
          noop
        end
      end
    RUBY

    findings = @rule.check(code, path: "router.rb")

    assert_equal 1, findings.size
    assert_equal "PATTERN_EXTRACTION", findings.first.rule
    assert_match(/Strategy opportunity/, findings.first.message)
  end

  def test_detects_pipeline_opportunity
    code = <<~RUBY
      def render(input)
        parsed = parse(input)
        normalized = normalize(parsed)
        scored = score(normalized)
        formatted = format(scored)
        formatted
      end
    RUBY

    findings = @rule.check(code, path: "pipeline.rb")

    assert_equal 1, findings.size
    assert_match(/Pipeline opportunity/, findings.first.message)
  end

  def test_ignores_small_methods
    code = <<~RUBY
      def present(value)
        normalized = normalize(value)
        format(normalized)
      end
    RUBY

    assert_empty @rule.check(code, path: "small.rb")
  end
end
