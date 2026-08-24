# frozen_string_literal: true

require_relative "helper"

# The spine has one job at this stage: emit the filter_complex render_dilla
# already emits. Until that is pinned as text, "it routes the same" is a claim
# rather than a fact, and the first genre moved onto it would be moved onto a
# guess.
#
# The reference strings below are the shape render_dilla builds by hand around
# lib/engine/render_dilla.rb:640-695 -- a labelled clause per source, amix with
# positional weights, then the master chain to [out].
class TestAudioGraph < Minitest::Test
  def test_a_single_channel_is_not_run_through_amix
    graph = AudioGraph.new
    graph.channel(:drums, input: "0:a", chain: ["highpass=f=30"])

    # amix with inputs=1 still resamples and reweights, so summing one channel
    # is not the same audio as the channel. The spine returns the channel.
    assert_equal "[0:a]highpass=f=30[drums];[drums]anull[out]", graph.to_filter_complex
  end

  def test_channels_sum_with_positional_weights
    graph = AudioGraph.new
    graph.channel(:chops, input: "1:a", chain: ["volume=0.5"], gain: 0.68)
    graph.channel(:subbed, input: "2:a", chain: ["lowpass=f=180"], gain: 0.72)

    assert_equal(
      "[1:a]volume=0.5[chops];" \
      "[2:a]lowpass=f=180[subbed];" \
      "[chops][subbed]amix=inputs=2:weights=0.68 0.72:duration=first:normalize=0[master_sum];" \
      "[master_sum]anull[out]",
      graph.to_filter_complex
    )
  end

  # The reason the spine exists. render_dilla reaches drum_bus and bus_filters;
  # techno, industrial and analog reach neither. Here a bus is a declaration.
  def test_a_bus_collects_its_channels_and_carries_its_own_chain
    graph = AudioGraph.new
    graph.bus(:drum, chain: ["acompressor=threshold=0.1"], gain: 0.9)
    graph.channel(:kick, input: "0:a", bus: :drum)
    graph.channel(:snare, input: "1:a", bus: :drum, gain: 0.8)
    graph.channel(:pad, input: "2:a", gain: 0.75)

    graph_text = graph.to_filter_complex

    assert_includes graph_text, "[kick][snare]amix=inputs=2:weights=1 0.8:duration=first:normalize=0[drum_sum]"
    assert_includes graph_text, "[drum_sum]acompressor=threshold=0.1[drum]"
    # The bus arrives at master as one channel, carrying its own weight.
    assert_includes graph_text, "[pad][drum]amix=inputs=2:weights=0.75 0.9:duration=first:normalize=0[master_sum]"
  end

  def test_the_master_chain_lands_on_the_out_label
    graph = AudioGraph.new
    graph.channel(:a, input: "0:a", gain: 0.5)
    graph.channel(:b, input: "1:a", gain: 0.5)
    graph.master(["alimiter=limit=0.97", "loudnorm=I=-14"])

    assert_match(/\[master_sum\]alimiter=limit=0\.97,loudnorm=I=-14\[out\]\z/, graph.to_filter_complex)
  end

  # amix's defaults are wrong for a mix bus and render_dilla already overrides
  # them. If a rewrite ever drops these the mix changes silently: longest pads
  # every channel to the longest source, and normalize=1 rescales by input count
  # so adding one quiet channel pulls everything else down.
  def test_amix_never_uses_ffmpegs_defaults
    graph = AudioGraph.new
    graph.channel(:a, input: "0:a", gain: 0.5)
    graph.channel(:b, input: "1:a", gain: 0.5)

    assert_includes graph.to_filter_complex, "duration=first:normalize=0"
    refute_match(/duration=longest|normalize=1/, graph.to_filter_complex)
  end

  def test_a_channel_with_no_filters_still_gets_a_label
    graph = AudioGraph.new
    graph.channel(:bare, input: "0:a")

    # A source with no processing still has to become a label amix can name.
    assert_equal "[0:a]anull[bare];[bare]anull[out]", graph.to_filter_complex
  end

  def test_it_refuses_a_graph_that_reaches_nothing
    assert_raises(ArgumentError) { AudioGraph.new.to_filter_complex }
    assert_raises(ArgumentError) { AudioGraph.new.bus(:loop, into: :loop) }
  end

  def test_duplicate_names_are_refused_rather_than_silently_merged
    graph = AudioGraph.new
    graph.channel(:x, input: "0:a")
    assert_raises(ArgumentError) { graph.channel(:x, input: "1:a") }
    graph.bus(:b)
    assert_raises(ArgumentError) { graph.bus(:b) }
  end

  # Weights are positional. If insertion order and emission order ever diverge,
  # every weight lands on the wrong channel and the mix is wrong in a way no
  # exception reports.
  def test_emission_follows_insertion_order
    graph = AudioGraph.new
    %i[first second third].each_with_index { |n, i| graph.channel(n, input: "#{i}:a", gain: (i + 1) / 10.0) }

    assert_includes graph.to_filter_complex,
                    "[first][second][third]amix=inputs=3:weights=0.1 0.2 0.3:duration=first:normalize=0"
  end
end
