# frozen_string_literal: true

require_relative "test_helper"

class TestSession < Minitest::Test
  def test_save_prunes_old_messages_to_summaries
    Dir.mktmpdir("session_test") do |dir|
      session = Master::Trace::Session.new(root: dir)
      45.times do |i|
        session.add_message(role: :user, content: "message #{i} " + ("x" * 400))
      end

      session.save!
      data = JSON.parse(File.read(File.join(dir, ".master", "session.json")))

      assert_equal 45, data["messages"].size
      assert data["messages"].first["summarized"]
      assert_operator data["messages"].first["content"].bytesize, :<, 280
      refute data["messages"].last["summarized"]
    end
  end

  # A save that dies before it finishes must leave the last good transcript,
  # because load! quarantines one it cannot parse and starts empty.
  def test_a_save_cut_short_leaves_the_previous_transcript
    Dir.mktmpdir("session_atomic") do |dir|
      session = Master::Trace::Session.new(root: dir)
      session.add_message(role: :user, content: "kept")
      session.save!
      session.add_message(role: :user, content: "lost")

      File.stub(:rename, ->(*) { raise Errno::ENOSPC }) do
        assert_raises(Errno::ENOSPC) { session.save! }
      end

      restored = Master::Trace::Session.new(root: dir).load!
      assert_equal ["kept"], restored.messages.map { |m| m[:content] }
    end
  end

  def test_record_cost_bills_the_same_tokens_the_meter_shows
    Dir.mktmpdir("session_cost") do |dir|
      session = Master::Trace::Session.new(root: dir)
      session.add_message(role: :user, content: "hello")
      session.record_cost(3.90, model: "paid-model", tokens: 1200)

      assert_in_delta 3.90, session.cost
      assert_equal 1200, session.tokens_billed
      refute_equal session.token_est, session.tokens_billed
    end
  end

  def test_a_flat_rate_row_says_it_is_approximate_and_a_billed_row_does_not
    Dir.mktmpdir("session_cost") do |dir|
      session = Master::Trace::Session.new(root: dir)
      session.record_cost(0.5, model: "unlisted-model", tokens: 10, approximate: true)
      session.record_cost(0.1, model: "priced-model", tokens: 10)

      rows = File.readlines(File.join(dir, ".master", "costs.jsonl")).map { |line| JSON.parse(line) }
      assert_equal [true, nil], rows.map { |row| row["approximate"] }
      assert_equal %w[unlisted-model priced-model], rows.map { |row| row["model"] }
    end
  end
end
