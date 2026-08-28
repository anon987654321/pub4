# frozen_string_literal: true
#
# The Dilla renderer.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# Which bus each channel belongs to, when there are buses at all.
#
# Off by default and it has to be. A bus is an extra amix, and while a bus at
# gain 1.0 with its channels' weights carried through is the same sum
# arithmetically, it is not the same graph as text -- and the parity proof for
# moving this renderer onto the spine is textual. So the default is what it has
# always been: every channel straight to master, one amix, no buses.
#
# DILLA_MIX_BUSES=1 groups them. The grouping is not cosmetic: a bus is the only
# place a filter can sit that affects a GROUP of channels, which is what makes
# it somewhere to hang a modulated filter. Modulating six channels separately is
# six routes and six instances; modulating the bus they share is one.
DILLA_MIX_BUS_MAP = {
  drums_c: :kit, drums: :kit, sc_mix: :kit, bedcarved: :kit, loopbed: :kit, bedbridged: :kit,
  harm: :harmonic, padbed: :harmonic, analogpad: :harmonic, chops: :harmonic,
  bassbus: :low, bassducked: :low, subbed: :low,
  vinyl: :texture, rumble: :texture, selfsample: :texture, wavmap: :texture,
}.freeze

def dilla_mix_buses? = ENV["DILLA_MIX_BUSES"] == "1"

# A bus chain is empty unless something asks for one. An empty-chained bus still
# sums, so the grouping is real even before anything is patched onto it -- which
# is the difference between a bus and a comment saying these belong together.
#
# DILLA_BUS_<NAME> puts a literal filter chain on one. BUS_MOD=<name> puts a
# MOVING one there, which is the reason buses were added at all: a modulated
# filter on a bus reaches every channel in it, and modulating six channels
# separately would be six routes and six filter instances that then have to agree.
def dilla_mix_bus_chain(name)
  raw = ENV["DILLA_BUS_#{name.to_s.upcase}"].to_s
  literal = raw.empty? ? [] : [raw]
  mod = dilla_bus_patch(name, @render_duration_sec.to_f) || dilla_bus_modulation(name)
  mod ? mod + literal : literal
end

# The modulated filter for a bus, as [asendcmd, named-filter] ready to prefix.
#
# One source, one destination, deliberately. A matrix can carry thirty-two routes
# and the useful thing here is the smallest complete demonstration that a
# parameter can move over a render: an LFO on a lowpass across a group of
# channels. Anything richer is worth building as a device rather than as four
# more environment variables.
#
# BUS_MOD names which bus (kit, harmonic, low, texture). Nothing moves unless it
# is set, and DILLA_MIX_BUSES=1 is required for buses to exist at all.
def dilla_bus_modulation(name)
  return nil unless ENV["BUS_MOD"].to_s == name.to_s
  return nil unless (duration = @render_duration_sec.to_f).positive?

  matrix = DillaModulation::Matrix.new
  # BUS_MOD_SYNC takes a musical division -- 1/4, 1/8T, 4bar -- and wins over
  # BUS_MOD_HZ when set. A rate in hertz does not move with the tempo, so on a
  # rotation that changes BPM per track it drifts against everything else.
  begin
    rate_hz = if (sync = ENV["BUS_MOD_SYNC"])
                DillaModulation.sync_hz(sync, @render_bpm || 88.0)
              else
                ENV.fetch("BUS_MOD_HZ", "0.25").to_f
              end
  rescue ArgumentError => e
    warn "bus modulation: #{e.message}"
    return nil
  end
  matrix.lfo(:bus, rate_hz:,
                   family: ENV.fetch("BUS_MOD_FAMILY", "curved").to_sym,
                   morph: ENV.fetch("BUS_MOD_MORPH", "0.33").to_f)
  filter = ENV.fetch("BUS_MOD_FILTER", "lowpass")
  param = ENV.fetch("BUS_MOD_PARAM", "frequency")
  begin
    matrix.route(:bus, instance: "bus#{name}", filter:, param:,
                       base: ENV["BUS_MOD_BASE"]&.to_f,
                       depth: ENV.fetch("BUS_MOD_DEPTH", "1.0").to_f,
                       mode: ENV.fetch("BUS_MOD_MODE", "modulate").to_sym)
  rescue ArgumentError => e
    # A route to a parameter ffmpeg will not accept at runtime is refused by the
    # matrix rather than emitted. Warn and carry on unmodulated: a render should
    # not die because a modulation target was misspelled.
    warn "bus modulation: #{e.message}"
    return nil
  end
  emit_bus_matrix(matrix, name, duration)
end

# BUS_PATCH=random — a whole patch on a bus instead of one LFO.
#
# P_4Ls most-used control is the one that patches itself, and the reason it gets
# used is that its output is worth hearing more often than not. PatchBay.random
# is built for that: one source per destination, depths biased low, and at least
# one inverted so the routes do not all rise together.
#
# BUS_PATCH_SEED pins it. A random patch nobody can get back is a take nobody can
# repeat, which is the fault provenance.rb exists to prevent.
def dilla_bus_patch(name, duration)
  return nil unless ENV["BUS_PATCH"].to_s == "random"

  matrix, patch = DillaModulation::PatchBay.random(
    bpm: @render_bpm || 88.0,
    routes: ENV.fetch("BUS_PATCH_ROUTES", "4").to_i,
    seed: ENV.fetch("BUS_PATCH_SEED", seed_for("buspatch")).to_i
  )
  dmesg("bus patch: " + patch.map { |src, ds| "#{src}->#{ds.keys.join("+")}" }.join(" "),
        unit: "harm0", parent: "dilla0")
  emit_bus_matrix(matrix, name, duration)
end

# A matrix as [asendcmd, filter, filter, ...] ready to prefix onto a bus chain.
#
# Every route needs its own named filter instance in the graph, and the name has
# to be the one the command file writes -- which is why both come from the same
# matrix rather than being spelled twice.
def emit_bus_matrix(matrix, name, duration)
  path = File.join(SCRATCH_DIR, "busmod_#{name}.cmds")
  FileUtils.mkdir_p(SCRATCH_DIR)
  prefix = DillaModulation.prefix_for(matrix, path:, duration:)
  return nil unless prefix

  matrix.describe.each { |line| dmesg("bus modulation: #{line}", unit: "harm0", parent: "dilla0") }
  [prefix] + matrix.routes.map do |route|
    "#{matrix.instance_name(route)}=#{route.param}=#{matrix.initial(route)}"
  end
end

def dilla_mix_graph(mix_labels, mix_weights)
  graph = AudioGraph.new
  buses = if dilla_mix_buses?
            mix_labels.filter_map { |l| DILLA_MIX_BUS_MAP[l.delete("[]").to_sym] }.uniq
          else
            []
          end
  # Buses first, so a bus's position in the master amix follows its declaration
  # rather than the position of whichever channel happened to mention it first.
  buses.each { |b| graph.bus(b, chain: dilla_mix_bus_chain(b)) }
  mix_labels.each_with_index do |label, i|
    name = label.delete("[]")
    bus = buses.empty? ? :master : (DILLA_MIX_BUS_MAP[name.to_sym] || :master)
    graph.channel(name, input: label, gain: mix_weights[i], bus:)
  end
  graph
end

# COPY_MACHINE=n — the sampled bed, played n times at once.
#
# ringtone.tools' Copy Machine, on the one source in a dilla render where it has
# something to say: the record. Copies at different speeds drift apart in time as
# well as pitch, so a four-bar loop stops being four bars and becomes a cloud of
# itself -- which is a texture this engine could not make. organic_vary already
# does multi-speed passes and does them SEQUENTIALLY, one at a time; this is the
# same idea with the passes sounding together.
#
# Applied after flip_loop_entry, so a flipped bed clouds the flip rather than the
# record it came from -- the flip is the musical decision and this is a texture
# over it.
#
# Off by default. It replaces the bed, which is the loudest sampled thing in a
# render, and turning it on for every take on nobody's say-so is not a choice a
# wiring change gets to make. COPY_MACHINE_FAMILY picks harmonic (default),
# chromatic or spray; the rest of CopyMachine's controls carry their own defaults.
def copy_machine_loop_entry(loop_entry, duration)
  copies = ENV.fetch("COPY_MACHINE", "0").to_i
  return loop_entry unless copies > 1 && loop_entry && File.file?(loop_entry[:path].to_s)

  dest = dilla_render_tmp("copymachine")
  out = CopyMachine.build!(
    src: loop_entry[:path], dest:,
    copies:,
    family: ENV.fetch("COPY_MACHINE_FAMILY", "harmonic").to_sym,
    reverse: ENV.fetch("COPY_MACHINE_REVERSE", "0.25").to_f,
    width: ENV.fetch("COPY_MACHINE_WIDTH", "0.8").to_f,
    drift: ENV.fetch("COPY_MACHINE_DRIFT", "220").to_f,
    seed: seed_for("copymachine"),
    duration:, rate: SAMPLE_RATE
  )
  return loop_entry unless out && File.file?(out)

  dmesg("copy machine: #{copies} copies of #{File.basename(loop_entry[:path])} at once",
        unit: "harm0", parent: "dilla0")
  # The bed now covers the whole duration by construction, so the caller must not
  # -stream_loop it -- the same reason organic_vary's output is fed straight in.
  loop_entry.merge(path: out, copy_machined: true)
end

def render_dilla(destination = File.join(OUTPUT_DIR, "beat.mp3"), bars_count = nil, keep_stems: false)
  require_tools! "ffmpeg"
  cleanup_render_scratch!
  pick_render_seed!
  remove_instance_variable(:@resolve_form_map) if instance_variable_defined?(:@resolve_form_map)
  @chord_motif_cache = {}
  ensure_drum_kit!
  FileUtils.mkdir_p(File.dirname(destination))
  cache_self_sample!(destination)
  # Set the previous take aside instead of deleting it.
  #
  # This line must not be FileUtils.rm_f(destination), which destroys the old
  # render before a single note of the new one exists. Every path out of this
  # method that is not "wrote #{destination}" therefore lost the take: a raise,
  # a timeout, a SIGTERM, ffmpeg refusing a filter, the operator pressing ^C
  # thirty seconds in. The window is not small — a 48-bar render is minutes long
  # and the file is gone for all of it.
  #
  # These renders are not reproducible. The seed rotates, the performer and
  # generation are chosen per run, and the mp3 is the only copy — the tree
  # ignores renders, so git has never held one. Two of the operator's tracks
  # went missing mid-session and the cause was read as "another agent"; it was
  # this. It reproduced here exactly: vaular_remix.mp3 existed, a re-render was
  # started against the same path, that render died at 137s, and the finished
  # take was gone with nothing to replace it.
  #
  # cache_self_sample! above keeps 1.2 seconds of the old file. That is a sample
  # source, not a backup, and it is the only thing that has ever survived this.
  previous_take = "#{destination}.prev" if File.file?(destination)
  FileUtils.mv(destination, previous_take) if previous_take
  cfg = dilla_resolve_config
  cfg = DillaSeeds.apply_to_cfg!(cfg)
  n_bars = bars_count || bars
  DillaRhythm.configure!(n_bars:, bpm: cfg[:bpm])
  @render_pad_attack_sec = (cfg[:sonic]&.dig("synth", "pad_attack_ms") || 72).to_f / 1000.0
  rel_ms = (cfg[:sonic]&.dig("synth", "pad_release_ms") || 1400).to_f
  @render_pad_release_decay = (1.0 / [rel_ms / 1000.0, 0.25].max).round(4)
  @render_pad_native_wave = DillaLofiMachine.native_wave_for_pad
  @render_pad_gain = (cfg[:sonic]&.dig("synth", "pad_volume_pct") || 40).to_f / 100.0
  composition_session!(n_bars:, track: cfg[:track].to_s)
  if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
    # ENV/SWING is the style DNA (56). The donuts groove table is 61 and
    # used to overwrite it on every composition render.
    dna = ENV["SWING"].to_s
    cfg = cfg.merge(swing: dna.empty? ? @composition_session.groove_profile[:swing].to_f : dna.to_f)
  end
  pick_synth_patches!(cfg, bar: n_bars / 2, n_bars:)
  beat_p = 60.0 / cfg[:bpm]
  duration = (beat_p * 4.0 * n_bars).round(3)
  # Buses are built far below this point and need the length to size a command
  # file; the alternative is threading it through four call sites that do not
  # otherwise care about it.
  @render_duration_sec = duration
  @render_bpm = cfg[:bpm].to_f
  needed_chords = (n_bars.to_f / cfg[:chord_bars]).ceil + 1
  if GENERATED_STYLES.include?(cfg[:progression].to_sym) || cfg[:progression].to_sym == :generated
    ENV["GEN_LENGTH"] = needed_chords.to_s
  end
  pads = dilla_progression(cfg[:progression])
  if pads.length < 2
    fallback = curated_progression_pads(:maj7_minor_cycle) ||
               curated_progression_pads(cfg[:progression])
    if fallback&.length.to_i >= 2
      warn "progression collapsed to #{pads.length} chord(s) for #{cfg[:track]} — using #{fallback.length}-chord fallback"
      pads = fallback
    else
      abort "progression too short (#{pads.length} chords) for track=#{cfg[:track]} — check chord symbols"
    end
  end
  # Before arrangement, so every downstream voice -- pads, bass, leads, the
  # arrangement's own generated sections -- inherits the loop's key rather than
  # being transposed one at a time afterwards.
  # Anything laid over a sampled loop has to agree with it. Where the loop's key
  # can be read confidently the generated harmony is moved onto it; where it
  # cannot, the tonal layers are MUTED rather than guessed at, and the render is
  # the loop and the kit alone.
  #
  # The threshold is not decorative. Krumhansl fit across the loops here runs
  # 0.697 to 0.836 when the cut is musically sensible, and fell to 0.27 on a cut
  # taken from the wrong part of the same record. Transposing pads onto a 0.27
  # reading is not a smaller version of getting it right -- it is a confident
  # move in an arbitrary direction, and two tonal parts a semitone apart is the
  # one fault no mixing repairs. Silence is the better failure.
  loop_for_key = sample_loop_for(ENV["TRACK"])&.dig(:path)
  # A generated progression in one key over a sampled loop in another is two
  # pieces of music playing at once. HARMONIC_KEEP defaulted OFF, so that is what
  # every sample-backed render did: the loop in its key, the pads in whatever key
  # the progression table happened to hold. Presence of a bed is reason enough --
  # there is no case where you lay pads over a record and want a different key.
  keep_key = HARMONIC_KEEP || !loop_for_key.nil?

  # A record that already states its chords needs nothing added.
  #
  # The guard below mutes the tonal layers when it cannot READ the loop's key,
  # on the reasoning that guessing a progression against an unknown key is worse
  # than silence. That is the right rule for an illegible loop and the wrong
  # question for this one: semua_untuk_mu reads Eb major at fit 0.79 — perfectly
  # legible — and the guard therefore transposed the pads to match and played
  # them over a record whose first ten seconds are vocal chords. Legible is not
  # the same as needs accompanying.
  #
  # Declared per record in TRACK_SAMPLE_LOOPS_BUILTIN, because only the crate
  # knows which records are like this, and the other loops there want their
  # progressions. SAMPLE_HARMONY=0 overrides for a one-off render.
  #
  # SAMPLE_CARRIES_HARMONY=1 says the same thing for a loop the crate has never
  # heard of. That gap was invisible while every loop came from the crate, and
  # opened the moment one did not: a SAMPLE_LOOP=<path> render has no TRACK to
  # look up, so this test was always false and the pads came back over the top
  # of a choir — the exact fault the paragraph above describes, on the exact
  # record it names. Expressing it needed ten environment variables set by hand
  # (PAD_VOL, HARM_MIX_WEIGHT, and the eight tonal layers below), which is a
  # list nobody will get right twice.
  #
  # One fact about the sample, one knob.
  carries_own_harmony = sample_loop_for(ENV["TRACK"])&.dig(:carries_own_harmony) ||
                        ENV["SAMPLE_CARRIES_HARMONY"] == "1"
  if carries_own_harmony && ENV["SAMPLE_HARMONY"] != "0"
    dmesg("harmony: the record carries it — tonal layers muted", unit: "harm0", parent: "dilla0")
    # ANALOG_PAD_WEIGHT belongs in the first list and was not in it. The branch
    # logs "tonal layers muted" and then rendered `analog pad: warm_pad on real
    # oscillators` anyway — a pad voicing the progression, over a record that
    # states its own chords, which is the whole thing this branch exists to
    # prevent. It survived because it is weighted separately from PAD_VOL at
    # render_dilla:615 and the list was written against the other one.
    %w[PAD_VOL HARM_MIX_WEIGHT ANALOG_PAD_WEIGHT].each { |k| ENV[k] = "0" }
    %w[MELODIC_LEAD SCALE_LEAD LEAD_ARP HARMONY_LEAD PAD_LAYERS PAD_TEXTURE
       CHOIR_VOX LUSH_SYNTH].each { |k| ENV[k] = "0" }
    # `pads` is deliberately NOT cleared, and that is the difference between this
    # and the guard below.
    #
    # Emptying it raised NoMethodError in lead_arp.rb's chord_variation_rng —
    # `stable_hash(chord[:name].to_s)` on a nil chord — because dilla_schedule
    # still walks the progression for timing whether or not anything voices it.
    # The guard below does `pads = []` too, so it carries the same crash; it has
    # never fired, because it only triggers on a loop whose key cannot be
    # read and every loop in the crate reads cleanly. A muted layer and an absent
    # progression are not the same thing: the chords still shape the schedule,
    # nothing renders them.
  end

  if loop_for_key && !pads.empty? && HARMONIC_GUARD
    key = sample_key(loop_for_key)
    fit = key ? key[2] : 0.0
    label = key ? "#{PITCH_CLASSES[key[0]]} #{key[1]}" : "unreadable"
    if fit < HARMONIC_MUTE_MIN
      warn "harmonic guard: loop key is #{label} at fit #{fit.round(2)}, below " \
           "#{HARMONIC_MUTE_MIN} — muting tonal layers rather than guessing. " \
           "Pin PROGRESSION and set HARMONIC_GUARD=0 to override."
      %w[PAD_VOL HARM_MIX_WEIGHT].each { |k| ENV[k] = "0" }
      %w[MELODIC_LEAD SCALE_LEAD LEAD_ARP HARMONY_LEAD PAD_LAYERS PAD_TEXTURE
         CHOIR_VOX].each { |k| ENV[k] = "0" }
      # Keep the progression for schedule timing. Emptying pads used to crash
      # lead_arp on chord[:name] of nil. Volumes already mute the tonal layers.
    elsif fit < HARMONIC_GUARD_MIN
      # The middle tier: the root is legible, the mode is not.
      #
      # Krumhansl reports a root and a mode together, but they are not equally
      # certain. The root comes from which pitch class carries the weight, which
      # a loop states plainly; the mode comes from where the THIRD sits, and a
      # horn line that never plays its third leaves that question open. Slot 04
      # read E major at 0.54 against a 0.55 threshold -- almost certainly E,
      # genuinely unsure whether major or minor.
      #
      # Muting the band over that is the wrong trade. So is picking a mode: the
      # third is exactly the note that clashes if the guess is wrong. Instead we
      # play chords that HAVE no third -- root, fifth, ninth. That voicing is
      # consonant against major and minor alike, because the note that
      # distinguishes them is not in it. Rock guitarists have leaned on this for
      # fifty years for the same reason.
      warn "harmonic guard: loop key is #{label} at fit #{fit.round(2)} — root is " \
           "readable, mode is not. Voicing without thirds so the pads sit under " \
           "either reading."
      pads = quintal_voicing(transpose_pads_to(pads, key[0]))
      ENV["MODE_UNCERTAIN"] = "1"
      # Leads pick their notes from the chord's scale, and every scale commits to
      # a third. Only the counter-line survives, restricted below to the tones
      # that both modes share.
      %w[SCALE_LEAD LEAD_ARP].each { |k| ENV[k] = "0" }
      # Already moved onto the loop's root just above; a second pass would
      # measure the transposed pads against the same target and shift by zero,
      # but it would also re-introduce the thirds this branch just removed.
      keep_key = false
    end
  end

  if (keep_key || HARMONIC_SHUFFLE) && !pads.empty?
    if keep_key && (loop_path = sample_loop_for(ENV["TRACK"])&.dig(:path))
      if (root_pc, mode, fit = sample_key(loop_path))
        was = hz_to_pitch_class(pads.first[:hz].min)
        pads = transpose_pads_to(pads, root_pc)
        puts "harmonic keep: loop reads #{PITCH_CLASSES[root_pc]} #{mode} (fit #{fit.round(2)}) — " \
             "pads #{PITCH_CLASSES[was]} → #{PITCH_CLASSES[root_pc]}"
      end
    end
    if HARMONIC_SHUFFLE
      before = pads.map { |c| c[:hz].max.round }
      pads = shuffle_pads_for_melody(pads)
      after = pads.map { |c| c[:hz].max.round }
      puts "harmonic shuffle: top voice #{before.join(' ')} → #{after.join(' ')}"
    end
  end

  fugue_phases = []
  chord_bar_lens = nil
  # Every arranger and pedal decision below reads these three, and two of them
  # read mutable ENV. Once each, up front: a log line that disagrees with the
  # branch it exists to explain is worse than no log line, and the same
  # progression must not be curated for the arranger and uncurated for the pedal.
  curated = curated_progression?(cfg)
  la_beat = la_beat_progression_enabled?
  soul_lock = soul_progression_locked?
  unless pads.empty?
    # Which arranger ran, and on what. A documented transcription asked for by
    # name rendered as D/E → Db/E → C/E → Bm/E → Bbm/E → Am/E -- parallel
    # triads planing down by semitone over an E pedal, which only
    # arrange_fugue/la_beat/camel produce, none of which should be reachable
    # with a curated progression and STREAM_SOUL+STREAM_LOCK set. Every input to
    # that decision (cfg[:progression], the three predicates) was correct when
    # driven directly, so the next render says which branch it actually took
    # instead of leaving it to be inferred from the chords.
    arranger = if camel_mode? && la_beat && !soul_lock
                 :camel
               elsif la_beat && !soul_lock
                 :la_beat
               elsif curated
                 :loop
               else
                 :fugue
               end
    dmesg("arrange #{arranger} progression=#{cfg[:progression]} track=#{cfg[:track]} " \
          "curated=#{curated} la_beat=#{la_beat} " \
          "soul_lock=#{soul_lock} chords=#{pads.length}→#{needed_chords}",
          unit: "harm0", parent: "dilla0")
    pads, fugue_phases, chord_bar_lens = case arranger
                                         when :camel
                                           arrange_camel_beat_progression(pads, needed_chords, cfg)
                                         when :la_beat
                                           arrange_la_beat_progression(pads, needed_chords, cfg)
                                         when :loop
                                           lp = arrange_loop_progression(pads, needed_chords, cfg)
                                           [lp[0], lp[1], nil]
                                         else
                                           fp = arrange_fugue_progression(pads, needed_chords, cfg)
                                           [fp[0], fp[1], nil]
                                         end
  end
  @render_chord_bar_lens = chord_bar_lens
  pedal_prob = curated ? 0.0 : DillaHarmony.pedal_probability(cfg)
  pedal_prob = 0.18 if pedal_prob.zero? && !curated
  pads = apply_pedal_point(pads, probability: pedal_prob, seed: stable_hash(cfg[:track])) unless pedal_prob.zero?
  pads, fugue_phases = if curated
                           DillaHarmony.beautify_curated_pipeline(pads, cfg, phases: fugue_phases)
                         else
                           DillaHarmony.beautify_pipeline(pads, cfg, phases: fugue_phases)
                         end
  @chord_phases = fugue_phases
  @progression_chords = pads
  DillaHarmony.remember_progression(pads)
  symbols = pads.map { |c| c[:name].to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "") }
  @progression_insight = pads.length >= 2 ? DillaHarmony.progression_insight(pads) : nil
  @progression_insight ||= DillaMusicGems.progression_analysis(symbols) if defined?(DillaMusicGems)
  @render_chord_bars = cfg[:chord_bars]
  @render_phrase_bars = cfg[:phrase_bars]
  log_progression_phases!(cfg[:track], cfg[:bpm], pads, fugue_phases)
  bass_pads = nil
  if slash_bass_enabled?(cfg) && !pads.empty?
    bass_pads = slash_bass_pads_for(pads, cfg)
  # Both branches need the same emptiness check. Only the first had one, and the
  # harmonic guard above empties `pads` by design -- so a loop that read below
  # the fit threshold took this branch and died on nil[:hz]. That is the guard
  # crashing on its own escape hatch: it exists to render the loop and the kit
  # alone, and instead it lost the track.
  elsif !curated && !pads.empty? && Random.new(stable_hash(cfg[:track].to_s)).rand < 0.1
    bass_pads = voice_lead_chords(generate_progression(root_hz: pads.first[:hz].min * 0.5, mode: :minor,
                                                         length: pads.length))
  end
  events = dilla_schedule(
    n_bars, beat_p, pads,
    chord_bars: cfg[:chord_bars], phrase_bars: cfg[:phrase_bars],
    swing: cfg[:swing], feel: cfg[:feel], timing: cfg[:timing], quintuplet: cfg[:quintuplet],
    bass_pads:, chord_phases: fugue_phases
  )
  @last_drum_events = events

  pick_external_drum_kit!
  ensure_external_kit_installed!
  kick_raw = load_mono_sample(drum_sample_path("kick.wav"))
  # RAW_KICK / comfort / custom oneshot: use the sample as-is (normalized).
  # layered_kick_sample was re-coating every kit with the same 808 synth so
  # "different drums" still sounded identical.
  kick_sample = if raw_kick_samples?
                  normalize_drum_sample(kick_raw, peak: 0.62)
                else
                  layered_kick_sample(kick_raw)
                end
  kit = extended_drum_kit(
    kick: kick_sample,
    snare: normalize_drum_sample(load_mono_sample(drum_sample_path("snare.wav")), peak: 0.72),
    ghost: normalize_drum_sample(load_mono_sample(drum_sample_path("ghost.wav")), peak: 0.45),
    hat: normalize_drum_sample(load_mono_sample(drum_sample_path("hat.wav")), peak: 0.48),
    open_hat: normalize_drum_sample(load_mono_sample(drum_sample_path("open_hat.wav")), peak: 0.5),
    bass_43: normalize_drum_sample(load_mono_sample(drum_sample_path("bass_43.wav")), peak: 0.55),
    shaker: synth_shaker_sample,
    cowbell: synth_cowbell_sample,
  )
  # Chop override off by default in comfort (DRUM_CHOPS=0); camel chops are
  # always the same Wonky slice and undo EXTERNAL_KIT character.
  apply_drum_chops_to_kit!(kit) if ENV.fetch("DRUM_CHOPS", comfort_mode? ? "0" : "1") != "0"
  unless dilla_pocket_drums_enabled?
    bar_p = beat_p * 4.0
  else
    # Opt-in only — poly + constant 8th shaker + cowbell turned the pocket into
    # a kitchen-sink loop. Set ECLECTIC_PERC=1 for experimental clutter.
    if ENV.fetch("ECLECTIC_PERC", "0") == "1"
      poly_beat = (beat_p * 4.0) / 3.0
      events[:poly] = (0...(duration / poly_beat).floor).map do |i|
        t = (i * poly_beat).round(6)
        [t, (0.16 + 0.07 * Math.sin(i * 1.7)).clamp(0.08, 0.3), :ghost]
      end
      step_p8 = beat_p / 2.0
      events[:shaker] = (0...(duration / step_p8).floor).map do |i|
        t = (i * step_p8).round(6)
        [t, dilla_velocity(0.55, i / 8, i % 8, spread: 0.15)]
      end
      cowbell_rng = Random.new((stable_hash(cfg[:track].to_s) % 100_000) + 41)
      events[:cowbell] = (0...(duration / beat_p).floor).filter_map do |i|
        next unless cowbell_rng.rand < 0.07
        t = (i * beat_p + cowbell_rng.rand(beat_p * 0.6)).round(6)
        [t, dilla_velocity(0.3, i, 0, spread: 0.1)]
      end
    end
    bar_p = beat_p * 4.0
    schedule_eclectic_percussion!(events, duration, beat_p, bar_p, cfg, n_bars) if ENV.fetch("ECLECTIC_PERC", "0") == "1"
  end

  drum_tmp = dilla_render_tmp("drums")
  harmonic_tmp = dilla_render_tmp("harmonic")
  render_sample_bus_wav(drum_tmp, events, duration, kit, drum_bus_mapping)
  drum_field_layer!(drum_tmp, duration:)
    console_strip!(drum_tmp, seed: 11)
  if wonky_drum_overlay_enabled?
    wonky_sub_tmp = dilla_render_tmp("wonky_sub")
    wonky_top_tmp = dilla_render_tmp("wonky_top")
    begin
      render_sample_bus_wav(wonky_sub_tmp, events, duration, kit, wonky_sub_bus_mapping)
      render_sample_bus_wav(wonky_top_tmp, events, duration, kit, wonky_top_bus_mapping)
      merge_wonky_dual_bus!(drum_tmp, wonky_sub_tmp, wonky_top_tmp)
    ensure
      FileUtils.rm_f(wonky_sub_tmp)
      FileUtils.rm_f(wonky_top_tmp)
      FileUtils.rm_f("#{drum_tmp}.merged.#{Process.pid}.wav")
    end
  end
  # Peak lift only — full loudnorm on the drum bus killed punch and made kicks
  # sound flat/wrong. Comfort / DRUM_PEAK_LIFT_DB=0 skips the old always-hot lift
  # that made every mix's drums equally loud regardless of bus fader.
  if File.file?(drum_tmp)
    peak_db = ENV.fetch("DRUM_PEAK_DB", wonky_primary_drums? ? "-1.0" : "-3.0").to_f
    lift_db = if ENV["DRUM_PEAK_LIFT_DB"] && !ENV["DRUM_PEAK_LIFT_DB"].empty?
                ENV["DRUM_PEAK_LIFT_DB"].to_f
              elsif comfort_mode?
                0.0
              elsif wonky_primary_drums?
                5.5
              else
                3.5
              end
    normed = "#{drum_tmp}.norm.wav"
    af = if lift_db.abs < 0.05
           "alimiter=limit=#{(10**(peak_db / 20.0)).round(4)}:level_out=0.92:attack=1:release=50"
         else
           "volume=#{lift_db}dB,alimiter=limit=#{(10**(peak_db / 20.0)).round(4)}:level_out=0.97:attack=1:release=50"
         end
    sh! "ffmpeg", "-y", "-i", drum_tmp, "-af", af, "-c:a", "pcm_s16le", normed
    FileUtils.mv(normed, drum_tmp) if File.file?(normed)
  end

  chop_gate = gate_expr(events[:chop], hold: 0.32, scale: 0.95)
  pad_gate = pad_gate_expr(events[:pad])
  stems = dilla_stem_paths
  stem_tempo = (cfg[:bpm] / 90.0).round(4)
  pan_hz = (cfg[:bpm] / 15.0).round(3)
  use_stem_harmony = !stems.empty?
  bass_bus_tmp = nil
  bass_bus_idx = nil
  bass_own_bus = !use_stem_harmony && ENV.fetch("BASS_OWN_BUS", "1") != "0" && events[:bass]&.any?
  unless use_stem_harmony
    # Bass is rendered on its own so it can bypass the harmonic bus high-pass,
    # which sits above its fundamental. Harmonic gets an empty bass list so the
    # layer is not counted twice.
    render_harmonic_wav(harmonic_tmp, events[:pad], events[:chop],
                        bass_own_bus ? [] : events[:bass], duration,
                        melody_events: events[:melody], cfg:, dfam_events: events[:dfam])
    # Pads and chops only. The bass bus is rendered separately below and is
    # deliberately left out: swelling the low end in and out is heard as an
    # unsteady mix rather than as playing.
    organic_breathe!(harmonic_tmp, bar_sec: (60.0 / cfg[:bpm]) * 4.0)
    console_strip!(harmonic_tmp, seed: 31)
# After the breath, before the mix: the loop shapes the pads while they
# are still a separate bus and can be operated on alone.
sample_drives_pads!(harmonic_tmp, sample_loop_for(ENV["TRACK"])&.dig(:path),
                    duration:)
    if bass_own_bus
      bass_bus_tmp = dilla_render_tmp("bassbus")
      render_harmonic_wav(bass_bus_tmp, [], [], events[:bass], duration, cfg:, pad_post: false)
      bass_own_bus = File.file?(bass_bus_tmp) && File.size(bass_bus_tmp) > 1_000
    end
  end

  command = ["ffmpeg", "-y", "-i", drum_tmp]
  idx = 1
  unless use_stem_harmony
    command += ["-i", harmonic_tmp]
    idx += 1
  end
  if bass_own_bus
    command += ["-i", bass_bus_tmp]
    bass_bus_idx = idx
    idx += 1
  end
  # The analogue pad, rendered before the graph is built so it can be an input
  # like any other file. Pure Ruby, so it costs about a second.
  analog_pad = analog_pad_file(pads, cfg, n_bars, beat_p)
  analog_idx = nil
  if analog_pad && File.file?(analog_pad)
    command += ["-i", analog_pad]
    analog_idx = idx
    idx += 1
  end
  # A picture, read as an oscillator. Same treatment as the analog pad: rendered
  # to a file first so it is an input like any other and needs no special case
  # anywhere downstream.
  wav_map_file = wav_map_layer!(cfg, duration)
  wav_map_idx = nil
  if wav_map_file && File.file?(wav_map_file)
    command += ["-i", wav_map_file]
    wav_map_idx = idx
    idx += 1
  end
  loop_entry = sample_loop_for(cfg[:track])
  # The flip. Cuts the record into pieces and plays a new line out of them,
  # against this track's own chords, instead of repeating the record. What comes
  # back is an ordinary audio file already at the render's tempo, so everything
  # downstream -- the bridges, the drum carving, the mix weight -- treats it
  # exactly as it treated the loop and needs no special case.
  #
  # Falls back to looping when the record will not yield enough usable pieces.
  # A worse version of the track is better than no track.
  loop_entry = flip_loop_entry(loop_entry, cfg, pads, n_bars) if loop_entry
  loop_entry = copy_machine_loop_entry(loop_entry, duration) if loop_entry
  loop_idx = nil
  if loop_entry
    varied = nil
    if ORGANIC_VARY
      varied = organic_vary_loop!(loop_entry[:path], dilla_render_tmp("varyloop"),
                                  duration:)
    end
    if varied
      # Already covers the full duration with each pass differing, so it must
      # NOT be stream_looped -- that would repeat the varied bed identically and
      # put the sameness back at a longer period.
      command += ["-i", varied]
    elsif loop_entry[:copy_machined]
      # Same reason: the cloud was rendered to the full duration, and looping it
      # would stack a second period on top of the one the copies already make.
      command += ["-i", loop_entry[:path]]
    else
      command += ["-stream_loop", "-1", "-i", loop_entry[:path]]
    end
    loop_idx = idx
    idx += 1
  end
  stem_map = {}
  stems.each do |key, path|
    command += ["-stream_loop", "-1", "-i", path]
    stem_map[key] = idx
    idx += 1
  end
  self_sample_idx = nil
  # Previous-render feedback can re-inject full Get Dis Money / prior mix as a "sample".
  if File.exist?(SELF_SAMPLE_CACHE) && ENV.fetch("SELF_SAMPLE", "1") != "0"
    command += ["-stream_loop", "-1", "-i", SELF_SAMPLE_CACHE]
    self_sample_idx = idx
    idx += 1
  end
  ir_input_idx = nil
  unless ENV["CONV_REVERB"] == "0"
    ir_room = ENV["CONV_REVERB"]&.to_sym
    ir_room = :chamber if deep_render? && (!ir_room || !CONVOLUTION_ROOMS.key?(ir_room))
    ir_room ||= render_pick(CONVOLUTION_ROOMS.keys, "conv_room")
    ir_path = DillaMaster.club_ir_path || synth_impulse_response!(ir_room)
    command += ["-i", ir_path]
    ir_input_idx = idx
    idx += 1
  end
  ghost_n = events[:ghost]&.length || 0
  kick_n = events[:kick]&.length || 1
  vinyl_base = sonic_vinyl_level(cfg[:sonic])
  vinyl_amp = vinyl_base.positive? ? DillaMl.groove_synced_vinyl(ghost_n, kick_n, base: vinyl_base) : 0.0
  if vinyl_amp.positive?
    command += ["-f", "lavfi", "-i", "anoisesrc=color=pink:r=#{SAMPLE_RATE}:amplitude=#{vinyl_amp}:d=#{duration}:seed=#{noise_seed(13)}"]
  end
  turntable_rumble = vinyl_amp.positive? && sonitex_enabled? &&
                     TURNTABLE_RUMBLE_VARIANTS.include?(analog_resolve_variant(track: cfg[:track].to_s))
  command += ["-f", "lavfi", "-i", "anoisesrc=color=brown:r=#{SAMPLE_RATE}:amplitude=0.02:d=#{duration}:seed=#{noise_seed(14)}"] if turntable_rumble

  # Every attempt to fix chord audibility by tuning EQ/weights/sidechain
  # *within* the elaborate mix chain (NY parallel drum compression, a
  # sub-150Hz sidechain duck keyed off the harm bus, per-bus RMS-matched
  # boosts, loudnorm) failed in real listening even when measurements said
  # it should work — confirmed by a from-scratch minimal mix (plain per-bus
  # volume + amix + one limiter, no sidechain/compression stack at all)
  # that DID produce audible chords. That proves the elaborate chain itself
  # was the problem, not the balance numbers. This mirrors that minimal,
  # proven-working mix instead of layering another fix onto the old one.
  # SP-1200-style crunch (that machine IS drum-sampler heritage: 12-bit,
  # tape-saturated) directly on the drum bus, on top of whatever the
  # whole-mix Sonitex pass adds later — more analog grit specifically where
  # it was asked for, not spread thin across the entire mix.
  # Complementary EQ carving, not just level: drums get a shallow dip right
  # where pad-chord fundamentals sit (300-700Hz) so the harm bus doesn't
  # have to fight for that space; the harm bus (below) gets the matching
  # cut down where the kick/bass actually live. Genuine frequency-slotting,
  # not another gain adjustment.
  # Each bus gets its section envelope prefixed onto its own chain, so a layer
  # leaves and returns instead of playing flat from bar one to the end.
  filt = [apply_section_envelope(build_drum_bus_filter(cfg, cfg[:sonic], duration:), :drums, n_bars, beat_p * 4.0)]
  # The kit is sharpened and tapped for a key signal here, once, before anything
  # downstream decides what to do with it. Doing this inside the sidechain
  # branch tied both to a preset flag: a track with sidechain off got neither a
  # crisp kit nor a key to carve the sampled bed with, for no musical reason.
  drum_label = "[drums]"
  if ENV["DRUM_FORWARD"] != "0"
    # Three taps off the kit, not two. [dr_key] carves the sampled bed and
    # [dr_bass] moves the bass out of the kick's way; both are tied off below if
    # their consumer is absent.
    filt << "[drums]asplit=3[dr_raw][dr_key][dr_bass]"
    filt << "[dr_raw]#{drum_crisp_chain || 'anull'}[drums_c]"
    drum_label = "[drums_c]"
  end
  mix_labels = [drum_label]
  # Drums sat at 0.72 under a 0.90 sampled bed and a 1.15 bass -- the quietest
  # thing in a genre built on them. The carve above buys most of the clarity
  # back without level, so this is a nudge rather than a shove.
  mix_weights = [resolved_drum_mix_weight.to_s]
  intro_bars = cfg.fetch(:intro_bars, 4)
  harm_fade_start = (beat_p * 4.0 * [intro_bars, 2].min).round(2)
  harm_fade_dur = (beat_p * 4.0 * 1.25).round(2)
  unless use_stem_harmony
    # The harmony bus is the loudest single channel in a typical render (weight
    # 1.12-1.70 against the kit's 0.95) and until now the only channel of that
    # size with no section shape at all. Under the default table :harm is
    # declared flat at 1.0 everywhere, so this is a no-op and the mix is
    # unchanged; under SECTION_LAYERS=full it swells into the breakdowns.
    filt << apply_section_envelope(
      build_harm_bus_filter(1, duration, cfg, cfg[:sonic], harm_fade_start, harm_fade_dur, beat_p, n_bars),
      :harm, n_bars, beat_p * 4.0
    )
    if cfg[:sidechain]
      filt.concat(sidechain_filter_chain(cfg, drum_label:))
      mix_labels = ["[sc_mix]"]
      mix_weights = ["1.0"]
    else
      mix_labels << "[harm]"
      mix_weights << ENV.fetch("HARM_MIX_WEIGHT", deep_render? ? "1.70" : "1.52").to_s
    end
  end

  # Bass joins the master mix directly, alongside drums, never through the harm
  # bus. Added after the sidechain branch above deliberately: when sidechain is
  # on it collapses drums+harm into [sc_mix], and the bass should not be ducked
  # by the same chord-triggered envelope that keeps the pads out of the kick.
  if bass_own_bus && bass_bus_idx
    filt << apply_section_envelope(build_bass_bus_filter(bass_bus_idx, duration), :bass, n_bars, beat_p * 4.0)
    bass_label = "[bassbus]"
    # The kick and the bass were both boosted in the same octave and
    # summed. The bass bus lifts 70 Hz by 3 dB, which is where a kick's
    # fundamental sits, and it entered the mix at 1.15 against the kit's 0.88 --
    # the loudest thing in the track, sitting exactly on top of the one sound
    # the track is built around.
    #
    # The note above about not ducking the bass is about the CHORD-triggered
    # envelope, and it is right: pads move out of the way of chords, and a bass
    # line that did the same would breathe on every chord change. A kick duck is
    # a different thing entirely, and the two got conflated. This one is keyed
    # off the kick alone -- the drums lowpassed to 120 Hz, so hats and snare
    # never trigger it -- and it releases in 90 ms, well inside an eighth note,
    # so the bass is back before the next note.
    if ENV["DRUM_FORWARD"] != "0" && ENV["BASS_DUCK"] != "0"
      filt << "[dr_bass]lowpass=f=120[dr_bass_k]"
      filt << "#{bass_label}[dr_bass_k]sidechaincompress=threshold=" \
              "#{ENV.fetch('BASS_DUCK_DB', '-28')}dB:ratio=6:attack=2:release=90:level_sc=1.0[bassducked]"
      bass_label = "[bassducked]"
      dmesg("bass ducks under the kick below 120 Hz", unit: "harm0", parent: "dilla0")
    end
    mix_labels << bass_label
    mix_weights << ENV.fetch("BASS_MIX_WEIGHT", "1.15").to_s
  end
  if loop_idx
    filt << apply_section_envelope(
      build_sample_loop_filter(loop_idx, duration, loop_entry[:bpm], cfg[:bpm]), :sample, n_bars, beat_p * 4.0
    )
    bed_label = "[loopbed]"
    if ENV["BRIDGES"] != "0"
      # Four bars, or the phrase if the phrase is shorter than that.
      #
      # Keying this to phrase_bars alone gave a 16-bar track one phrase and
      # therefore no boundary at all -- the feature was on, correct, and silent.
      # Four bars is the unit a hip-hop section actually turns on, and it is
      # where a producer reaches for the filter.
      every = ENV.fetch("BRIDGE_EVERY_BARS", [cfg[:phrase_bars] || 4, 4].min).to_i
      plan = bridge_plan(n_bars, beat_p * 4.0, cfg[:track].to_s, every)
      unless plan.empty?
        filt.concat(bridge_filters(input: bed_label, output: "[bedbridged]", n_bars:,
                                   bar_sec: beat_p * 4.0, track: cfg[:track].to_s, every_bars: every))
        bed_label = "[bedbridged]"
        dmesg("bridges: #{plan.map { |b| "#{b[:kind]}@#{(b[:at] / (beat_p * 4.0)).round}" }.join(' ')}",
              unit: "harm0", parent: "dilla0")
      end
    end
    # The kit's third split exists only when the sidechain branch above ran.
    # Without it there is no key to carve against, and the bed goes in flat.
    if ENV["DRUM_FORWARD"] != "0"
      filt.concat(drum_forward_filters(bed: bed_label, key: "[dr_key]", out: "[bedcarved]"))
      mix_labels << "[bedcarved]"
      dmesg("drums forward: bed carved at #{DRUM_FORWARD_SPLIT.join('/')} Hz", unit: "harm0", parent: "dilla0")
    else
      mix_labels << bed_label
    end
    mix_weights << ENV.fetch("SAMPLE_LOOP_WEIGHT", "0.9").to_s
    dmesg("sample bed #{File.basename(loop_entry[:path])} @#{loop_entry[:bpm].round}bpm -> #{cfg[:bpm].round}bpm",
          unit: "harm0", parent: "dilla0")
  end

  # An asplit output that nothing reads never drains, and a filtergraph with an
  # undrained pad does not finish -- it hangs, with no error to read. The kit
  # splits three ways unconditionally, so on any render without a carved bed the
  # third pad has to be tied off here.
  if ENV["DRUM_FORWARD"] != "0"
    filt << "[dr_key]anullsink" unless mix_labels.include?("[bedcarved]")
    filt << "[dr_bass]anullsink" unless mix_labels.include?("[bassducked]")
  end

  if analog_idx
    filt << apply_section_envelope(
      "[#{analog_idx}:a]aformat=channel_layouts=stereo,highpass=f=70,lowpass=f=6800," \
      "atrim=0:#{duration},apad=whole_dur=#{duration},asetpts=PTS-STARTPTS[analogpad]",
      # :pad, not :harm. This call asked for :harm and the default table says
      # nothing about :harm, so it has always returned the chain untouched --
      # the analog pad, the second-loudest channel in a typical render, has
      # never had a section shape. :harm is the synth harmony bus below and now
      # gets its own; this one is the analog pad and gets :pad. Under the
      # default table both are silent, exactly as before.
      :pad, n_bars, beat_p * 4.0
    )
    mix_labels << "[analogpad]"
    mix_weights << ENV.fetch("ANALOG_PAD_WEIGHT", "0.62").to_s
    dmesg("analog pad: #{ENV.fetch('ANALOG_PAD_PATCH', 'warm_pad')} on real oscillators",
          unit: "harm0", parent: "dilla0")
  end
  if stem_map[:mids]
    pan_fx = cfg[:stereo_pan] ? ",apulsator=mode=sine:hz=#{pan_hz}:amount=0.38" : ""
    filt << "[#{stem_map[:mids]}:a]aformat=channel_layouts=stereo,atempo=#{stem_tempo},atrim=0:#{duration},asetpts=PTS-STARTPTS," \
             "lowpass=f=3400,volume='#{pad_gate}':eval=frame,aphaser=speed=0.11:decay=0.4#{pan_fx}[padbed]"
    mix_labels << "[padbed]"
    mix_weights << "0.82"
  end
  if stem_map[:highs]
    # SECTION_LAYER_GAIN has always said chops are silent through the intro, the
    # breakdown and the outro. Nothing read it until now.
    #
    # Under SECTION_LAYERS=full only, for the same reason the lead's envelope is:
    # every stem render ever made was made without this, and switching it on by
    # default would change all of them on the strength of a table entry rather
    # than on somebody listening.
    chops_chain = "[#{stem_map[:highs]}:a]aformat=channel_layouts=stereo,atempo=#{stem_tempo}," \
                  "atrim=0:#{duration},asetpts=PTS-STARTPTS," \
                  "highpass=f=400,volume='#{chop_gate}':eval=frame,aecho=0.35:0.4:90:0.25[chops]"
    chops_chain = apply_section_envelope(chops_chain, :chops, n_bars, beat_p * 4.0) if section_layers_full?
    filt << chops_chain
    mix_labels << "[chops]"
    mix_weights << "0.68"
  end
  if stem_map[:sub]
    filt << "[#{stem_map[:sub]}:a]aformat=channel_layouts=stereo,atempo=#{stem_tempo},atrim=0:#{duration},asetpts=PTS-STARTPTS," \
             "lowpass=f=180,equalizer=f=72:t=o:w=1:g=4,volume=0.68[subbed]"
    mix_labels << "[subbed]"
    mix_weights << "0.72"
  end
  if stem_map[:center] && !stem_map[:mids]
    filt << "[#{stem_map[:center]}:a]aformat=channel_layouts=stereo,atrim=0:#{duration},asetpts=PTS-STARTPTS," \
             "lowpass=f=3000,volume='#{pad_gate}':eval=frame[padbed]"
    mix_labels << "[padbed]"
    mix_weights << "0.75"
  end

  # The wav_Map drone joins as a texture channel. Highpassed off the sub so it
  # does not fight the bass it sits under, and lowpassed so a picture full of
  # fine detail does not arrive as a sheet of top end. Its weight puts it under
  # the analog pad rather than beside it.
  if wav_map_idx
    filt << apply_section_envelope(
      "[#{wav_map_idx}:a]aformat=channel_layouts=stereo," \
      "highpass=f=#{ENV.fetch('WAV_MAP_HP', '55')},lowpass=f=#{ENV.fetch('WAV_MAP_LP', '7000')}," \
      "atrim=0:#{duration},apad=whole_dur=#{duration},asetpts=PTS-STARTPTS[wavmap]",
      :texture, n_bars, beat_p * 4.0
    )
    mix_labels << "[wavmap]"
    mix_weights << ENV.fetch("WAV_MAP_WEIGHT", "0.30").to_s
  end

  # Vinyl and rumble carry the :texture envelope, which the default table has no
  # entry for -- so under SECTION_LAYERS=1 these are byte-identical to what they
  # were. Under `full` they come up when the band drops out, which is when a
  # record's surface is something you hear rather than something under the mix.
  if vinyl_amp.positive?
    filt << apply_section_envelope(
      "[#{idx}:a]highpass=f=120,lowpass=f=6000,volume=0.045[vinyl]", :texture, n_bars, beat_p * 4.0
    )
    mix_labels << "[vinyl]"
    mix_weights << "0.35"
  end
  if turntable_rumble
    rumble_idx = vinyl_amp.positive? ? idx + 1 : idx
    filt << apply_section_envelope(
      "[#{rumble_idx}:a]lowpass=f=40,highpass=f=22,volume=0.04[rumble]", :texture, n_bars, beat_p * 4.0
    )
    mix_labels << "[rumble]"
    mix_weights << "0.25"
  end
  if self_sample_idx
    # Previous render feedback — off by default on Camel (re-injects prior vocals/sample).
    filt << "[#{self_sample_idx}:a]atrim=0:#{duration},asetpts=PTS-STARTPTS," \
             "lowpass=f=1800,areverse,volume=0.06[selfsample]"
    mix_labels << "[selfsample]"
    mix_weights << "0.55"
  end
  # The mix goes through the routing spine instead of being joined by hand.
  #
  # audio_graph.rb was written to make "route this to the drum bus" sayable and
  # then had exactly one caller -- render_industrial, for a bed -- while this
  # renderer, the one the spine was modelled on, kept assembling the string
  # itself. Its header says so. This is the second caller.
  #
  # Every entry in mix_labels is a label a clause above already emitted, so each
  # becomes a pass-through channel: the spine writes no rename for it, and the
  # amix it emits is character-identical to the line this replaces -- weights,
  # positional order and options included. test_audio_graph_render_dilla.rb pins
  # that against the literal string, so a divergence fails rather than ships.
  #
  # The weights stay Strings deliberately. They are ENV.fetch results and tuned
  # literals -- "1.0", "1.70", "0.9" -- and a round trip through Float would
  # write "1" and "1.7" instead. Same mix, different text, and the parity proof
  # is textual. AudioGraph#format_gain passes a String through untouched.
  graph = dilla_mix_graph(mix_labels, mix_weights)
  filt << graph.to_filter_complex(out_label: nil)
  filt.concat(master_bus_filters(graph.sum_label, track: cfg[:track].to_s, duration:, ir_input_idx:, cfg:))

  # Drop empty segments so a stray "" never becomes "No such filter: ''".
  filt_graph = filt.flatten.compact.map(&:to_s).map(&:strip).reject(&:empty?).join(";")
  command += ["-filter_complex", filt_graph, "-map", "[out]", "-t", duration.to_s, *codec_for(destination), destination]
  File.write("/tmp/last_filter_graph.txt", filt_graph.gsub(";", ";\n")) if ENV["DEBUG_FILTER_DUMP"]
  sh!(*command)
  # Parallel dry kit after Sonitex — measured demo was peak 0.27 with flat 16ths
  # (pattern erased). Blend pre-master drums back so Camel grid is audible.
  if camel_mode? && ENV.fetch("CAMEL_DRY_DRUMS", "1") != "0" && File.file?(drum_tmp) && File.file?(destination)
    # Default dry kit quiet under pads (0.55); raise CAMEL_DRY_DRUM_WEIGHT for kit-forward.
    dry_w = ENV.fetch("CAMEL_DRY_DRUM_WEIGHT", "0.55").to_f
    bed_w = ENV.fetch("CAMEL_BED_WEIGHT", "1.3").to_f
    dry_mix = "#{destination}.drykit#{File.extname(destination)}"
    begin
      sh! "ffmpeg", "-y", "-i", destination, "-i", drum_tmp,
          "-filter_complex",
          "[1:a]aformat=channel_layouts=stereo,equalizer=f=55:t=o:w=0.8:g=2.5," \
          "equalizer=f=200:t=o:w=1:g=1.5,equalizer=f=4500:t=o:w=1.5:g=3,volume=#{dry_w}[dk];" \
          "[0:a]volume=#{bed_w}[bed];" \
          "[bed][dk]amix=inputs=2:weights=1.25 0.75:duration=first:normalize=0," \
          "alimiter=limit=0.97:level_out=0.98[out]",
          "-map", "[out]", *codec_for(dry_mix), dry_mix
      FileUtils.mv(dry_mix, destination) if File.file?(dry_mix)
    rescue StandardError => e
      warn "camel dry drums: #{e.message}"
      FileUtils.rm_f(dry_mix)
    end
  end
  if (rap_slug = rap_vocal_stream_slug)
    begin
      # A different point in the performance per track. Keyed on track and
      # slug together so one track does not enter two voices at the same word.
      variant = stable_hash("#{cfg[:track]}/#{rap_slug}") % RAP_VOCAL_VARIANTS
      fit = rap_vocal_fit!(rap_slug, beat_bpm: cfg[:bpm], n_bars:, progression: cfg[:progression],
                           variant:)
      if fit && File.file?(fit)
        rap_tmp = "#{destination}.rap#{File.extname(destination)}"
        mix_rap_vocal_layer!(destination, fit, rap_tmp, beat_bpm: cfg[:bpm])
        FileUtils.mv(rap_tmp, destination)
        puts "rap-vocal: mixed #{rap_slug} → #{destination}"
      end
    rescue StandardError, SystemExit => e
      warn "rap-vocal: skipped (#{e.class}) — #{e.message}"
    end
  end
  if punk_guitar_enabled?
    begin
      gtr = render_punk_guitar_layer!(cfg[:bpm], n_bars, cfg)
      if gtr && File.file?(gtr)
        gtr_tmp = "#{destination}.gtr#{File.extname(destination)}"
        mix_punk_guitar_layer!(destination, gtr, gtr_tmp)
        FileUtils.mv(gtr_tmp, destination)
        FileUtils.rm_f(gtr)
        puts "punk-guitar: mixed power-chord stabs → #{destination}"
      end
    rescue StandardError, SystemExit => e
      warn "punk-guitar: skipped (#{e.class}) — #{e.message}"
    end
  end
  if DILLA_DRONE
    begin
      # Synthesised by default: harmonic_tmp is the engine's own pad/chord bus,
      # so the drone is built from sound this file made rather than from a
      # sample on disk, and it is in the render's key by construction.
      # DILLA_DRONE_SRC=loop takes the track's sampled loop instead.
      drone_src = if ENV["DILLA_DRONE_SRC"].to_s == "loop"
                    sample_loop_for(ENV["TRACK"])&.dig(:path) || harmonic_tmp
                  else
                    harmonic_tmp
                  end
      drone_tmp = "#{destination}.drone.wav"
      if dilla_render_drone!(drone_src, drone_tmp, duration:)
        mixed = "#{destination}.droned#{File.extname(destination)}"
        sh! "ffmpeg", "-y", "-i", destination, "-i", drone_tmp,
            "-filter_complex",
            "[1:a]volume=#{DILLA_DRONE_VOL}[dr];" \
            "[0:a][dr]amix=inputs=2:duration=first:normalize=0," \
            "alimiter=limit=0.97:level_out=0.98[out]",
            "-map", "[out]", *codec_for(mixed), mixed
        FileUtils.mv(mixed, destination)
        puts "drone: #{File.basename(drone_src)} stretched under the mix → #{destination}"
      end
      FileUtils.rm_f(drone_tmp)
    rescue StandardError => e
      warn "drone: skipped (#{e.class}) — #{e.message}"
    end
  end

  # Final integrated loudness — every track (with or without vocals) same level.
  if ENV.fetch("STREAM_NORMALIZE", "1") != "0" || ENV["DILLA_STREAMING"] == "1"
    normalize_track_loudness!(destination)
  end

  # After loudness for the same reason the brake is: loudnorm would flatten a
  # swell applied before it, which is exactly what happened when this lived on
  # the pad bus.
  organic_swell_master!(destination, bar_sec: (60.0 / cfg[:bpm]) * 4.0)
  dilla_dropout!(destination, bar_sec: (60.0 / cfg[:bpm]) * 4.0)
  tape_hysteresis!(destination)
  master_tilt!(destination)
  master_smooth!(destination)
  mono_bass!(destination)

  # After loudness, not before: the brake ends in near-silence, and normalising
  # a file whose last bar is a fade to nothing pulls the whole track up to
  # compensate for it.
  if DILLA_TAPE_STOP
    begin
      dilla_tape_stop!(destination, beat_bpm: cfg[:bpm])
      puts "tape-stop: #{DILLA_TAPE_STOP_BEATS.round} beats of brake → #{destination}"
    rescue StandardError => e
      warn "tape-stop: skipped (#{e.class}) — #{e.message}"
    end
  end
  export_render_stems!(destination, drum_tmp, harmonic_tmp, events, duration, cfg,
                       use_stem_harmony:)
  keep_stems ||= ENV["KEEP_STEMS"] != "0"
  unless keep_stems
    FileUtils.rm_f(drum_tmp)
    FileUtils.rm_f(harmonic_tmp) unless use_stem_harmony
  end
  stem_note = use_stem_harmony ? stems.keys.join("+") : "synth-harmony+melody"
  mix_note = sonitex_label
  lead_arp_style = lead_arp_cfg_for(@render_lead_patch)&.dig(:style)
  # Only name patches that actually sounded.
  #
  # The lead patches are picked before the lead gate is consulted, so this line
  # listed scale_arp_moog/soul_prophet_arp on renders where lead_arp_enabled? was
  # false and both event arrays came back empty — i.e. it advertised arps in a
  # pads-only render. Read alongside "lead=0/off" in the stream banner two lines
  # later, it directly contradicted the truth, and cost a debugging session
  # chasing arps that were never in the mix.
  # The same trap one level down: under NO_ARP the arp styles are still *chosen*
  # (the patch tables are read before the gate), so this line went on printing
  # "major_third_cycle_full/updown/pingpong" for renders where all three arp paths returned
  # zero events. Naming the styles is conditional on them actually running.
  lead_note = if lead_arp_enabled?
                arp_names = no_arp? ? [] : [@render_scale_arp_style, @render_arp_style, lead_arp_style]
                scale_id = no_arp? ? nil : @render_scale_lead_patch&.dig(:id)
                [scale_id, @render_lead_patch&.dig(:id), *arp_names]
              else
                []
              end
  patch_note = [@render_ep_patch&.dig(:id), @render_warm_patch&.dig(:id), *lead_note].compact.join("/")
  patch_note += " (no lead)" unless lead_arp_enabled?
  kick_note = kicks_enabled? ? "kicks" : "no-kicks"
  comp_note = ""
  if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
    @composition_session.save!
    s = @composition_session
    comp_note = ", performer=#{s.performer}/#{s.groove_dna} gen=#{s.generation}"
  end
  # Layer first so the loudness target is measured on the finished balance, and
  # varispeed last: resampling the master is the final act, the way a tape
  # machine running slow is.
  layer_master!(destination)
  # The album signature sits here: after the per-render character stages, before
  # loudness, so every beat is finished identically and then levelled identically.
  melt_master!(destination)
  normalise_master!(destination, cfg)
  varispeed_master!(destination)
  puts "wrote #{destination} (#{cfg[:bpm].to_i} BPM, #{n_bars} bars, #{cfg[:track]}, #{kick_note}, #{mix_note}, #{stem_note}, patches=#{patch_note}#{comp_note})"
ensure
  # The call at the TOP of this method only clears ITS OWN pid's leftovers
  # from a *previous* call in the same long-lived process (stream()'s loop);
  # it never fires for a fresh one-shot process, since a new pid has no
  # scratch yet at start. Without this, every subprocess-per-render caller
  # (showcase_demo!, .all_tracks_demo/fill_holes.rb) leaked its own
  # .dilla_harmonic.<pid>.wav.*/.dilla_drums.<pid>.wav scratch forever --
  # `ensure` so it still fires if this method raises partway through.
  cleanup_render_scratch!
  # Put the old take back unless a new one actually landed.
  #
  # "Landed" is a size check, not File.exist?: a render killed during the final
  # ffmpeg leaves a truncated destination behind, and restoring nothing over a
  # 40-byte stub would lose the take just as completely as the delete did.
  # 64 KB is under a second of 320k mp3 — anything smaller is wreckage.
  if defined?(previous_take) && previous_take && File.file?(previous_take)
    if File.size?(destination).to_i > 64_000
      FileUtils.rm_f(previous_take)
    else
      FileUtils.mv(previous_take, destination)
      warn "render did not finish — kept the previous #{File.basename(destination)}"
    end
  end
end
