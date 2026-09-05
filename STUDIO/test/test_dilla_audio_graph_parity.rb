# frozen_string_literal: true

require_relative "dilla_helper"

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
  CHOPS = "[4:a]aformat=channel_layouts=stereo,atempo=#{TEMPO},atrim=0:#{DURATION},asetpts=PTS-STARTPTS," \
           "highpass=f=400,volume='#{CHOP_GATE}':eval=frame,aecho=0.35:0.4:90:0.25[chops]".freeze
  SUBBED = "[5:a]aformat=channel_layouts=stereo,atempo=#{TEMPO},atrim=0:#{DURATION},asetpts=PTS-STARTPTS," \
           "lowpass=f=180,equalizer=f=72:t=o:w=1:g=4,volume=0.68[subbed]".freeze
  VINYL = "[6:a]highpass=f=120,lowpass=f=6000,volume=0.045[vinyl]".freeze

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

# ---------------------------------------------------------------------------
# The same question, asked of the code the renderer actually calls.
#
# Absorbed from test_audio_graph_render_dilla.rb. The class above proves the
# spine CAN emit a flat mix from literals. These call dilla_mix_graph, which
# is what the renderer now uses, and pin the bus-routed graph it actually
# emits (kit_sum / harmonic_sum / low_sum / texture_sum).
# ---------------------------------------------------------------------------
  # A full six-channel render: the shape a default `dilla dilla` produces.
  # DILLA_FULL defaults DILLA_MIX_BUSES on, so the engine emits kit / harmonic /
  # low / texture buses rather than one flat amix.
  LABELS = %w([drums_c] [harm] [bassducked] [analogpad] [vinyl] [rumble]).freeze
  WEIGHTS = %w[0.95 1.12 1.15 0.62 0.35 0.25].freeze
  BUSSED_SIX = "[drums_c]amix=inputs=1:weights=0.95:duration=first:normalize=0[kit_sum];" \
               "[harm][analogpad]amix=inputs=2:weights=1.12 0.62:duration=first:normalize=0[harmonic_sum];" \
               "[bassducked]amix=inputs=1:weights=1.15:duration=first:normalize=0[low_sum];" \
               "[vinyl][rumble]amix=inputs=2:weights=0.35 0.25:duration=first:normalize=0[texture_sum];" \
               "[kit_sum][harmonic_sum][low_sum][texture_sum]amix=inputs=4:weights=1 1 1 1:duration=first:normalize=0[mix]"
  FLAT_SIX = "#{LABELS.join}amix=inputs=#{LABELS.length}:weights=#{WEIGHTS.join(' ')}:duration=first:normalize=0[mix]"

  def through_spine(labels, weights)
    graph = dilla_mix_graph(labels, weights)
    [graph.to_filter_complex(out_label: nil), graph.sum_label]
  end

  def test_the_six_channel_mix_is_character_identical
    text, sum = through_spine(LABELS, WEIGHTS)

    assert_equal BUSSED_SIX, text.gsub(sum, "mix")
  end

  # Weights are positional in amix, so a reordered graph silently reassigns every
  # one of them. This is the failure that would not look like a failure.
  def test_each_weight_stays_with_its_own_channel
    text, = through_spine(LABELS, WEIGHTS)

    assert_match(/\[drums_c\]amix=inputs=1:weights=0\.95:/, text)
    assert_match(/\[harm\]\[analogpad\]amix=inputs=2:weights=1\.12 0\.62:/, text)
    assert_match(/\[bassducked\]amix=inputs=1:weights=1\.15:/, text)
    assert_match(/\[vinyl\]\[rumble\]amix=inputs=2:weights=0\.35 0\.25:/, text)
  end

  # "1.0" is not "1", and the difference is the whole reason format_gain takes
  # Strings verbatim. render_dilla's sidechain branch sets exactly this weight.
  def test_a_string_weight_is_emitted_as_written
    text, = through_spine(%w([sc_mix] [bassducked]), %w[1.0 1.15])

    assert_includes text, "[sc_mix]amix=inputs=1:weights=1.0:"
    refute_includes text, "[sc_mix]amix=inputs=1:weights=1:"
    assert_includes text, "[bassducked]amix=inputs=1:weights=1.15:"
  end

  # Every channel a render can produce has to reach master. A name missing from
  # DILLA_MIX_BUS_MAP falls back to :master, which is safe -- but a name mapped
  # to a bus that is never declared would be dropped from the sum silently, and
  # that is a channel that stops being audible with no error anywhere.
  def test_no_channel_is_dropped_under_bus_routing
    text, = through_spine(LABELS, WEIGHTS)
    LABELS.each do |label|
      assert_includes text, label, "#{label} vanished from the graph under bus routing"
    end
  end

  # DILLA_FULL turns buses on. DILLA_MIX_BUSES=0 is the flat path, and it still
  # has to emit a different graph or the opt-out is not doing what it says.
  def test_bus_routing_is_on_by_default_and_the_flat_path_is_opt_out
    bussed, sum = through_spine(LABELS, WEIGHTS)
    flat, flat_sum = with_env("DILLA_MIX_BUSES" => "0") { through_spine(LABELS, WEIGHTS) }

    refute_equal bussed, flat
    assert_includes bussed, "kit_sum"
    refute_includes flat, "kit_sum"
    assert_equal BUSSED_SIX, bussed.gsub(sum, "mix")
    assert_equal FLAT_SIX, flat.gsub(flat_sum, "mix")
  end

  # The map exists to group channels. A typo in a label name there would route a
  # channel to :master by accident and read as working, so the names are checked
  # against the ones the renderer can actually emit.
  def test_every_mapped_name_is_a_label_some_clause_emits
    source = File.read(DillaSources.entry)
    DILLA_MIX_BUS_MAP.each_key do |name|
      assert_includes source, "[#{name}]", "DILLA_MIX_BUS_MAP names [#{name}], which render_dilla never emits"
    end
  end

  private

  def with_env(pairs)
    previous = pairs.keys.to_h { |k| [k, ENV.fetch(k, nil)] }
    pairs.each { |k, v| ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

end