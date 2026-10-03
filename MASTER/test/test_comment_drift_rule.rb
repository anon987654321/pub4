# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"

# The rule pairs each comment with the method it sits above, asks a model which
# comments lie, and turns the answer back into findings on the comment's line.
# The model is faked here — what is being tested is the pairing, the parsing and
# the failure behaviour, none of which need a real one.
#
# The failure behaviour is the reason this test matters most. The rule carries a
# long note about a period when an absent CLI was logged per file and produced
# 4,663 identical entries, which is what a genuinely load-bearing failure has to
# compete with when somebody finally reads the log. Both halves of that fix are
# pinned: absence is recorded once, misbehaviour every time, and neither is ever
# reported as "no drift".
class TestCommentDriftRule < Minitest::Test
  # Records the prompt so a test can assert what the model was actually shown.
  class FakeAgent
    attr_reader :prompts

    def initialize(reply: "CLEAN", raises: nil)
      @reply = reply
      @raises = raises
      @prompts = []
    end

    def ask(prompt, **)
      @prompts << prompt
      raise @raises if @raises

      @reply
    end
  end

  SOURCE = <<~RUBY
    # Returns the total in cents.
    def total
      @amount.to_s
    end

    # Saves the record.
    def save
      @repo.write(self)
    end
  RUBY

  def rule(agent) = Master::Review::Scan::Rules::CommentDriftRule.new(agent:)

  def flags(agent, source: SOURCE, path: "lib/thing.rb")
    rule(agent).check(source, path:).map(&:message)
  end

  def test_a_flagged_pair_becomes_a_finding_on_the_comment_line
    found = rule(FakeAgent.new(reply: "0:says cents, returns a string")).check(SOURCE, path: "lib/thing.rb")

    assert_equal 1, found.size
    assert_equal 1, found.first.line, "the finding belongs on the comment, which is the thing that lies"
    assert_includes found.first.message, "comment drift"
    assert_includes found.first.message, "returns a string"
  end

  def test_a_clean_answer_produces_nothing
    assert_empty flags(FakeAgent.new(reply: "CLEAN"))
  end

  # An index the model invented must be dropped, and the real ones beside it
  # must survive. Asserted with a good index present on purpose: an answer of
  # only "47:..." is empty either way — with the bounds check, because the pair
  # is nil; without it, because the NoMethodError is swallowed by the rule's own
  # rescue and takes every finding in the file with it. Mixing the two is what
  # separates a guard from a crash.
  def test_an_index_the_model_invented_is_dropped_without_losing_the_real_ones
    found = rule(FakeAgent.new(reply: "0:a real one\n47:no such pair")).check(SOURCE, path: "lib/thing.rb")

    assert_equal 1, found.size
    assert_includes found.first.message, "a real one"
  end

  def test_every_flagged_pair_is_reported
    assert_equal 2, flags(FakeAgent.new(reply: "0:first\n1:second")).size
  end

  # The pairing is comment-immediately-above-def. A comment floating on its own
  # has no method to contradict.
  def test_only_comments_attached_to_a_method_are_sent
    agent = FakeAgent.new
    rule(agent).check(<<~RUBY, path: "lib/thing.rb")
      # A note about the file in general.

      # Returns the total.
      def total = 1
    RUBY

    assert_equal 1, agent.prompts.size
    assert_includes agent.prompts.first, "Returns the total"
    refute_includes agent.prompts.first, "about the file in general"
  end

  # No model, no question — and no findings either. Silence here is correct
  # because nothing was asked, which is different from an answer of "clean".
  def test_without_an_agent_it_asks_nothing
    assert_empty Master::Review::Scan::Rules::CommentDriftRule.new(agent: nil).check(SOURCE, path: "lib/thing.rb")
  end

  def test_it_reads_only_ruby
    agent = FakeAgent.new(reply: "0:drift")

    assert_empty flags(agent, path: "lib/thing.txt")
    assert_empty agent.prompts, "a non-Ruby file must not cost a model call"
  end

  # A missing binary is a capability this machine lacks, and it is the same fact
  # on every file. It must still produce no findings — an unreachable model is
  # never evidence of a clean file.
  def test_an_absent_model_binary_yields_no_findings
    assert_empty flags(FakeAgent.new(raises: Errno::ENOENT.new("claude")))
  end

  # A model that is present and misbehaving is a different case and also must
  # not read as clean.
  def test_a_misbehaving_model_yields_no_findings
    assert_empty flags(FakeAgent.new(raises: RuntimeError.new("upstream exploded")))
  end
end
