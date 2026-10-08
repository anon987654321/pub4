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

  def test_last_user_question_skips_commands_and_the_current_fix
    Dir.mktmpdir("session_question") do |dir|
      session = Master::Trace::Session.new(root: dir)
      session.add_message(role: :user, content: "what should we improve next?")
      session.add_message(role: :user, content: "/status")
      session.add_message(role: :user, content: "/fix MASTER")

      assert_equal "what should we improve next?",
                   session.last_user_question(before: "/fix MASTER")
    end
  end

  def test_save_replaces_invalid_utf8_without_crashing
    Dir.mktmpdir("session_utf8") do |dir|
      session = Master::Trace::Session.new(root: dir)
      invalid = "hello ".dup.force_encoding("UTF-8")
      invalid << "\xFF".b.force_encoding("UTF-8")
      session.add_message(role: :user, content: invalid)

      assert_silent { session.save! }

      data = JSON.parse(File.read(File.join(dir, ".master", "session.json")))
      assert_equal "hello \uFFFD", data["messages"].first["content"]
    end
  end

  def test_record_cost_replaces_invalid_utf8_without_crashing
    Dir.mktmpdir("session_cost_utf8") do |dir|
      session = Master::Trace::Session.new(root: dir)
      invalid = "model-".dup.force_encoding("UTF-8")
      invalid << "\xFF".b.force_encoding("UTF-8")

      assert_silent { session.record_cost(0.1, model: invalid, tokens: 1) }

      row = JSON.parse(File.read(File.join(dir, ".master", "costs.jsonl"))).first
      assert_equal "model-\uFFFD", row["model"]
    end
  end

  def test_invalid_utf8_session_file_is_quarantined
    Dir.mktmpdir("session_load_utf8") do |dir|
      path = File.join(dir, ".master", "session.json")
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, "{\"messages\":[\"\xFF\"]}")

      session = Master::Trace::Session.new(root: dir)
      assert_silent { session.load! }

      assert_empty session.messages
      refute File.exist?(path)
      assert_equal 1, Dir.glob("#{path}.corrupt.*").size
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
