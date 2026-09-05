# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/master"

# One Session object, one transcript, every visitor at once.
#
# The web container is a process singleton (web/config/initializers/
# master_container.rb) and nothing scoped the session under it, so
# Agent#conversation_context — which feeds the model `messages.last(17)` —
# handed over whatever the last person to type had said. /chat/history is
# auth-gated, so the endpoint never leaked; the model did, by answering one
# person with another's words. It is also how the welcome greeting compounded:
# every page load dropped "introduce yourself" into the conversation everyone
# else was already having.
#
# Absent key means :local, so the CLI and every test that never heard of
# conversations keep the behaviour they had.
class ConversationIsolationSpec < Minitest::Test
  def with_session
    Dir.mktmpdir("session-isolation") { |dir| yield Master::Trace::Session.new(root: dir) }
  end

  def teardown
    Fiber[:master_conversation] = nil
  end

  # add_message writes to whatever the fiber-local says, because its real caller
  # is Agent several frames down. The readers take a key. Both halves are
  # exercised here, in the order the runtime uses them.
  def say(session, key, content)
    Fiber[:master_conversation] = key
    session.add_message(role: :user, content: content)
  ensure
    Fiber[:master_conversation] = nil
  end

  def contents(session, key) = session.messages(key).map { |m| m[:content] }

  def test_two_conversations_do_not_see_each_other
    with_session do |session|
      say(session, "visitor-a", "my card number is 4111 1111 1111 1111")

      assert_empty session.messages("visitor-b"), "visitor b can read visitor a's transcript"

      say(session, "visitor-b", "hello")

      assert_equal ["hello"], contents(session, "visitor-b")
      assert_equal 1, session.messages("visitor-a").size, "visitor a's transcript changed when b typed"
      refute_includes contents(session, "visitor-a"), "hello"
    end
  end

  # The whole point: what the model is handed.
  def test_the_model_context_of_one_visitor_excludes_another
    with_session do |session|
      say(session, "a", "secret-a")
      say(session, "b", "secret-b")

      refute_includes contents(session, "b"), "secret-a"
      assert_includes contents(session, "b"), "secret-b"
    end
  end

  # No key at all is the CLI. It must behave exactly as it did.
  def test_no_key_is_the_local_conversation
    with_session do |session|
      session.add_message(role: :user, content: "from the cli")

      assert_equal ["from the cli"], contents(session, Master::Trace::Session::LOCAL)
      assert_equal ["from the cli"], session.messages.map { |m| m[:content] }
    end
  end

  def test_token_est_and_name_are_per_conversation
    with_session do |session|
      say(session, "a", "a much longer message than the other one")
      say(session, "b", "hi")

      assert_operator session.token_est("a"), :>, session.token_est("b"),
                      "token_est is still being pooled across visitors"
      refute_equal session.name("a"), session.name("b")
    end
  end

  # clear! is reachable from a visitor. It must not empty anyone else's.
  def test_clear_only_empties_the_callers_conversation
    with_session do |session|
      say(session, "a", "keep me")
      say(session, "b", "drop me")

      Fiber[:master_conversation] = "b"
      session.clear!
      Fiber[:master_conversation] = nil

      assert_equal 1, session.messages("a").size
      assert_empty session.messages("b")
    end
  end

  def test_the_fiber_local_defaults_to_local_when_unset
    assert_equal Master::Trace::Session::LOCAL, Master::Trace::Session.conversation_key
    Fiber[:master_conversation] = "someone"
    assert_equal "someone", Master::Trace::Session.conversation_key
  end

  # session.json is the operator's transcript. A visitor's turns must not reach
  # it, whichever conversation happens to be current when it is written.
  def test_persistence_writes_only_the_local_conversation
    with_session do |session|
      session.add_message(role: :user, content: "operator turn")
      say(session, "visitor", "visitor turn")

      Fiber[:master_conversation] = "visitor"
      session.save!
      Fiber[:master_conversation] = nil
      saved = File.read(File.join(session.instance_variable_get(:@root), ".master", "session.json"))

      assert_includes saved, "operator turn"
      refute_includes saved, "visitor turn", "a visitor's message was persisted to the operator's session.json"
    end
  end

  def test_load_restores_into_local_without_touching_a_visitor
    with_session do |session|
      session.add_message(role: :user, content: "operator turn")
      session.save!
      say(session, "visitor", "visitor turn")

      Fiber[:master_conversation] = "visitor"
      session.load!
      Fiber[:master_conversation] = nil

      assert_equal ["visitor turn"], contents(session, "visitor"),
                   "load! overwrote a visitor's conversation with the operator's file"
      assert_equal ["operator turn"], contents(session, Master::Trace::Session::LOCAL)
    end
  end
end
