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
end
