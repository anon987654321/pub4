# frozen_string_literal: true

require_relative "test_helper"

class TestSession < Minitest::Test
  def test_streamed_output_is_accumulated_even_when_units_console_is_active
    session = Master::CLI::Session.allocate
    state = { streamed: false }

    session.instance_variable_set(:@unit_sub, -> {})
    accumulated = +""
    handler = session.send(:build_on_turn_handler, accumulated, state)

    handler.call("hello from the stream")

    assert_equal true, state[:streamed]
    assert_equal "hello from the stream\n", accumulated
  end

  def test_pipeline_passes_a_chunk_stream_to_casual_llm_turns
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@container, {})
    session.define_singleton_method(:cli_felt_sense) { nil }
    session.define_singleton_method(:terminal_ask) { |_thread| nil }

    seen = nil
    Master::CLI::TurnRouter.stub(:call, ->(**kwargs) { seen = kwargs; Master::Result.ok("ok") }) do
      thread = session.send(:spawn_pipeline_thread, "hello", ->(_line) {})
      thread.value
    end

    assert_respond_to seen[:on_chunk], :call
  end

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
  def test_summary_truncation_never_splits_utf8
    Dir.mktmpdir("session_utf8_summary") do |dir|
      session = Master::Trace::Session.new(root: dir)
      content = ("x" * 239) + "ø" + ("y" * 120)
      session.add_message(role: :user, content:)
      session.instance_variable_set(:@conversations, {
        Master::Trace::Session::LOCAL => {
          messages: session.messages(Master::Trace::Session::LOCAL),
          token_est: session.token_est(Master::Trace::Session::LOCAL),
          name: "utf8"
        }
      })

      session.add_message(role: :user, content: "another")
      session.instance_variable_get(:@conversations)[Master::Trace::Session::LOCAL][:messages] = Array.new(
        41, session.messages(Master::Trace::Session::LOCAL).first
      )
      session.save!

      data = JSON.parse(File.read(File.join(dir, ".master", "session.json")))
      assert data["messages"].all? { |message| message["content"].valid_encoding? }
      assert_includes data["messages"].first["content"], "ø"
    end
  end

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
