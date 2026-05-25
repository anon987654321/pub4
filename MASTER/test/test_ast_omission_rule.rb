# frozen_string_literal: true

require_relative "test_helper"

class TestAstOmissionRule < Minitest::Test
  def setup
    @rule = Master::Judge::Scan::Rules::AstOmissionRule.new
  end

  def test_responds_to_check
    assert_respond_to @rule, :check
  end

  def test_returns_array
    result = @rule.check("def foo; end", path: "foo.rb")
    assert_kind_of Array, result
  end
end
