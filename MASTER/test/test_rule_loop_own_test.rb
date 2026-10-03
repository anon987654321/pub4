# frozen_string_literal: true

require_relative "test_helper"

# A fix is refused when the file's own test fails after it lands. The runner
# called bare `ruby test/test_doctor.rb`, which cannot load test_helper, so
# the first fix /fix MASTER's verifier approved (bin/doctor's rescue) was
# refused for a test that passes when the suite runs it.
class TestRuleLoopOwnTest < Minitest::Test
  def test_a_passing_own_test_does_not_refuse_the_fix
    loop = Master::Fix::RuleLoop.allocate
    loop.instance_variable_set(:@root, Master::ROOT)

    assert_nil loop.send(:failing_test_for, File.join(Master::ROOT, "bin", "doctor"))
  end
end
