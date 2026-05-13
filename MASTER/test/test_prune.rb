# frozen_string_literal: true

require_relative "test_helper"

class TestPrune < Minitest::Test
  def stage
    Master::Now::Stages::Prune.new
  end

  def call(text)
    stage.call({ output: text })
  end

  def test_strips_preamble
    r = call("Certainly! Here is the answer.")
    assert r.ok?
    assert_equal "Here is the answer.", r.value![:output]
  end

  def test_strips_hedge
    r = call("I think that Ruby is great.")
    assert r.ok?
    assert_equal "Ruby is great.", r.value![:output]
  end

  def test_skips_code_blocks
    code = "```ruby\njust use this\n```"
    r = call(code)
    assert_equal code, r.value![:output]  # must not mangle code
  end

  def test_passthrough_non_string
    r = stage.call({ output: 42 })
    assert r.ok?
    assert_equal 42, r.value![:output]
  end

  def test_empty_string_passthrough
    r = call("")
    assert r.ok?
  end
end
