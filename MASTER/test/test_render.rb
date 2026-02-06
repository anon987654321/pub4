# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/result"
require_relative "../lib/typography"
require_relative "../lib/stages/render"

class TestRender < Minitest::Test
  def setup
    @render = MASTER::Stages::Render.new
  end

  def test_formats_response_text
    input = { response: "Hello world" }
    result = @render.call(input)
    
    assert result.ok?
    assert result.value[:rendered]
  end

  def test_preserves_code_blocks
    input = {
      response: "Text\n```ruby\ncode\n```\nMore text"
    }
    
    result = @render.call(input)
    assert result.ok?
    assert_includes result.value[:rendered], "```ruby"
    assert_includes result.value[:rendered], "code"
  end

  def test_handles_empty_response
    input = { response: "" }
    result = @render.call(input)
    
    assert result.ok?
    assert_equal "", result.value[:rendered]
  end
end
