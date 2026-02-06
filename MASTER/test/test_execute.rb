# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/result"
require_relative "../lib/pledge"
require_relative "../lib/stages/execute"

class TestExecute < Minitest::Test
  def setup
    @execute = MASTER::Stages::Execute.new
  end

  def test_extracts_and_executes_ruby_code
    input = {
      response: "```ruby\nputs 'hello'\n```"
    }
    
    result = @execute.call(input)
    assert result.ok?
    assert result.value[:executed]
    assert result.value[:success]
    assert_equal 1, result.value[:results].length
    assert_includes result.value[:results][0][:output], "hello"
  end

  def test_returns_false_when_no_code_blocks
    input = { response: "just text" }
    
    result = @execute.call(input)
    assert result.ok?
    refute result.value[:executed]
    assert_empty result.value[:results]
  end

  def test_captures_execution_errors
    input = {
      response: "```ruby\nraise 'boom'\n```"
    }
    
    result = @execute.call(input)
    assert result.ok?
    assert result.value[:executed]
    refute result.value[:success]
  end

  def test_executes_multiple_code_blocks
    input = {
      response: "```ruby\nputs '1'\n```\ntext\n```ruby\nputs '2'\n```"
    }
    
    result = @execute.call(input)
    assert result.ok?
    assert_equal 2, result.value[:results].length
  end
end
