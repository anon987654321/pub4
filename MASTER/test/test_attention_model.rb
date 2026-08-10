# frozen_string_literal: true

require "minitest/autorun"

# The face's blink and gaze timing, guarded as physiology rather than taste.
#
# Blink rate is the strongest single cue a viewer reads for "alive", and on
# 2026-08-10 this model sat far outside human range: simulated over ten minutes
# it blinked 5.1/min idle, 3.4 thinking, 5.9 speaking and 2.1 listening — one
# blink every 29 seconds while holding the visitor's gaze. It also had the
# speaking/listening relationship backwards; people blink MORE while speaking,
# not less.
#
# The intent behind those numbers was right and is preserved: VOICE_IDLE_
# SIGNATURES calls the target "composed, steady gaze, still baseline, slow
# deliberate blink". What went wrong is that composure was implemented as *less
# motion*, which crosses from composed into inanimate. Composure is small,
# smooth, economical motion. So amplitudes stay low — this file does not touch
# them — and only the rates are held inside what a calm human does.
#
# Read as source rather than executed: there is no JS runtime in this suite, and
# the numbers are declared as literals precisely so they can be checked without
# one.
class TestAttentionModel < Minitest::Test
  MODEL = File.expand_path("../web/public/attention_model.js", __dir__)

  # Resting adult blink rate is roughly 15-20/min. The floor is set below that
  # deliberately — this face is meant to read as composed — but a rate under 8
  # is a stare, and above 25 is agitation.
  HUMAN_FLOOR = 8.0
  HUMAN_CEILING = 25.0

  # A gap this long without a blink stops reading as composure. The old
  # listening policy allowed 38 seconds.
  MAX_PLAUSIBLE_GAP_S = 10.0

  def source
    @source ||= File.read(MODEL)
  end

  def blink_intervals
    @blink_intervals ||= source.scan(/(\w+):\s*\{[^}]*?blinkInterval:\s*\[(\d+),\s*(\d+)\]/m)
                               .to_h { |mode, lo, hi| [mode, [lo.to_i, hi.to_i]] }
  end

  def rate_per_min(range)
    60_000.0 / ((range[0] + range[1]) / 2.0)
  end

  def test_every_mode_declares_a_blink_interval
    assert_equal %w[idle thinking listening speaking].sort, blink_intervals.keys.sort,
                 "a mode without a blink interval falls back to the generic default and idles wrong"
  end

  def test_blink_rates_are_inside_human_range
    offenders = blink_intervals.filter_map do |mode, range|
      rate = rate_per_min(range)
      next if rate.between?(HUMAN_FLOOR, HUMAN_CEILING)

      "#{mode}: #{rate.round(1)}/min (#{range.inspect} ms)"
    end

    assert_empty offenders, <<~MSG.strip
      blink rates outside human range (#{HUMAN_FLOOR}-#{HUMAN_CEILING}/min):

        #{offenders.join("\n  ")}

      Under the floor the face reads as a stare rather than as composure; over
      the ceiling it reads as agitation. Amplitude is where composure belongs.
    MSG
  end

  def test_the_face_blinks_more_while_speaking_than_while_listening
    speaking = rate_per_min(blink_intervals.fetch("speaking"))
    listening = rate_per_min(blink_intervals.fetch("listening"))

    assert_operator speaking, :>, listening,
                    "humans blink more while speaking and less while attending; this was " \
                    "inverted, which is part of why holding the visitor's gaze read as a stare"
  end

  def test_no_mode_can_hold_a_stare
    worst = blink_intervals.max_by { |_, range| range[1] }
    assert_operator worst[1][1] / 1000.0, :<=, MAX_PLAUSIBLE_GAP_S,
                    "#{worst[0]} allows #{(worst[1][1] / 1000.0).round(1)}s without a blink"
  end

  # The pieces that make stillness read as control rather than absence. Each was
  # missing, and each is cheap; asserting they are present stops a future
  # simplification quietly restoring the waxwork.
  def test_blink_is_asymmetric
    close = source[/BLINK_CLOSE_MS\s*=\s*(\d+)/, 1].to_i
    open = source[/BLINK_OPEN_MS\s*=\s*(\d+)/, 1].to_i

    assert_operator close, :>, 0, "no blink close duration declared"
    assert_operator open, :>, close,
                    "the lid falls faster than it lifts; an equal rise and fall is a shutter"
  end

  def test_the_eye_never_parks_perfectly_still
    assert_match(/DRIFT_STEP/, source, "no ocular drift: gaze decayed to exactly zero and held")
    assert_match(/DRIFT_LIMIT/, source, "drift must be bounded or it wanders off centre")
    assert_match(/DRIFT_RETURN/, source, "drift needs mean reversion or fixation is lost")
  end

  def test_blinks_can_be_cued_by_speech
    assert_match(/function cue\(/, source, "no cue(): blinking stays a timer rather than punctuation")
    assert_match(/utterance_end/, source)
    speech = File.read(File.expand_path("../web/public/face_speech_runtime.js", __dir__))
    assert_match(/MASTER_ATTENTION\?\.cue\?\.\(/, speech,
                 "the speech runtime must cue a blink when an utterance completes")
  end
end
