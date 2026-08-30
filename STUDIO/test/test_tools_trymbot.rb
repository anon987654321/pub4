# frozen_string_literal: true

require_relative "studio_helper"
require_relative "../trymbot/trymbot"

# Trymbot talks to one eleven-year-old, so the properties worth pinning are the
# ones that decide who it talks to and whether it answers at all. The rest of
# the file is HTTP, which a unit test can only restate.
#
# Nothing here reaches the network: every case either exercises pure string
# handling or stubs the one method that would.
class TestTrymbot < Minitest::Test
  # A bot username is public. Anyone who finds @whatever_bot can open a chat
  # with it, and the only thing standing between that stranger and a child is
  # this list — so the empty list has to mean nobody, not everybody.
  #
  # Written as its own test because the tempting spelling, `return true if
  # allowlist.empty?`, reads like a sensible default and inverts the guard.
  def test_empty_allowlist_admits_nobody
    Trymbot.stub(:allowlist, []) do
      refute Trymbot.allowed?(12_345)
      refute Trymbot.allowed?(0)
    end
  end

  def test_allowlist_admits_only_listed_ids
    Trymbot.stub(:allowlist, ["12345"]) do
      assert Trymbot.allowed?(12_345), "the listed id is Trym and must get through"
      assert Trymbot.allowed?("12345"), "Telegram hands back an Integer, a file holds a String"
      refute Trymbot.allowed?(1_234), "a prefix of the listed id is a different person"
      refute Trymbot.allowed?(123_456)
    end
  end

  # One id per line is what the help text tells the operator to write, but a
  # copied id arrives with whitespace and a second one usually arrives with a
  # comma, so both separators are accepted.
  def test_allowlist_parses_whitespace_and_commas
    with_env("TRYMBOT_ALLOW" => "111, 222\n333\t444") do
      assert_equal %w[111 222 333 444], Trymbot.allowlist
    end
  end

  # An unlisted chat is dropped before anything is sent, so this passes with no
  # network and would hang if the guard moved below the first API call.
  def test_unlisted_chat_is_dropped_before_any_reply
    message = { "chat" => { "id" => 999 }, "text" => "hei", "from" => { "username" => "stranger" } }

    Trymbot.stub(:allowlist, ["12345"]) do
      _out, err = capture_io { assert_nil Trymbot.handle(message) }
      assert_match(/ignored chat 999/, err, "the refused id is what the operator needs in order to allow it")
    end
  end

  def test_empty_and_missing_text_is_ignored
    Trymbot.stub(:allowlist, ["1"]) do
      assert_nil Trymbot.handle({ "chat" => { "id" => 1 }, "text" => "   " })
      assert_nil Trymbot.handle({ "chat" => { "id" => 1 } })
      assert_nil Trymbot.handle({ "text" => "hei" })
    end
  end

  # Telegram refuses a message over 4096 characters outright rather than
  # truncating it, so a long answer that is not split is an answer Trym never
  # sees.
  def test_long_text_splits_under_the_limit
    text = (1..400).map { |n| "Linje #{n} med litt norsk tekst i seg." }.join("\n\n")
    chunks = Trymbot.chunk(text)

    assert_operator chunks.length, :>, 1, "the fixture has to be long enough to split"
    chunks.each { |part| assert_operator part.length, :<=, Trymbot::MESSAGE_LIMIT }
    assert_equal text.gsub(/\s+/, " ").strip, chunks.join(" ").gsub(/\s+/, " ").strip,
                 "splitting may move whitespace but must not lose a word"
  end

  def test_short_text_is_not_split
    assert_equal ["Hei Trym!"], Trymbot.chunk("Hei Trym!")
  end

  # The transcript is capped, and the cap has to drop the oldest rather than
  # refuse the newest.
  def test_history_keeps_the_most_recent_turns
    Trymbot.histories.delete(:pin)
    30.times { |n| Trymbot.remember(:pin, "user", "melding #{n}") }
    log = Trymbot.histories[:pin]

    assert_equal Trymbot::HISTORY_TURNS, log.length
    assert_equal "melding 29", log.last[:content]
    refute_includes log.map { |m| m[:content] }, "melding 0"
  ensure
    Trymbot.histories.delete(:pin)
  end

  # gemma4:26b is pulled on this host and cannot initialise its context on
  # ollama 0.33.2 — it takes about two minutes to say so. Trying it once per
  # message would put that delay in front of every single thing Trym types, so
  # a model that has failed is not tried again for the rest of the run.
  def test_a_failed_model_is_not_tried_twice
    tried = []
    Trymbot.broken_models.clear

    Trymbot.stub(:ollama_models, ["broken:26b", "working:8b"]) do
      Trymbot.stub(:ollama_chat, ->(model, _messages) { tried << model; model == "working:8b" ? "hei!" : nil }) do
        assert_equal "hei!", Trymbot.ollama_reply([{ role: "user", content: "hei" }])
        assert_equal ["broken:26b", "working:8b"], tried

        assert_equal "hei!", Trymbot.ollama_reply([{ role: "user", content: "hei igjen" }])
        assert_equal ["broken:26b", "working:8b", "working:8b"], tried,
                     "the broken model must not be tried a second time"
      end
    end
  ensure
    Trymbot.broken_models.clear
  end

  # A pinned model means that model or nothing, so a typo surfaces as silence
  # rather than as a quiet answer from a model the operator did not choose.
  def test_pinned_model_wins_over_what_is_installed
    with_env("TRYMBOT_MODEL" => "gemma4:26b") do
      Trymbot.stub(:ollama_models, ["llama3:latest"]) do
        assert_equal ["gemma4:26b"], Trymbot.ollama_candidates
      end
    end
  end

  # The CLIs take one string rather than a transcript, and the brief is the
  # whole persona — a prompt built without it is a stranger talking to a child.
  def test_cli_prompt_carries_the_brief_and_names_the_speakers
    prompt = Trymbot.cli_prompt([{ role: "user", content: "hva er en takt?" },
                                 { role: "assistant", content: "Pip! En takt er ..." }])

    assert_includes prompt, "Du er Trymbot"
    assert_includes prompt, "Trym: hva er en takt?"
    assert_includes prompt, "Trymbot: Pip! En takt er ..."
  end

  # The persona is the reason the file exists, and it is a child's chat: these
  # are the instructions that must survive an edit to the prose around them.
  def test_the_brief_is_norwegian_and_keeps_its_boundaries
    assert_includes Trymbot::BRIEF, "Snakk alltid norsk"
    assert_includes Trymbot::BRIEF, "elleve år"
    assert_match(/Ingenting om vold, sex, rus/, Trymbot::BRIEF)
  end

  # The token is full control of the bot and this tree has a public remote.
  def test_no_secret_is_stored_in_the_tree
    source = File.read(File.expand_path("../trymbot/trymbot.rb", __dir__))

    refute_match(/\d{8,10}:[A-Za-z0-9_-]{35}/, source, "that is the shape of a Telegram bot token")
    assert_includes Trymbot::TOKEN_FILE, File.expand_path("~")
    refute_includes Trymbot::TOKEN_FILE, Studio::ROOT
  end
end
