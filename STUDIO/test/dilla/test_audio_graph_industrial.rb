# frozen_string_literal: true

require_relative "helper"

# Parity for the second renderer, and the one the spine exists to rescue.
#
# render_industrial builds its bed by hand at lib/engine/render_industrial.rb
# 155-171: four sources, one of them conditional on a file existing, summed with
# positional weights. This reproduces that bed through AudioGraph and compares
# the emitted graph as text, in both the with-texture and without-texture cases,
# because the conditional channel is where a hand-built weights list is easiest
# to get wrong.
#
# It reproduces the CURRENT graph, wrong parts included. render_industrial omits
# normalize=0 where render_dilla sets it, and measured against a 440Hz reference
# that is a 4.1 dB difference (-21.07 vs -16.94 RMS) into a chain of
# level-dependent stages. Proving parity first is what makes changing it later a
# decision with a measurement behind it rather than a side effect of a refactor.
class TestAudioGraphIndustrial < Minitest::Test
  DURATION = "230.4"
  LEGACY_AMIX = "duration=first"

  RUMBLE  = "[2:a]aformat=channel_layouts=mono,lowpass=f=95,equalizer=f=48:t=o:w=0.8:g=8,volume=0.42[rumble]"
  TEXTURE = "[1:a]aformat=channel_layouts=stereo,atrim=0:#{DURATION},asetpts=PTS-STARTPTS," \
            "highpass=f=180,lowpass=f=8500,volume=0.18[texture]"
  NOISE   = "[3:a]highpass=f=400,lowpass=f=5000,volume=0.04[noise]"

  def chain_of(clause) = clause[/\](.*)\[[a-z_]+\]\z/m, 1].split(",")
  def input_of(clause) = clause[/\A\[([^\]]+)\]/, 1]

  # The bed exactly as render_industrial assembles it.
  def bed_by_hand(with_texture:)
    filt = [RUMBLE]
    filt << TEXTURE if with_texture
    filt << NOISE
    mix_in = ["[drums]", "[rumble]"]
    mix_w  = ["1.0", "0.55"]
    if with_texture
      mix_in << "[texture]"
      mix_w << "0.28"
    end
    mix_in << "[noise]"
    mix_w << "0.06"
    filt << "#{mix_in.join}amix=inputs=#{mix_in.length}:weights=#{mix_w.join(' ')}:#{LEGACY_AMIX}[bed]"
    filt.join(";")
  end

  def bed_through_spine(with_texture:)
    graph = AudioGraph.new(amix_options: LEGACY_AMIX)
    # [drums] arrives already split off the source by asplit, so it enters the
    # graph as a label rather than an input index — the spine takes either.
    graph.channel(:drums, input: "[drums]", chain: [], gain: 1.0)
    graph.channel(:rumble, input: input_of(RUMBLE), chain: chain_of(RUMBLE), gain: 0.55)
    graph.channel(:texture, input: input_of(TEXTURE), chain: chain_of(TEXTURE), gain: 0.28) if with_texture
    graph.channel(:noise, input: input_of(NOISE), chain: chain_of(NOISE), gain: 0.06)
    # out_label: nil — the bed is not the end of industrial's graph. It feeds
    # the sidechain compressor and the two sends, so the spine stops at the sum
    # and the renderer keeps building from graph.sum_label.
    graph.to_filter_complex(out_label: nil)
  end

  # The spine emits a clause for every channel including the pass-through, and
  # names the sum. Hand-built industrial writes [drums] inline and calls the sum
  # [bed]. Normalising those two differences is what the comparison is about.
  def normalise(graph_text)
    # Three differences that are not the mix: the spine emits a clause for the
    # pass-through channel where industrial writes [drums] inline, it names the
    # sum master_sum, and it writes a unity weight as 1 where the hand-written
    # list says 1.0. ffmpeg reads 1 and 1.0 identically, so the last is spelling.
    graph_text.sub("[drums]anull[drums];", "")
              .gsub("master_sum", "bed")
              .sub("weights=1 ", "weights=1.0 ")
  end

  def test_the_bed_matches_without_the_optional_texture
    assert_equal bed_by_hand(with_texture: false),
                 normalise(bed_through_spine(with_texture: false))
  end

  def test_the_bed_matches_with_the_optional_texture
    assert_equal bed_by_hand(with_texture: true),
                 normalise(bed_through_spine(with_texture: true))
  end

  # The conditional channel is the whole risk in a hand-built weights list: the
  # labels and the weights are two arrays that have to stay the same length and
  # the same order, appended in two places under the same `if`.
  def test_the_optional_channel_lands_in_both_lists_or_neither
    with = bed_through_spine(with_texture: true)
    without = bed_through_spine(with_texture: false)

    assert_equal 4, with[/inputs=(\d+)/, 1].to_i
    assert_equal 3, without[/inputs=(\d+)/, 1].to_i
    assert_equal %w[1 0.55 0.28 0.06], with[/weights=([^:]+):/, 1].split
    assert_equal %w[1 0.55 0.06], without[/weights=([^:]+):/, 1].split
  end

  # Guards the reason this file passes LEGACY_AMIX at all. If the spine's
  # default ever silently becomes the legacy form, the migration stops being a
  # decision and every new graph inherits the quieter bed.
  def test_the_spine_default_is_still_the_explicit_form
    assert_equal "duration=first:normalize=0", AudioGraph::AMIX_OPTIONS
    refute_includes bed_through_spine(with_texture: true), "normalize=0"

    explicit = AudioGraph.new
    explicit.channel(:a, input: "0:a", gain: 0.5)
    explicit.channel(:b, input: "1:a", gain: 0.5)
    assert_includes explicit.to_filter_complex, "normalize=0"
  end
end
