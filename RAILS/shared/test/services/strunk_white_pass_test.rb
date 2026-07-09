# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../app/services/shared/strunk_white_pass"

class StrunkWhitePassTest < Minitest::Test
  def test_strips_hedges_and_preambles
    input = "In summary, I think that perhaps this could be useful."
    output = Shared::StrunkWhitePass.call(input)

    refute_match(/In summary/i, output)
    refute_match(/I think that/i, output)
    refute_match(/perhaps/i, output)
    assert_match(/useful/i, output)
  end

  def test_removes_reddit_markers
    input = "[r/bergen] Great café — scraped & fictivized from Reddit (score: 42, comments: 7)"
    output = Shared::StrunkWhitePass.call(input)

    refute_match(/\[r\//i, output)
    refute_match(/reddit/i, output)
    refute_match(/score:/i, output)
    assert_match(/café/i, output)
  end

  def test_preserves_code_fences
    input = "Use this:\n```ruby\nvalue = 1\n```\nDone."
    output = Shared::StrunkWhitePass.call(input)

    assert_includes output, "```ruby"
    assert_includes output, "value = 1"
  end
end