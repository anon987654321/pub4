# frozen_string_literal: true

require_relative "test_helper"

# What RuleLoop takes from a model's reply as the new file. Every streamed
# repair of a bin/ script in the first /fix MASTER run ended no_proposal or
# rejected, and the extractor was half of it: a script has no extension, so
# only a ```text or bare fence counted, and a ```ruby answer passed through
# whole, prose and fences included.
class TestRuleLoopExtractCode < Minitest::Test
  def extract(text, ext) = Master::Fix::RuleLoop.allocate.send(:extract_code, text, ext)

  def test_an_extensionless_script_takes_a_ruby_fence
    assert_equal "puts 1", extract("Here is the fix:\n```ruby\nputs 1\n```\nDone.", "")
  end

  def test_the_block_in_the_files_language_wins_over_an_earlier_one
    reply = "Before:\n```js\nx\n```\nAfter:\n```ruby\ny = 1\n```\n"

    assert_equal "y = 1", extract(reply, ".rb")
  end

  def test_a_fenced_refusal_is_no_proposal
    assert_nil extract("```ruby\nUNCHANGED\n```\n", ".rb")
  end
end
