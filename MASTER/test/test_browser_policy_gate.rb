# frozen_string_literal: true

require "minitest/autorun"
require_relative "../gates/support/gate_result"

module Master
  ROOT = File.expand_path("..", __dir__) unless const_defined?(:ROOT, false)
end

require_relative "../gates/lib/source/browser_policy"

class TestBrowserPolicyGate < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_gate_returns_a_result_without_masking_an_internal_exception
    result = Deploy::BrowserPolicyGate.run

    assert_instance_of Deploy::GateResult, result
    refute result.errored?, result.errors.join("\n")
  end

  def test_gate_uses_instance_result_methods_not_missing_class_factories
    source = File.read(File.join(ROOT, "gates/lib/source/browser_policy.rb"))

    refute_match(/\bGateResult\.(?:fail|pass)\s*\(/, source)
  end
end
