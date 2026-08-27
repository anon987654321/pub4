# frozen_string_literal: true
#
# Scheduling every event in a Dilla render.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

def melody_pitch_from_chord(chord, bar, mel_step)
  return unless chord && chord[:hz]&.any?
  tones = chord[:hz].sort
  midis = tones.map { |h| hz_to_midi(h) }.sort
  # Rotate through upper chord tones (3rd, 5th, 7th, 9th) — not always the root.
  color_idx = [1, 2, 3, 0, 2, 1][(bar + mel_step) % 6] % midis.length
  base_midi = midis[color_idx]
  rng = Random.new((bar * 97) + (mel_step * 41) + stable_hash(chord[:name].to_s))
  approach = if composition_enabled? && rng.rand < 0.22
               neighbor = DillaComposition::Counterpoint.neighbor_tone(midi_to_hz(base_midi + 12),
                                                                     direction: rng.rand < 0.5 ? :up : :down)
               hz_to_midi(neighbor)
             elsif rng.rand < 0.28
               base_midi - (rng.rand < 0.5 ? 1 : 2)
             else
               base_midi
             end
  voiced = DillaComposition::Counterpoint.adjust_voices([midi_to_hz(approach + 12)])
  voiced.first || midi_to_hz(approach + 12)
end

def schedule_dfam_events!(events, n_bars, beat_p, swing, quintuplet, timing)
  return unless DfamEngine.enabled?
  step_p = beat_p / 4.0
  bar_p = beat_p * 4.0
  track = (ENV["TRACK"] || DillaLofiMachine::DEFAULT_PROFILE).to_s
  pattern = DfamEngine.resolve_pattern(seed: (@render_seed || 0) + stable_hash(track))
  patch = DfamEngine.resolve_patch
  ticks = DillaLofiMachine.humanize_ticks_for(track)
  n_bars.times do |bar|
    16.times do |step|
      idx = (bar * 16 + step) % DfamEngine::STEPS
      pitch = pattern[:pitch][idx] / 100.0
      vel = pattern[:velocity][idx] / 100.0
      t = bar * bar_p + step * step_p +
          dilla_swing_offset(step, step_p, swing, quintuplet:) +
          dilla_timing_ms(:hat_down, bar, step, timing, beat_p) / 1000.0
      if ticks.positive?
        h_ms = DillaLofiMachine.humanize_ms(60.0 / beat_p, ticks)
        t += Random.new(bar * 97 + step * 31 + idx).rand(-h_ms..h_ms) / 1000.0
      end
      events[:dfam] << [[t, 0.0].max.round(6), vel, pitch, idx, patch]
    end
  end
end

def render_dfam_wav(path, events, duration)
  return unless events&.any?
  write_stereo_chunks(path, duration) do |chunk_start, chunk_frames, left, right|
    DfamEngine.mix_events!(left, right, events, chunk_start, chunk_frames, sample_rate: SAMPLE_RATE)
  end
  patch = DfamEngine.resolve_patch
  tmp = "#{path}.fx.wav"
  q = (patch[:res_pct] / 100.0 * 6.0 + 0.5).round(2)
  sh! "ffmpeg", "-y", "-i", path, "-af",
      "lowpass=f=#{patch[:filter_hz]}:width_type=q:width=#{q},volume=0.62",
      "-c:a", "pcm_s16le", tmp
  FileUtils.mv(tmp, path)
  path
end

def dilla_hat_steps(bar, feel, n_bars: nil)
  steps = drum_pattern_pick(bar, feel, :hats)
  steps = DillaGroove.euclidean(5, 16, rotation: bar % 16) if ENV["EUCLIDEAN_HATS"] == "1"
  # Replaces rather than adds, and has to stay replaced through the markov line
  # below. Assigning `steps` here is not enough on its own: `steps + pool` unions
  # the preset's own bar-locked hat list back in two lines later, which puts the
  # downbeat under every bar again -- measured, POLYMETER_HATS=3 came back as
  # [0,2,3,5,6,8,9,11,12,14,15] on bar 1, the precessed cycle OR'd with the
  # [0,3,6,9,12,15] it was supposed to displace. That is the exact failure this
  # switch exists to avoid, so the pool is dropped while it is on.
  poly = DillaGroove.polymeter_hat_steps(bar)
  steps = poly if poly.any?
  steps += DillaGroove.prime_poly_steps(bar) if ENV["PRIME_GRID"] == "1"
  pool = if poly.any?
           []
         else
           DRUM_PATTERN_SETS.fetch(drum_feel_key(feel), DRUM_PATTERN_SETS[:default])[:hats]&.flatten || steps
         end
  steps = DillaGroove.markov_steps(bar, :hat, steps + pool)
  steps = DillaGroove.trap_morph_hat_density(bar, n_bars || 16, steps) if n_bars
  steps = DillaRhythm.subdivision_density_steps(steps, bar) if defined?(DillaRhythm)
  if n_bars && bar >= (n_bars * 0.82).to_i
    progress = 1.0 - ((n_bars - 1 - bar).to_f / [n_bars * 0.18, 1].max)
    steps += (0..15).select { |i| i.odd? && Random.new(bar * 421).rand < (0.25 + 0.45 * progress) }
  elsif n_bars && bar >= n_bars - 2
    progress = 1.0 - ((n_bars - 1 - bar).to_f / 2)
    steps += (0..15).select { |i| i.odd? && Random.new(bar * 421 + 7).rand < (0.35 + 0.5 * progress) }
  end
  steps.uniq.sort
end

def wonky_overlay_steps(bar, section, role)
  if (learned = learned_wonky_overlay_steps(role))&.any?
    return learned.dup
  end
  wonky_overlay_grid_pick(bar, section, role)
end

def schedule_wonky_drum_overlay!(events, bar, n_bars, base, step_p, _bar_p, beat_p, swing, _quintuplet, timing,
                                 sec_gain, section, pad_chords, chord_bars:, phrase_bars:, chord_phases:)
  return unless wonky_drum_overlay_enabled?
  return if camel_mode? && bar < camel_drum_entry_bar
  return if !camel_drum_lock? && drum_drop_bar?(bar, section)

  density = wonky_overlay_density(bar, n_bars, chord_bars:, pad_chords:,
                                  chord_phases:, phrase_bars:)
  density = density.clamp(wonky_primary_drums? ? 0.7 : 0.2, 1.35)
  bar_bpm = DillaRhythm.bar_bpm(bar)
  overlay_gain = camel_drum_lock? ? density : (sec_gain * density)
  timing_use = timing || DillaLofiMachine::DILLA_TIMING
  swing_use = [swing.to_f, 60.0].max

  # --- Simplicity: sparse rotating phrases (not dense onset dumps) ---
  if DillaGroove.pocket_dna?
    kicks = DillaGroove.pocket_kicks(bar)
    hard_snares = DillaGroove.pocket_snares_hard(bar, section:)
    ghost_snares = DillaGroove.pocket_snares_ghost(bar)
    hat_steps = DillaGroove.pocket_hats(bar)
  else
    kicks = wonky_overlay_steps(bar, section, :kicks)
    hard_snares = wonky_overlay_steps(bar, section, :snares)
    ghost_snares = Array(learned_wonky_overlay_steps(:ghost_snares)).map(&:to_i)
    hat_steps = wonky_overlay_steps(bar, section, :hats)
  end

  # --- Micro-timing: swing + snare-early / kick-late / hats-late + freehand kick ---
  place = lambda do |step, role_timing|
    t = base + step * step_p
    t += dilla_swing_offset(step, step_p, swing_use, quintuplet: false, bar:, bpm: bar_bpm)
    t += dilla_timing_ms(role_timing, bar, step, timing_use, beat_p) / 1000.0
    t = DillaGroove.apply_pocket_place(t, role: role_timing, beat_p:, bar:, step:, bpm: bar_bpm, section:)
    [t, 0.0].max
  end

  kicks.each do |step|
    role = step.zero? ? :kick_anchor : :kick_sync
    t = place.call(step, role)
    base_vel = step.zero? ? 0.98 : 0.78
    vel = dilla_velocity(base_vel, bar, step, spread: 0.03) *
          overlay_gain * wonky_kick_velocity_scale
    vel *= 0.75 unless step.zero? || step == 10
    sk = DillaGroove.kick_sample_key(bar, step)
    events[:wonky_kick] << [t.round(6), vel.clamp(0.55, 0.99), sk]
  end

  return if section == :breakdown && !camel_keep_wonky_on_breakdown? && !camel_drum_lock?

  (hard_snares | ghost_snares).each do |step|
    ghost = ghost_snares.include?(step) && !hard_snares.include?(step)
    t = place.call(step, ghost ? :ghost : :snare)
    base_vel = ghost ? 0.22 : 0.9
    vel = dilla_velocity(base_vel, bar, step, spread: 0.04) *
          overlay_gain * (ghost ? 1.0 : 1.75)
    sk = DillaGroove.snare_sample_key(ghost:)
    events[:wonky_snare] << [t.round(6), vel.clamp(ghost ? 0.1 : 0.6, ghost ? 0.32 : 0.98), sk]
  end

  if backbeat_clap_enabled?
    hard_snares.each do |step|
      t = place.call(step, :clap)
      vel = dilla_velocity(0.32, bar, step, spread: 0.03) * overlay_gain
      events[:clap] << [t.round(6), vel.clamp(0.14, 0.48), :clap]
    end
  end

  hat_steps.each do |step|
    role = step.even? ? :hat_down : :hat_up
    t = place.call(step, role)
    base_vel = step.even? ? 0.46 : 0.32
    vel = dilla_velocity(base_vel, bar, step, spread: 0.06) * overlay_gain
    events[:wonky_hat] << [t.round(6), vel.clamp(0.16, 0.68), :hat]
  end

  return unless DillaGroove.pocket_open_hat?(bar)
    t = place.call(14, :open)
    vel = dilla_velocity(0.38, bar, 14, spread: 0.04) * overlay_gain
    events[:wonky_hat] << [t.round(6), vel.clamp(0.18, 0.5), :open_hat]

  # No perc / quint / rim spam — simplicity is the trick.
end

def dilla_schedule(n_bars, beat_p, pad_chords, chord_bars: 4, phrase_bars: nil, drums_only: false,
                   swing: 58.0, feel: :default, timing: nil, quintuplet: false, bass_pads: nil,
                   chord_phases: nil)
  bar_p = (beat_p * 4.0).round(6)
  step_p = (beat_p / 4.0).round(6)
  events = Hash.new { |h, k| h[k] = [] }
  groove_meta = { snare_early_ms: [], hat_late_ms: [], ghost_vel: [] }
  # Odd-meter/hemiola nod (Aydin Esen's Turkish-modal odd meters, without a
  # full rewrite of the 16-step grid): every 16th bar loses its last 2
  # steps — a real short bar, not a fake accent. Cumulative bar starts
  # since bar durations are no longer uniform.
  drop_beat_bar = ->(b) { b.positive? && b % 16 == 15 }
  bar_starts = [0.0]
  (1..n_bars).each { |b| bar_starts << bar_starts.last + (drop_beat_bar.call(b - 1) ? bar_p * 0.875 : bar_p) }
  chord_change_i = -1
  prev_bass_root = nil
  prev_pad_chord = nil
  cfg_sched = dilla_resolve_config
  bpm_base = cfg_sched[:bpm]
  # Loop-invariant: cfg_sched[:progression] does not change inside the bar loop.
  curated_sched = curated_progression?(cfg_sched)

  if DillaRhythm.macro_enabled? && %w[1].intersect?([ENV["TEMPO_RAMP"], ENV["BPM_STAIRCASE"], ENV["TEMPO_ACCEL"]])
    bar_starts = [0.0]
    (1...n_bars).each { |b| bar_starts << bar_starts.last + DillaRhythm.bar_duration_sec(b - 1, beat_p) }
  end

  # feel gets reassigned per-phrase below (alternating_drum_feel) when
  # DRUM_STYLE_ALTERNATE is on; original_feel keeps the preset's own value
  # so alternation toggles base<->techno_house every phrase instead of
  # drifting once it flips (feel itself would otherwise become the "base"
  # for the next comparison).
  original_feel = feel

  n_bars.times do |bar|
    base = bar_starts[bar]
    bar_bpm = DillaRhythm.bar_bpm(bar)
    beat_p_bar = 60.0 / bar_bpm
    section = dilla_section(bar, n_bars)
    apply_motif_recall!(bar)
    apply_drum_archetype!(bar, phrase_bars)
    feel = alternating_drum_feel(bar, phrase_bars, original_feel)
    ghost_tier = ghost_tier_for(bar, section)
    sec_gain = dilla_section_gain(bar, n_bars, chord_phases:, pad_chords:,
                                  chord_bars:, phrase_bars:)
    sec_gain *= DillaRhythm.stripdown_gain(bar, section)
    sec_gain *= DillaRhythm.element_strip_gain(base)
    sec_gain *= DillaRhythm.periodic_layer_drop_gain(bar)
    phase = chord_phase_at(bar, pad_chords, chord_phases, chord_bars:, phrase_bars:)
    chop_entry = spectral_arp_chop_bar?(bar, chord_bars, drums_only, section)
    pattern = if DillaGroove.kick_snare_swap?
                dilla_snare_steps(bar, feel, section:)
              else
                dilla_kick_pattern(bar, n_bars, feel)
              end
    pattern = (pattern + [0, 15]).uniq.sort if chop_entry && kicks_enabled?
    pattern = [7, 14] if section == :breakdown
    intro_drum_cutoff = camel_mode? ? camel_drum_entry_bar : 4
    pattern = [0, 10] if section == :intro && bar < intro_drum_cutoff
    pattern = pattern.select { |s| s < 14 } if drop_beat_bar.call(bar)

    chord_lens_sched = instance_variable_defined?(:@render_chord_bar_lens) ? @render_chord_bar_lens : nil
    cur_chord = if drums_only || pad_chords.empty?
                  nil
                else
                  pad_chords[dilla_chord_index(bar, pad_chords, chord_bars:, phrase_bars:,
                                                 chord_bar_lens: chord_lens_sched)]
                end
    # Real bitonal composition, not just chord-following: when bass_pads is
    # given, the bass tracks its own independent progression instead of
    # always echoing the pad chord's root — the bass and the chords can
    # genuinely disagree, on purpose.
    bass_chord = if bass_pads && !bass_pads.empty?
                   bass_pads[dilla_chord_index(bar, bass_pads, chord_bars:, phrase_bars:)]
                 else
                   cur_chord
                 end
    bass_root = dilla_chord_bass_hz(bass_chord)
    unless drums_only || section == :breakdown || bass_root.nil?
      slide_from = bass_slide_enabled? && prev_bass_root && (prev_bass_root - bass_root).abs > 0.5 ? prev_bass_root : nil
      # Was a fixed 0.012s pickup offset, not the tick-authentic system used
      # everywhere else -- 12ms at 90 BPM is ~1.73 ticks, a value no real
      # 96-PPQ nudge could produce. Rounded to the nearest whole tick.
      bass_tick = beat_p / 96.0
      bass_pickup = bass_tick.positive? ? (0.012 / bass_tick).round * bass_tick : 0.012
      bar_bass = [base + bass_pickup, dilla_velocity(0.52, bar, 99, spread: 0.04) * sec_gain, bass_root, bar_p * 0.92]
      bar_bass << slide_from if slide_from
      events[:bass] << bar_bass

      # A line, not a root held for the whole bar.
      #
      # The bass was one note per bar: the chord's root, sounded on the downbeat
      # and sustained for 92% of the bar. That is a bass PART only in the sense
      # that something low is present. It states the harmony the pads are already
      # stating, at the moment they state it, which is the same fault the lead
      # had -- and with the drums and the counter-line both now moving, it was
      # the last layer standing still.
      #
      # Two additions, and no more, because a busy bass under this idiom stops
      # being a pocket and starts being a solo:
      #
      #   Beat 3 gets the fifth, or the octave when the fifth would drop below
      #   the register. That is the oldest move in bass playing and it is what
      #   makes a bar feel like it has two halves.
      #
      #   The last eighth approaches the NEXT bar's root by a semitone, from
      #   whichever side is closer. A chromatic approach is how a walking line
      #   gets somewhere, and it turns a bar line from a seam into a hand-off.
      #
      # Both go through dilla_timing_ms like everything else, so they sit in the
      # same pocket as the note they follow rather than landing on the grid.
      if bass_line_enabled?
        fifth = bass_root * 1.5
        fifth /= 2.0 while fifth > BASS_REGISTER_TOP
        events[:bass] << [
          (base + (beat_p * 2) + (dilla_timing_ms(:bass, bar, 8, timing, beat_p) / 1000.0)).round(6),
          dilla_velocity(0.38, bar, 8, spread: 0.05) * sec_gain, fifth, beat_p * 0.7
        ]

        nxt = bass_pads && !bass_pads.empty? ? bass_pads[dilla_chord_index(bar + 1, bass_pads, chord_bars:, phrase_bars:)] : nil
        target = dilla_chord_bass_hz(nxt) || bass_root
        approach = target * (target >= bass_root ? APPROACH_BELOW : APPROACH_ABOVE)
        events[:bass] << [
          (base + (beat_p * 3.5) + (dilla_timing_ms(:bass, bar, 14, timing, beat_p) / 1000.0)).round(6),
          dilla_velocity(0.32, bar, 14, spread: 0.05) * sec_gain, approach, beat_p * 0.42
        ]
      end
      prev_bass_root = bass_root
    end
    if feel == :chromatic_planing
      pickup = base - step_p * 2
      if kicks_enabled?
        events[:kick] << [[pickup + dilla_timing_ms(:kick_sync, bar, 0, timing, beat_p) / 1000.0, 0.0].max.round(6),
                          dilla_velocity(0.88, bar, 0)]
      end
      events[:bass] << [[pickup + dilla_timing_ms(:bass, bar, 0, timing, beat_p) / 1000.0, 0.0].max.round(6),
                        dilla_velocity(0.50, bar, 0, spread: 0.05), bass_root]
    end

    drop_bar = drum_drop_bar?(bar, section)

    if dilla_pocket_drums_enabled? && kicks_enabled? && !drop_bar
      pattern.each_with_index do |step, i|
        next if DillaGroove.kick_should_drop?(bar, step)
        role = (feel == :syncopated_slash_ninth || step.nonzero?) ? :kick_sync : :kick_anchor
        t = [base + step * step_p +
             dilla_swing_offset(step, step_p, swing, quintuplet:, bar:, bpm: bar_bpm) +
             dilla_timing_ms(role, bar, step, timing, beat_p) / 1000.0, 0.0].max
        t = DillaGroove.apply_event_timing!(t, role: :kick, beat_p:, bar:, step:, bpm: bar_bpm, section:)
        ks = kick_velocity_scale
        kick_role = step.zero? ? :kick_anchor : :kick_sync
        kick_vel = dilla_role_velocity(kick_role, bar, step, sec_gain: sec_gain * ks)
        events[:kick] << [t.round(6), kick_vel]
        double_ticks = DillaGroove.kick_double_offset_ticks(bar, step)
        if double_ticks
          dbl_t = (t + double_ticks * (beat_p / 96.0)).round(6)
          events[:kick] << [dbl_t, (kick_vel * 0.55).clamp(0.05, 0.95)]
        end
        if step.zero?
          events[:sub_osc] ||= []
          events[:sub_osc] << [t.round(6), dilla_velocity(0.06, bar, step, spread: 0.04) * sec_gain * ks, 40.0]
        end
        bass_skip = drums_only ||
                    (feel == :syncopated_slash_ninth && bar.zero? && step < 7) ||
                    (feel != :syncopated_slash_ninth && bar.zero?) ||
                    (section == :breakdown && step < 8)
        next if bass_skip
        bass_lag = feel == :syncopated_slash_ninth ? step_p * 0.12 : 0.0
        events[:bass] << [[t + dilla_timing_ms(:bass, bar, step, timing, beat_p) / 1000.0 + bass_lag, 0.0].max.round(6),
                          dilla_velocity(0.28, bar, step, spread: 0.06) * sec_gain, bass_root, step_p * 0.55]
      end
    end

    if dilla_pocket_drums_enabled? && !(section == :intro && bar < intro_drum_cutoff)
      dilla_snare_steps(bar, feel, section:).each_with_index do |step, si|
        next if drop_bar
        next if section == :breakdown
        t = [base + step * step_p +
             dilla_swing_offset(step, step_p, swing, quintuplet:, bar:, bpm: bar_bpm) +
             dilla_timing_ms(:snare, bar, step, timing, beat_p) / 1000.0 +
             DillaGroove.flam_offset_sec(beat_p), 0.0].max
        t = DillaGroove.apply_event_timing!(t, role: :snare, beat_p:, bar:, step:, bpm: bar_bpm, section:)
        backbeat = halftime? ? [8].include?(step) : [4, 12].include?(step)
        groove_meta[:snare_early_ms] << dilla_timing_ms(:snare, bar, step, timing, beat_p) if backbeat
        snare_vel = dilla_role_velocity(:snare, bar, step, sec_gain:, backbeat:)
        events[:snare] << [t.round(6), snare_vel]
        if backbeat && backbeat_clap_enabled? && %i[main build].include?(section)
          events[:clap] ||= []
          events[:clap] << [t.round(6), dilla_role_velocity(:clap, bar, step, sec_gain:), :clap]
        end
        if backbeat && si.zero? && DillaGroove.snare_prehit_ghost?(bar, step)
          ghost_vel = apply_ghost_tier_vel(dilla_role_velocity(:ghost, bar, step, sec_gain:) * 0.72, ghost_tier)
          groove_meta[:ghost_vel] << ghost_vel
          prehit_t = (t - 3 * (beat_p / 96.0)).round(6).clamp(0.0, Float::INFINITY)
          events[:ghost] << [prehit_t, ghost_vel]
        end
      end
    end

    if dilla_pocket_drums_enabled?
      ghost_steps = dilla_ghost_steps(bar, feel, section:)
      ghost_steps += [1, 9] if feel == :loose_pocket && bar.odd?
      ghost_steps += [5] if feel == :loose_pocket && bar.even?
      ghost_steps += fugue_ghost_answer_steps(pattern, phase)
      ghost_steps.uniq.each do |step|
        next if drop_bar
        t = [base + step * step_p +
             dilla_swing_offset(step, step_p, swing, quintuplet:, bar:, bpm: bar_bpm) +
             dilla_timing_ms(:ghost, bar, step, timing, beat_p) / 1000.0, 0.0].max
        # Ghosts must share pocket place + section jitter — previously skipped
        # apply_event_timing! so they sat on a dead grid while kick/snare breathed.
        t = DillaGroove.apply_event_timing!(t, role: :ghost, beat_p:, bar:, step:,
                                            bpm: bar_bpm, section:)
        ghost_vel = apply_ghost_tier_vel(dilla_role_velocity(:ghost, bar, step, sec_gain:), ghost_tier)
        ghost_vel = (ghost_vel * 1.12).clamp(0.03, 0.72).round(3) if feel == :loose_pocket
        groove_meta[:ghost_vel] << ghost_vel
        events[:ghost] << [t.round(6), ghost_vel]
      end

      hat_steps = dilla_hat_steps(bar, feel, n_bars:)
      # Breakdowns should thin closer to silence, not just half-density --
      # real Dilla breakdowns often drop hats almost entirely rather than
      # keeping a steady (if sparser) pulse.
      hat_steps = if section == :breakdown
                    hat_steps.select.with_index { |_, i| (i % 4).zero? }
                  elsif chop_entry
                    hat_steps.select.with_index { |_, i| i.even? }
                  else
                    hat_steps
                  end
      hat_steps.each_with_index do |step, i|
        next if drop_bar
        next if DillaGroove.hat_should_drop?(bar, step, section:)
        role = if [3, 11].include?(step) && feel == :syncopated_slash_ninth
                 :hat_up
               elsif feel == :loose_pocket && step.odd?
                 :hat_up
               else
                 i.even? ? :hat_down : :hat_up
               end
        t = [base + step * step_p +
             dilla_swing_offset(step, step_p, swing, quintuplet:, bar:, bpm: bar_bpm) +
             dilla_timing_ms(role, bar, step, timing, beat_p) / 1000.0, 0.0].max
        t = DillaGroove.apply_event_timing!(t, role:, beat_p:, bar:, step:, bpm: bar_bpm, section:)
        hat_role = role == :hat_up ? :hat_up : :hat_down
        groove_meta[:hat_late_ms] << dilla_timing_ms(hat_role, bar, step, timing, beat_p)
        events[:hat] << [t.round(6), dilla_role_velocity(hat_role, bar, step, sec_gain:)]
      end

      dilla_open_steps(bar, feel, section:).each do |open_step|
        t = [base + open_step * step_p +
             dilla_swing_offset(open_step, step_p, swing, quintuplet:, bar:, bpm: bar_bpm) +
             0.008, 0.0].max
        t = DillaGroove.apply_event_timing!(t, role: :open, beat_p:, bar:, step: open_step,
                                            bpm: bar_bpm, section:)
        events[:open] << [t.round(6), dilla_role_velocity(:open, bar, open_step, sec_gain:)]
      end
      if feel == :loose_pocket && section == :main && bar % 6 == 4
        t = [base + 10 * step_p +
             dilla_swing_offset(10, step_p, swing, quintuplet:, bar:, bpm: bar_bpm), 0.0].max
        t = DillaGroove.apply_event_timing!(t, role: :ghost, beat_p:, bar:, step: 10,
                                            bpm: bar_bpm, section:)
        events[:ghost] << [t.round(6), dilla_velocity(0.22, bar, 10, spread: 0.04) * sec_gain]
      end

      schedule_hat_roll!(events, bar, base, step_p, swing, quintuplet, timing, beat_p, sec_gain, section) unless drop_bar
      schedule_drum_fills!(events, bar, base, step_p, swing, quintuplet, timing, beat_p, sec_gain, feel, section) unless drop_bar
    end
    schedule_wonky_drum_overlay!(events, bar, n_bars, base, step_p, bar_p, beat_p, swing, quintuplet, timing,
                                 sec_gain, section, pad_chords, chord_bars:, phrase_bars:,
                                 chord_phases:)

    next if drums_only
    next if section == :intro && bar < 2

    chord_lens = instance_variable_defined?(:@render_chord_bar_lens) ? @render_chord_bar_lens : nil
    cur_idx = dilla_chord_index(bar, pad_chords, chord_bars:, phrase_bars:,
                                chord_bar_lens: chord_lens)
    prev_idx = bar.positive? ? dilla_chord_index(bar - 1, pad_chords, chord_bars:,
                                                 phrase_bars:, chord_bar_lens: chord_lens) : -1
    if chord_lens&.any?
      next unless bar.zero? || cur_idx != prev_idx
    else
      next unless (bar % chord_bars).zero?
    end

    chord_change_i += 1
    chord = pad_chords[cur_idx]
    pad_chord = if section == :breakdown && DillaHarmony.soul_profile?(cfg_sched[:track])
                  DillaHarmony.strip_voices(chord, count: 2)
                else
                  chord
                end
    pad_chord = DillaHarmony.fix_chord_for_schedule(pad_chord, prev_pad_chord, curated: curated_sched)
    cvar = dilla_chord_change_variation(chord_change_i, bar, section, feel, step_p, pad_chord)
    pad_t = base + cvar[:pad_offset] + dilla_timing_ms(:pad, bar, 0, timing, beat_p) / 1000.0
    if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
      lead_role = DillaComposition::Conversation.turn_order(bar).first
      pad_t += DillaComposition::Conversation.answer_offset(lead_role, beat_p) * 0.12
    end
    hold_bars = chord_lens&.dig(cur_idx) || chord_bars
    legato_mul = if la_beat_progression_enabled?
                   rng_leg = Random.new(patch_cycle_seed(cur_idx + bar))
                   rng_leg.rand(0.78..1.12)
                 else
                   1.0
                 end
    sustain = (hold_bars * bar_p * 0.97 * cvar[:sustain_mul] * legato_mul *
               DillaHarmony.pad_overlap_mul(prev_pad_chord, pad_chord) *
               harmonic_space_mul(chord_change_i, section, phase)).round(4)
    prev_pad_chord = pad_chord
    pad_vel = dilla_velocity(phase == :recapitulation ? 0.96 : 0.92, bar, 0, spread: 0.03) * sec_gain
    pad_vel *= 0.88 if phase == :development
    pad_vel *= cvar[:pad_vel_mul]
    events[:pad] << [[pad_t, 0.0].max.round(6), pad_vel, pad_chord, sustain]
    if cvar[:double_pad]
      events[:pad] << [[pad_t + cvar[:double_pad_delay], 0.0].max.round(6),
                       dilla_velocity(cvar[:double_pad_vel], bar, 1, spread: 0.05) * sec_gain, pad_chord, sustain * 0.68]
    elsif (feel == :timeless || LOFI_DRUM_FEELS.include?(feel)) && section == :main && bar % 4 == 1 && phase != :development
      events[:pad] << [[pad_t + step_p * 0.5, 0.0].max.round(6),
                       dilla_velocity(0.22, bar, 1, spread: 0.05) * sec_gain, pad_chord, sustain * 0.72]
    end
    unless section == :breakdown || phase == :development
      chop_steps = cvar[:chop_steps]
      chop_steps = chop_steps.select { |s| s < 12 } if phase != :recapitulation && chop_steps.length > 4
      chop_steps << 15 if phase == :recapitulation && chord_change_i % 3 == 1
      chop_chord = if DillaSpectral.breath_mode?
                     { name: "breath", hz: DillaSpectral.breath_perc_hz }
                   elsif DillaHarmony.soul_profile?(cfg_sched[:track])
                     DillaHarmony.chop_tones(pad_chord)
                   else
                     pad_chord
                   end
      chop_steps.uniq.sort.each do |chop_step|
        chop_rng = chord_variation_rng(cfg_sched, chord_change_i, pad_chord, salt: 8819 + chop_step.to_i)
        anchored_step = dilla_anchor_chop_step(chop_step, pattern + dilla_snare_steps(bar, feel, section:), chop_rng)
        chop_t = [base + anchored_step * step_p +
                  dilla_swing_offset(anchored_step.floor, step_p, swing, quintuplet:, bar:, bpm: bar_bpm) +
                  cvar[:chop_jitter], 0.0].max
        chop_t = DillaGroove.apply_event_timing!(chop_t, role: :hat_up, beat_p:, bar:, step: anchored_step.floor,
                                                 bpm: bar_bpm, section:)
        chop_vel = phase == :recapitulation ? 0.58 : 0.52
        events[:chop] << [chop_t.round(6), dilla_velocity(chop_vel, bar, anchored_step.floor, spread: 0.04) * sec_gain, chop_chord]
      end
    end
    mel_allowed = !drums_only && section == :main && phase != :coda &&
                  (phase == :recapitulation || (bar % 4 == 2 && phase != :development))
    if mel_allowed
      mel_step = [2, 6, 10][bar % 3]
      mel_hz = melody_pitch_from_chord(chord, bar, mel_step)
      if mel_hz
        mel_t = [base + mel_step * step_p + dilla_swing_offset(mel_step, step_p, swing, quintuplet:) + 0.006, 0.0].max
        mel_vel = phase == :recapitulation ? 0.44 : 0.38
        events[:melody] << [mel_t.round(6), dilla_velocity(mel_vel, bar, mel_step, spread: 0.06) * sec_gain, mel_hz]
      end
    end
  end
  schedule_dfam_events!(events, n_bars, beat_p, swing, quintuplet, timing)
  events[:_groove_meta] = groove_meta
  events
end

# --- Sample-based drum engine (MPC one-shots + Ruby mixer) ---

def drum_kit_ready?
  %w[kick.wav snare.wav ghost.wav hat.wav open_hat.wav bass_43.wav
     ind_kick.wav ind_clap.wav ind_hat.wav ind_bass_e.wav ind_bass_bb.wav ind_stab.wav].all? do |name|
    File.exist?(File.join(DRUM_DIR, name))
  end
end
