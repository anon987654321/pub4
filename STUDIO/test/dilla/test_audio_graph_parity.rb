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

# ---------------------------------------------------------------------------
# The same question, asked of the code the renderer actually calls.
#
# Absorbed from test_audio_graph_render_dilla.rb. The class above proves the
# spine CAN emit what render_dilla used to build by hand, from literals copied
# out of it -- which would keep passing if render_dilla had been migrated
# wrongly, because it never calls render_dilla's code. These call
# dilla_mix_graph, which is what the renderer now uses.
# ---------------------------------------------------------------------------
  # A full six-channel render: the shape a default `dilla dilla` produces, taken
  # from a dumped filter graph rather than imagined -- drums, harm, bass,
  # analog pad, vinyl and rumble at the weights that render used.
  LABELS = %w([drums_c] [harm] [bassducked] [analogpad] [vinyl] [rumble]).freeze
  WEIGHTS = %w[0.95 1.12 1.15 0.62 0.35 0.25].freeze

  def by_hand(labels, weights)
    "#{labels.join}amix=inputs=#{labels.length}:weights=#{weights.join(' ')}:duration=first:normalize=0[mix]"
  end

  def through_spine(labels, weights)
    graph = dilla_mix_graph(labels, weights)
    [graph.to_filter_complex(out_label: nil), graph.sum_label]
  end

  def test_the_six_channel_mix_is_character_identical
    text, sum = through_spine(LABELS, WEIGHTS)

    assert_equal by_hand(LABELS, WEIGHTS), text.gsub(sum, "mix")
  end

  # Weights are positional in amix, so a reordered graph silently reassigns every
  # one of them. This is the failure that would not look like a failure.
  def test_each_weight_stays_with_its_own_channel
    text, = through_spine(LABELS, WEIGHTS)
    order = text[/amix=inputs=6:weights=([^:]+):/, 1].split
    labels = text[/((?:\[[a-z_0-9]+\])+)amix/, 1].scan(/\[([a-z_0-9]+)\]/).flatten

    assert_equal WEIGHTS, order
    assert_equal LABELS.map { |l| l.delete("[]") }, labels
  end

  # "1.0" is not "1", and the difference is the whole reason format_gain takes
  # Strings verbatim. render_dilla's sidechain branch sets exactly this weight.
  def test_a_string_weight_is_emitted_as_written
    text, = through_spine(%w([sc_mix] [bassducked]), %w[1.0 1.15])

    assert_includes text, "weights=1.0 1.15:"
    refute_includes text, "weights=1 1.15:"
  end

  # Every channel a render can produce has to reach master. A name missing from
  # DILLA_MIX_BUS_MAP falls back to :master, which is safe -- but a name mapped
  # to a bus that is never declared would be dropped from the sum silently, and
  # that is a channel that stops being audible with no error anywhere.
  def test_no_channel_is_dropped_under_bus_routing
    with_env("DILLA_MIX_BUSES" => "1") do
      text, = through_spine(LABELS, WEIGHTS)
      LABELS.each do |label|
        assert_includes text, label, "#{label} vanished from the graph under bus routing"
      end
    end
  end

  # Bus routing is opt-in precisely because it changes the text. If it ever
  # stopped doing so, the default path and the bus path would have converged and
  # one of them is not doing what it says.
  def test_bus_routing_is_off_by_default_and_changes_the_graph_when_on
    flat, = through_spine(LABELS, WEIGHTS)
    bussed, = with_env("DILLA_MIX_BUSES" => "1") { through_spine(LABELS, WEIGHTS) }

    refute_equal flat, bussed
    assert_includes bussed, "kit_sum"
  end

  # The map exists to group channels. A typo in a label name there would route a
  # channel to :master by accident and read as working, so the names are checked
  # against the ones the renderer can actually emit.
  def test_every_mapped_name_is_a_label_some_clause_emits
    source = File.read(File.join(DillaSources.root, "lib", "engine", "render_dilla.rb"))
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