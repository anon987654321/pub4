# frozen_string_literal: true
#
# Scale-locked leads and arpeggios.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

def harmony_lead_enabled?
  # Dilla/camel style DNA enables harmony lead (DILLA_STYLE_DEFAULTS /
  # DILLA_BEST_DEFAULTS). long_soul/golden same. Explicit HARMONY_LEAD=0 wins.
  default = if camel_mode? || %w[long_soul golden warp].include?(ENV["RENDER_MODE"].to_s.downcase)
              "1"
            else
              "0"
            end
  ENV.fetch("HARMONY_LEAD", default) != "0"
end

def harmony_lead_mode
  raw = (ENV["HARMONY_LEP_MODE"] || "hybrid").to_sym
  %i[chord scale hybrid].include?(raw) ? raw : :hybrid
end

def harmony_lead_cfg_for(patch = nil)
  style = (ENV["HARMONY_ARP_STYLE"] || "major_third_cycle_full").to_sym
  {
    style:,
    subdiv: 8,
    gate: 0.68,
    vel: 0.42,
    arp_styles: patch&.dig(:arp_styles) || %i[major_third_cycle_full quint_spread call motif updown],
  }
end

def harmony_lead_events(pad_events, cfg, arp_cfg, progression_insight: nil)
  return [] if pad_events.empty? || arp_cfg.nil?
  beat_p = 60.0 / cfg[:bpm]
  bar_p = beat_p * 4.0
  lead_patch = @render_scale_lead_patch || @render_lead_patch
  octave_mul = 2.0**((lead_patch&.fetch(:octave, 2) || 2) - 1)
  n_bars_est = pad_events.empty? ? 32 : ((pad_events.last[0] / bar_p).ceil + 1)
  events = []
  prev_chord = nil
  pad_events.each_with_index do |(time, velocity, chord, sustain), i|
    next unless chord && chord[:hz]&.any?
    bar_approx = (time / bar_p).floor.clamp(0, [n_bars_est - 1, 0].max)
    section = dilla_section(bar_approx, n_bars_est)
    next if section == :intro && bar_approx < 2
    progress = i.to_f / [pad_events.length - 1, 1].max
    density = DillaHarmonyLead.section_density(section, progress)
    style_hint = DillaHarmonyLead.arp_style_for_change(prev_chord, chord, insight: progression_insight)
    variation = arp_variation_for_chord(i, chord, cfg, arp_cfg, patch: lead_patch, role: :lead)
    variation[:style] = style_hint if style_hint
    variation[:pattern_mode] = :motif if style_hint == :motif
    variation[:pattern_mode] = :call if style_hint == :call
    subdiv = variation[:subdiv]
    step_p = beat_p / subdiv.to_f
    gate = variation[:gate]
    rng = chord_variation_rng(cfg, i, chord, salt: 12_007)
    swing = cfg[:swing].to_f / 100.0 * step_p * 0.28
    tones = DillaHarmonyLead.harmonic_arp_tones_for_chord(chord, prev_chord:, mode: harmony_lead_mode)
    tones = tones.map { |hz| hz * octave_mul }.select { |hz| hz < 2500.0 }
    next if tones.empty?
    pattern = arp_pattern_for_chord(chord, variation, tones.length, rng)
    pattern = chord_motif_for(chord).map { |d| d % tones.length } if variation[:pattern_mode] == :motif
    n_steps = [((sustain / step_p).floor * variation[:n_steps_mul] * density).to_i, 3].max
    step_dur = step_p * gate
    n_steps.times do |step|
      next if arp_rest_step?(step, variation[:rest_prob], i)
      hz = if harmony_lead_mode == :hybrid && step.odd? && (pass = DillaHarmonyLead.passing_tone_hz(chord, step, rng))
             pass
           else
             tones[pattern[step % pattern.length] % tones.length]
           end
      t = arp_step_time(time, step, step_p, swing, variation[:step_jitter], variation)
      break if t >= time + sustain - step_dur * 0.35
      accent = step.zero? || (step % 4).zero?
      vel = (velocity * variation[:vel] * (accent ? 0.92 : 0.78) * density).clamp(0.18, 0.62)
      events << [t, vel, { name: "harmony_lead", hz: [hz] }, step_dur]
    end
    prev_chord = chord
  end
  events.sort_by { |e| e[0] }
end

# Parse root letter from chord name (handles slash chords: D/E → D, not E pedal).
def chord_root_pc(chord)
  raw = chord[:name].to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "").sub(/low\z/, "")
  # Upper structure before slash is the harmony root for lead scale.
  head = raw.split("/").first.to_s
  m = head.match(/\A([A-Ga-g])([#b]?)/)
  return unless m
  names = %w[C C# D D# E F F# G G# A A# B]
  letter = m[1].upcase
  acc = m[2]
  base = { "C" => 0, "D" => 2, "E" => 4, "F" => 5, "G" => 7, "A" => 9, "B" => 11 }[letter]
  return unless base
  pc = base
  pc += 1 if acc == "#"
  pc -= 1 if acc == "b"
  pc % 12
end

# Infer scale mode from chord quality — lead must stay diatonic to this scale.
def chord_scale_mode(chord)
  return :minor unless chord && chord[:hz]&.any?
  name = chord[:name].to_s.downcase
  # Slash chords: quality is on the upper symbol (D/E → major triad on D).
  head = name.split("/").first.to_s
  return :major if head.include?("lyd") || head.include?("maj13") || head.include?("maj9") || head.include?("maj7")
  return :minor if head.include?("dor") || head.include?("m11") || head.include?("m9") || head.include?("m7")
  return :minor if head.match?(/(?:^|[^a-z])m[0-9#b]?/) || head.match?(/[a-g][#b]?m\z/)
  return :major if head.include?("maj") || head.include?("add9") || head.include?("sus")
  # Bare letter or letter+accidental (D, Db, F#) → major triad default.
  return :major if head.match?(/\A[a-g][#b]?\z/)
  # Dominant / mixolydian flavor still uses major scale degrees with b7 via chord tones.
  return :major if head.match?(/7\z/) || head.include?("dom") || head.include?("mix")
  # Interval check from harmonic root (not pedal bass).
  root_pc = chord_root_pc(chord)
  midis = chord[:hz].map { |h| hz_to_midi(h).round }
  if root_pc
    ivs = midis.map { |m| (m - root_pc) % 12 }.uniq
  else
    ivs = chord_intervals_from_hz(chord[:hz])
  end
  return :minor if ivs.include?(3) && !ivs.include?(4)
  return :major if ivs.include?(4) && !ivs.include?(3)
  return :minor if ivs.include?(10) && !ivs.include?(11)
  :major
end

# Semitone degrees for the chord's parent scale (0–11 relative to harmonic root).
def chord_scale_semitones(chord)
  # Prefer richer quality-aware set from harmony-lead heuristics when available.
  if defined?(DillaHarmonyLead) && DillaHarmonyLead.respond_to?(:chord_scale_semitones)
    return DillaHarmonyLead.chord_scale_semitones(chord)
  end
  SCALE_SEMITONES.fetch(chord_scale_mode(chord), SCALE_SEMITONES[:major])
end

def scale_tones_for_chord(chord, lead_low: 58, lead_high: 88)
  return [] unless chord && chord[:hz]&.any?
  root_pc = chord_root_pc(chord)
  root_midi = if root_pc
                # Place root near mid register from chord's center of mass.
                center = chord[:hz].map { |h| hz_to_midi(h) }.sum / chord[:hz].length
                base = center.floor - (center.floor % 12) + root_pc
                base -= 12 while base > center + 6
                base += 12 while base < center - 6
                base
              else
                hz_to_midi(chord[:hz].min).floor
              end
  scale = chord_scale_semitones(chord)
  tones = []
  (-1..3).each do |oct|
    scale.each do |semi|
      midi = root_midi + semi + oct * 12
      tones << midi_to_hz(midi) if midi.between?(lead_low, lead_high)
    end
  end
  tones = tones.uniq.sort
  return tones unless tones.empty?
  chord[:hz].sort.map { |hz| hz * 2.0 }.uniq.sort
end

# Lead tone set: chord tones first (in-register), then scale tones of THIS chord only.
# Guarantees arps/melodies never leave the pad harmony's scale.
def lead_scale_locked_tones_hz(chord, lead_patch: nil, lead_low: 58, lead_high: 84)
  return [] unless chord && chord[:hz]&.any?
  scale_hz = scale_tones_for_chord(chord, lead_low:, lead_high:)
  scale_pcs = scale_hz.map { |h| hz_to_midi(h).round % 12 }.uniq
  chord_midis = chord[:hz].map { |h| hz_to_midi(h) }.sort
  # Drop pedal/bass if multi-voice so lead sits above pads.
  chord_midis = chord_midis.drop(1) if chord_midis.length >= 4
  chord_in_scale = chord_midis.filter_map do |m|
    m += 12 while m < lead_low
    m -= 12 while m > lead_high
    next unless scale_pcs.include?(m.round % 12)
    next unless m.between?(lead_low, lead_high)
    midi_to_hz(m)
  end.uniq
  # Prefer chord tones; fill with scale for arpeggio motion.
  ordered = (chord_in_scale + scale_hz).uniq
  return ordered unless ordered.empty?
  # Fallback: force chord tones into lead register (still better than chromatic).
  chord_midis.map do |m|
    m += 12 while m < lead_low
    m -= 12 while m > lead_high
    midi_to_hz(m)
  end.uniq.sort
end

def scale_arp_section_density(section, progress)
  base = case section
         when :intro then 0.38
         when :breakdown then 0.48
         when :build then 0.88
         when :outro then 0.58
         else 0.74
         end
  base * (progress < 0.1 ? 0.7 : 1.0)
end

def pad_midi_events_for_layer(pad_events, cfg, _patch, role:, duration:)
  return pad_events if pad_events.length < 2
  return pad_events unless la_beat_progression_enabled? || ENV["PAD_LEGATO_VAR"] == "1"
  rng = Random.new(patch_cycle_seed(stable_hash(role) + pad_events.length))
  beat_p = 60.0 / cfg[:bpm]
  pad_events.map.with_index do |parts, i|
    time, vel, chord, sustain = parts
    legato = rng.rand(0.74..1.14)
    stagger = rng.rand(-0.03..0.06) * beat_p
    [time + stagger, vel * rng.rand(0.9..1.02), chord, sustain * legato]
  end
end

def resolve_midi_fx_for(patch, role:)
  midi_fx_specs_for_role(role, patch)
end

def lead_arp_enabled?
  # Explicit off always wins — was: pad_arp_mode != :held forced leads on even
  # when LEAD_ARP=0, so "pads only" streams still rendered wonky lead soup.
  return false if ENV["LEAD_ARP"] == "0"
  return true if pad_arp_mode != :held
  ENV.fetch("LEAD_ARP", "1") != "0"
end

# When true, lead uses subdiv arps (spiral/skip/…); when false, slow melodic phrases.
def lead_true_arp_mode?
  # NO_ARP covers leads, not just pads. It only ever reached pad_arp_mode, so
  # "stop using arpeggiators" silenced the pad arps and left the leads running
  # theirs — and both STREAM_STYLE_SAFE and stream_iterate set LEAD_FORCE_ARP=1
  # on every track, so the forced flag won every time. This has to be checked
  # before that flag rather than after it.
  #
  # False here does not silence the lead; it routes it to slow melodic phrases
  # instead of subdiv arp figures, which is what was being asked for.
  return false if no_arp?

  return false if ENV["MELODIC_LEAD"] == "1" && ENV["LEAD_FORCE_ARP"] != "1"
  return true if ENV["LEAD_FORCE_ARP"] == "1" || ENV["MELODIC_LEAD"] == "0"
  mode = (ENV["LEAD_ARP_MODE"] || lead_arp_mode || "").to_s
  !%w[melodic_soul melodic soul_wash ballad_bloom donuts_shimmer].include?(mode)
end

# Lead arp figure — LEAD_ARP_MODE preset, experimental pool, PAD fallback, or patch midi_arp.
def lead_arp_cfg_for(patch)
  return unless lead_arp_enabled?
  key = lead_arp_preset_key
  base = if key && LEAD_ARP_PRESETS[key]
           LEAD_ARP_PRESETS[key].dup
         elsif key && EXPERIMENTAL_LEAD_ARP_PRESETS[key]
           EXPERIMENTAL_LEAD_ARP_PRESETS[key].dup
         elsif key && PAD_ARP_PRESETS[key]
           PAD_ARP_PRESETS[key].dup.tap { |h| h[:vel] = (h[:vel] * 1.85).clamp(0.38, 0.58) }
         end
  if base
    styles = (base[:arp_styles] || []) | Array(patch&.dig(:arp_styles)) | ARP_PATTERN_BUILDERS.keys.first(8)
    merged = base.merge(patch&.dig(:midi_arp) || {})
                 .merge(arp_styles: styles.uniq)
    # melodic_soul, the default lead mode, sits at gate 0.92 — each note holds
    # 92% of its slot, so one runs into the next and the line reads as legato
    # even before portamento is applied. Capping it detaches the notes.
    merged[:gate] = [merged[:gate] || LEAD_SIMPLE_GATE_MAX, LEAD_SIMPLE_GATE_MAX].min if lead_simple?
    merged
  else
    patch&.dig(:midi_arp) || {
      style: @render_arp_style || :spiral,
      subdiv: 8,
      gate: (patch&.fetch(:gate, 0.72) || 0.72) * 0.88,
      vel: 0.55,
      arp_styles: %i[spiral skip_up euclidean wonky_wobble pingpong],
    }
  end
end

def lead_arp_section_density(section, progress)
  base = case section
         when :intro then 0.55
         when :breakdown then 0.65
         when :build then 1.0
         when :outro then 0.72
         else 0.85
         end
  base * (progress < 0.08 ? 0.75 : 1.0)
end

def xlead_arp_section_density(section, progress)
  base = case section
         when :intro then 0.78
         when :breakdown then 0.88
         when :build then 1.0
         when :outro then 0.82
         else 0.94
         end
  base * (progress < 0.05 ? 0.88 : 1.0)
end

def melodic_lead_mode?
  # NO_ARP has to win here, above the MELODIC_LEAD=0 check, or it does nothing.
  #
  # stream_rotate_voices_and_arps! sets MELODIC_LEAD=0 on every stream and
  # demo-all slot. Turning off lead_true_arp_mode? therefore left the lead in
  # neither state — not a true arp, but blocked from melodic — so it fell
  # through to lead_arp_events with the preset config still attached, which is
  # style=skip_up at subdiv 8. Arps were "off" and the lead was still running
  # eight notes a chord.
  return true if no_arp?

  return false if lead_true_arp_mode?
  return false if ENV["MELODIC_LEAD"] == "0"
  return true if ENV.fetch("MELODIC_LEAD", "0") != "0"
  mode = (ENV["LEAD_ARP_MODE"] || lead_arp_mode || "").to_s
  %w[soul_wash melodic_soul melodic donuts_shimmer ballad_bloom].include?(mode)
end

# Melodic phrase: 1 note/beat, motif 0-2-1-3, voice-led from previous phrase.
# Tones are scale-locked to the current pad chord.
# Let the chord go before the next one arrives.
#
# Measured on an 8-bar render: the harmonic stem sounds 100.0% of the track,
# against 88.6% for drums and 73.1% for bass. Chords hold 97% of their slot and
# then overlap into the next, so the harmony never stops — there is no moment
# where the drums are alone and the next chord has to arrive.
#
# That is the one thing every writeup of Ahmad Jamal's playing puts first, and
# it is the reason his records sample so well: the space was already in them.
# Space is not the absence of an arrangement decision, it is one.
#
# Applied to every fourth chord change, and only in the main sections — an intro
# is already sparse and a breakdown is already the space. HARMONIC_SPACE=0
# restores the continuous hold; HARMONIC_SPACE_MUL tunes how much is given back.
def harmonic_space_mul(chord_change_i, section, phase)
  return 1.0 if ENV["HARMONIC_SPACE"] == "0"
  return 1.0 unless %i[main recapitulation].include?(section) || phase == :recapitulation
  return 1.0 unless (chord_change_i % 4).zero?

  (ENV["HARMONIC_SPACE_MUL"] || "0.62").to_f.clamp(0.3, 1.0)
end

def lead_melodic_phrase_for_chord(time, velocity, chord, sustain, chord_i, cfg, lead_patch,
                                  role: :lead, prev_end_hz: nil)
  tones = lead_scale_locked_tones_hz(chord, lead_patch:)
  return [] if tones.empty?
  beat_p = 60.0 / cfg[:bpm]
  # The lead sits behind the keys, which already sit behind the drums. `time`
  # arrives carrying the pad's offset, so only the remainder is added here.
  time += DillaGroove.role_timing_offset(:lead_extra, beat_p, 0, 0)
  # Quarter notes (subdiv 1 per beat) — readable top line, not arp soup.
  step_p = beat_p
  # Was a hardcoded 0.9, which is legato regardless of LEAD_SIMPLE. The cap has
  # to apply here too, since this is the path NO_ARP now routes every lead into.
  gate = lead_simple? ? LEAD_SIMPLE_GATE_MAX : 0.9
  step_dur = step_p * gate
  n_steps = [(sustain / step_p).floor, 2].max
  n_steps = [n_steps, 6].min
  # Motif over chord tones; rotate per chord so the line breathes.
  base = [0, 2, 1, 3, 1, 0]
  rot = chord_i % [tones.length, 3].max
  pattern = base.map { |d| (d + rot) % tones.length }
  # Voice-lead start: pick tone nearest previous phrase end.
  if prev_end_hz
    start_i = tones.each_with_index.min_by { |hz, _| (hz - prev_end_hz).abs }&.last || 0
    pattern = [start_i] + pattern.reject.with_index { |_, i| i.zero? }
  end
  vel_base = (velocity * 0.62).clamp(0.38, 0.78)
  events = []
  n_steps.times do |step|
    # Leave air every other chord on the last beat.
    next if step == n_steps - 1 && (chord_i % 2).zero? && n_steps > 2
    idx = pattern[step % pattern.length] % tones.length
    hz = tones[idx]
    t = time + step * step_p
    break if t >= time + sustain - step_dur * 0.25
    accent = step.zero?
    vel = (vel_base * (accent ? 1.05 : 0.88)).clamp(0.34, 0.82)
    tag = role == :xlead ? "xlead" : "lead_arp"
    events << [t, vel, { name: tag, hz: [hz] }, step_dur]
  end
  events
end

def lead_arp_events_for_chord(time, velocity, chord, sustain, chord_i, cfg, arp_cfg, lead_patch,
                              role: :lead, n_bars_est: nil, skip_intro: false, progress: nil,
                              prev_end_hz: nil)
  return [] unless chord && chord[:hz]&.any? && arp_cfg
  if role != :xlead && melodic_lead_mode?
    return lead_melodic_phrase_for_chord(time, velocity, chord, sustain, chord_i, cfg, lead_patch,
                                         role:, prev_end_hz:)
  end
  beat_p = 60.0 / cfg[:bpm]
  bar_p = beat_p * 4.0
  n_bars_est ||= ((time / bar_p).ceil + 4)
  bar_approx = (time / bar_p).floor.clamp(0, [n_bars_est - 1, 0].max)
  section = dilla_section(bar_approx, n_bars_est)
  # Keep lead present from bar 0 so streams always have a top line.
  if skip_intro && section == :intro && bar_approx < 1 && role != :xlead
    return []
  end
  progress ||= chord_i.to_f / [n_bars_est, 1].max
  density = role == :xlead ? xlead_arp_section_density(section, progress) : lead_arp_section_density(section, progress)
  density = [density, 0.75].max if role != :xlead
  variation = arp_variation_for_chord(chord_i, chord, cfg, arp_cfg, patch: lead_patch, role:)
  # Melodic (slow phrase) only when melodic_lead_mode? — otherwise full subdiv arps.
  if role != :xlead && melodic_lead_mode?
    variation = variation.merge(
      style: arp_cfg[:style] || :updown,
      subdiv: [arp_cfg.fetch(:subdiv, 2), 4].min,
      rest_prob: [variation[:rest_prob].to_f, 0.22].max,
      pattern_mode: :motif,
      n_steps_mul: 0.55,
      step_jitter: [variation[:step_jitter].to_f, 0.008].min,
    )
  elsif role != :xlead
    # True arp: denser 8ths/16ths, rotate styles from preset pool.
    styles = Array(arp_cfg[:arp_styles])
    styles = %i[spiral skip_up euclidean wonky_wobble] if styles.empty?
    style = styles[chord_i % styles.length] || arp_cfg[:style] || :spiral
    variation = variation.merge(
      style:,
      subdiv: [arp_cfg.fetch(:subdiv, 8), 6].max.clamp(4, 12),
      rest_prob: [variation[:rest_prob].to_f, 0.12].min,
      pattern_mode: :arp,
      n_steps_mul: 1.0,
      step_jitter: [variation[:step_jitter].to_f, 0.012].min,
    )
  end
  subdiv = variation[:subdiv]
  step_p = beat_p / subdiv.to_f
  gate = variation[:gate]
  vel_scale = (variation[:vel] * 1.25).clamp(0.42, 0.72)
  rng = chord_variation_rng(cfg, chord_i, chord, salt: role == :xlead ? 12_007 : 9907)
  swing = cfg[:swing].to_f / 100.0 * step_p * (role == :xlead ? 0.42 : 0.28)
  # Strict: only pitches from this chord's parent scale (+ chord tones).
  tones = lead_scale_locked_tones_hz(chord, lead_patch:)
  tones = scale_tones_for_chord(chord) if tones.empty?
  return [] if tones.empty?
  pattern = arp_pattern_for_chord(chord, variation, tones.length, rng)
  n_steps = [((sustain / step_p).floor * variation[:n_steps_mul]).to_i, role == :xlead ? 3 : 4].max
  n_steps = [n_steps, melodic_lead_mode? ? 8 : 16].min if role != :xlead
  step_dur = step_p * gate
  vel_lo = role == :xlead ? 0.32 : 0.34
  vel_hi = role == :xlead ? 0.9 : 0.85
  events = []
  n_steps.times do |step|
    rest_p = role == :xlead ? [variation[:rest_prob].to_f * 0.35, 0.08].min : [variation[:rest_prob].to_f, 0.18].max
    next if arp_rest_step?(step, rest_p, chord_i)
    hz = tones[pattern[step % pattern.length] % tones.length]
    t = arp_step_time(time, step, step_p, swing, variation[:step_jitter], variation)
    break if t >= time + sustain - step_dur * 0.3
    accent = step.zero? || (step % 4).zero?
    vel = (velocity * vel_scale * (accent ? 1.08 : 0.9) * density).clamp(vel_lo, vel_hi)
    tag = role == :xlead ? "xlead" : "lead_arp"
    events << [t, vel, { name: tag, hz: [hz] }, step_dur]
  end
  events
end

# Continuous lead arpeggiator — chord-tone figures on the lead voice (8th/16th
# subdivisions, patch-specific pattern + MIDI FX). Rendered on its own FluidSynth
# stem (lead_arp.wav); distinct from scale_lead and creative-lead bursts.
def lead_arp_events(pad_events, cfg, arp_cfg)
  return [] if pad_events.empty? || arp_cfg.nil?
  beat_p = 60.0 / cfg[:bpm]
  bar_p = beat_p * 4.0
  lead_patch = @render_lead_patch
  n_bars_est = pad_events.empty? ? 32 : ((pad_events.last[0] / bar_p).ceil + 1)
  prev_end = nil
  events = []
  pad_events.each_with_index do |(time, velocity, chord, sustain), i|
    progress = i.to_f / [pad_events.length - 1, 1].max
    chunk = lead_arp_events_for_chord(time, velocity, chord, sustain, i, cfg, arp_cfg, lead_patch,
                                      role: :lead, n_bars_est:, progress:,
                                      prev_end_hz: prev_end).to_a
    prev_end = chunk.last&.dig(2, :hz)&.first if chunk.any?
    events.concat(chunk)
  end
  events.sort_by { |e| e[0] }
end

# Continuous scale-locked arp on every pad chord — same root/mode as the pad,
# stepping 16ths through scale degrees for the full chord sustain.
def lead_events_scale_arp(pad_events, cfg, duration: nil, n_bars: nil)
  return [] if pad_events.empty?
  # A third arp path. NO_ARP reached pad_arp_mode, then lead_true_arp_mode?, and
  # this one still ran 16ths over every chord underneath both — which is why the
  # render banner kept naming an arp style after the other two were silenced.
  # Returning empty drops a voice rather than muting the track: the melodic lead
  # and the pads both still play.
  return [] if no_arp?
  beat_p = 60.0 / cfg[:bpm]
  bar_p = beat_p * 4.0
  n_bars ||= duration ? (duration / bar_p).ceil : 32
  scale_patch = @render_scale_lead_patch
  base_gate = scale_patch&.fetch(:gate, 0.62) || 0.62
  base_cfg = { style: @render_scale_arp_style || :updown, subdiv: 4, gate: base_gate, vel: 0.38 }
  events = []
  pad_events.each_with_index do |(time, velocity, chord, sustain), i|
    next unless chord && chord[:hz]&.any?
    bar_approx = (time / bar_p).floor.clamp(0, n_bars - 1)
    section = dilla_section(bar_approx, n_bars)
    next if section == :intro && bar_approx < 2
    progress = i.to_f / [pad_events.length - 1, 1].max
    density = scale_arp_section_density(section, progress)
    scale_tones = lead_scale_locked_tones_hz(chord, lead_patch: scale_patch)
    scale_tones = scale_tones_for_chord(chord) if scale_tones.empty?
    next if scale_tones.empty?
    variation = arp_variation_for_chord(i, chord, cfg, base_cfg, patch: scale_patch, role: :scale_lead)
    subdiv = variation[:subdiv]
    step_p = beat_p / subdiv.to_f
    gate = variation[:gate]
    rng = chord_variation_rng(cfg, i, chord, salt: 4423)
    pattern = arp_pattern_for_chord(chord, variation, scale_tones.length, rng)
    n_steps = [((sustain / step_p).floor * variation[:n_steps_mul]).to_i, 4].max
    n_steps = [n_steps, (sustain / step_p).ceil].min
    step_dur = step_p * gate * 0.9
    swing = cfg[:swing].to_f / 100.0 * step_p * 0.35
    n_steps.times do |step|
      next if arp_rest_step?(step, variation[:rest_prob] * 0.65, i)
      hz = scale_tones[pattern[step % pattern.length] % scale_tones.length]
      t = arp_step_time(time, step, step_p, swing, variation[:step_jitter], variation)
      break if t >= time + sustain - step_dur * 0.4
      accent = step.zero? || (step % 4).zero?
      vel = (velocity * (accent ? 0.44 : 0.34) * density * variation[:vel]).clamp(0.14, 0.58)
      events << [t, vel, { name: "scale_arp", hz: [hz] }, step_dur]
    end
  end
  events
end

def arp_degrees_for(style, tone_count, rng)
  return [] if tone_count.to_i <= 0

  builder = ARP_PATTERN_BUILDERS[style] || ARP_PATTERN_BUILDERS[:updown]
  raw = builder.arity >= 2 ? builder.call(tone_count, rng) : builder.call(tone_count)
  raw.map { |d| d % tone_count }
end

# Per-chord RNG — same progression, different figure/timing every change.
def chord_variation_rng(cfg, chord_i, chord, salt: 0)
  seed = (stable_hash(cfg[:track].to_s) % 100_000) + (@render_seed || 0) + chord_i * 131 +
         (stable_hash(chord[:name].to_s) % 5000) + salt
  Random.new(seed)
end

def arp_styles_for_patch(patch, fallback_style)
  patch&.dig(:arp_styles) || [fallback_style || :updown]
end

# Euclidean/ratchet/random_walk/stutter/burst already exist in
# ARP_PATTERN_BUILDERS but every patch's own arp_styles list sticks to the
# safe up/down/updown/pingpong shapes — this is the IDM/Warp-leaning
# opt-in that reaches for the shapes that are already built but unused.
ARP_IDM_STYLES = %i[euclidean ratchet random_walk stutter burst].freeze

# The same opt-in for the shape-based figures. They are already reachable --
# the xlead and lead paths below sample the whole builder table -- but only by
# chance, and a figure you can only get by luck is one you cannot A/B. This is
# the switch that asks for them on purpose. ARP_SHAPE_BIAS=1.
ARP_SHAPE_STYLES = %i[
  plain_hunt golden_rotation tide pendulum cascade
  swallow_dive undertow call_answer rosary murmuration
].freeze

# Each pad/lead chord gets its own arp style, subdiv, gate, swing, and pattern shape.
def arp_variation_for_chord(chord_i, chord, cfg, base_arp_cfg, patch: nil, role: :lead)
  rng = chord_variation_rng(cfg, chord_i, chord, salt: stable_hash(role))
  styles = base_arp_cfg[:arp_styles] || arp_styles_for_patch(patch, base_arp_cfg[:style])
  style = styles[chord_i % styles.length]
  style = ARP_IDM_STYLES.sample(random: rng) if ENV["ARP_IDM_BIAS"] == "1" && rng.rand < 0.65
  style = ARP_SHAPE_STYLES.sample(random: rng) if ENV["ARP_SHAPE_BIAS"] == "1" && rng.rand < 0.65
  if role == :pad
    subdiv_pool = [base_arp_cfg.fetch(:subdiv, 8), 4, 6, 8].uniq
    pattern_modes = %i[style motif sparse stagger call]
    return {
      style:,
      subdiv: subdiv_pool[chord_i % subdiv_pool.length],
      gate: base_arp_cfg.fetch(:gate, 0.75) * rng.rand(0.92..1.06),
      vel: base_arp_cfg.fetch(:vel, 0.22) * rng.rand(0.88..1.1),
      time_offset: rng.rand(-0.02..0.05),
      step_jitter: rng.rand(0.0..0.012),
      rest_prob: rng.rand(0.0..0.06),
      pattern_mode: pattern_modes[chord_i % pattern_modes.length],
      swing_mul: rng.rand(0.75..1.15),
      n_steps_mul: rng.rand(0.72..1.0),
    }
  end
  if role == :xlead
    style = ARP_PATTERN_BUILDERS.keys.sample(random: rng) if rng.rand < 0.55
    subdiv_pool = [3, 4, 6, 8, 12, 16].uniq
    return {
      style:,
      subdiv: subdiv_pool[rng.rand(subdiv_pool.length)],
      gate: base_arp_cfg.fetch(:gate, 0.5) * rng.rand(0.7..1.28),
      vel: base_arp_cfg.fetch(:vel, 0.58) * rng.rand(0.82..1.38),
      time_offset: rng.rand(-0.05..0.12),
      step_jitter: rng.rand(0.0..0.035),
      rest_prob: rng.rand(0.0..0.1),
      pattern_mode: %i[style motif retrograde sparse call stagger burst stutter].sample(random: rng),
      swing_mul: rng.rand(0.5..1.55),
      n_steps_mul: rng.rand(0.55..1.15),
    }
  end
  style = ARP_PATTERN_BUILDERS.keys.sample(random: rng) if rng.rand < 0.3
  subdiv_pool = [base_arp_cfg.fetch(:subdiv, 8), 3, 4, 6, 8, 12].uniq
  # Operator, 2026-08-11: leads at half rate. subdiv is steps per bar, so
  # halving it halves the note rate — the figure is the same, played twice as
  # slow. Floor of 2 so a pool entry of 3 cannot round to a subdivision that
  # produces no steps.
  {
    style:,
    subdiv: [subdiv_pool[rng.rand(subdiv_pool.length)] / 2, 2].max,
    gate: base_arp_cfg.fetch(:gate, 0.62) * rng.rand(0.82..1.14),
    vel: base_arp_cfg.fetch(:vel, 0.5) * rng.rand(0.75..1.2),
    time_offset: rng.rand(-0.035..0.09),
    step_jitter: rng.rand(0.0..0.022),
    rest_prob: rng.rand(0.0..0.14),
    pattern_mode: lead_pattern_mode(chord_i, cfg, rng),
    swing_mul: rng.rand(0.6..1.4),
    n_steps_mul: rng.rand(0.5..1.0),
  }
end

# Every arp pattern was picked fresh per chord with no thread between phrases
# — a melody that never restates or develops an idea, cycles shapes.
# chord_motif_for already gives a stable, chord-symbol-consistent figure and
# :motif already exists as a pattern_mode; this deliberately reaches for
# it at phrase openings (not every chord — variation still matters) so a
# phrase can actually be recognized as "the same idea" when it returns.
def phrase_start_chord?(chord_i, cfg)
  chord_bars = cfg[:chord_bars]
  phrase_bars = cfg[:phrase_bars]
  return chord_i.zero? unless chord_bars && phrase_bars && chord_bars.positive?
  chords_per_phrase = (phrase_bars / chord_bars.to_f).round
  return chord_i.zero? if chords_per_phrase <= 0
  (chord_i % chords_per_phrase).zero?
end

def lead_pattern_mode(chord_i, cfg, rng)
  modes = %i[style motif retrograde sparse call stagger]
  return modes.sample(random: rng) unless motif_recall_enabled?
  return :motif if phrase_start_chord?(chord_i, cfg) && rng.rand < 0.7
  modes.sample(random: rng)
end

def arp_pattern_for_chord(chord, variation, tone_count, rng)
  return [] if tone_count.to_i <= 0 || chord.nil?

  case variation[:pattern_mode]
  when :motif
    chord_motif_for(chord).map { |d| d % tone_count }
  when :retrograde
    arp_degrees_for(variation[:style], tone_count, rng).reverse
  when :sparse
    arp_degrees_for(variation[:style], tone_count, rng).each_with_index.filter_map { |d, i| (i.even? || rng.rand < 0.42) ? d : nil }
  when :call
    chord_motif_for(chord).map { |d| d % tone_count } +
      arp_degrees_for(variation[:style], tone_count, rng).first(4)
  when :stagger
    base = arp_degrees_for(variation[:style], tone_count, rng)
    base.flat_map.with_index { |d, i| i.even? ? [d, d] : [d] }
  else
    arp_degrees_for(variation[:style], tone_count, rng)
  end
end

def arp_rest_step?(step, rest_prob, chord_i)
  return false if rest_prob < 0.02
  Random.new(chord_i * 97 + step * 13).rand < rest_prob
end

def arp_step_time(time, step, step_p, swing, jitter, variation)
  t = time + variation[:time_offset] + step * step_p
  t += (step.odd? ? swing * variation[:swing_mul] : 0.0)
  t += jitter * ((step % 3) - 1)
  t
end

# Pad chord entry + chop placement — not locked to bar%4 templates.
def dilla_chord_change_variation(chord_i, bar, section, feel, step_p, chord)
  cfg = dilla_resolve_config
  rng = chord_variation_rng(cfg, chord_i, chord, salt: 7711)
  base_pad_offset = DillaHarmony.pad_entry_late(cfg, feel, step_p)
  sustain_mul = DillaHarmony.pad_sustain_mul(cfg, section, rng)
  chop_density = DillaHarmony.chop_density(cfg, section)
  chop_templates = [
    [1, 5, 9, 13], [2, 6, 10, 14], [1, 9, 13], [3, 7, 11, 15],
    [0, 4, 8, 12], [1, 3, 7, 11], [2, 5, 9, 14], [4, 8, 12, 15],
    [1, 7, 13], [2, 8, 10, 14], [5, 9, 13], [0, 6, 10, 14], [3, 9, 15]
  ]
  chop_steps = chop_templates[(chord_i + bar) % chop_templates.length].dup
  chop_steps.delete_at(rng.rand(chop_steps.length)) if rng.rand < 0.38 && chop_steps.length > 2
  chop_steps << [0, 3, 6, 10, 14].sample(random: rng) if rng.rand < 0.28 && chop_density > 0.3
  if chop_density < 0.35
    keep = (chop_steps.length * chop_density * 2.5).ceil.clamp(1, chop_steps.length)
    chop_steps = chop_steps.sort_by { |s| rng.rand }.first(keep).sort
  end
  {
    pad_offset: base_pad_offset + rng.rand(-step_p * 0.4..step_p * 0.9),
    sustain_mul:,
    chop_steps: chop_steps.uniq.sort,
    chop_jitter: rng.rand(-0.028..0.028),
    pad_vel_mul: rng.rand(0.86..1.1),
    double_pad: rng.rand < 0.2 && section == :main,
    double_pad_delay: step_p * rng.rand(0.2..0.85),
    double_pad_vel: rng.rand(0.18..0.32),
  }
end

def dilla_anchor_chop_step(chop_step, drum_steps, rng)
  return chop_step if ENV.fetch("CHOP_ANCHOR_DRUMS", "1") == "0"
  anchors = Array(drum_steps).map(&:to_i).uniq
  return chop_step if anchors.empty?
  nearest = anchors.min_by { |s| (s - chop_step).abs }
  return chop_step unless nearest && (nearest - chop_step).abs <= 2

  # Dilla-style chops often feel performed with the kit: close to the transient,
  # but not machine-locked to it. Keep a small MPC-tick drift around the anchor.
  drift_ticks = ENV.fetch("CHOP_DRIFT_TICKS", "3").to_i.clamp(0, 8)
  drift = drift_ticks.positive? ? rng.rand(-drift_ticks..drift_ticks) / 24.0 : 0.0
  (nearest + drift).clamp(0.0, 15.75)
end

def lead_section_chance(section, progress)
  case section
  when :intro then 0.06
  when :breakdown then 0.12
  when :build then 0.48
  when :outro then 0.18
  else progress > 0.78 ? 0.42 : 0.26
  end
end
