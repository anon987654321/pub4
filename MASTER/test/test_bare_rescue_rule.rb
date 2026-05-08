# frozen_string_literal: true

require_relative "test_helper"

class TestBareRescueRule < Minitest::Test
  def setup
    @rule = Master::Scan::Rules::BareRescueRule.new
  end

  def test_detects_bare_rescue
    code = File.read(File.join(__dir__, "fixtures_bare_rescue.rb"))

    findings = @rule.check(code, path: "test/fixtures_bare_rescue.rb")

    refute_empty findings
    assert_equal "bare_rescue", findings.first[:rule]
    assert_match(/specify exception type/, findings.first[:message])
  end

  def test_passes_when_rescue_names_exception
    code = <<~RUBY
      def safe
        do_work
      rescue StandardError => e
        warn e.message
      end
    RUBY

    findings = @rule.check(code, path: "safe.rb")

    assert_empty findings
  end
end
