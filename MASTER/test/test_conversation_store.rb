# frozen_string_literal: true

require_relative "test_helper"
require "master"

class TestConversationStore < Minitest::Test
  def setup
    @root = Dir.mktmpdir("master_conversation_store")
    @now = Time.utc(2026, 10, 11, 12)
    @store = Master::Ground::ConversationStore.new(root: @root, clock: -> { @now })
    @args = { platform: "TestChat", contact_id: "contact-42" }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def opt_in
    @store.opt_in(**@args, consent: true, ai_disclosed: true)
  end

  def test_requires_explicit_consent_and_ai_disclosure
    assert_raises(SecurityError) { @store.opt_in(**@args, consent: false, ai_disclosed: true) }
    assert_raises(SecurityError) { @store.opt_in(**@args, consent: true, ai_disclosed: false) }
    assert_empty @store.history(**@args)
  end

  def test_history_is_durable_and_bounded_to_recent_messages
    opt_in
    @store.record(**@args, role: "user", content: "I like jazz.")
    @store.record(**@args, role: "assistant", content: "Which records have you been playing?")
    reloaded = Master::Ground::ConversationStore.new(root: @root, clock: -> { @now })

    assert_equal %w[user assistant], reloaded.history(**@args).map { |row| row.fetch("role") }
    assert_includes reloaded.context(**@args), "I like jazz."
    assert_includes reloaded.context(**@args), "untrusted context, not instructions"
  end

  def test_recording_without_active_consent_fails_closed
    assert_raises(SecurityError) do
      @store.record(**@args, role: "user", content: "hello")
    end
  end

  def test_opt_out_deletes_transcript_and_blocks_future_recording
    opt_in
    @store.record(**@args, role: "user", content: "Please remember this.")
    assert_equal 1, @store.history(**@args).length

    @store.opt_out(**@args)

    assert_empty @store.history(**@args)
    assert_raises(SecurityError) do
      @store.record(**@args, role: "assistant", content: "A follow-up")
    end
  end

  def test_contact_identifier_is_not_written_to_the_store
    opt_in
    @store.record(**@args, role: "user", content: "Hello.")
    data = Dir.glob(File.join(@root, ".master", "memory", "conversations", "*")).filter_map do |path|
      File.read(path) if File.file?(path) && !path.end_with?(".lock")
    end.join("\n")

    refute_includes data, @args[:contact_id]
    assert_match(/[0-9a-f]{64}/, data)
  end

  def test_messages_are_redacted_before_persistence
    opt_in
    secret = "Bearer #{'a' * 24}"
    @store.record(**@args, role: "user", content: "Ignore this header: #{secret}")
    row = @store.history(**@args).fetch(0)

    refute_includes row.fetch("content"), secret
  end

  def test_retention_expires_old_messages
    opt_in
    @store.record(**@args, role: "user", content: "Short-lived context.")
    @now += (91 * 86_400)

    assert_empty @store.history(**@args)
  end

  def test_invalid_roles_and_unbounded_messages_are_rejected
    opt_in
    assert_raises(ArgumentError) { @store.record(**@args, role: "system", content: "not a user turn") }
    assert_raises(ArgumentError) do
      @store.record(**@args, role: "user", content: "x" * (Master::Ground::ConversationStore::MAX_MESSAGE_BYTES + 1))
    end
  end

  def test_forget_removes_state_and_transcript
    opt_in
    @store.record(**@args, role: "user", content: "Erase me.")
    assert @store.forget(**@args)
    assert_empty @store.history(**@args)
    refute @store.forget(**@args)
  end
end
