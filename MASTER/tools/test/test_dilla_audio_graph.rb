# frozen_string_literal: true

require_relative "dilla_helper"
require "open3"

# The spine has one job at this stage: emit the filter_complex render_dilla
# already emits. Until that is pinned as text, "it routes the same" is a claim
# rather than a fact, and the first genre moved onto it would be moved onto a
# guess.
#
# The reference strings below are the shape render_dilla builds by hand around
# dilla.rb:286 (class AudioGraph) -- a labelled clause per source, amix with
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
    # The bus arrives at master as one channel, carrying its own weight, and in
    # the position it was declared -- :drum is declared above :pad here, so it
    # leads. This expectation used to read [pad][drum], which was the old
    # sum-channels-then-buses behaviour rather than a decision.
    assert_includes graph_text, "[drum][pad]amix=inputs=2:weights=0.9 0.75:duration=first:normalize=0[master_sum]"
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

  # Found by migrating render_industrial rather than by reading the code: the
  # first version summed every channel and then every bus, so a bus declared
  # first arrived last. The sum is the same either way -- each weight travels
  # with its input -- but the graph differs as text, and text is how a migration
  # is proved. A bus is a routing declaration, not a second-class one.
  def test_a_bus_holds_its_declared_position_among_channels
    graph = AudioGraph.new
    graph.bus(:drum)
    graph.channel(:kit, input: "[drums]", bus: :drum)
    graph.channel(:rumble, input: "1:a", gain: 0.55)
    graph.channel(:noise, input: "2:a", gain: 0.06)

    # :drum was declared before both channels, so [drums] leads the sum.
    assert_includes graph.to_filter_complex,
                    "[drums][rumble][noise]amix=inputs=3:weights=1 0.55 0.06"
  end

  # The other half of the same fix: a pass-through of an already-labelled source
  # is that label. Renaming it would be audibly identical and textually noisy.
  def test_a_pass_through_of_a_label_emits_no_clause
    graph = AudioGraph.new
    graph.channel(:kit, input: "[drums]")
    graph.channel(:other, input: "1:a", gain: 0.5)

    refute_includes graph.to_filter_complex, "anull[kit]"
    assert_includes graph.to_filter_complex, "[drums][other]amix"
  end

  # An aeval that does not name its channel layout leaves every biquad after it
  # inert: lowpass, highpass, equalizer, bass and treble pass the audio through
  # untouched, on mono and stereo input alike, with no warning. Measured on
  # 2026-09-14 against this ffmpeg; :c=same restores them. So each aeval in the
  # engine names its layout, and the line is held in both halves: the behaviour,
  # so an ffmpeg that fixes it is noticed, and the source.
  def test_an_unnamed_aeval_layout_silences_the_filters_after_it
    skip "ffmpeg not on PATH" unless system("which", "ffmpeg", out: File::NULL, err: File::NULL)

    top = lambda do |chain|
      out, = Open3.capture2e("ffmpeg", "-hide_banner", "-nostats", "-f", "lavfi", "-i", "anoisesrc=d=1:seed=5", "-af",
                             "#{chain},highpass=f=4000,highpass=f=4000,astats=metadata=0:measure_perchannel=none:measure_overall=RMS_level",
                             "-f", "null", "-")
      out[/RMS level dB:\s*(-?[\d.]+)/, 1].to_f
    end
    assert_operator top.call("aeval=exprs='val(0)':c=same,lowpass=f=500"), :<, top.call("aeval=exprs='val(0)',lowpass=f=500") - 20,
                    "if an unnamed aeval no longer bypasses the lowpass, the :c=same pins can be relaxed"
  end

  def test_every_engine_aeval_names_its_channel_layout
    unpinned = DillaSources.all.flat_map do |path|
      unpinned_aevals(File.read(path)).map { |line| "#{File.basename(path)}:#{line}" }
    end
    assert_empty unpinned, "aeval without :c=same bypasses every biquad after it"
  end

  private

  # The end of each aeval's expression, found the way ffmpeg reads it: a quoted
  # argument runs to its closing quote, an unquoted one to the next separator.
  def unpinned_aevals(source)
    lines = []
    from = 0
    while (at = source.index("aeval=", from))
      from = at + 6
      next if source[at - 1].to_s.match?(/[a-z]/)

      body = at + 6
      body += 6 if source[body, 6] == "exprs="
      pinned = if source[body] == "'"
                 options_after_quote(source, body).match?(/\A:(?:c|channel_layout)=/)
               else
                 stop = source.index(/[,\[\]"\n;]/, body)
                 source[body...stop].match?(/:(?:c|channel_layout)=/)
               end
      next if pinned

      lines << (source[0, at].count("\n") + 1)
    end
    lines
  end

  # The characters after a quoted expression, as ffmpeg reads them: past the
  # closing quote (stepping over #{...} spans so TAPE['drive'] does not end the
  # expression early), then across any Ruby string-continuation to the options,
  # which may open the next source line, as tape_chain's do.
  def options_after_quote(source, body)
    depth = 0
    i = body + 1
    while i < source.bytesize
      if source[i, 2] == "\#{"
        depth += 1
        i += 2
      elsif depth.positive? && source[i] == "}"
        depth -= 1
        i += 1
      elsif depth.zero? && source[i] == "'"
        return source[(i + 1)..].to_s.sub(/\A"(?:[ \t]*\\\n[ \t]*)?"/, "")
      else
        i += 1
      end
    end
    ""
  end
end
