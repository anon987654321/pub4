# frozen_string_literal: true

require "minitest/autorun"

class TestDillaEntrypoint < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ENTRY = File.join(ROOT, "dilla", "dilla.rb")

  def test_live_entrypoint_contains_the_engine_and_live_router
    source = File.read(ENTRY)

    assert_operator source.bytesize, :>, 100_000
    assert_includes source, "def live!(argv)"
    assert_includes source, "LIVE_SYNTH_VERBS"
    assert_match(/LIVE_SYNTH_VERBS = %w\[.*\bplay\b.*\]\.freeze/, source)
    assert_includes source, 'mode=flylo'
    assert_includes source, 'dilla.wav'
    assert_includes source, 'require_relative "lib/sound"'
  end
end
