# frozen_string_literal: true
#
# Writing standard MIDI files and their FX automation.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# --- FluidSynth pad rendering (real sampled electric-piano tone instead of ---
# --- the pure-additive-sine aevalsrc engine above) -------------------------

# GM program 4 = "Electric Piano 1" (Rhodes-style) — the classic Dilla/neo-soul
# keys tone. Overridable since a different soundfont's map may differ.
PAD_GM_PROGRAM = ENV.fetch("DILLA_PAD_PROGRAM", "4").to_i
# Electric-piano family (Dilla/neo-soul: Rhodes, Wurlitzer-adjacent DX EP)
# and warm-analog-pad family (Prophet/Moog-adjacent GM pad patches) — a
# different pair picked per render instead of the same two programs every
# time.
EP_GM_PROGRAMS = [4, 5, 0, 2, 1, 3].freeze # Rhodes, DX EP, acoustic, Electric Grand, Wurlitzer-adjacent
SMF_PPQN = 480
SMF_TICKS_PER_SECOND = SMF_PPQN * 2 # fixed internal reference tempo of 120 BPM

def pad_soundfont_path
  return ENV["DILLA_SOUNDFONT"] if ENV["DILLA_SOUNDFONT"] && File.exist?(ENV["DILLA_SOUNDFONT"])

  # GeneralUser GS (mrbumpy409/GeneralUser-GS on GitHub, free-for-any-use
  # license) — a real 261-preset GM bank, cached locally rather than
  # committed to the repo. Falls back to fluid-synth's small bundled test
  # font if it hasn't been fetched.
  cached = File.expand_path("~/.cache/dilla-soundfonts/GeneralUser-GS.sf2")
  return cached if File.exist?(cached)

  Dir.glob("/opt/homebrew/Cellar/fluid-synth/*/share/fluid-synth/sf2/*.sf2")
     .find { |f| f.match?(/VintageDreamsWaves-v2\.sf2\z/) }
end

def fluidsynth_pad_available?
  tool_available?("fluidsynth") && !pad_soundfont_path.nil?
end

def midi_vlq(number)
  bytes = [number & 0x7f]
  number >>= 7
  while number.positive?
    bytes.unshift((number & 0x7f) | 0x80)
    number >>= 7
  end
  bytes.pack("C*")
end

# A simpler lead: fewer things moving, and nothing moving the pitch.
#
# The lead carried nine simultaneous automation lanes — mod wheel, portamento
# time, pan, expression, resonance, a filter sweep, reverb and chorus sends, and
# an 8-cent pitch LFO — on top of a 0.92 gate, which is near-continuous legato.
# Everything slid into everything else.
#
# Two kinds of lane are dropped rather than reduced. `bend:` is a pitch LFO and
# CC5 is portamento time; both modulate frequency, so they are what makes a line
# read as gliding rather than as played notes. The rest survive at roughly half
# depth, which keeps the patch alive without the movement being the subject.
#
# LEAD_SIMPLE=0 restores the full automation and the original gates.
def lead_simple? = ENV.fetch("LEAD_SIMPLE", "1") != "0"

LEAD_SIMPLE_GATE_MAX = 0.6
LEAD_SIMPLE_DEPTH_SCALE = 0.5

def simplify_lead_midi_fx(specs)
  return specs unless lead_simple?

  Array(specs).reject { |s| s[:bend] || s[:cc] == 5 }.map do |s|
    s[:depth] ? s.merge(depth: (s[:depth] * LEAD_SIMPLE_DEPTH_SCALE).round) : s
  end
end

def midi_fx_specs_for_role(role, patch = nil)
  base = patch&.dig(:midi_fx)
  if role == :lead || role == :lead_arp
    # Rich stacks three more lanes on top; simple mode never wants it.
    rich = !lead_simple? && ENV.fetch("STREAM_LEAD_MIDI_RICH", "1") != "0"
    return simplify_lead_midi_fx(rich ? MIDI_FX_LEAD_RICH : MIDI_FX_LEAD) unless base && !base.empty?
    simplify_lead_midi_fx(rich ? (base + MIDI_FX_LEAD_RICH.last(3)) : base)
  elsif role == :scale_lead
    (base && !base.empty?) ? base : MIDI_FX_SCALE_LEAD
  else
    base || case role
            when :ep then MIDI_FX_PAD_EP
            when :warm, :texture then MIDI_FX_PAD_WARM
            end
  end
end

def midi_fx_automation(duration, specs, channel: 0)
  return [] unless duration && specs && !specs.empty?
  ticks_total = (duration * SMF_TICKS_PER_SECOND).round
  out = []
  specs.each do |spec|
    if spec[:bend]
      rate = spec.fetch(:rate_hz, 0.3)
      depth = spec.fetch(:depth_cents, 10)
      samples = (duration * 6).ceil.clamp(8, 48)
      samples.times do |i|
        tick = (i * ticks_total.to_f / samples).round
        t = i.to_f / samples
        cents = depth * Math.sin(2 * Math::PI * rate * duration * t)
        bend_val = (8192 + (cents / 100.0 * 4096)).round.clamp(0, 16_383)
        lsb = bend_val & 0x7f
        msb = (bend_val >> 7) & 0x7f
        out << [tick, [0xE0 | channel, lsb, msb]]
      end
      next
    end
    cc = spec[:cc]
    depth = spec.fetch(:depth, 40)
    base = spec.fetch(:base, 30)
    rate = spec.fetch(:rate_hz, 0.25)
    curve = spec.fetch(:curve, :sine)
    samples = (duration * 6).ceil.clamp(8, 48)
    samples.times do |i|
      tick = (i * ticks_total.to_f / samples).round
      t = i.to_f / [samples - 1, 1].max
      val = case curve
            when :sine then base + depth * Math.sin(2 * Math::PI * rate * duration * (i.to_f / samples))
            when :swell then base + depth * Math.sin(Math::PI * t * 0.85)
            when :slow_open then spec.fetch(:start, 60) + (spec.fetch(:end, 110) - spec.fetch(:start, 60)) * t
            else base
            end
      out << [tick, [0xB0 | channel, cc, val.round.clamp(0, 127)]]
    end
  end
  out.sort_by { |tick, _| tick }
end

# Writes SMF with note events plus MIDI CC / pitch-bend automation.
def write_smf(path, note_events, program: PAD_GM_PROGRAM, bank: 0, duration: nil, midi_fx: nil, channel: 0,
              lead_mode: false)
  timed = []
  note_events.each do |parts|
    time, velocity, chord, sustain = parts[0], parts[1], parts[2], parts[3]
    next unless chord && chord[:hz]&.any?
    chord[:hz].each do |hz|
      note = hz_to_midi(hz).round.clamp(0, 127)
      on_tick = (time * SMF_TICKS_PER_SECOND).round
      off_tick = (on_tick + (sustain * SMF_TICKS_PER_SECOND)).round
      vel_mul = lead_mode ? 100 : 108
      vel_min = lead_mode ? 36 : 48
      vel = (velocity.clamp(0.0, 1.0) * vel_mul).round.clamp(vel_min, 127)
      timed << [on_tick, :on, note, vel]
      timed << [off_tick, :off, note, 0]
    end
  end
  midi_fx_automation(duration, midi_fx, channel:).each do |tick, bytes|
    timed << [tick, :cc, bytes]
  end
  timed.sort_by! { |tick, kind, *| [tick, kind == :off ? 0 : 1, kind == :cc ? 1 : 2] }

  track_events = [[0, [0xB0 | channel, 0x00, bank & 0x7f].pack("C*")],
                  [0, [0xC0 | channel, nonflute_program(program)].pack("C*")]]
  last_tick = 0
  timed.each do |entry|
    tick = entry[0]
    kind = entry[1]
    delta = [tick - last_tick, 0].max
    bytes = if kind == :cc
              entry[2].pack("C*")
            else
              status = kind == :on ? (0x90 | channel) : (0x80 | channel)
              [status, entry[2], entry[3]].pack("C*")
            end
    track_events << [delta, bytes]
    last_tick = tick
  end
  track_events << [0, [0xFF, 0x2F, 0x00].pack("C*")]

  track_data = track_events.map { |delta, bytes| midi_vlq(delta) + bytes }.join
  track_chunk = "MTrk" + [track_data.bytesize].pack("N") + track_data
  header = "MThd" + [6].pack("N") + [0, 1, SMF_PPQN].pack("n3")
  File.binwrite(path, header + track_chunk)
  path
end

# Per-chord bank/program changes — morph Rhodes / Prophet / Moog presets across a progression.
def write_smf_morph(path, pad_events, duration:, role:, midi_fx: nil, channel: 0, lead_mode: false)
  timed = []
  first_patch = nil
  pad_events.each_with_index do |parts, i|
    patch = morph_patch_for_chord(i, role:)
    next unless patch
    first_patch ||= patch
    voice = patch_voice_for(patch)
    time, velocity, chord, sustain = parts[0], parts[1], parts[2], parts[3]
    next unless chord && chord[:hz]&.any?
    on_tick = (time * SMF_TICKS_PER_SECOND).round
    off_tick = (on_tick + (sustain * SMF_TICKS_PER_SECOND)).round
    timed << [on_tick, :bank, voice[:bank]]
    timed << [on_tick, :prog, voice[:program]]
    chord[:hz].each do |hz|
      note = hz_to_midi(hz).round.clamp(0, 127)
      vel_mul = lead_mode ? 100 : 108
      vel_min = lead_mode ? 36 : 48
      vel = (velocity.clamp(0.0, 1.0) * vel_mul).round.clamp(vel_min, 127)
      timed << [on_tick, :on, note, vel]
      timed << [off_tick, :off, note, 0]
    end
  end
  if la_beat_progression_enabled? && pad_events.length >= 2
    pad_events.each_with_index do |parts, i|
      on_tick = (parts[0] * SMF_TICKS_PER_SECOND).round
      seg_dur = [parts[3], 0.5].max
      fx = LA_BEAT_MIDI_FX_ROTATE[i % LA_BEAT_MIDI_FX_ROTATE.length]
      midi_fx_automation(seg_dur, [fx], channel:).each do |tick, bytes|
        timed << [on_tick + tick, :cc, bytes]
      end
    end
  end
  midi_fx_automation(duration, midi_fx, channel:).each do |tick, bytes|
    timed << [tick, :cc, bytes]
  end
  kind_prio = { bank: 0, prog: 1, on: 2, cc: 3, off: 4 }
  timed.sort_by! { |tick, kind, *| [tick, kind_prio.fetch(kind, 5)] }

  track_events = []
  last_tick = 0
  timed.each do |entry|
    tick = entry[0]
    kind = entry[1]
    delta = [tick - last_tick, 0].max
    bytes = case kind
            when :bank
              [0xB0 | channel, 0x00, entry[2] & 0x7f].pack("C*")
            when :prog
              [0xC0 | channel, nonflute_program(entry[2])].pack("C*")
            when :cc
              entry[2].pack("C*")
            else
              status = kind == :on ? (0x90 | channel) : (0x80 | channel)
              [status, entry[2], entry[3]].pack("C*")
            end
    track_events << [delta, bytes]
    last_tick = tick
  end
  track_events << [0, [0xFF, 0x2F, 0x00].pack("C*")]

  track_data = track_events.map { |delta, bytes| midi_vlq(delta) + bytes }.join
  track_chunk = "MTrk" + [track_data.bytesize].pack("N") + track_data
  header = "MThd" + [6].pack("N") + [0, 1, SMF_PPQN].pack("n3")
  File.binwrite(path, header + track_chunk)
  [path, first_patch]
end

def write_smf_timed(path, timed, duration:, midi_fx: nil, channel: 0, lead_mode: false)
  midi_fx_automation(duration, midi_fx, channel:).each do |tick, bytes|
    timed << [tick, :cc, bytes]
  end
  kind_prio = { bank: 0, prog: 1, on: 2, cc: 3, off: 4 }
  timed.sort_by! { |tick, kind, *| [tick, kind_prio.fetch(kind, 5)] }

  track_events = []
  last_tick = 0
  timed.each do |entry|
    tick = entry[0]
    kind = entry[1]
    delta = [tick - last_tick, 0].max
    bytes = case kind
            when :bank
              [0xB0 | channel, 0x00, entry[2] & 0x7f].pack("C*")
            when :prog
              [0xC0 | channel, nonflute_program(entry[2])].pack("C*")
            when :cc
              entry[2].pack("C*")
            else
              status = kind == :on ? (0x90 | channel) : (0x80 | channel)
              vel_mul = lead_mode ? 100 : 108
              vel_min = lead_mode ? 36 : 48
              vel = kind == :on ? entry[3] : 0
              vel = (vel.is_a?(Float) ? (vel.clamp(0.0, 1.0) * vel_mul).round.clamp(vel_min, 127) : vel)
              [status, entry[2], vel].pack("C*")
            end
    track_events << [delta, bytes]
    last_tick = tick
  end
  track_events << [0, [0xFF, 0x2F, 0x00].pack("C*")]

  track_data = track_events.map { |delta, bytes| midi_vlq(delta) + bytes }.join
  track_chunk = "MTrk" + [track_data.bytesize].pack("N") + track_data
  header = "MThd" + [6].pack("N") + [0, 1, SMF_PPQN].pack("n3")
  File.binwrite(path, header + track_chunk)
  path
end

def render_xlead_native_fm(path, pad_events, duration, cfg)
  return unless lead_morph_enabled? && fm_native_enabled?
  return if pad_events.empty?

  filters = []
  labels = []
  note_i = 0
  beat_p = 60.0 / cfg[:bpm]
  bar_p = beat_p * 4.0
  n_bars_est = ((pad_events.last[0] / bar_p).ceil + 1)
  pad_events.each_with_index do |(time, velocity, chord, sustain), i|
    patch = morph_lead_patch_for_chord(i)
    next unless chord && chord[:hz]&.any?
    arp_cfg = morph_lead_arp_cfg_for_chord(i, patch)
    chord_events = lead_arp_events_for_chord(time, velocity, chord, sustain, i, cfg, arp_cfg, patch,
                                             role: :xlead, n_bars_est:, skip_intro: false)
    next if chord_events.empty?
    ratio = fm_ratio_for_chord(i)
    mod_ratio_expr = fm_mod_ratio_expr(ratio[:m], ratio[:target_m], sustain, irrational: ratio[:irrational])
    chord_events.each do |(t, vel, ch, dur)|
      hz = ch[:hz].first
      next unless hz&.positive?
      base_idx = fm_index_from_velocity(vel, base_index: FM_INDEX_BASE_XLEAD, role: :xlead)
      mod_env = fm_mod_envelope(role: :xlead)
      index_expr = "(#{base_idx})*#{mod_env}"
      drift = "1"
      body = native_fm_waveform_body(hz, index_expr:, bloom: 0.22, drift:,
                                     feedback: FM_FEEDBACK_DEFAULT, phase_seed: note_i * 0.71,
                                     mod_ratio_expr:)
      amp = (vel * 0.12).round(5)
      atk = 0.003
      rel = (1.0 / [dur, 0.02].max).round(3)
      env = "min(1,pow(t/#{atk},0.9))*exp(-t*#{rel})"
      expr = "#{amp}*#{env}*#{body}"
      delay = [(t * 1000.0).round, 0].max
      label = "xl#{note_i}"
      filters << "aevalsrc=exprs='#{expr}|#{expr}':d=#{dur.round(4)}:s=#{PAD_RENDER_SAMPLE_RATE}," \
                 "adelay=#{delay}|#{delay}[#{label}]"
      labels << "[#{label}]"
      note_i += 1
    end
  end
  return if labels.empty?

  filters << "#{labels.join}amix=inputs=#{labels.length}:duration=longest:normalize=0," \
             "atrim=0:#{duration},highpass=f=180,lowpass=f=8200,alimiter=limit=0.94:level_out=0.92[xlead]"
  sh_filter_complex!(filters.join(";"), "-map", "[xlead]", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", path)
  path
end

def blend_xlead_stems(destination, fs_path, native_path, duration)
  return fs_path if native_path.nil? || !File.exist?(native_path)
  return native_path if fs_path.nil? || !File.exist?(fs_path)
  tmp = "#{destination}.blend.wav"
  sh! "ffmpeg", "-y", "-i", fs_path, "-i", native_path,
      "-filter_complex",
      "[0:a][1:a]amix=inputs=2:weights=1.0 #{FM_XLEAD_NATIVE_MIX}:duration=longest:normalize=0," \
      "alimiter=limit=0.96:level_out=0.96[out]",
      "-map", "[out]", "-t", duration.to_s, "-c:a", "pcm_s16le", tmp
  FileUtils.mv(tmp, destination)
  destination
end

def render_xlead_morph_fluidsynth(path, pad_events, duration, cfg)
  return unless lead_morph_enabled? && fluidsynth_pad_available?
  return if pad_events.empty?

  timed = []
  first_patch = nil
  beat_p = 60.0 / cfg[:bpm]
  bar_p = beat_p * 4.0
  n_bars_est = ((pad_events.last[0] / bar_p).ceil + 1)
  pad_events.each_with_index do |(time, velocity, chord, sustain), i|
    patch = morph_lead_patch_for_chord(i)
    next unless patch && chord && chord[:hz]&.any?
    first_patch ||= patch
    voice = patch_voice_for(patch)
    arp_cfg = morph_lead_arp_cfg_for_chord(i, patch)
    chord_events = lead_arp_events_for_chord(time, velocity, chord, sustain, i, cfg, arp_cfg, patch,
                                             role: :xlead, n_bars_est:, skip_intro: false)
    next if chord_events.empty?
    on_tick = (time * SMF_TICKS_PER_SECOND).round
    timed << [on_tick, :bank, voice[:bank]]
    timed << [on_tick, :prog, voice[:program]]
    chord_events.each do |(t, vel, ch, dur)|
      note = hz_to_midi(ch[:hz].first).round.clamp(0, 127)
      note_on = (t * SMF_TICKS_PER_SECOND).round
      note_off = (note_on + (dur * SMF_TICKS_PER_SECOND)).round
      v = (vel.clamp(0.0, 1.0) * 100).round.clamp(40, 127)
      timed << [note_on, :on, note, v]
      timed << [note_off, :off, note, 0]
    end
  end
  return if timed.empty?

  midi_path = "#{path}.smf.mid"
  write_smf_timed(midi_path, timed, duration:, midi_fx: MIDI_FX_LEAD, lead_mode: true)
  fs_gain = first_patch&.fetch(:fs_gain, 1.38) || 1.38
  fluidsynth_render!(path, pad_soundfont_path, midi_path, gain: fs_gain)
  FileUtils.rm_f(midi_path)
  sh! "ffmpeg", "-y", "-i", path, "-af", lead_post_fx_chain(first_patch, duration, 0.0),
      "-c:a", "pcm_s16le", "#{path}.xlead.wav"
  FileUtils.mv("#{path}.xlead.wav", path)
  normalize_wav_to_rms!(path, LEAD_TARGET_RMS_DB)
  path
end

def write_pad_smf(path, pad_events, program: PAD_GM_PROGRAM, bank: 0, duration: nil, midi_fx: nil, patch: nil,
                    role: :ep)
  cfg = dilla_resolve_config
  events = pad_midi_events_for_layer(pad_events, cfg, patch, role:, duration: duration || 0)
  fx = midi_fx || resolve_midi_fx_for(patch, role:)
  write_smf(path, events, program:, bank:, duration:, midi_fx: fx)
end
