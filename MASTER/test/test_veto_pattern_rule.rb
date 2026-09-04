# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"

class TestVetoPatternRule < Minitest::Test
  def test_detects_secret_pattern
    rule = Master::Review::Scan::Rules::VetoPatternRule.new(root: Master::ROOT)
    code = "key = 'sk-abcdefghijklmnopqrstuvwxyz123456'\n"
    findings = rule.check(code, path: "lib/example.rb")
    assert findings.any?
    assert_match(/veto.*secrets/i, findings.first.message)
  end
end
