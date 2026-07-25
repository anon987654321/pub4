# frozen_string_literal: true

# Generic "any parameter can vary over time" helper — the ffmpeg-expression
# equivalent of a DAW automation lane. Several places in dilla.rb hand-build
# a one-off `if(lt(t,X),A,B)':eval=frame` volume expression (radio_club_morph
# being the clearest example); this replaces the ad-hoc string-building with
# one function so a third breakpoint, or a new automated parameter, is a data
# change instead of a new hand-rolled expression.
#
# Only proven against ffmpeg's `volume` filter (`eval=frame` + `t` variable).
# `lowpass`/`highpass` do NOT accept this syntax (confirmed empirically) —
# automating those needs `asendcmd` with a timed command file instead, which
# is a different, heavier mechanism not implemented here.
module DillaAutomation
  module_function

  # points: [[time_sec, value], ...] sorted ascending by time. Value before
  # the first point's time is the first point's value; after the last
  # point's time, the last point's value. Builds a right-nested if-ladder.
  def volume_expr(points)
    raise ArgumentError, "need at least one point" if points.empty?
    return points.first.last.to_s if points.length == 1

    sorted = points.sort_by(&:first)
    ladder = sorted.last.last.to_s
    (sorted.length - 1).downto(1) do |i|
      threshold_time = sorted[i].first
      value_before = sorted[i - 1].last
      ladder = "if(lt(t,#{threshold_time}),#{value_before},#{ladder})"
    end
    ladder
  end

  # Convenience for the common two-step case (radio_club_morph's shape).
  def step_expr(before:, at_sec:, after:)
    volume_expr([[0, before], [at_sec, after]])
  end

  def volume_filter(points)
    "volume='#{volume_expr(points)}':eval=frame"
  end

  # The "analog pad" character effect (lowpass + phaser) was hand-duplicated
  # across three render-mode pad-bus chains with slightly drifted numbers —
  # this is the shared definition; call sites keep their own tuned params
  # (real per-mode differences, not drift) but the string shape lives once.
  def pad_character_filter(cutoff_hz:, phaser_speed: 0.11, phaser_decay: 0.4)
    "lowpass=f=#{cutoff_hz},aphaser=speed=#{phaser_speed}:decay=#{phaser_decay}"
  end
end
