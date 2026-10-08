# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../app/services/shared/strunk_white_pass"
require_relative "../../app/services/shared/content_rewriter"

class ContentRewriterTest < Minitest::Test
  def test_rewrites_and_applies_strunk_pass
    rewriter = Shared::ContentRewriter.new(city_name: "Bergen")
    rewriter.define_singleton_method(:ask_llm) do |**_kwargs|
      {
        title: "Local café tip",
        body: "Try the cinnamon bun on Torget.",
        comments: [ "I believe it might be worth the queue.", "Open early on Saturdays." ],
      }
    end

    result = rewriter.rewrite(
      title: "[r/bergen] Best kanelbolle?",
      body: "I think that perhaps someone could recommend a bakery.",
      comments: [ "I believe it might be Baker Hansen." ],
    )

    assert_equal "Local café tip", result.title
    assert_match(/cinnamon bun/i, result.body)
    refute_match(/\[r\//i, result.title)
    refute_match(/perhaps/i, result.body)
    assert result.comments.size >= 1
    refute_match(/I believe/i, result.comments.first)
  end
end
