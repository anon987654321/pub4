# frozen_string_literal: true

require_relative "helper"

# Parity with the graph render_dilla builds by hand.
#
# The spine is only worth moving a genre onto if it emits what the working
# renderer already emits. This reconstructs render_dilla's stem mixdown
# (lib/engine/render_dilla.rb around 637-692) as literal strings, builds the same
# thing through AudioGraph, and compares the two as text.
#
# The literals here are copied from that renderer, weights included. If someone
# retunes 0.82 or 0.68 there and not here, this test fails and says the two have
# diverged -- which is the point. It is a parity pin, not a second opinion about
# what the mix should be.
class TestAudioGraphParity < Minitest::Test
  TEMPO = "0.9871".freeze
  DURATION = "38.4".freeze
  PAD_GATE = "0.31".freeze
  CHOP_GATE = "0.44".freeze

  # Verbatim from render_dilla, with the interpolations resolved.
  PADBED = "[3:a]aformat=channel_layouts=stereo,atempo=#{TEMPO},atrim=0:#{DURATION},asetpts=PTS-STARTPTS," \
           "lowpass=f=3400,volume='#{PAD_GATE}':eval=frame,aphaser=speed=0.11:decay=0.4[padbed]".freeze
  CHOPS  = "[4:a]aformat=channel_layouts=stereo,atempo=#{TEMPO},atrim=0:#{DURATION},asetpts=PTS-STARTPTS," \
           "highpass=f=400,volume='#{CHOP_GATE}':eval=frame,aecho=0.35:0.4:90:0.25[chops]".freeze
  SUBBED = "[5:a]aformat=channel_layouts=stereo,atempo=#{TEMPO},atrim=0:#{DURATION},asetpts=PTS-STARTPTS," \
           "lowpass=f=180,equalizer=f=72:t=o:w=1:g=4,volume=0.68[subbed]".freeze
  VINYL  = "[6:a]highpass=f=120,lowpass=f=6000,volume=0.045[vinyl]".freeze

  # The chain each stem carries before it reaches the sum, split from its label.
  def stem_chain(body)
    body[/\](.*)\[[a-z]+\]\z/m, 1].split(",")
  end

  def stem_input(body)
    body[/\A\[([^\]]+)\]/, 1]
  end

  def build_by_hand
    filt = [PADBED, CHOPS, SUBBED, VINYL]
    labels = %w([padbed] [chops] [subbed] [vinyl])
    weights = %w(0.82 0.68 0.72 0.35)
    filt << "#{labels.join}amix=inputs=#{labels.length}:weights=#{weights.join(' ')}:duration=first:normalize=0[mix]"
    filt << "[mix]alimiter=limit=0.97[out]"
    filt.join(";")
  end

  def build_through_spine
    graph = AudioGraph.new
    { padbed: [PADBED, 0.82], chops: [CHOPS, 0.68], subbed: [SUBBED, 0.72], vinyl: [VINYL, 0.35] }
      .each do |name, (body, gain)|
        graph.channel(name, input: stem_input(body), chain: stem_chain(body), gain: gain)
      end
    graph.master(["alimiter=limit=0.97"])
    graph.to_filter_complex
  end

  def test_the_spine_emits_the_graph_render_dilla_builds_by_hand
    # The spine calls the sum master_sum where render_dilla calls it mix. That
    # rename aside, clause order, per-stem chains, amix inputs, positional
    # weights and the amix options all have to match character for character.
    assert_equal build_by_hand, build_through_spine.gsub("master_sum", "mix")
  end

  def test_the_sum_label_is_the_only_difference
    # Guards the rename above: if the two ever become identical without it, the
    # gsub is dead and the test above stops proving anything.
    refute_equal build_by_hand, build_through_spine
  end

  # The weights are the tuning. render_dilla's numbers were set against real
  # material; a spine that reorders channels silently reassigns every one of
  # them, because amix takes weights positionally and not by name.
  def test_weights_stay_with_their_channels
    spine = build_through_spine
    order = spine[/amix=inputs=4:weights=([^:]+):/, 1].split
    labels = spine.scan(/\[(padbed|chops|subbed|vinyl)\]amix|\[(padbed|chops|subbed|vinyl)\]\[/).flatten.compact

    assert_equal %w[0.82 0.68 0.72 0.35], order
    assert_equal "padbed", labels.first, "the first weight belongs to the first label"
  end
end
