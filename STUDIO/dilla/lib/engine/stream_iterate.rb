# frozen_string_literal: true
#
# Iterating a stream track: measure the render, evolve, render again.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# Loss-gate report for stream promote — RadioBergenStudy#analyze_audio is
# module-private; DeepAudio has the dynamics block gates need.
def stream_analyze_for_gates(path)
  RadioBergenStudy::DeepAudio.analyze(path)
rescue StandardError
  RadioBergenStudy.analyze_audio(path) if RadioBergenStudy.respond_to?(:analyze_audio)
rescue StandardError
  nil
end

def stream_iterate_after_render!(path)
  return unless File.file?(path)
  @stream_iterate_count = (@stream_iterate_count || 0) + 1
  beauty = DillaHarmony.score_beauty(DillaHarmony.last_progression_chords)
  spectrum = render_spectrum(path)
  harsh = DillaMaster.analyze_harshness(spectrum)
  sk = DillaMaster.sub_kick_balance(spectrum, beauty)
  notes = []
  # Dilla-style stream: soft mix nudges only — no morph / grid rewrite / analog roulette.
  if camel_mode?
    if sk[:recommendation] == "boost_sub"
      notes << "sub_ok"
    end
    if harsh[:needs_notch]
      notes << "harsh_soft"
    end
    promote_progression_hook!(ENV["TRACK"].to_s, beauty,
                               report: (stream_analyze_for_gates(path) if DillaMaster.loss_gates.any?),
                               path:)
    notes.concat(stream_iterate_evolve_harmony!) if (@stream_iterate_count % 4).zero?
    reassert_camel_beauty_locks!
    line = "[#{Time.now.utc.iso8601}] ##{@stream_iterate_count} track=#{ENV['TRACK']} beauty=#{beauty} " \
           "camel_beauty #{notes.join(' ')}"
    File.open(STREAM_ITERATE_LOG, "a") { |f| f.puts(line) }
    puts "stream iterate: beauty=#{beauty} camel_lock #{notes.join(', ')}"
    return
  end
  if refine_deep_mix_env!(path)
    notes << "kick=#{ENV['KICK_GAIN']} harm=#{ENV['DEBUG_HARM_WEIGHT']}"
  end
  if harsh[:needs_notch]
    dv = [(resolved_drum_mix_weight - 0.03), 0.22].max
    notes << "drum_vol=#{apply_drum_vol!(dv)}"
  end
  if sk[:recommendation] == "boost_sub" && (ENV["PAD_VOL"] || "52").to_i < 58
    ENV["PAD_VOL"] = ((ENV["PAD_VOL"] || "52").to_i + 2).to_s
    notes << "pad_vol=#{ENV['PAD_VOL']}"
  end
  groove_score = nil
  if instance_variable_defined?(:@last_drum_events) && @last_drum_events
    groove_score = DillaGrooveScore.analyze(@last_drum_events)[:score]
    @last_groove_score = groove_score
    notes << "groove=#{groove_score}"
  end
  promote_progression_hook!(ENV["TRACK"].to_s, beauty,
                             report: (stream_analyze_for_gates(path) if DillaMaster.loss_gates.any?),
                             path:)
  every = [(ENV["EVOLVE_EVERY"] || "3").to_i, 1].max
  evolve_due = composition_enabled? && (@stream_iterate_count % every).zero?
  groove_low = groove_score && groove_score < (ENV["GROOVE_SCORE_MIN"] || "75").to_f
  if evolve_due
    stream_evolve_composition!
    stream_evolve_pocket!
    notes << "evolved"
  elsif groove_low
    stream_evolve_pocket!
    notes << "pocket_nudge"
  end
  if stream_creative_freedom_enabled?
    notes.concat(stream_iterate_creative_freedom!)
  end
  notes.concat(stream_iterate_evolve_harmony!)
  notes.concat(stream_iterate_evolve_wonky_drums!)
  notes.concat(stream_iterate_analog_emulation!)
  line = "[#{Time.now.utc.iso8601}] ##{@stream_iterate_count} track=#{ENV['TRACK']} beauty=#{beauty} " \
         "sub=#{sk[:recommendation]} harsh=#{harsh[:harshness]} #{notes.join(' ')}"
  File.open(STREAM_ITERATE_LOG, "a") { |f| f.puts(line) }
  puts "stream iterate: beauty=#{beauty} #{notes.join(', ')}"
end

def stream_evolve_composition!
  return unless composition_enabled?
  bars = (ENV["BARS"] || STREAM_BARS_COUNT).to_i
  track = ENV["TRACK"].to_s
  sess = composition_session!(n_bars: bars, track:)
  keep_performer = ENV["PERFORMER"]
  keep_groove = ENV["GROOVE_DNA"]
  rng = render_rng("stream_evolve_0", drift: (@stream_iterate_count || 0) + 0)
  sess.motifs.each { |m| m.evolve! if rng.rand < 0.35 }
  if ENV.fetch("STREAM_EVOLVE_PERFORMER", "0") == "1"
    sess.mutate!
    ENV["PERFORMER"] = sess.performer.to_s
    ENV["GROOVE_DNA"] = sess.groove_dna.to_s
  else
    ENV["PERFORMER"] = keep_performer if keep_performer && !keep_performer.empty?
    ENV["GROOVE_DNA"] = keep_groove if keep_groove && !keep_groove.empty?
    sess.instance_variable_set(:@generation, sess.generation + 1)
  end
  cfg = dilla_resolve_config
  ENV["SWING"] = cfg[:swing].round(1).to_s if cfg[:swing]
  sess.save!
  puts "stream evolve gen=#{sess.generation} performer=#{ENV['PERFORMER']} groove=#{ENV['GROOVE_DNA']}"
end

def stream_evolve_pocket!(groove_analysis: nil)
  return unless stream_iterate_enabled?
  cfg = dilla_resolve_config
  return unless DillaComposition::Evolution.dilla_pocket_style?(cfg)
  rng = render_rng("stream_evolve_17", drift: (@stream_iterate_count || 0) + 17)
  events = groove_analysis || (instance_variable_defined?(:@last_drum_events) ? @last_drum_events : nil)
  recs = events ? DillaGrooveScore.evolve_recommendations(DillaGrooveScore.analyze(events)) : {}
  @last_groove_score = recs[:score]

  ENV["SNARE_EARLY"] = recs[:snare_early] == false ? "0" : "1"
  ENV["HATS_LATE"] = recs[:hats_late] == false ? "0" : "1"
  ENV["GROOVE_LOCK"] = "kick"
  ENV["FLAM"] = "1"
  ENV["MARKOV_DRUMS"] = "1" if recs[:markov_ghosts]
  ENV["GHOST_TIER"] = recs[:ghost_tier].to_s if recs[:ghost_tier]

  delta = recs[:swing_delta] || rng.rand(-1.5..1.5)
  swing = (cfg[:swing] || 57).to_f + delta + rng.rand(-0.8..0.8)
  ENV["SWING"] = swing.clamp(52, 62).round(1).to_s
  ENV["SWING_JITTER_TICKS"] = (recs[:jitter_ticks] || 3).to_s

  if rng.rand < 0.45 || recs[:groove_pool]
    pool = recs[:groove_pool] || %w[donuts fantastic_vol2 endtroducing madvillainy]
    ENV["GROOVE_DNA"] = pool.sample(random: rng)
  end

  ENV["GHOST_BOOST_NUDGE"] = recs[:ghost_boost_nudge].round(3).to_s if recs[:ghost_boost_nudge]
  ENV["VELOCITY_SPREAD_NUDGE"] = recs[:velocity_spread_nudge].round(3).to_s if recs[:velocity_spread_nudge]

  ENV["SIDECHAIN_STYLE"] = "dilla" if cfg[:sidechain]
  score_note = @last_groove_score ? " groove_score=#{@last_groove_score}" : ""
  puts "stream pocket: swing=#{ENV['SWING']} groove=#{ENV['GROOVE_DNA']} tier=#{ENV['GHOST_TIER']}#{score_note}"
end

def load_promoted_track_bias
  return unless File.file?(PROMOTED_PROFILES_PATH)
  data = JSON.parse(File.read(PROMOTED_PROFILES_PATH))
  counts = data.reject { |k, _| k.start_with?("_") }
  top = counts.max_by { |_, v| v.to_i }
  top ? top.first.to_sym : nil
rescue StandardError
  nil
end

# Auto-iterate soul harmony: rotate voicing + Donuts-family tracks; bias promoted/learned profiles.
def stream_iterate_evolve_harmony!
  return [] unless stream_iterate_enabled?
  every = [(ENV["STREAM_HARMONY_EVERY"] || ENV["EVOLVE_EVERY"] || "2").to_i, 1].max
  return [] unless (@stream_iterate_count % every).zero?

  rng = render_rng("stream_evolve_31", drift: (@stream_iterate_count || 0) + 31)
  notes = []

  soul_locked = ENV["STREAM_SOUL"] == "1" && ENV["STREAM_LOCK"] == "1"
  if ENV.fetch("STREAM_LEARN_BIAS", "0") != "0"
    if (hint = learn_catalog_top_hint)
      DillaSourceLearn.apply_hints_to_env!(hint)
      notes << "catalog_bias=#{hint[:track] || hint['track']}"
    end
    report = DillaSourceLearn.load_last_report
    if report && report[:engine_hints]
      DillaSourceLearn.apply_hints_to_env!(report[:engine_hints])
      notes << "learn_bias=#{report[:engine_hints][:track]}"
    end
  end

  promoted = load_promoted_track_bias
  if soul_locked
    apply_track_soul_profile!(ENV["TRACK"], force: false)
    notes << "soul_lock=#{ENV['TRACK']}"
  elsif promoted && SOUL_TRACK_FAMILY.include?(promoted) && rng.rand < 0.35
    ENV["TRACK"] = promoted.to_s
    apply_track_soul_profile!(ENV["TRACK"], force: false)
    notes << "promoted=#{promoted}"
  elsif rng.rand < 0.55
    pick = if promoted && SOUL_TRACK_FAMILY.include?(promoted) && rng.rand < 0.4
             promoted
           else
             SOUL_TRACK_FAMILY.sample(random: rng)
           end
    ENV["TRACK"] = pick.to_s
    apply_track_soul_profile!(ENV["TRACK"], force: false)
    notes << "track=#{pick}"
  end

  voicings = DillaHarmony::VOICING_STYLES
  voicing = voicings[(@stream_iterate_count + rng.rand(0..2)) % voicings.length]
  ENV["VOICING"] = voicing.to_s
  notes << "voicing=#{voicing}"

  w = (ENV["EVOLVE_HARMONY_W"] || "0.18").to_f
  ENV["EVOLVE_HARMONY_W"] = (w + rng.rand(-0.04..0.06)).clamp(0.08, 0.35).round(3).to_s
  notes << "harm_w=#{ENV['EVOLVE_HARMONY_W']}"

  notes
end

# Evolve Wonky overlay density, grid bias, quint hats, and dual-bus mix across stream iterations.
def stream_iterate_evolve_wonky_drums!
  return [] unless wonky_drum_overlay_enabled? && stream_iterate_enabled?
  every = [(ENV["STREAM_WONKY_EVERY"] || ENV["EVOLVE_EVERY"] || "2").to_i, 1].max
  return [] unless (@stream_iterate_count % every).zero?

  rng = render_rng("stream_evolve_67", drift: (@stream_iterate_count || 0) + 67)
  notes = []
  remove_instance_variable(:@wonky_overlay_grid_cache) if instance_variable_defined?(:@wonky_overlay_grid_cache)

  ENV["WONKY_OVERLAY_GAIN"] = rng.rand(0.62..0.88).round(2).to_s
  ENV["WONKY_CHORD_DUCK"] = rng.rand(0.72..0.9).round(2).to_s
  ENV["WONKY_SUB_MIX"] = rng.rand(0.42..0.58).round(2).to_s
  ENV["WONKY_TOP_MIX"] = rng.rand(0.38..0.54).round(2).to_s
  ENV["WONKY_GRID_BIAS"] = %i[intro main build turn breakdown outro].sample(random: rng).to_s
  ENV["SIDECHAIN_STYLE"] = "wonky" if rng.rand < 0.4

  if ENV.fetch("STREAM_LEARN_BIAS", "0") != "0" && rng.rand < 0.45
    if (hint = learn_catalog_top_hint)
      DillaSourceLearn.apply_hints_to_env!(hint)
      notes << "wonky_learn=#{hint[:track] || hint['track']}"
    end
  end

  notes << "wonky_gain=#{ENV['WONKY_OVERLAY_GAIN']}"
  notes << "wonky_grid=#{ENV['WONKY_GRID_BIAS']}"
  notes << "drum_gain=#{ENV['DRUM_BUS_GAIN']}" if ENV["DRUM_BUS_GAIN"]
  notes << "rap_vocal=#{ENV['RAP_VOCAL']}" if rap_vocal_stream_slug
  notes
end

# Rotate Sonitex + analog grade stacks; wild random FX mashups for authentic chaos.
def stream_iterate_analog_emulation!
  return [] unless stream_iterate_enabled?
  # Camel “full sound” locks donuts_soul + summing_phasy; rotating to acetate/scuzz
  # re-introduces wall-of-noise and killed the pad character people liked.
  return [] if camel_mode? && ENV.fetch("CAMEL_LOCK_COLOR", "1") != "0"
  every = (ENV["STREAM_ANALOG_EVERY"] || "0").to_i
  return [] if every <= 0
  return [] unless (@stream_iterate_count % every).zero?

  rng = render_rng("stream_evolve_53", drift: (@stream_iterate_count || 0) + 53)
  notes = []

  if ENV.fetch("STREAM_ANALOG_WILD", "1") != "0" && rng.rand < 0.35
    wild_name = build_random_wild_analog_chain!(rng)
    ENV["ANALOG_CHAIN"] = wild_name.to_s
    notes << "analog=#{wild_name}(#{@stream_wild_analog_chain[:fx].length}fx)"
  else
    pool = ANALOG_CHAIN_ROTATE + ANALOG_CHAIN_WILD_ROTATE
    pick = pool[(@stream_iterate_count + rng.rand(0..3)) % pool.length]
    ENV["ANALOG_CHAIN"] = pick.to_s
    @stream_wild_analog_chain = nil
    notes << "analog=#{pick}"
  end

  if rng.rand < 0.5
    sonitex = SONITEX_ROTATE_STREAM[(@stream_iterate_count + rng.rand(0..2)) % SONITEX_ROTATE_STREAM.length]
    ENV["SONITEX_PRESET"] = sonitex.to_s
    ENV["SONITEX"] = sonitex.to_s
    notes << "sonitex=#{sonitex}"
  end

  if rng.rand < 0.4
    cr = CONV_REVERB_ROTATE[(@stream_iterate_count + rng.rand(0..1)) % CONV_REVERB_ROTATE.length]
    ENV["CONV_REVERB"] = cr
    notes << "conv=#{cr}"
  end

  if rng.rand < 0.35
    vinyl = rng.rand(22..48).round
    ENV["VINYL"] = vinyl.to_s
    notes << "vinyl=#{vinyl}"
  end

  notes
end

# Rotate PAD_VOICE + fresh Rhodes/Prophet/Moog pool picks each stream iteration.
def stream_iterate_morph_synth!
  return [] unless synth_morph_enabled?
  voices = PAD_VOICE_MORPH_VOICES
  unless instance_variable_defined?(:@stream_user_pad_locked) && @stream_user_pad_locked
    ENV["PAD_VOICE"] = voices[(@stream_iterate_count || 0) % voices.length].to_s
  end
  reset_render_patches!
  if lead_morph_enabled?
    unless instance_variable_defined?(:@stream_user_lead_locked) && @stream_user_lead_locked
      ENV["LEAD_MORPH_VOICE"] = LEAD_MORPH_VOICES[(@stream_iterate_count || 0) % LEAD_MORPH_VOICES.length].to_s
      arp_key = MORPH_LEAD_ARP_CYCLE[(@stream_iterate_count || 0) % MORPH_LEAD_ARP_CYCLE.length]
      ENV["LEAD_ARP_MODE"] = arp_key.to_s
    end
  end
  cfg = dilla_resolve_config
  pick_synth_patches!(cfg, bar: (@stream_iterate_count || 0) * 4)
  notes = [
    "morph_pad=#{ENV['PAD_VOICE']}",
    "ep=#{@render_ep_patch&.dig(:id)}",
    "warm=#{@render_warm_patch&.dig(:id)}",
  ]
  if lead_morph_enabled?
    notes << "morph_lead=#{ENV['LEAD_MORPH_VOICE'] || ENV['LEAD_VOICE']}"
    notes << "xlead_arp=#{ENV['LEAD_ARP_MODE']}"
    notes << "lead=#{@render_lead_patch&.dig(:id)}"
    notes << "fm_native=1" if fm_native_enabled?
  end
  notes
end

# Per-track creative rotation: new lead/scale patches, arp figures, stem balance.
def stream_iterate_creative_freedom!
  return [] unless stream_creative_freedom_enabled?
  pick_render_seed! # clears the patch cache
  notes = stream_iterate_morph_synth!
  unless notes.any?
    reset_render_patches!
    cfg = dilla_resolve_config
    pick_synth_patches!(cfg, bar: (@stream_iterate_count || 0) * 4)
  end
  rng = render_rng("arp_style", drift: (@stream_iterate_count || 0) + (@render_seed || 0))
  styles = (@render_lead_patch&.dig(:arp_styles) || ARP_PATTERN_BUILDERS.keys).to_a
  @render_arp_style = styles.sample(random: rng)
  scale_styles = (@render_scale_lead_patch&.dig(:arp_styles) || styles).to_a
  @render_scale_arp_style = scale_styles.sample(random: rng)
  nudge = ->(key, field, delta) {
    base = harmonic_stem_mix_value(key, field)
    lo, hi = field == :weight ? [0.08, 1.6] : [0.4, 1.4]
    ENV["HARMONIC_#{key.to_s.upcase}_#{field.to_s.upcase}"] = (base + delta).clamp(lo, hi).round(3).to_s
  }
  nudge.call(:lead_arp, :weight, rng.rand(-0.06..0.08))
  nudge.call(:xlead, :weight, rng.rand(-0.04..0.1)) if lead_morph_enabled?
  nudge.call(:xlead, :volume, rng.rand(-0.06..0.08)) if lead_morph_enabled?
  nudge.call(:lead, :weight, rng.rand(-0.05..0.07))
  nudge.call(:scale_lead, :weight, rng.rand(-0.05..0.06))
  lead_id = @render_lead_patch&.dig(:id) || "lead"
  scale_id = @render_scale_lead_patch&.dig(:id) || "scale"
  notes + [
    "creative=#{@render_arp_style}/#{@render_scale_arp_style}",
    "leads=#{scale_id}+#{lead_id}",
    "stem_w=#{ENV['HARMONIC_LEAD_ARP_WEIGHT']}/#{ENV['HARMONIC_LEAD_WEIGHT']}",
  ]
end

def phone_preview_gate_enabled?
  ENV["PHONE_PREVIEW_GATE"] == "1"
end
