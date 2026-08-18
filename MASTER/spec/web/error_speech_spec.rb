# frozen_string_literal: true

require "minitest/autorun"

# A failure must not be spoken as though it were the answer.
#
# The face's SSE handling has two lanes and one prefix separates them.
# face.part5.txt's onMessage branches on a chunk starting with "ERROR:" —
# transcript, veto tint, shake, and a short spoken "Sorry, I hit a snag."
# Everything else is reply content: appended to `pending` and synthesised in
# MASTER's own voice.
#
# ChatService wrote the redactor's message onto the second lane, so a visitor
# heard "An internal error occurred. Retry or check server logs." spoken aloud.
# Both call sites are covered here because they fail differently: the `rescue`
# in #call writes to the stream directly, and #rendered_text returns text that
# #write_fallback later hands to #write_chunk.
#
# This spec asserts both ends. A gate that pinned only the server would pass
# while the client stopped honouring the prefix, and vice versa — and that is
# the shape of a check that measures nothing.
class ErrorSpeechSpec < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def read(path) = File.read(File.join(ROOT, path))

  def service = @service ||= read("web/app/services/chat_service.rb")

  def face = @face ||= read("web/public/face.part5.txt")

  def test_the_client_still_has_an_error_lane_keyed_on_the_prefix
    assert_includes face, "raw.startsWith('ERROR:')",
                    "the face no longer branches on the ERROR: prefix — the server's prefix now buys nothing"
  end

  # The point of the lane: it says something short of its own rather than
  # reading the error text out.
  def test_the_error_lane_speaks_a_short_failure_not_the_message
    branch = face[/if \(raw\.startsWith\('ERROR:'\)\) \{.*?\n      \}/m]

    refute_nil branch, "the ERROR: branch moved or changed shape"
    assert_includes branch, "speakFailure(", "the error lane no longer speaks a short failure line"
    refute_includes branch, "pending +=", "the error lane appends to the TTS buffer, so the error is spoken verbatim"
  end

  def test_the_server_declares_the_prefix_the_client_branches_on
    assert_match(/ERROR_PREFIX\s*=\s*"ERROR: "/, service,
                 "ChatService no longer declares the prefix face.part5.txt branches on")
  end

  # Both paths that can emit the redactor's message must take the error lane.
  # Without this the next call site added is unprefixed by default, which is
  # exactly how this one got here.
  def test_every_public_error_message_emission_is_prefixed
    unprefixed = service.each_line.with_index(1).select do |line, _|
      line.include?("public_error_message") && !line.include?("ERROR_PREFIX")
    end

    assert_empty unprefixed.map { |line, no| "#{no}: #{line.strip}" },
                 "an error message reaches the stream without ERROR_PREFIX, so the face speaks it as a reply"
  end

  def test_the_redactor_message_itself_carries_no_prefix
    # The prefix is a wire concern. Baking it into the redactor would put it in
    # log lines and any non-SSE caller too.
    refute_includes read("lib/ground/redactor.rb"), "ERROR:",
                    "the wire prefix leaked into the redactor, which has callers that are not the SSE stream"
  end
end
