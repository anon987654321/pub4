# frozen_string_literal: true
#
# Rendering leads and counter-leads, and mixing the harmonic stems.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# 81 Sawtooth (original), 87 Lead 8 "bass+lead" (GM's own name traces to the
# classic Prophet-5 "BigLead" patch — literally the historical big-lead
# archetype), 84 Lead 5 Charang (aggressive/bright, cuts through), 86 Lead 7
# Fifths (built-in parallel fifths give arps instant harmonic width free).
LEAD_GM_PROGRAMS = [81, 87, 84, 86].freeze
# Hotter lead target so arps cut over multi-layer pads.
LEAD_TARGET_RMS_DB = -14.5

# Voices for the counter-line: strings and choirs, not synth leads.
#
# The four programs above are all bright synth leads, chosen to cut through. A
# second voice that has to cut through is a second voice competing, which is the
# problem this layer exists to solve. Strings and voices do the opposite -- they
# hold a note and sit behind, so the line is heard as an answer rather than as
# something shouting over the top.
#
# They also suit what the line actually plays. It holds each note for about two
# beats, and a held note is what strings and choirs are for; a square-wave lead
# holding for two beats just sounds stuck.
#
# These voices are already in the patch table (choir_aahs, voice_oohs,
# juno_strings, string_orchestra) but only as pads -- every one is registered
# role: :warm, so nothing could reach them for a melody until now.
COUNTER_LEAD_PROGRAMS = {
  choir: 52,          # choir aahs -- the "aah" bed
  voices: 53,         # voice oohs -- softer, rounder, further back
  strings: 48,        # string ensemble
  warm_strings: 49,   # slower attack, arrives under the beat
  synth_strings: 50,  # solina-ish, the most obviously synthetic of the five
  synth: 81,          # the old bright lead, if it is ever wanted back,
}.freeze

def counter_lead_program
  COUNTER_LEAD_PROGRAMS.fetch(ENV.fetch("LEAD_TIMBRE", "choir").downcase.to_sym) do
    COUNTER_LEAD_PROGRAMS[:choir]
  end
end

# Softer than a lead and darker than a pad.
#
# Leads here target -14.5 dBFS so an arp can cut over the stack. This one is not
# trying to cut over anything, so it sits about 6 dB under that, and a lowpass
# takes the top off. Standard advice for putting a part behind another is to
# lower it AND roll off its highs -- level alone leaves a small bright thing in
# front rather than a soft thing behind.
COUNTER_LEAD_TARGET_RMS_DB = -20.5
COUNTER_LEAD_LOWPASS_HZ = 5200

# Never quite in tune, and never quite dry.
#
# A sampled record is a few cents off because the tape it came from was, and
# nothing in this idiom is at concert pitch by accident. A perfectly tuned
# choir sitting on top of samples that are not is the one voice that sounds
# synthetic. asetrate does it the way a varispeed does -- pitch and duration
# move together -- rather than pretending the two are separable.
#
# The reverb is a send, filtered the way a send should be: high-passed so the
# tail does not muddy the low mid, low-passed so it sits behind the dry signal
# rather than adding brightness of its own. Standard practice on a return, and
# the reason the counter-line reads as "in the room" instead of "on top".
COUNTER_LEAD_DETUNE_CENTS = -7.0
COUNTER_LEAD_VERB_HP_HZ = 300
COUNTER_LEAD_VERB_LP_HZ = 9000

# Drenched, not damp.
#
# A lead can be a problem in two ways: it can play the wrong notes, or it can be
# too present. This one had been rewritten three times for the notes and still
# sat too far forward, so it comes back pushed into the room instead of onto the
# front of the mix. At this depth the line reads as atmosphere with a melody
# inside it rather than as a part demanding attention -- which is what a
# sixty-percent wet return does, and what a thirty-four-percent one does not.
#
# Eight taps out to 1.6 seconds rather than three out to 180 ms. The long ones
# are what makes it a space; the short ones alone are a slapback.
COUNTER_LEAD_VERB_MIX = (ENV["LEAD_VERB_MIX"] || 0.62).to_f
COUNTER_LEAD_VERB_TAPS = "aecho=0.9:0.88:60|110|180|320|520|780|1120|1600:" \
                         "0.5|0.44|0.38|0.32|0.26|0.2|0.15|0.1"

# No varispeed here. The detune happens at synthesis; see counter_lead_detune.
#
# This chain used to start with asetrate + aresample to pull the voice 7 cents
# flat. asetrate is a VARISPEED -- it moves pitch and duration together, the way
# a tape machine does -- and applied to a whole rendered layer rather than to a
# one-shot sample it stretches the entire performance. At -7 cents the layer
# plays 0.405% slow, so every note after the first arrives progressively later
# than the drums it was written against:
#
#   over 46s   0.188s late by the end = 1.10 sixteenth notes at 88 BPM
#   over 60s   0.243s late by the end = 1.43 sixteenths
#
# It is never in the same relationship to the beat twice, and it gets worse as
# the track runs. The operator heard it as "the leads sound off", which is
# exactly what it was: off the beat, by more than a sixteenth, increasingly.
#
# Detuning the NOTES instead gets the same out-of-tune-tape colour with the
# timing untouched, because a frequency written 7 cents flat is 7 cents flat and
# nothing else moves.
def counter_lead_space_chain
  # Two echoes in series, not one: the second smears the first's taps into each
  # other, which is how a cheap reverb is built and why it stops sounding like
  # discrete repeats. Modulated slightly so the tail moves instead of ringing on
  # one pitch.
  wet = "highpass=f=#{COUNTER_LEAD_VERB_HP_HZ},lowpass=f=#{COUNTER_LEAD_VERB_LP_HZ}," \
        "#{COUNTER_LEAD_VERB_TAPS},aecho=0.85:0.8:37|53:0.4|0.32," \
        "vibrato=f=0.6:d=0.06,volume=#{COUNTER_LEAD_VERB_MIX}"
  "lowpass=f=#{COUNTER_LEAD_LOWPASS_HZ}," \
    "asplit=2[cldry][clwet];[clwet]#{wet}[clverb];[cldry][clverb]amix=inputs=2:normalize=0"
end

# The ratio to write into a note's frequency, applied where the note is chosen.
def counter_lead_detune = 2.0**(COUNTER_LEAD_DETUNE_CENTS / 1200.0)

def invert_motif(motif)
  top = motif.max
  motif.map { |d| top - d }
end

# Leitmotif seeded from the progression's own opening chord — stable for
# a given piece, so the lead states one real idea and develops it
# (inversion/retrograde/augmentation) instead of generating a fresh,
# unrelated arp pattern at every chord change.
def leitmotif_for(pad_events)
  if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
    hook = @composition_session.motifs.find { |m| m.id == "hook" }
    return hook.degrees_for_playback if hook
  end
  seed_source = pad_events.first&.dig(2, :name).to_s
  rng = Random.new(stable_hash(seed_source) % 100_000)
  length = [3, 4].sample(random: rng)
  Array.new(length) { rng.rand(4) }
end

def resolve_scale_lead_voice
  if ENV["DILLA_SCALE_LEAD_PROGRAM"]
    return { sf2: pad_soundfont_path, bank: 0, program: ENV["DILLA_SCALE_LEAD_PROGRAM"].to_i,
             patch: @render_scale_lead_patch }
  end
  patch_voice_for(@render_scale_lead_patch) ||
    patch_voice_for(@render_lead_patch) ||
    { sf2: pad_soundfont_path, bank: 0, program: render_pick(LEAD_GM_PROGRAMS, "lead_program"), patch: nil }
end

# Interesting default lead FX — delay, chorus, subtle phaser, air shelf, soft drive.
LEAD_FX_RICH_DEFAULT = [
  "highpass=f=180",
  "equalizer=f=2800:t=o:w=1.4:g=2.8",
  "equalizer=f=5200:t=h:w=1.2:g=1.6",
  "chorus=0.48:0.68:36|48:0.22|0.18:0.26|0.22:1.1|1.35",
  "aecho=0.48:0.42:140|280:0.28|0.14",
  "aphaser=speed=0.14:decay=0.45",
  "vibrato=f=0.32:d=0.011",
  "lowpass=f=6200:width_type=q:width=0.85",
].join(",").freeze

LEAD_FX_VARIANTS = [
  LEAD_FX_RICH_DEFAULT,
  "highpass=f=200,tremolo=f=4.2:d=0.08,chorus=0.4:0.6:30|40:0.18|0.14:0.22|0.18:1.0|1.25,aecho=0.42:0.36:100|190:0.24|0.12,lowpass=f=5400",
  "highpass=f=160,aecho=0.55:0.5:180|320:0.32|0.16,aphaser=speed=0.2:decay=0.5,equalizer=f=3200:t=o:w=1.3:g=3.2,lowpass=f=7000",
  "highpass=f=220,acrusher=bits=12:samples=1.5:mix=0.06,chorus=0.52:0.72:40|52:0.24|0.2:0.28|0.24:1.15|1.4,aecho=0.4:0.35:90|160:0.2|0.1,lowpass=f=5000",
  "highpass=f=190,vibrato=f=0.55:d=0.016,tremolo=f=0.35:d=0.06,aecho=0.5:0.44:150|260:0.26|0.14,lowpass=f=5800",
].freeze

# Trim a rendered stem to a target RMS. Exists because the lead path used to
# measure the raw fluidsynth output, apply the make-up gain, and only THEN run
# the patch's fx chain -- and 95 of the catalog's aecho/chorus entries carry
# attenuating in_gain:out_gain pairs worth -12..-20 dB (the same argument-order
# mistake fixed on the harmonic bus in f733aa3ee). The fx knocked the lead back
# down after the gain had already been committed, so LEAD_TARGET_RMS_DB was
# never actually reached and leads sat far under the kit. Normalising on the way
# out measures what the listener actually gets.
def normalize_wav_to_rms!(path, target_db, floor: -24.0, ceil: 26.0)
  return path unless File.file?(path) && tool_available?("ffmpeg")
  measured = band_rms(path, highpass: 20, lowpass: 20_000)
  return path unless measured.finite?
  gain = (target_db - measured).clamp(floor, ceil)
  return path if gain.abs < 0.2
  tmp = "#{path}.norm.wav"
  sh! "ffmpeg", "-y", "-i", path, "-af",
      "volume=#{gain.round(2)}dB,alimiter=limit=0.96:level_out=0.97",
      "-c:a", "pcm_s16le", tmp
  FileUtils.mv(tmp, path) if File.file?(tmp)
  path
end

def lead_post_fx_chain(patch, duration, boost_db)
  base = "volume=#{boost_db.round(2)}dB"
  patch_fx = patch&.dig(:fx)
  # Blend patch identity FX with a rotating rich chain so every take has motion.
  # Process.pid used to be in here, so the lead came out with a different effect
  # chain on every single run -- the take you liked could not be got back, and
  # two renders of one track were never comparable. The render seed alone is
  # what it was always meant to be keyed on.
  variant = LEAD_FX_VARIANTS[(@render_seed || 0) % LEAD_FX_VARIANTS.length]
  rich = ENV.fetch("LEAD_FX_RICH", "1") != "0"
  body = if patch_fx && !patch_fx.empty?
           rich ? "#{patch_fx},#{variant}" : patch_fx
         else
           rich ? variant : LEAD_FX_RICH_DEFAULT
         end
  [base, body, "apad=whole_dur=#{duration}", "alimiter=limit=0.94:level_out=0.97"].join(",")
end

HARMONIC_STEM_MIX = {
  pads:          { volume: 1.35, weight: 1.7 },
  tones:         { volume: 0.72, weight: 0.55 },
  # The melodic voice when SU_MELODY is on, which is also when every lead lane
  # below is empty by construction — so this carries the top line alone.
  su_melody:     { volume: 1.4, weight: 1.15 },
  harmony_lead:  { volume: 1.15, weight: 0.72 },
  scale_lead:    { volume: 1.2, weight: 0.78 },
  lead_arp:      { volume: 1.45, weight: 1.05 },
  lead:          { volume: 1.1, weight: 0.55 },
  xlead:         { volume: 0.74, weight: 0.36 },
}.freeze

def harmonic_stem_mix_value(key, field)
  env_key = "HARMONIC_#{key.to_s.upcase}_#{field.to_s.upcase}"
  raw = ENV[env_key]
  return raw.to_f if raw && !raw.empty?
  HARMONIC_STEM_MIX.dig(key, field) || 1.0
end

def mix_harmonic_wav_stems(destination, duration, **stem_paths)
  lanes = HARMONIC_STEM_MIX.filter_map do |key, _mix|
    path = stem_paths[key]
    next unless path && File.exist?(path)
    [key, path, harmonic_stem_mix_value(key, :volume), harmonic_stem_mix_value(key, :weight)]
  end
  return false if lanes.length < 2

  filter_labels = []
  mix_in = []
  lanes.each_with_index do |(_key, _path, volume, _weight), idx|
    label = "h#{idx}"
    filter_labels << "[#{idx}:a]volume=#{volume}[#{label}]"
    mix_in << "[#{label}]"
  end
  weights = lanes.map { |l| l[3] }.join(" ")
  filter = "#{filter_labels.join(';')};" \
             "#{mix_in.join}amix=inputs=#{lanes.length}:weights=#{weights}:duration=longest:normalize=0," \
             "aresample=#{SAMPLE_RATE},alimiter=limit=0.96:level_out=0.98[harmonic]"
  args = ["ffmpeg", "-y"]
  lanes.each { |(_, path)| args << "-i" << path }
  sh!(*args, "-filter_complex", filter, "-map", "[harmonic]",
      "-t", duration.to_s, "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", destination)
  lanes.drop(2).each { |(_, path)| FileUtils.rm_f(path) }
  true
end

def render_lead_via_fluidsynth(path, lead_events, duration, scale_arp: false, counter: false, program_override: nil)
  return if lead_events.empty? || !fluidsynth_pad_available?
  midi_path = "#{path}.smf.mid"
  lead_voice = scale_arp ? resolve_scale_lead_voice : resolve_lead_voice
  patch = lead_voice[:patch] || (scale_arp ? @render_scale_lead_patch : @render_lead_patch)
  role = scale_arp ? :scale_lead : :lead
  # The counter-line borrows the lead's soundfont and takes a strings or choir
  # program out of it, rather than the bright synth the rotation would pick.
  program = program_override || (counter ? counter_lead_program : lead_voice[:program])
  write_smf(midi_path, lead_events, program:, bank: (counter ? 0 : lead_voice[:bank]),
            duration:, midi_fx: resolve_midi_fx_for(patch, role:), lead_mode: true)
  fs_gain = lead_voice[:patch]&.fetch(:fs_gain, 1.3) || 1.3
  fluidsynth_render!(path, lead_voice[:sf2], midi_path, gain: fs_gain)
  FileUtils.rm_f(midi_path)
  target_db = if counter then COUNTER_LEAD_TARGET_RMS_DB
              elsif scale_arp then LEAD_TARGET_RMS_DB + 1.5
              else LEAD_TARGET_RMS_DB
              end
  patch = lead_voice[:patch] || (scale_arp ? @render_scale_lead_patch : @render_lead_patch)
  chain = lead_post_fx_chain(patch, duration, 0.0)
  if counter
    # Detune, roll the top off, and send to a filtered reverb -- all BEFORE the
    # patch chain, so what follows is working on an already-soft, already-placed
    # signal rather than brightening it back up.
    sh! "ffmpeg", "-y", "-i", path, "-filter_complex",
        "[0:a]#{counter_lead_space_chain},#{chain}[out]", "-map", "[out]",
        "-c:a", "pcm_s16le", "#{path}.lead.wav"
  else
    sh! "ffmpeg", "-y", "-i", path, "-af", chain, "-c:a", "pcm_s16le", "#{path}.lead.wav"
  end
  FileUtils.mv("#{path}.lead.wav", path)
  normalize_wav_to_rms!(path, target_db)
  path
end

def render_harmonic_wav(path, pad_events, chop_events, bass_events, duration, melody_events: [], cfg: nil, dfam_events: nil,
                        pad_post: true)
  cfg ||= dilla_resolve_config
  pick_synth_patches!(cfg) unless @render_ep_patch
  @render_used_fluidsynth_pad = false
  tones_path = "#{path}.tones.wav"
  pads_path = "#{path}.pads.wav"
  lead_path = "#{path}.lead.wav"
  lead_arp_path = "#{path}.lead_arp.wav"
  xlead_path = "#{path}.xlead.wav"
  harmony_lead_path = "#{path}.harmony_lead.wav"
  scale_lead_path = "#{path}.scale_lead.wav"
  used_singers_chops = false
  if singers_chop_pads_enabled?
    begin
      used_singers_chops = !!render_singers_chop_pads(pads_path, pad_events, duration)
    rescue StandardError => e
      warn "singers chop pads skipped: #{e.message}"
    end
  end
  # Octave doubling applies to the pad render only. pad_events is also what the
  # bass, the chop grid and the melody read their chords from, and adding voices
  # to the shared list would have the bass playing the doubling too.
  pad_render_events = grand_pads? ? grandeur_pad_events(pad_events) : pad_events
  if grand_pads?
    dmesg("grand pads: #{pad_events.length} chords -> #{pad_render_events.length} voicings (8vb root+5th, 8va upper)",
          unit: "harm0", parent: "dilla0")
  end
  if used_singers_chops
    # Real chopped vocal bed replaces the synth pad stack entirely.
  elsif fluidsynth_pad_available?
    render_pad_via_fluidsynth(pads_path, pad_render_events, duration)
  else
    render_native_pad_wav(pads_path, pad_render_events, duration)
  end
  # Soft Singers Unlimited–like ooh/aah on chord tones under the pad bed —
  # redundant (and muddy) when the bed already IS chopped real vocals.
  if choir_vox_enabled? && !used_singers_chops
    choir_path = "#{path}.choir_vox.wav"
    begin
      if render_choir_vox_layer(choir_path, pad_events, duration)
        mix_choir_into_pads!(pads_path, choir_path, duration)
      else
        FileUtils.rm_f(choir_path)
      end
    rescue StandardError => e
      warn "choir_vox skipped: #{e.message}"
      FileUtils.rm_f(choir_path)
    end
  end
  # Granular cloud resynthesized from the finished pad+choir bed itself
  # (see render_pad_granular_layer) and floated back under it.
  if pad_granular_enabled?
    grain_path = "#{path}.grains.wav"
    begin
      if render_pad_granular_layer(grain_path, pads_path, duration, pad_events)
        mix_granular_into_pads!(pads_path, grain_path, duration)
      else
        FileUtils.rm_f(grain_path)
      end
    rescue StandardError => e
      warn "pad granular skipped: #{e.message}"
      FileUtils.rm_f(grain_path)
    end
  end
  # The resynthesized choir IS the top line, so every synth lead lane below is
  # skipped rather than mixed quiet. Two top lines at once is the soup the
  # comment further down is about, and a vocal one loses that fight by being
  # the more interesting signal — mixing them just muddies both.
  su_melody_path = "#{path}.su_melody.wav"
  su_melody_rendered = nil
  if su_melody_enabled? && !no_lead?
    begin
      su_melody_rendered = render_su_tunnel_melody(
        su_melody_path, pad_events, duration,
        cfg: cfg, n_bars: (duration / ((60.0 / cfg[:bpm]) * 4.0)).ceil
      )
    rescue StandardError => e
      warn "su tunnel melody skipped: #{e.message}"
    end
  end
  # NO_LEAD=1 silences every top line there is: the four synth lanes and the
  # choir together. Asked for twice -- the first time it was read as "change it",
  # which was the other half of the same sentence and the wrong half. With no
  # lead the rapper is the top line, which is what a Dilla beat is anyway.
  leads_muted = !!su_melody_rendered || no_lead?

  n_bars_est = (duration / ((60.0 / cfg[:bpm]) * 4.0)).ceil
  # One clean melodic lead by default — scale/creative layers turned the top line into soup.
  scale_on = !leads_muted && lead_arp_enabled? && ENV.fetch("SCALE_LEAD", "0") != "0"
  creative_on = !leads_muted && lead_arp_enabled? && ENV.fetch("CREATIVE_LEAD", "0") != "0"
  scale_events = scale_on ? lead_events_scale_arp(pad_events, cfg, duration:, n_bars: n_bars_est) : []
  lead_arp_cfg = lead_arp_cfg_for(@render_lead_patch)
  # The counter-line replaces the arp rather than joining it. Two top lines at
  # once is the soup the comment above is about, and this one is written to
  # answer the chords, which only works if nothing else is talking over them.
  counter_events = leads_muted ? [] : lead_events_melodic(pad_events, cfg, duration:, n_bars: n_bars_est)
  lead_arp_ev = !leads_muted && lead_arp_enabled? && counter_events.empty? ?
                lead_arp_events(pad_events, cfg, lead_arp_cfg) : []
  harmony_lead_cfg = harmony_lead_cfg_for(@render_scale_lead_patch)
  insight = instance_variable_defined?(:@progression_insight) ? @progression_insight : nil
  harmony_lead_ev = !leads_muted && harmony_lead_enabled? && ENV.fetch("HARMONY_LEAD", "0") != "0" ?
                    harmony_lead_events(pad_events, cfg, harmony_lead_cfg, progression_insight: insight) : []
  creative_events = creative_on ? lead_events_creative(pad_events, cfg, duration:, n_bars: n_bars_est) : []

  # MIDI_BAG=1 — the lead's pitches, on the kit's rhythm.
  #
  # ringtone.tools' MIDI Bag, at the one place in this engine where both halves
  # already exist as note events: the arp has pitches with a contour, and the
  # drum grid has onsets with accents. Normally a note is an indivisible pair of
  # the two. This refuses that pairing and takes each half from a different part.
  #
  # sample_flip does the same separation for AUDIO slices and constrains them to
  # the chord underneath. Nothing did it for note events, so a melody the engine
  # generated could not be re-rhythmed by a pattern the engine also generated.
  #
  # Applied before the section envelope below, so a bagged lead still obeys the
  # arrangement -- the envelope drops notes outside their sections, and it has to
  # act on the notes that will actually sound.
  harmony_lead_ev = midi_bag_lead_events(harmony_lead_ev, cfg, n_bars_est)
  lead_arp_ev = midi_bag_lead_events(lead_arp_ev, cfg, n_bars_est)

  # The lead's section envelope, applied to its notes because it has no bus.
  #
  # All four lead paths, for the reason the comment below gives about the log
  # line that reported on two of them: a feature wired into half the paths it
  # applies to is the harder bug to see, because it works.
  if section_layers_full? && (lead_bar_p = (60.0 / cfg[:bpm].to_f) * 4.0).positive?
    scale_events = apply_section_envelope_to_events(scale_events, :lead, n_bars_est, lead_bar_p)
    counter_events = apply_section_envelope_to_events(counter_events, :lead, n_bars_est, lead_bar_p)
    lead_arp_ev = apply_section_envelope_to_events(lead_arp_ev, :lead, n_bars_est, lead_bar_p)
    harmony_lead_ev = apply_section_envelope_to_events(harmony_lead_ev, :lead, n_bars_est, lead_bar_p)
    creative_events = apply_section_envelope_to_events(creative_events, :lead, n_bars_est, lead_bar_p)
  end

  scale_lead_rendered = scale_events.any? ? render_lead_via_fluidsynth(scale_lead_path, scale_events, duration, scale_arp: true) : nil
  harmony_lead_rendered = harmony_lead_ev.any? ? render_hocket_lead!(harmony_lead_path, harmony_lead_ev, duration) : nil
  # Say which lead actually played, and how many notes it played.
  #
  # The counter-line silently returned nothing for a whole render batch because
  # apply_best_defaults! set MELODIC_LEAD=0 after demo_all had cleared it. The
  # banner still announced steady mode, every take came out with the old arps,
  # and nothing in the log disagreed. One line here would have caught it in the
  # first render instead of the eighth.
  #
  # All four lead paths, not two. This message was written to answer "which lead
  # actually played" and then reported on counter_events and lead_arp_ev only,
  # while scale_events and harmony_lead_ev were computed twenty lines above and
  # rendered to fluidsynth on the two lines above this one. So a take with a
  # harmony lead on it logged "lead: none", which is the same silence the comment
  # above is about — one layer over.
  #
  # It cost a render to find. A Vaular take was re-rendered specifically to add a
  # lead, on the strength of this line saying there was none.
  #
  # leads_muted is named separately rather than left to fall through to "none".
  # Under SU_MELODY every one of the four lanes is empty by construction, so the
  # honest four-path report and a silent-by-mistake render print the same word.
  # That is the exact confusion both comments above are about, so the one case
  # where the silence is deliberate says so.
  if leads_muted
    # Two different silences, and the message used to claim the choir either
    # way. Under NO_LEAD nothing is playing a top line at all, and saying "su
    # tunnel choir" there reports a voice that is not in the render -- the exact
    # thing the four-lane comment below was written to stop.
    dmesg(su_melody_rendered ? "lead: su tunnel choir (four synth lanes muted)"
                             : "lead: none (NO_LEAD -- four synth lanes, choir and pluck all off)",
          unit: "harm0", parent: "dilla0")
  else
    played = []
    played << "counter-line #{counter_events.length}n/#{ENV.fetch('LEAD_TIMBRE', 'choir')}" if counter_events.any?
    played << "arp #{lead_arp_ev.length}n" if lead_arp_ev.any?
    played << "scale #{scale_events.length}n" if scale_events.any?
    played << "harmony #{harmony_lead_ev.length}n" if harmony_lead_ev.any?
    dmesg("lead: #{played.empty? ? 'none' : played.join(' + ')}", unit: "harm0", parent: "dilla0")
  end

  lead_arp_rendered = if counter_events.any?
                        render_lead_via_fluidsynth(lead_arp_path, counter_events, duration, counter: true)
                      elsif lead_arp_ev.any?
                        render_lead_via_fluidsynth(lead_arp_path, lead_arp_ev, duration)
                      end
  xlead_rendered = nil
  if lead_morph_enabled? && !leads_muted
    xlead_fs = render_xlead_morph_fluidsynth(xlead_path, pad_events, duration, cfg)
    xlead_native = render_xlead_native_fm("#{xlead_path}.native.wav", pad_events, duration, cfg)
    xlead_rendered = blend_xlead_stems(xlead_path, xlead_fs, xlead_native, duration)
    FileUtils.rm_f("#{xlead_path}.native.wav")
  end
  lead_rendered = creative_events.any? ? render_lead_via_fluidsynth(lead_path, creative_events, duration) : nil
  # Karplus-Strong plucked-string accent on each chord's root — a genuinely
  # new instrument timbre (real physical-modeling algorithm, not another
  # oscillator/soundfont voice), pre-rendered per chord since the algorithm
  # itself needs a contiguous buffer, then windowed into the tones stream
  # the same way chop/melody events already are.
  # The pluck plays the root of every chord, for 1.1s, on every take, and it was
  # the only melodic voice in the engine with no switch at all. With the four
  # synth lanes and the choir silenced it was what remained playing a line --
  # which is why "not that lead" came after a lead had already been removed.
  # PLUCK=0 turns it off; NO_LEAD takes it with everything else.
  pluck_on = ENV.fetch("PLUCK", "1") != "0" && !no_lead?
  pluck_buffers = (pluck_on ? pad_events : []).filter_map do |(t, v, chord, _sustain)|
    next unless chord && chord[:hz]&.any?
    [t, v, karplus_strong_pluck(chord[:hz].min, 1.1, seed: stable_hash(chord[:name].to_s) % 100_000)]
  end
  write_stereo_chunks(tones_path, duration) do |chunk_start, chunk_frames, left, right|
    pluck_buffers.each do |(t, v, buf)|
      event_frame = (t * SAMPLE_RATE).round
      window = overlap_window(event_frame, buf.length, chunk_start, chunk_frames)
      next unless window
      local_start, source_offset, count = window
      count.times do |i|
        sample = buf[source_offset + i] * v * 0.16
        left[local_start + i] += sample
        right[local_start + i] += sample
      end
    end
    chop_events.each do |(t, v, chord)|
      hz_list = chop_hz(chord)
      next if hz_list.empty?
      event_frame = (t * SAMPLE_RATE).round
      total = (0.28 * SAMPLE_RATE).round
      window = overlap_window(event_frame, total, chunk_start, chunk_frames)
      next unless window
      local_start, source_offset, count = window
      frequency = hz_list[((t * 10).to_i) % hz_list.length]
      mix_sine!(left, right, local_start, count, frequency, v * 0.13,
                decay: 2.0, mod_hz: 0.45, source_offset:)
    end

    melody_events.each do |(t, v, hz)|
      event_frame = (t * SAMPLE_RATE).round
      total = (0.18 * SAMPLE_RATE).round
      window = overlap_window(event_frame, total, chunk_start, chunk_frames)
      next unless window
      local_start, source_offset, count = window
      frequency = hz.is_a?(Numeric) ? hz : MELODY_CHOP_HZ.first
      count.times do |i|
        tt = (source_offset + i).to_f / SAMPLE_RATE
        sample = v * 0.11 * Math.exp(-tt * 8.5) * Math.sin(2 * Math::PI * frequency * tt)
        left[local_start + i] += sample * 0.55
        right[local_start + i] += sample * 0.45
      end
    end

    bass_events.each do |hit|
      t, v = hit[0], hit[1]
      root = hit[2].is_a?(Numeric) ? hit[2] : 43.65
      slide_from = hit[4].is_a?(Numeric) ? hit[4] : nil
      total = [((hit[3] || BASS_SUSTAIN_SEC) * SAMPLE_RATE).round, 1].max
      event_frame = (t * SAMPLE_RATE).round
      window = overlap_window(event_frame, total, chunk_start, chunk_frames)
      next unless window
      local_start, source_offset, count = window
      slide_portion = bass_slide_enabled? && slide_from ? 0.38 : 0.0
      count.times do |i|
        tt = (source_offset + i).to_f / SAMPLE_RATE
        lfo = 0.03 * Math.sin(2 * Math::PI * 0.12 * tt)
        progress = i.to_f / [count - 1, 1].max
        freq = if slide_portion.positive? && progress < slide_portion
                 slide_from + (root - slide_from) * (progress / slide_portion)
               else
                 root
               end
        sample = v * BASS_LEVEL * Math.exp(-tt * BASS_DECAY_RATE) *
                 Math.sin(2 * Math::PI * freq * (1.0 + lfo) * tt)
        left[local_start + i] += sample
        right[local_start + i] += sample
      end
    end
  end
  # Balance pads and tones (chop+melody+bass) independently before mixing —
  # a shared limiter meant a loud bass transient in "tones" ducked the pad
  # chords along with it. Static gain staging (volume=), not a limiter per
  # stem, does that same job with zero dynamic/gain-reduction interaction —
  # a limiter's job is peak safety, and stacking one per stem plus another
  # on the combine (mastering-engineer critique: too many cascaded limiter
  # stages loses transient definition) bought nothing a plain gain match
  # didn't already cover. One limiter at the combine stage remains as the
  # actual safety net; master_bus_filters is the real mastering-stage limit
  # downstream.
  mix_harmonic_wav_stems(path, duration,
                         pads: pads_path, tones: tones_path,
                         su_melody: (su_melody_rendered ? su_melody_path : nil),
                         harmony_lead: (harmony_lead_rendered ? harmony_lead_path : nil),
                         scale_lead: (scale_lead_rendered ? scale_lead_path : nil),
                         lead_arp: (lead_arp_rendered ? lead_arp_path : nil),
                         xlead: (xlead_rendered ? xlead_path : nil),
                         lead: (lead_rendered ? lead_path : nil))
  FileUtils.rm_f(pads_path)
  FileUtils.rm_f(tones_path)
  FileUtils.rm_f(su_melody_path)
  if dfam_events&.any?
    dfam_path = "#{path}.dfam.wav"
    render_dfam_wav(dfam_path, dfam_events, duration)
    tmp = "#{path}.dfam_mix.wav"
    sh! "ffmpeg", "-y", "-i", path, "-i", dfam_path,
        "-filter_complex", "[0:a][1:a]amix=inputs=2:weights=1.0 0.26:duration=first:normalize=0,alimiter=limit=0.96[out]",
        "-map", "[out]", "-t", duration.to_s, "-c:a", "pcm_s16le", tmp
    FileUtils.mv(tmp, path)
    FileUtils.rm_f(dfam_path)
  end
  # Skipped for the bass-only render: this chain is voiced for pads (3.2k
  # lowpass, chorus, echo, pad-shaped compression) and smears a sine bass.
  warm_dilla_pad_post(path, cfg: cfg || dilla_resolve_config) if pad_post
end

# Measured (not guessed) via zero-crossing analysis of the sample body,
# post-attack — the "43" in the filename doesn't reliably encode a MIDI
# note. Only sample keys listed here get pitch-shifted to a target hz;
# everything else (kick/snare/hat/ghost) plays at native pitch.
# The pitch each sample was cut or synthesised at, so a hit asking for a target
# frequency can be resampled to it. A sample missing from here cannot be pitched
# at all -- ratio falls to 1.0 and the hit plays at its own pitch silently,
# which is how the industrial bass stayed in a fixed E-to-Bb tritone no matter
# what key the rest of the catalogue was in. Both values are read straight off
# the generators in ensure_drum_kit!: ind_bass_e is aevalsrc at 41.2 Hz,
# ind_bass_bb at 58.27 Hz.
SAMPLE_NATURAL_HZ = { bass_43: 49.0, cowbell: 670.0,
                      ind_bass_e: 41.2, ind_bass_bb: 58.27 }.freeze

def render_sample_bus_wav(path, events, duration, kit, mapping)
  write_stereo_chunks(path, duration) do |chunk_start, chunk_frames, left, right|
    mapping.each do |event_key, default_key|
      events.fetch(event_key, []).each do |hit|
        time, velocity = hit[0], hit[1]
        target_hz = hit[2].is_a?(Numeric) ? hit[2] : nil
        sample_key = hit[2].is_a?(Symbol) ? hit[2] : default_key
        pan = hit[3].is_a?(Numeric) ? hit[3].to_f : 0.0
        sample = kit.fetch(sample_key)
        natural_hz = SAMPLE_NATURAL_HZ[sample_key]
        # Sample-based bass ignored bass_root entirely — every hit played
        # samples/drums/bass_43.wav at its own fixed pitch regardless of the
        # actual chord, so the loudest, most frequent low-end voice in the
        # mix never followed the harmony. Resample (classic MPC-style pitch
        # shift) toward the chord root instead.
        ratio = (target_hz && natural_hz) ? (target_hz / natural_hz) : 1.0
        src_len = ratio == 1.0 ? sample.length : (sample.length / ratio).floor
        event_frame = (time * SAMPLE_RATE).round
        window = overlap_window(event_frame, src_len, chunk_start, chunk_frames)
        next unless window
        local_start, source_offset, count = window
        count.times do |i|
          value =
            if ratio == 1.0
              sample[source_offset + i] * velocity
            else
              src_pos = (source_offset + i) * ratio
              i0 = src_pos.floor
              frac = src_pos - i0
              s0 = sample[i0] || 0.0
              s1 = sample[i0 + 1] || s0
              (s0 + (s1 - s0) * frac) * velocity
            end
          left[local_start + i] += value * (0.5 - pan * 0.35)
          right[local_start + i] += value * (0.5 + pan * 0.35)
        end
      end
    end
  end
end

def gate_expr(hits, hold: 0.38, scale: 1.0)
  parts = hits.map do |hit|
    t, v = hit[0], hit[1]
    "between(t,#{t.round(4)},#{(t + hold).round(4)})*#{(v * scale).round(4)}"
  end
  parts.empty? ? "0" : parts.join("+")
end

def pad_gate_expr(pad_events)
  parts = pad_events.map do |(t, v, _chord, sustain)|
    "between(t,#{t.round(4)},#{(t + sustain).round(4)})*#{(v * 0.85).round(4)}"
  end
  parts.empty? ? "0.22" : "(#{parts.join('+')})"
end

def dilla_stem_paths
  paths = {}
  paths[:mids]    = STEM_MIDS    if File.exist?(STEM_MIDS)
  paths[:highs]   = STEM_HIGHS   if File.exist?(STEM_HIGHS)
  paths[:sub]     = STEM_SUB     if File.exist?(STEM_SUB)
  paths[:center]  = STEM_CENTER  if File.exist?(STEM_CENTER)
  paths
end

PROGRESSION_LOG_PATH = File.join(SCRATCH_DIR, "progressions_log.txt")
LEGACY_PROGRESSION_LOGS = [
  File.join(OUTPUT_DIR, ".dilla_progressions_log.txt"),
  File.join(SCRATCH_DIR, "dilla_progressions_log.txt"),
].freeze

# Older versions wrote the log as a dotfile into the invoking directory —
# fold any of those into the canonical log the first time we write, so the
# "nothing explored is lost" guarantee survives the path change.
def migrate_legacy_progression_logs!
  LEGACY_PROGRESSION_LOGS.each do |legacy|
    next unless File.exist?(legacy)
    File.open(PROGRESSION_LOG_PATH, "a") { |f| f.write(File.read(legacy)) }
    FileUtils.rm_f(legacy)
    puts "migrated legacy progression log #{legacy} -> #{PROGRESSION_LOG_PATH}"
  end
end

# Every chord walked during a render, appended so nothing explored is lost —
# generated progressions especially never repeat, so this is the only
# record of what actually played if it's worth turning into a real song.
def log_progression!(track, bpm, pads, phases = nil)
  return if pads.empty?

  FileUtils.mkdir_p(SCRATCH_DIR)
  migrate_legacy_progression_logs!
  lines = pads.each_with_index.map do |chord, i|
    notes = chord[:hz].map { |hz| nearest_note(hz) }.join(" ")
    hz = chord[:hz].map { |h| h.round(1) }.join(", ")
    phase = phases&.[](i)
    prefix = phase ? "[#{phase}] " : ""
    "  #{prefix}#{chord[:name]}: #{notes}  (#{hz} Hz)"
  end
  File.open(PROGRESSION_LOG_PATH, "a") do |f|
    # Tagged (fugue) only when there are fugue phases. render_dilla calls this
    # for every render, not just fugues, so the tag was hardcoded onto all of
    # them -- all 133 entries in the log say (fugue), including batucada and
    # afrobeats_pocket. A label that is always printed identifies nothing.
    f.puts "=== #{Time.now.iso8601} — TRACK=#{track} BPM=#{bpm.round(1)}#{phases ? ' (fugue)' : ''} ==="
    f.puts lines
    f.puts
  end
rescue StandardError => e
  warn "progression log write failed: #{e.message}"
end

# Full Jay Dee render: sample drums + stem chops, Dilla Time scheduling.
SELF_SAMPLE_CACHE = File.join(SCRATCH_DIR, "self_sample.wav")

# "Collapse over accretion": before this render's predecessor is deleted,
# grab a short slice of it and cache it — the next render can layer that
# slice back in as texture, a real feedback loop across renders rather
# than each one starting from nothing.
def cache_self_sample!(destination)
  return if ENV.fetch("SELF_SAMPLE", "1") == "0"
  return unless File.exist?(destination) && tool_available?("ffprobe")
  # Not media_metadata: it calls abort() on failure, which would kill the
  # whole render for what's meant to be a best-effort optional step.
  output, _err, status = capture("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of",
                                  "default=noprint_wrappers=1:nokey=1", destination)
  return unless status.success?
  duration = output.to_f
  return if duration < 2.0
  offset = (rand * [duration - 1.5, 0.1].max).round(2)
  FileUtils.mkdir_p(SCRATCH_DIR)
  sh! "ffmpeg", "-y", "-i", destination, "-ss", offset.to_s, "-t", "1.2",
      "-ac", "2", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", SELF_SAMPLE_CACHE
rescue StandardError
  FileUtils.rm_f(SELF_SAMPLE_CACHE)
end

# --------------------------------------------------------------- MIDI Bag
#
# The lead's pitches laid onto the kit's onsets, as MidiDevices::Bag defines it.
#
# Off by default and it must be: this changes WHEN every lead note sounds, which
# is the most audible thing about a part. It is also the device most likely to be
# wanted per-track rather than globally -- a bagged lead is a strong effect, and
# the same setting that makes one beat sound played makes another sound broken.
#
# The timing source is the kit's actual grid rather than an invented one: a
# sixteenth grid with the fourth sixteenth of each beat thinned on even steps,
# accented on the quarters. That is what makes the bagged part inherit the beat's
# pocket instead of running as a machine.
def midi_bag_lead_events(events, cfg, n_bars)
  return events unless ENV["MIDI_BAG"] == "1"
  return events if events.nil? || events.empty?

  bar_p = (60.0 / cfg[:bpm].to_f) * 4.0
  return events unless bar_p.positive? && n_bars.to_i.positive?

  timing = midi_bag_grid(bar_p, n_bars)
  return events if timing.empty?

  chord_at = if ENV.fetch("MIDI_BAG_FIT", "1") != "0"
               chords = dilla_progression(cfg[:progression])
               ->(t) { chords[((t / bar_p).floor) % chords.length] } if chords&.any?
             end
  out = MidiDevices::Bag.apply(
    pitches: events, timing:,
    order: ENV.fetch("MIDI_BAG_ORDER", "cycle").to_sym,
    velocity_from: ENV.fetch("MIDI_BAG_VELOCITY", "timing").to_sym,
    rests: ENV.fetch("MIDI_BAG_RESTS", "0.25").to_f,
    seed: seed_for("midibag"),
    chord_at:
  )
  return events if out.empty?

  dmesg("midi bag: #{events.length} lead pitch(es) on #{out.length} kit onset(s)",
        unit: "harm0", parent: "dilla0")
  out
end

# The kit's onsets as timing slots, with its accents.
def midi_bag_grid(bar_p, n_bars)
  step = bar_p / 16.0
  (0...(n_bars.to_i * 16)).filter_map do |i|
    beat = i % 16
    next if [3, 7, 11, 15].include?(beat) && i.even?

    [i * step, [0, 4, 8, 12].include?(beat) ? 0.9 : 0.55, { hz: [110.0] }, step * 0.85]
  end
end

# --------------------------------------------------------------- Hocket
#
# One line, distributed across the pad voices the engine already has.
#
# HOCKET=n splits a lead across n voices; the caller renders each through a
# different patch, so a line played on one instrument becomes a line played BY an
# ensemble. Returns the voices as an array, or a single-element array when off --
# so a caller can treat the two cases the same and the off path stays exactly
# what it was.
def hocket_lead_voices(events)
  voices = ENV.fetch("HOCKET", "1").to_i
  return [events] unless voices > 1 && events&.any?

  split = MidiDevices::Hocket.split(
    events, voices:,
    mode: ENV.fetch("HOCKET_MODE", "pendulum").to_sym,
    hold: ENV.fetch("HOCKET_HOLD", "1").to_i,
    seed: seed_for("hocket")
  )
  dmesg("hocket: #{events.length} note(s) across #{voices} voice(s) " \
        "(#{split.map(&:length).join('/')})", unit: "harm0", parent: "dilla0")
  split
end

# The harmony lead, played by an ensemble instead of an instrument.
#
# HOCKET=1 (the default) renders exactly what it always rendered, through the one
# call it always used. Above 1 the line is split by MidiDevices::Hocket and each
# voice goes through a DIFFERENT electric-piano program from EP_GM_PROGRAMS, then
# the voices are summed.
#
# Different programs is the whole point and not a flourish: hocketing a line
# across four copies of one patch is a line with gaps in it, which sounds like a
# fault. Across four timbres it is an ensemble handing a melody between players,
# which is what the technique is for and what it is named after.
#
# amix with normalize=0, for the reason audio_graph.rb gives -- the default
# rescales by input count, so a four-voice hocket would arrive a quarter the
# level of the one-voice line it replaces and read as "the leads got quiet".
# 1/sqrt(n) instead: the voices play at different times and sum as power.
def render_hocket_lead!(path, events, duration)
  voices = hocket_lead_voices(events)
  return render_lead_via_fluidsynth(path, events, duration, scale_arp: true) if voices.one?

  rendered = voices.each_with_index.filter_map do |voice, i|
    next if voice.empty?

    part = "#{path}.hocket#{i}.wav"
    render_lead_via_fluidsynth(part, voice, duration, scale_arp: true,
                                                      program_override: EP_GM_PROGRAMS[i % EP_GM_PROGRAMS.length])
    File.file?(part) ? part : nil
  end
  return nil if rendered.empty?
  return (FileUtils.mv(rendered.first, path) && path) if rendered.one?

  inputs = rendered.flat_map { |f| ["-i", f] }
  gain = (1.0 / Math.sqrt(rendered.length)).round(4)
  sh! "ffmpeg", "-y", *inputs, "-filter_complex",
      "#{(0...rendered.length).map { |i| "[#{i}:a]" }.join}" \
      "amix=inputs=#{rendered.length}:duration=longest:normalize=0,volume=#{gain}[out]",
      "-map", "[out]", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", path
  rendered.each { |f| FileUtils.rm_f(f) }
  File.file?(path) ? low_pass_gate_lead!(path) : nil
end

# LPG=1 — the lead through a Buchla-style low-pass gate.
#
# Wired to the lead and not to a bus because an LPG is a NOTE device: it works on
# something struck, where each event decays, and its whole character is that the
# decay darkens. On a sustained pad it would just be a dull filter, and on a full
# mix it would gate the whole arrangement against the kick.
#
# Measured on a decaying pluck: over the decay the 4-12 kHz band falls 17.5 dB
# further than the 200-800 Hz band does, against 0.4 dB for the same note without
# it. That gap is the device.
#
# Off by default. It changes every note of the part it touches.
def low_pass_gate_lead!(path)
  return path unless ENV["LPG"] == "1"

  gated = "#{path}.lpg.wav"
  out = LowPassGate.build!(src: path, dest: gated, rate: SAMPLE_RATE,
                           blend: ENV.fetch("LPG_BLEND", "1.0").to_f,
                           depth: ENV.fetch("LPG_DEPTH", "1.0").to_f,
                           decay_ms: ENV.fetch("LPG_DECAY_MS", "220").to_f,
                           droop: ENV.fetch("LPG_DROOP", "2.4").to_f)
  return path unless out && File.file?(out)

  FileUtils.mv(out, path)
  dmesg("low-pass gate: the lead darkens as it decays", unit: "harm0", parent: "dilla0")
  path
end
