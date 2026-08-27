# frozen_string_literal: true

# Synth patches: the catalogue, the pools they group into, and the selection
# that picks one. These were patch_catalog.rb, patch_pools.rb and
# patch_select.rb — three files for one concept, each referring to the others
# in both directions, and none of them a namespace: every method here lands on
# Object like the rest of lib/engine.
#
# Merged in catalogue-pools-selection order because the catalogue is the data
# the other two read.

# --- was patch_catalog.rb ---------------------------------------------

#
# The synth patch catalogue and its MIDI-FX stacks.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# Rich synth patch catalog — GM programs, optional external sf2, native fallback timbres,
# and per-patch post-FX chains (tremolo/LFO/filter/delay) applied at render time.
def synth_patch(id, role:, program:, bank: 0, sf2: :default, weight: 1.0, native: nil, mix: 1.0, fx: nil,
                arp_styles: nil, octave: 2, gate: 0.82, color: nil, fs_gain: 1.5, midi_fx: nil, midi_arp: nil)
  { id:, role:, program:, bank:, sf2:, weight:, native:,
    mix:, fx: normalize_aecho_gains(fx), arp_styles: arp_styles || [:up, :updown], octave:, gate:, color:,
    fs_gain:, midi_fx:, midi_arp: }
end

# MIDI CC automation baked into SMF before FluidSynth — mod wheel, expression,
# filter, chorus, pan, and pitch-bend LFO (hardware-synth style movement).
# Held chord pads — gentle movement only; aggressive filter sweeps read as
# "horrible" on Rhodes/Moog/Prophet voicings (arp belongs on the lead layer).
MIDI_FX_PAD_EP = [
  { cc: 1, rate_hz: 0.14, depth: 10, base: 22, curve: :sine },
  { cc: 11, curve: :swell, depth: 22, base: 78 },
  { cc: 74, curve: :slow_open, start: 98, end: 108 },
].freeze
MIDI_FX_PAD_WARM = [
  { cc: 1, rate_hz: 0.1, depth: 14, base: 24, curve: :sine },
  { cc: 91, rate_hz: 0.08, depth: 12, base: 44, curve: :sine },
].freeze
# Lead MIDI automation — mod, portamento, pan, filter, chorus, reverb, pitch LFO.
MIDI_FX_LEAD = [
  { cc: 1, rate_hz: 0.48, depth: 48, base: 32, curve: :sine },      # mod wheel
  { cc: 5, rate_hz: 0.22, depth: 28, base: 52, curve: :sine },      # portamento time
  { cc: 10, rate_hz: 0.16, depth: 22, base: 64, curve: :sine },     # pan
  { cc: 11, rate_hz: 0.12, depth: 18, base: 88, curve: :swell },    # expression
  { cc: 71, rate_hz: 0.2, depth: 24, base: 62, curve: :sine },      # resonance
  { cc: 74, curve: :slow_open, start: 68, end: 118 },                 # filter cutoff
  { cc: 91, rate_hz: 0.09, depth: 20, base: 48, curve: :sine },     # reverb send
  { cc: 93, rate_hz: 0.14, depth: 18, base: 40, curve: :sine },     # chorus send
  { bend: true, rate_hz: 0.38, depth_cents: 8 },                      # pitch LFO,
].freeze
MIDI_FX_SCALE_LEAD = [
  { cc: 1, rate_hz: 0.55, depth: 42, base: 36, curve: :sine },
  { cc: 5, rate_hz: 0.2, depth: 20, base: 50, curve: :sine },
  { cc: 10, rate_hz: 0.2, depth: 16, base: 64, curve: :sine },
  { cc: 74, curve: :slow_open, start: 70, end: 120 },
  { cc: 91, rate_hz: 0.1, depth: 16, base: 42, curve: :sine },
  { bend: true, rate_hz: 0.45, depth_cents: 8 },
].freeze
# Extra motion when STREAM_LEAD_MIDI_RICH=1 (default on stream).
MIDI_FX_LEAD_RICH = (
  MIDI_FX_LEAD + [
    { cc: 1, rate_hz: 0.9, depth: 22, base: 40, curve: :sine },
    { cc: 74, rate_hz: 0.35, depth: 30, base: 80, curve: :sine },
    { bend: true, rate_hz: 0.65, depth_cents: 8 },
  ]
).freeze

SYNTH_PATCH_CATALOG = [
  # --- Electric keys (EP / Rhodes family) ---
  # Galaxy SF2 when present — GM program 4 alone never reads as a real Rhodes
  # (no tine attack, no bell). Bank 2 is Galaxy's Mark-I family.
  synth_patch(:rhodes_mark1, role: :ep, program: 4, bank: 2, sf2: :galaxy, weight: 3.6, mix: 1.35, fs_gain: 1.85,
              color: "Mark I warm tine",
              midi_fx: MIDI_FX_PAD_EP,
              arp_styles: %i[skip_up euclidean quint_spread],
              midi_arp: { style: :skip_up, subdiv: 8, gate: 0.78, vel: 0.16 },
              # Bell/tine at 2–4 kHz is the Rhodes identity; keep body, light tremolo.
              fx: "tremolo=f=0.32:d=0.05,equalizer=f=280:t=o:w=1:g=2.2," \
                  "equalizer=f=2400:t=h:w=1400:g=3.2,equalizer=f=4200:t=h:w=1.2:g=1.8," \
                  "chorus=0.28:0.48:24|34:0.12|0.08:0.14|0.1:0.85|1.05," \
                  "aecho=0.35:0.42:50|100:0.18|0.1,lowpass=f=6200"),
  synth_patch(:rhodes_stage73, role: :ep, program: 4, bank: 3, sf2: :galaxy, weight: 3.2, mix: 1.28, fs_gain: 1.8,
              color: "stage Rhodes bark",
              midi_fx: MIDI_FX_PAD_EP,
              fx: "equalizer=f=900:t=o:w=0.9:g=2.4,equalizer=f=2800:t=h:w=1600:g=2.8," \
                  "chorus=0.38:0.58:28|38:0.16|0.12:0.2|0.16:0.95|1.2," \
                  "aecho=0.3:0.38:65|120:0.18|0.1,lowpass=f=5800"),
  synth_patch(:rhodes_tine_wurli, role: :ep, program: 2, weight: 2.2, mix: 1.05, fs_gain: 1.55,
              color: "Wurli bite + tine",
              fx: "equalizer=f=900:t=o:w=0.9:g=2.8,acrusher=bits=12:samples=1.2:mix=0.08,lowpass=f=5200"),
  synth_patch(:rhodes_dx_blend, role: :ep, program: 5, weight: 1.8, mix: 1.0, fs_gain: 1.5,
              color: "DX glass + Rhodes body",
              fx: "aecho=0.45:0.5:80|150:0.28|0.14,aphaser=speed=0.1:decay=0.55,equalizer=f=2400:t=h:w=1200:g=1.8"),
  synth_patch(:rhodes_bleeding_edge, role: :ep, program: 4, weight: 1.6, mix: 1.2, fs_gain: 1.75,
              color: "convolution-warm EP",
              fx: "aecho=0.55:0.65:110|220:0.35|0.18,chorus=0.5:0.7:35|45:0.22|0.18:0.28|0.22:1.1|1.45,vibrato=f=0.22:d=0.01,lowpass=f=4800"),
  synth_patch(:rhodes_bright, role: :ep, program: 0, weight: 1.2, color: "acoustic piano edge",
              fx: "highpass=f=120,equalizer=f=3500:t=h:w=2000:g=1.4"),
  synth_patch(:wurli_bite, role: :ep, program: 2, color: "electric grand",
              fx: "equalizer=f=1100:t=o:w=0.8:g=3.0,acrusher=bits=11:samples=1.4:mix=0.1"),
  synth_patch(:dx_ep_glass, role: :ep, program: 5, color: "FM bell EP",
              fx: "aecho=0.4:0.5:90|170:0.3|0.16,aphaser=speed=0.1:decay=0.6"),
  synth_patch(:clav_funk, role: :ep, program: 7, color: "clavinet"),
  synth_patch(:harpsi_pluck, role: :ep, program: 6, color: "harpsichord"),
  synth_patch(:vibes_mallet, role: :ep, program: 11, color: "vibraphone"),
  synth_patch(:marimba_chop, role: :ep, program: 12, color: "marimba"),
  synth_patch(:galaxy_ep1, role: :ep, program: 4, bank: 2, sf2: :galaxy, weight: 2.4, mix: 1.12, fs_gain: 1.6,
              color: "Galaxy EP",
              fx: "tremolo=f=0.35:d=0.08,aecho=0.4:0.5:60|120:0.25|0.12,lowpass=f=4500"),
  synth_patch(:galaxy_ep2, role: :ep, program: 5, bank: 3, sf2: :galaxy, weight: 2.0, mix: 1.08, fs_gain: 1.55,
              color: "Galaxy EP bright",
              fx: "equalizer=f=1800:t=h:w=1400:g=2.2,aecho=0.35:0.45:80|150:0.22|0.1"),
  synth_patch(:galaxy_ep_bleeding, role: :ep, program: 4, bank: 4, sf2: :galaxy, weight: 1.5, mix: 1.15,
              color: "Galaxy EP + chorus halo",
              fx: "chorus=0.55:0.75:40|50:0.28|0.22:0.3|0.25:1.15|1.55,aphaser=speed=0.12:decay=0.5"),
  synth_patch(:organ_drawbar, role: :ep, program: 16, weight: 1.8, mix: 1.05, fs_gain: 1.52,
              color: "drawbar soul", midi_fx: MIDI_FX_PAD_EP,
              fx: "chorus=0.32:0.48:28|36:0.14|0.1:0.18|0.14:0.9|1.1,lowpass=f=4600"),
  synth_patch(:organ_perc, role: :ep, program: 17, weight: 1.4, mix: 1.0, fs_gain: 1.48,
              color: "perc organ", midi_fx: MIDI_FX_PAD_EP,
              fx: "tremolo=f=0.42:d=0.08,lowpass=f=4200"),
  synth_patch(:rhodes_vintage_tape, role: :ep, program: 4, bank: 2, sf2: :galaxy, weight: 3.0, mix: 1.25, fs_gain: 1.75,
              color: "Rhodes + tape wobble", midi_fx: MIDI_FX_PAD_EP,
              fx: "tremolo=f=0.24:d=0.05,vibrato=f=0.14:d=0.01," \
                  "equalizer=f=2200:t=h:w=1300:g=2.6,equalizer=f=320:t=o:w=1:g=1.6," \
                  "lowpass=f=5200"),
  synth_patch(:rhodes_cafe_warm, role: :ep, program: 4, bank: 2, sf2: :galaxy, weight: 3.2, mix: 1.3, fs_gain: 1.78,
              color: "Rhodes cafe warmth", midi_fx: MIDI_FX_PAD_EP,
              fx: "tremolo=f=0.3:d=0.045,equalizer=f=2600:t=h:w=1500:g=2.8," \
                  "equalizer=f=300:t=o:w=1:g=1.8,aecho=0.36:0.4:65|120:0.2|0.1,lowpass=f=5600"),
  synth_patch(:wurli_soul_bite, role: :ep, program: 2, weight: 2.3, mix: 1.1, fs_gain: 1.56,
              color: "Wurli soul bite", midi_fx: MIDI_FX_PAD_EP,
              fx: "tremolo=f=0.35:d=0.06,aecho=0.32:0.38:50|90:0.18|0.08,lowpass=f=5200"),
  synth_patch(:clav_neo_funk, role: :ep, program: 7, weight: 2.0, mix: 1.02, fs_gain: 1.5,
              color: "neo-soul clav", midi_fx: MIDI_FX_PAD_EP,
              fx: "highpass=f=180,lowpass=f=4500,tremolo=f=0.48:d=0.05"),
  synth_patch(:dx7_bell_ep, role: :ep, program: 5, weight: 1.9, mix: 1.0, fs_gain: 1.48,
              color: "DX bell EP", midi_fx: MIDI_FX_PAD_EP,
              fx: "aecho=0.45:0.5:90|160:0.28|0.14,lowpass=f=5600"),
  synth_patch(:soul_piano_tack, role: :ep, program: 0, weight: 1.5, mix: 0.95, fs_gain: 1.42,
              color: "tacked upright soul", midi_fx: MIDI_FX_PAD_EP,
              fx: "lowpass=f=3800,acompressor=threshold=-26dB:ratio=2:attack=18:release=120"),
  synth_patch(:celeste_dust, role: :ep, program: 8, weight: 1.3, mix: 0.88, fs_gain: 1.38,
              color: "celeste dust", midi_fx: MIDI_FX_PAD_EP,
              fx: "aecho=0.5:0.55:120|220:0.24|0.12,lowpass=f=5000"),
  synth_patch(:ep_mark1_dark, role: :ep, program: 1, weight: 1.6, mix: 1.0, fs_gain: 1.45,
              color: "dark EP mark", midi_fx: MIDI_FX_PAD_EP,
              fx: "lowpass=f=3200,tremolo=f=0.18:d=0.03"),
  # --- Warm analog pads (Moog / Prophet / Juno) ---
  synth_patch(:moog_model_d, role: :warm, program: 91, weight: 3.0, mix: 0.78, fs_gain: 1.48,
              color: "Minimoog ladder pad",
              midi_fx: MIDI_FX_PAD_WARM,
              arp_styles: %i[up downup quint_spread],
              midi_arp: { style: :up, subdiv: 4, gate: 0.88, vel: 0.26 },
              fx: "lowpass=f=3000:width_type=q:width=0.75,tremolo=f=0.18:d=0.06,chorus=0.38:0.58:32|42:0.14|0.1:0.18|0.14:0.92|1.15,aecho=0.28:0.36:80|150:0.18|0.08,equalizer=f=180:t=o:w=1:g=1.6"),
  # The instruments the two producers this engine is modelled on actually owned.
  #
  # Researched 2026-08-09 rather than assumed. J Dilla: a Minimoog Voyager built
  # and signed for him by Bob Moog in 2002, an MPC3000, a MicroKORG and a
  # Motif-Rack ES. Flying Lotus: Fender Rhodes and Wurlitzer, an Access Virus,
  # and a Voyager of his own; the Cosmogramma synths are reported to have come
  # from the MicroKORG.
  #
  # The overlap is the point. Voyager and MicroKORG are the two boxes BOTH of
  # them worked on, and neither had a patch here -- 205 patches and not one named
  # for the synth that made the records. Rhodes, Wurlitzer and Juno were already
  # covered, so this fills the gap rather than restating what exists.
  #
  # Weights are deliberately modest against the incumbents (rhodes_mark1 3.6,
  # prophet_5_pad 3.6, moog_model_d 3.0): these join the rotation, they do not
  # take it over.
  synth_patch(:voyager_ladder_pad, role: :warm, program: 90, weight: 2.2, mix: 0.8, fs_gain: 1.46,
              color: "Voyager ladder pad",
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "lowpass=f=2600,equalizer=f=110:t=o:w=0.9:g=3.0," \
                  "chorus=0.5:0.7:22|30:0.2|0.15:0.14|0.1:0.9|1.2"),
  # Octave 1 and a tight gate: the Voyager's signature on these records is a
  # monophonic line low in the register, not a chord.
  synth_patch(:voyager_mono_lead, role: :lead, program: 87, weight: 2.0, mix: 0.9, fs_gain: 1.42,
              octave: 1, gate: 0.62, arp_styles: %i[up updown],
              color: "Voyager mono line",
              # speed=0.1, not 0.09: ffmpeg's aphaser floor is 0.1 and it refuses
              # anything below, which took the whole fx chain down with it — so
              # this patch was handed back with no phaser, no lowpass and no EQ.
              # 0.1 is the nearest legal value to what was written.
              fx: "lowpass=f=2400,equalizer=f=180:t=q:w=1.4:g=4.0,aphaser=speed=0.1:decay=0.5"),
  # Thin, slightly brittle and digital next to the Moog -- that contrast is what
  # it is for, so it is not smoothed with chorus.
  synth_patch(:microkorg_lead, role: :lead, program: 81, weight: 1.8, mix: 0.86, fs_gain: 1.35,
              octave: 2, gate: 0.7, arp_styles: %i[updown spiral],
              color: "MicroKORG digital lead",
              fx: "equalizer=f=2600:t=h:w=1500:g=2.0,lowpass=f=7000,acrusher=bits=12:samples=1.2:mix=0.08"),
  synth_patch(:microkorg_vox_texture, role: :texture, program: 54, weight: 1.5, mix: 0.8, fs_gain: 1.3,
              color: "MicroKORG vocoder wash",
              fx: "chorus=0.6:0.8:35|48:0.26|0.2:0.24|0.18:1.1|1.4,lowpass=f=5200"),
  synth_patch(:access_virus_hyper, role: :warm, program: 89, weight: 1.9, mix: 0.84, fs_gain: 1.44,
              color: "Access Virus hypersaw pad",
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "chorus=0.7:0.9:38|52|61:0.3|0.24|0.2:0.28|0.22|0.18:1.1|1.35|1.6,lowpass=f=6200"),
  synth_patch(:motif_rack_strings, role: :warm, program: 49, weight: 1.7, mix: 0.82, fs_gain: 1.42,
              color: "Motif-Rack ES strings",
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "equalizer=f=320:t=o:w=1.1:g=1.4,lowpass=f=5600,aecho=0.5:0.6:120|200:0.22|0.12"),
  synth_patch(:motif_rack_ep, role: :ep, program: 5, weight: 1.6, mix: 1.02, fs_gain: 1.5,
              color: "Motif-Rack ES FM EP",
              fx: "equalizer=f=2200:t=h:w=1600:g=1.8,tremolo=f=0.3:d=0.06,lowpass=f=6000"),

  synth_patch(:moog_sub37_pad, role: :warm, program: 38, weight: 2.4, mix: 0.78, fs_gain: 1.4,
              color: "Moog sub harmonic pad",
              fx: "lowpass=f=2200,equalizer=f=95:t=o:w=0.8:g=3.5,aphaser=speed=0.1:decay=0.55"),
  synth_patch(:moog_bleeding_edge, role: :warm, program: 91, weight: 1.8, mix: 0.85, fs_gain: 1.5,
              color: "Moog + tape drift",
              midi_fx: MIDI_FX_PAD_WARM,
              arp_styles: %i[up downup quint_spread],
              midi_arp: { style: :up, subdiv: 4, gate: 0.88, vel: 0.26 },
              fx: "vibrato=f=0.18:d=0.014,tremolo=f=0.55:d=0.12,aecho=0.42:0.52:100|190:0.28|0.14,lowpass=f=3000"),
  # Supersaw bank = analog poly stack the GM "Pad 2" never delivers.
  # Wide chorus + gentle LFO is the Prophet bedroom-record character.
  synth_patch(:prophet_5_pad, role: :warm, program: 0, sf2: :supersaw, weight: 3.6, mix: 1.05, fs_gain: 1.65,
              color: "Prophet-5 poly",
              midi_fx: MIDI_FX_PAD_WARM,
              arp_styles: %i[updown pingpong major_third_cycle_full],
              midi_arp: { style: :updown, subdiv: 4, gate: 0.86, vel: 0.24 },
              fx: "chorus=0.58:0.78:38|48:0.28|0.22:0.32|0.26:1.2|1.5," \
                  "vibrato=f=0.16:d=0.012,equalizer=f=220:t=o:w=1:g=2.0," \
                  "equalizer=f=1800:t=h:w=1200:g=1.6,aecho=0.34:0.42:90|170:0.22|0.12,lowpass=f=5200"),
  synth_patch(:prophet_6_warm, role: :warm, program: 3, sf2: :supersaw, weight: 3.0, mix: 1.0, fs_gain: 1.58,
              color: "Prophet-6 stereo wash",
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "chorus=0.62:0.82:42|52:0.3|0.26:0.36|0.3:1.25|1.55," \
                  "equalizer=f=180:t=o:w=1:g=1.8,aecho=0.36:0.44:95|180:0.24|0.12,lowpass=f=5000"),
  # FM-synthesized (not sampled-analog) pad from the giga-hq-fm-gm soundfont --
  # a genuinely different source timbre rather than more ffmpeg fx stacked on
  # the same default GeneralUser-GS patches the other warm pads use.
  synth_patch(:fm_bowed_pad, role: :warm, program: 92, weight: 2.6, mix: 0.8, fs_gain: 1.4,
              sf2: :giga_fm, color: "FM bowed/glass pad, heavy tape/VHS wobble + dub space echo",
              # aecho's in_gain scales the DRY signal, not just the echo tail --
              # low in_gain here (0.5, 0.35) was silently halving level twice,
              # which is why this measured ~24dB quieter than the raw patch in
              # isolation testing. Keep in_gain near 1.0 and use decay for the
              # echo character instead; volume= makes up the remaining loss
              # from chorus's dry/wet summing so the pad stays audible.
              fx: "lowpass=f=3200,vibrato=f=0.55:d=0.025,tremolo=f=6.5:d=0.09," \
                  "chorus=0.5:0.7:35|45:0.22|0.18:0.25|0.2:1.1|1.3," \
                  "acrusher=bits=9:samples=3:mix=0.22,equalizer=f=3200:t=h:w=1:g=-6," \
                  "aecho=0.9:0.9:60|140:0.3|0.15,aecho=0.9:0.9:420|680:0.28|0.2,volume=2.2"),
  synth_patch(:prophet_rev2_bleeding, role: :warm, program: 5, sf2: :supersaw, weight: 2.4, mix: 0.92, fs_gain: 1.55,
              color: "Rev2 hybrid supersaw bed",
              midi_fx: MIDI_FX_PAD_WARM,
              arp_styles: %i[updown pingpong major_third_cycle_full],
              midi_arp: { style: :updown, subdiv: 4, gate: 0.86, vel: 0.24 },
              fx: "chorus=0.6:0.8:44|54:0.3|0.26:0.34|0.28:1.25|1.55," \
                  "aphaser=speed=0.12:decay=0.48,equalizer=f=1600:t=h:w=1.2:g=1.4,lowpass=f=4800"),
  synth_patch(:juno_strings, role: :warm, program: 50, weight: 2.2, mix: 0.72,
              fx: "chorus=0.55:0.75:40|55:0.3|0.25:0.35|0.3:1.1|1.5"),
  synth_patch(:solina_ensemble, role: :warm, program: 51, fx: "aphaser=speed=0.12:decay=0.5"),
  synth_patch(:prophet_pad, role: :warm, program: 1, sf2: :supersaw, weight: 2.6, mix: 0.95, fs_gain: 1.5,
              color: "Prophet poly bed",
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "vibrato=f=0.28:d=0.014,chorus=0.5:0.7:34|44:0.22|0.18:0.28|0.22:1.1|1.35," \
                  "equalizer=f=200:t=o:w=1:g=1.6,lowpass=f=4800"),
  synth_patch(:oberheim_pad, role: :warm, program: 90, fx: "tremolo=f=4.2:d=0.14"),
  synth_patch(:moog_pad, role: :warm, program: 91, weight: 2.2, mix: 0.8,
              fx: "lowpass=f=2600:width_type=q:width=0.75,tremolo=f=0.35:d=0.1,equalizer=f=160:t=o:w=1:g=2.0"),
  synth_patch(:cs80_ensemble, role: :warm, program: 92, fx: "aecho=0.35:0.45:120|200:0.28|0.14"),
  synth_patch(:pwm_sweep_pad, role: :warm, program: 93, fx: "tremolo=f=0.55:d=0.22,aphaser=speed=0.14:decay=0.55"),
  # Singers Unlimited–style beds: soft GM choir, slow attack via pad envelope + FX.
  # ---------------------------------------------------- the famous machines
  #
  # Six patches that people can name. Each is a General MIDI voice reshaped into
  # the sound the real instrument is remembered for -- not the instrument, which
  # would need its oscillators, but the fingerprint: what the filter did, what
  # the chorus did, where the harmonics sat.
  #
  # The fingerprint is usually one or two things, and they are usually not the
  # oscillators. A Juno-106 is a fairly ordinary single-oscillator synth wearing
  # a famous chorus; a Minimoog is remembered for a filter and for three
  # oscillators that would not stay in tune with each other. Reproduce those and
  # most of the character follows.

  # MINIMOOG. Three oscillators, never quite in tune with one another, into a
  # 24 dB-per-octave ladder filter with a resonance that thickens rather than
  # whistles. The bass on Thriller.
  #
  # The detuning is the point and is why a Moog bass sounds enormous from one
  # note: three saws a few cents apart beat against each other, and the beating
  # is heard as weight. Here that is a short chorus with almost no modulation --
  # a fixed detune rather than a moving one -- and the ladder is a steep lowpass
  # with a resonant lift sitting on top of the cutoff.
  synth_patch(:minimoog_bass, role: :bass, program: 38, weight: 3.0, mix: 1.2, fs_gain: 1.7,
              fx: "chorus=0.6:0.9:11|17|23:0.28|0.22|0.18:0.05|0.04|0.03:0.6|0.5|0.4," \
                  "equalizer=f=520:t=q:w=1.6:g=4.5,lowpass=f=520,lowpass=f=520," \
                  "asubboost=dry=0.9:wet=0.5:decay=0.7:feedback=0.6:cutoff=90"),

  # JUNO-106. One oscillator, a sub, and the chorus that made it famous -- a
  # bucket-brigade delay running two slightly detuned copies against the dry
  # signal. Chorus II is the wide one, and it is most of what people mean when
  # they say "Juno".
  #
  # The giveaway is that the chorus is NOISY and slightly out of tune, because a
  # bucket-brigade line is an analogue delay with its own noise floor. Clean
  # digital chorus does not sound like this.
  synth_patch(:juno106_pad, role: :warm, program: 89, weight: 2.6, mix: 0.88, fs_gain: 1.35,
              fx: "chorus=0.7:0.85:24|31:0.42|0.38:0.32|0.28:1.6|2.1," \
                  "highpass=f=90,lowpass=f=7200,volume=0.94"),

  # DX7 E.PIANO 1. The preset on every ballad of the late eighties. Frequency
  # modulation, not subtraction, which is why it has a glassy bell on the attack
  # that no analogue synth produces and a hollow body underneath it.
  #
  # Shaped here by lifting the bell region hard on top of an electric piano and
  # rolling away the low mids, which is where the difference between an FM piano
  # and a Rhodes actually lives.
  synth_patch(:dx7_epiano, role: :ep, program: 5, weight: 2.4, mix: 1.1, fs_gain: 1.6,
              fx: "equalizer=f=2600:t=q:w=1.2:g=5.0,equalizer=f=420:t=q:w=1.0:g=-3.0," \
                  "chorus=0.5:0.8:26|38:0.3|0.24:0.2|0.16:1.1|1.4,highpass=f=70"),

  # PROPHET-5. Two oscillators with pulse-width modulation, a filter that opens
  # slowly, and Poly-Mod routing one oscillator into the other's pitch. The
  # brass sound is the one it is remembered for.
  #
  # Pulse-width modulation is a slow sweep of the pulse shape, heard as the tone
  # hollowing and filling. A phaser is the closest thing to it here.
  synth_patch(:prophet5_brass, role: :warm, program: 62, weight: 2.4, mix: 0.9, fs_gain: 1.4,
              # aphaser takes `delay` (0-5 ms), not `depth`, and a rejected
              # option fails the entire chain -- so the patch would have
              # rendered with no effects at all rather than with a warning.
              fx: "aphaser=speed=0.14:decay=0.5:delay=4," \
                  "equalizer=f=1400:t=q:w=1.3:g=3.0,lowpass=f=6400,highpass=f=110"),

  # TB-303. Not a bass machine by intent -- a failed accompaniment box -- and the
  # entire foundation of acid house by accident. One oscillator, an 18 dB filter
  # with far more resonance than is sensible, and an envelope that slams the
  # cutoff on every accented note.
  #
  # The squelch IS the resonance sweeping. A fixed filter cannot make this sound,
  # so the cutoff is swept here by asendcmd in the layer that uses it; what the
  # patch carries is the resonant peak and the drive behind it.
  synth_patch(:tb303_acid, role: :lead, program: 87, weight: 1.6, mix: 0.85, fs_gain: 1.3,
              octave: 1, gate: 0.55,
              fx: "equalizer=f=900:t=q:w=3.2:g=9.0,lowpass=f=1800," \
                  "volume=10dB,asoftclip=type=tanh:param=2.0:oversample=4,volume=-10dB"),

  # OBERHEIM OB-Xa. Two detuned sawtooths per voice, unison, filter wide open.
  # The riff on "Jump", and the reason Oberheim brass is described as a wall.
  #
  # Wider and brighter than the Prophet: more detune, less filtering, and the
  # stereo spread that having eight voices doubled gives you.
  synth_patch(:obxa_brass, role: :warm, program: 63, weight: 2.2, mix: 0.86, fs_gain: 1.4,
              fx: "chorus=0.65:0.8:18|29:0.5|0.44:0.24|0.2:0.9|1.3," \
                  "equalizer=f=2200:t=q:w=1.5:g=3.5,lowpass=f=8200,extrastereo=m=1.12"),

  synth_patch(:choir_aahs, role: :warm, program: 52, weight: 1.4, mix: 0.42, fs_gain: 1.15,
              fx: "highpass=f=220,aecho=0.5:0.55:100|180:0.32|0.16,lowpass=f=3800:width_type=q:width=0.7,volume=0.85"),
  synth_patch(:voice_oohs, role: :warm, program: 53, weight: 1.3, mix: 0.38, fs_gain: 1.1,
              fx: "highpass=f=260,vibrato=f=0.38:d=0.014,chorus=0.4:0.55:28|42:0.16|0.12:0.2|0.16:1.0|1.2,lowpass=f=3600,volume=0.82"),
  synth_patch(:analog_pad1, role: :warm, program: 88),
  # Was program 94 — "metallic pad". Named analog, roled warm, and rendering as
  # struck metal. 90 is "warm pad", which is what the name always claimed.
  synth_patch(:analog_pad2, role: :warm, program: 90),
  synth_patch(:analog_pad3, role: :warm, program: 95),
  synth_patch(:string_orchestra, role: :warm, program: 48, fx: "lowpass=f=4200"),
  synth_patch(:slow_attack_pad, role: :warm, program: 49, fx: "acompressor=threshold=-24dB:ratio=1.8:attack=80:release=220"),
  synth_patch(:fm_bell_pad, role: :warm, program: 14, fx: "aecho=0.4:0.5:90|160:0.32|0.18"),
  synth_patch(:bowed_glass, role: :warm, program: 13, fx: "aphaser=speed=0.12:decay=0.7"),
  synth_patch(:memorymoon_pad, role: :warm, program: 88, weight: 2.1, mix: 0.74, fs_gain: 1.4,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "chorus=0.42:0.62:34|44:0.18|0.14:0.22|0.18:0.95|1.15,lowpass=f=3900"),
  # Also mis-assigned to 94. Weight 2.0 meant this one was picked twice as
  # often as its neighbours, so the metallic pad was over-represented.
  synth_patch(:warm_analog_duo, role: :warm, program: 90, weight: 2.0, mix: 0.76, fs_gain: 1.38,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "tremolo=f=0.28:d=0.1,aphaser=speed=0.1:decay=0.52,lowpass=f=3400"),
  synth_patch(:tape_string_pad, role: :warm, program: 48, weight: 2.2, mix: 0.7, fs_gain: 1.36,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "vibrato=f=0.15:d=0.01,lowpass=f=3600,aecho=0.32:0.4:100|180:0.2|0.1"),
  synth_patch(:polysynth_soul, role: :warm, program: 89, weight: 2.3, mix: 0.72, fs_gain: 1.42,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "chorus=0.48:0.68:36|46:0.22|0.18:0.26|0.22:1.05|1.25,lowpass=f=4100"),
  synth_patch(:mellotron_flute_pad, role: :warm, program: 73, weight: 1.8, mix: 0.68, fs_gain: 1.34,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "aecho=0.42:0.48:140|260:0.24|0.12,lowpass=f=3800"),
  synth_patch(:analog_hollow, role: :warm, program: 95, weight: 1.9, mix: 0.74, fs_gain: 1.37,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "lowpass=f=3000,tremolo=f=0.32:d=0.08,equalizer=f=200:t=o:w=1:g=2.2"),
  synth_patch(:juno_chorus_wash, role: :warm, program: 50, weight: 2.4, mix: 0.7, fs_gain: 1.4,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "chorus=0.62:0.82:44|54:0.32|0.28:0.38|0.32:1.15|1.45,lowpass=f=4300"),
  synth_patch(:prophet_brass_wash, role: :warm, program: 62, weight: 1.7, mix: 0.66, fs_gain: 1.35,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "lowpass=f=3500,acompressor=threshold=-24dB:ratio=2.2:attack=14:release=110"),
  # --- Texture layers (quiet bed under EP+pad) ---
  synth_patch(:shimmer_organ, role: :texture, program: 19, mix: 0.22, fx: "lowpass=f=2400,volume=0.35"),
  synth_patch(:ethnic_flute, role: :texture, program: 75, mix: 0.18, fx: "aecho=0.5:0.6:200|380:0.25|0.12"),
  synth_patch(:soft_synth_str, role: :texture, program: 50, mix: 0.15, fx: "lowpass=f=1800"),
  synth_patch(:space_voice, role: :texture, program: 54, mix: 0.12, fx: "aphaser=speed=0.12:decay=0.8"),
  synth_patch(:music_box, role: :texture, program: 10, mix: 0.14, fx: "aecho=0.45:0.55:60|120:0.3|0.15"),
  synth_patch(:kalimba_dust, role: :texture, program: 108, mix: 0.16, fx: "highpass=f=400"),
  synth_patch(:reverse_pad_ghost, role: :texture, program: 95, mix: 0.1, fx: "areverse,lowpass=f=1600"),
  # --- Lead / arp voices ---
  synth_patch(:prophet_lead, role: :lead, program: 81, weight: 2.5, fs_gain: 1.35, arp_styles: %i[updown skip_up], octave: 2,
              midi_fx: MIDI_FX_LEAD, midi_arp: { style: :skip_up, subdiv: 8, gate: 0.58, vel: 0.52 },
              fx: "chorus=0.42:0.62:32|42:0.18|0.14:0.22|0.18:0.95|1.2,aecho=0.5:0.4:150|280:0.3|0.18,lowpass=f=4800"),
  synth_patch(:big_lead_prophet5, role: :lead, program: 87, weight: 2.8, fs_gain: 1.4, arp_styles: %i[pingpong quint_spread], octave: 2,
              fx: "chorus=0.52:0.72:36|46:0.24|0.2:0.28|0.22:1.15|1.45,aecho=0.45:0.38:140|260:0.28|0.16,lowpass=f=5400"),
  synth_patch(:prophet_bleeding_lead, role: :lead, program: 87, sf2: :supersaw, weight: 1.6, fs_gain: 1.38,
              arp_styles: %i[spiral major_third_cycle_full], octave: 2,
              midi_fx: MIDI_FX_LEAD, midi_arp: { style: :spiral, subdiv: 8, gate: 0.54, vel: 0.54 },
              fx: "chorus=0.58:0.78:44|54:0.3|0.25:0.32|0.28:1.25|1.6,aphaser=speed=0.16:decay=0.5,vibrato=f=0.38:d=0.015"),
  synth_patch(:charang_bite, role: :lead, program: 84, arp_styles: %i[up fibonacci], octave: 2,
              fx: "tremolo=f=5.5:d=0.18,aecho=0.5:0.38:140|260:0.28|0.16"),
  synth_patch(:fifths_lead, role: :lead, program: 86, arp_styles: %i[updown major_third_cycle_full], octave: 2,
              fx: "vibrato=f=0.55:d=0.02,lowpass=f=4800"),
  synth_patch(:saw_lead, role: :lead, program: 81, arp_styles: %i[random_walk wonky_wobble], octave: 2,
              midi_fx: MIDI_FX_LEAD, midi_arp: { style: :pingpong, subdiv: 8, gate: 0.55, vel: 0.5 },
              fx: "tremolo=f=3.2:d=0.2,aphaser=speed=0.22:decay=0.45"),
  synth_patch(:square_lead, role: :lead, program: 80, arp_styles: %i[euclidean donda_stab], octave: 2,
              midi_fx: MIDI_FX_LEAD, midi_arp: { style: :euclidean, subdiv: 8, gate: 0.52, vel: 0.46 },
              fx: "acrusher=bits=10:samples=2:mix=0.18,aecho=0.4:0.35:100|200:0.25|0.14"),
  synth_patch(:supersaw_1, role: :lead, program: 0, sf2: :supersaw, arp_styles: %i[spiral updown], octave: 2,
              fx: "chorus=0.6:0.8:45|55:0.3|0.25:0.3|0.25:1.2|1.6,lowpass=f=6000"),
  synth_patch(:supersaw_2, role: :lead, program: 3, sf2: :supersaw, arp_styles: %i[skip_up pingpong], octave: 2,
              fx: "tremolo=f=4.8:d=0.16,aecho=0.55:0.45:180|340:0.3|0.18"),
  synth_patch(:supersaw_3, role: :lead, program: 7, sf2: :supersaw, arp_styles: %i[wonky_wobble random_walk], octave: 2,
              fx: "aphaser=speed=0.18:decay=0.5,vibrato=f=0.4:d=0.015"),
  synth_patch(:brass_synth, role: :lead, program: 62, arp_styles: %i[up major_third_cycle_full], octave: 1,
              fx: "acompressor=threshold=-20dB:ratio=3:attack=8:release=90,lowpass=f=3800"),
  synth_patch(:soft_synth_lead, role: :lead, program: 88, arp_styles: %i[updown downup], octave: 2,
              fx: "aecho=0.6:0.5:220|400:0.35|0.2,lowpass=f=3400"),
  synth_patch(:fm_lead_bell, role: :lead, program: 98, arp_styles: %i[fibonacci quint_spread], octave: 3,
              fx: "aecho=0.45:0.5:90|170:0.35|0.2,aphaser=speed=0.1:decay=0.65"),
  synth_patch(:oboe_solo, role: :lead, program: 68, arp_styles: %i[updown skip_up], octave: 2,
              fx: "vibrato=f=0.62:d=0.018,tremolo=f=2.2:d=0.08"),
  synth_patch(:clarinet_lead, role: :lead, program: 71, arp_styles: %i[downup pingpong], octave: 2,
              fx: "lowpass=f=3000,aecho=0.35:0.4:130|240:0.22|0.12"),
  synth_patch(:flute_airy, role: :lead, program: 73, arp_styles: %i[spiral random_walk], octave: 3,
              fx: "aecho=0.5:0.55:200|360:0.3|0.16,highpass=f=280"),
  synth_patch(:whistle_hook, role: :lead, program: 78, arp_styles: %i[up euclidean], octave: 3,
              fx: "tremolo=f=6.5:d=0.12,aecho=0.4:0.45:80|150:0.28|0.14"),
  synth_patch(:guitar_muted, role: :lead, program: 28, arp_styles: %i[skip_up donda_stab], octave: 2,
              fx: "lowpass=f=2600,acrusher=bits=11:samples=1.5:mix=0.12"),
  synth_patch(:dist_guitar, role: :lead, program: 30, arp_styles: %i[major_third_cycle_full updown], octave: 1,
              fx: "acompressor=threshold=-18dB:ratio=4:attack=3:release=60,lowpass=f=4200"),
  synth_patch(:pluck_synth, role: :lead, program: 24, arp_styles: %i[up pingpong], octave: 2, gate: 0.55,
              fx: "aecho=0.35:0.4:60|110:0.25|0.12,highpass=f=200"),
  synth_patch(:banjo_pluck, role: :lead, program: 105, arp_styles: %i[skip_up fibonacci], octave: 2, gate: 0.5,
              fx: "aecho=0.3:0.35:50|90:0.2|0.1"),
  synth_patch(:koto_pluck, role: :lead, program: 107, arp_styles: %i[euclidean spiral], octave: 2, gate: 0.48,
              fx: "lowpass=f=3500,aecho=0.4:0.45:70|130:0.22|0.1"),
  synth_patch(:voice_lead, role: :lead, program: 54, arp_styles: %i[updown wonky_wobble], octave: 2,
              fx: "vibrato=f=0.5:d=0.014,aphaser=speed=0.1:decay=0.6"),
  synth_patch(:minimoog_lead, role: :lead, program: 81, weight: 2.4, fs_gain: 1.35, arp_styles: %i[up random_walk], octave: 1,
              midi_fx: MIDI_FX_LEAD, midi_arp: { style: :updown, subdiv: 4, gate: 0.65, vel: 0.48 },
              fx: "lowpass=f=2200:width_type=q:width=0.8,tremolo=f=2.5:d=0.12,equalizer=f=140:t=o:w=0.9:g=2.5,aecho=0.42:0.35:110|200:0.22|0.1"),
  synth_patch(:moog_ladder_lead, role: :lead, program: 38, weight: 2.0, fs_gain: 1.32, arp_styles: %i[updown fibonacci], octave: 1,
              midi_fx: MIDI_FX_LEAD, midi_arp: { style: :fibonacci, subdiv: 4, gate: 0.6, vel: 0.5 },
              fx: "lowpass=f=2800,tremolo=f=3.5:d=0.14,chorus=0.35:0.55:28|36:0.14|0.1:0.18|0.14:0.85|1.1"),
  synth_patch(:cs_lead, role: :lead, program: 82, arp_styles: %i[downup quint_spread], octave: 2,
              fx: "chorus=0.4:0.6:35|45:0.2|0.15:0.2|0.2:0.9|1.2"),
  # --- Soul lead arp voices (LEAD_ARP stem — chord-tone figures up top) ---
  synth_patch(:donuts_wurli_lead, role: :lead, program: 5, weight: 3.0, fs_gain: 1.32, gate: 0.68, octave: 2,
              arp_styles: %i[skip_up euclidean quint_spread], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :skip_up, subdiv: 8, gate: 0.64, vel: 0.5 },
              fx: "tremolo=f=0.28:d=0.04,aecho=0.48:0.42:100|180:0.24|0.12,lowpass=f=5200"),
  synth_patch(:soul_prophet_arp, role: :lead, program: 81, weight: 3.2, fs_gain: 1.36, gate: 0.62, octave: 2,
              arp_styles: %i[pingpong skip_up updown], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :pingpong, subdiv: 6, gate: 0.6, vel: 0.52 },
              fx: "chorus=0.44:0.64:32|42:0.2|0.16:0.22|0.2:1.0|1.25,aecho=0.5:0.4:160|280:0.28|0.16,lowpass=f=4600"),
  synth_patch(:moog_dilla_pocket, role: :lead, program: 38, weight: 2.8, fs_gain: 1.34, gate: 0.66, octave: 1,
              arp_styles: %i[up downup quint_spread], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :up, subdiv: 4, gate: 0.68, vel: 0.54 },
              fx: "lowpass=f=2600,tremolo=f=2.8:d=0.11,equalizer=f=180:t=o:w=1:g=2.8,aecho=0.38:0.32:90|160:0.18|0.1"),
  synth_patch(:neo_soul_pluck, role: :lead, program: 24, weight: 2.6, fs_gain: 1.28, gate: 0.58, octave: 2,
              arp_styles: %i[skip_up fibonacci donda_stab], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :skip_up, subdiv: 8, gate: 0.54, vel: 0.48 },
              fx: "aecho=0.42:0.38:70|130:0.22|0.1,highpass=f=220,lowpass=f=4200"),
  synth_patch(:wonky_fm_shimmer, role: :lead, program: 98, weight: 2.4, fs_gain: 1.3, gate: 0.56, octave: 3,
              arp_styles: %i[spiral fibonacci random_walk], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :spiral, subdiv: 8, gate: 0.56, vel: 0.46 },
              fx: "aecho=0.5:0.45:110|200:0.3|0.16,aphaser=speed=0.12:decay=0.55,lowpass=f=5800"),
  # --- Bubbles: the liquid Brainfeeder texture ---------------------------
  #
  # wonky_fm_shimmer above is the glassy end of this family (GM 98, crystal).
  # These are the wet end: short gates so each note is a blip rather than a
  # sustained tone, pitch movement from vibrato instead of from the arp, and
  # close echo taps so notes overlap into a burble rather than a delay line.
  #
  # The resonant peak is what makes them read as liquid at all -- ffmpeg's
  # lowpass has no resonance control, so the peak is an `equalizer` band
  # under the cutoff. Without it these are quiet blips.

  # Main bubble voice: mid-register, wobbling, notes tumbling over each other.
  synth_patch(:wonky_bubble, role: :lead, program: 102, weight: 2.3, fs_gain: 1.24, gate: 0.34, octave: 3,
              arp_styles: %i[bubble_rise bubble_pop spiral], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :bubble_rise, subdiv: 8, gate: 0.34, vel: 0.44 },
              fx: "vibrato=f=6.5:d=0.28,aecho=0.6:0.55:70|130|210:0.4|0.24|0.14," \
                  "equalizer=f=1800:t=q:w=1.2:g=6,lowpass=f=6200"),

  # Droplets: higher, faster, drier. Sparse enough to sit over a busy kit.
  synth_patch(:wonky_droplet, role: :lead, program: 96, weight: 1.9, fs_gain: 1.2, gate: 0.22, octave: 4,
              arp_styles: %i[bubble_pop stutter ratchet], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :bubble_pop, subdiv: 16, gate: 0.22, vel: 0.38 },
              fx: "vibrato=f=11:d=0.4,aecho=0.5:0.4:45|95:0.35|0.18,highpass=f=400," \
                  "equalizer=f=2600:t=q:w=0.9:g=8,lowpass=f=9000"),

  # Submerged: slow, dark and phasing -- the same idea heard from underwater.
  # Pairs with the sparse slow grids (wonky_massage, wonky_flamagra) where a
  # fast bubble figure would crowd the space they exist to leave.
  synth_patch(:wonky_gloop, role: :lead, program: 88, weight: 2.1, fs_gain: 1.3, gate: 0.62, octave: 2,
              arp_styles: %i[bubble_rise wonky_wobble quint_spread], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :bubble_rise, subdiv: 4, gate: 0.62, vel: 0.42 },
              fx: "flanger=delay=4:depth=6:speed=0.4,aphaser=speed=0.25:decay=0.6," \
                  "lowpass=f=3400,aecho=0.7:0.6:180|320:0.35|0.2"),

  synth_patch(:jazz_ballad_lead, role: :lead, program: 73, weight: 2.5, fs_gain: 1.26, gate: 0.7, octave: 2,
              arp_styles: %i[updown major_third_cycle_full], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :updown, subdiv: 4, gate: 0.72, vel: 0.44 },
              fx: "vibrato=f=0.45:d=0.012,aecho=0.55:0.48:200|360:0.28|0.14,lowpass=f=4000"),
  synth_patch(:gospel_brass_lead, role: :lead, program: 62, weight: 2.2, fs_gain: 1.3, gate: 0.64, octave: 1,
              arp_styles: %i[major_third_cycle_full up quint_spread], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :major_third_cycle_full, subdiv: 6, gate: 0.62, vel: 0.5 },
              fx: "acompressor=threshold=-22dB:ratio=2.5:attack=12:release=100,lowpass=f=3600"),
  synth_patch(:erykah_dust_lead, role: :lead, program: 4, weight: 2.9, fs_gain: 1.3, gate: 0.6, octave: 2,
              arp_styles: %i[euclidean skip_up], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :euclidean, subdiv: 8, gate: 0.7, vel: 0.42 },
              fx: "tremolo=f=0.22:d=0.03,acrusher=bits=12:samples=2:mix=0.08,lowpass=f=4800"),
  synth_patch(:watermelon_glass, role: :lead, program: 88, weight: 2.7, fs_gain: 1.28, gate: 0.64, octave: 2,
              arp_styles: %i[updown quint_spread], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :quint_spread, subdiv: 6, gate: 0.66, vel: 0.46 },
              fx: "aecho=0.52:0.46:140|260:0.26|0.14,lowpass=f=3800"),
  synth_patch(:rhodes_lead_comp, role: :lead, program: 4, weight: 2.5, fs_gain: 1.3, gate: 0.64, octave: 2,
              arp_styles: %i[updown skip_up], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :updown, subdiv: 6, gate: 0.66, vel: 0.48 },
              fx: "tremolo=f=0.3:d=0.05,lowpass=f=4600"),
  synth_patch(:mark1_soul_lead, role: :lead, program: 5, weight: 2.4, fs_gain: 1.32, gate: 0.62, octave: 2,
              arp_styles: %i[skip_up quint_spread], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :skip_up, subdiv: 8, gate: 0.6, vel: 0.5 },
              fx: "aecho=0.4:0.38:80|150:0.22|0.1,lowpass=f=5000"),
  synth_patch(:dangelo_clav_lead, role: :lead, program: 7, weight: 2.3, fs_gain: 1.28, gate: 0.56, octave: 2,
              arp_styles: %i[skip_up donda_stab], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :skip_up, subdiv: 8, gate: 0.54, vel: 0.52 },
              fx: "highpass=f=200,lowpass=f=4200"),
  synth_patch(:stevie_organ_lead, role: :lead, program: 16, weight: 2.1, fs_gain: 1.3, gate: 0.68, octave: 2,
              arp_styles: %i[major_third_cycle_full up], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :major_third_cycle_full, subdiv: 6, gate: 0.7, vel: 0.46 },
              fx: "chorus=0.36:0.52:28|36:0.14|0.1:0.16|0.14:0.9|1.1,lowpass=f=4000"),
  synth_patch(:glasper_ep_lead, role: :lead, program: 4, weight: 2.6, fs_gain: 1.34, gate: 0.6, octave: 2,
              arp_styles: %i[quint_spread major_third_cycle_full], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :quint_spread, subdiv: 6, gate: 0.62, vel: 0.46 },
              fx: "aecho=0.45:0.4:110|200:0.26|0.14,lowpass=f=4400"),
  synth_patch(:warm_prophet_hook, role: :lead, program: 81, weight: 2.5, fs_gain: 1.36, gate: 0.6, octave: 2,
              arp_styles: %i[pingpong updown], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :pingpong, subdiv: 6, gate: 0.64, vel: 0.5 },
              fx: "chorus=0.4:0.58:30|40:0.18|0.14:0.2|0.18:0.95|1.15,lowpass=f=4200"),
  synth_patch(:questlove_moog_lead, role: :lead, program: 38, weight: 2.4, fs_gain: 1.33, gate: 0.66, octave: 1,
              arp_styles: %i[up downup], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :up, subdiv: 4, gate: 0.68, vel: 0.54 },
              fx: "lowpass=f=2800,tremolo=f=2.6:d=0.1"),
  synth_patch(:portishead_dust_lead, role: :lead, program: 4, weight: 2.2, fs_gain: 1.28, gate: 0.58, octave: 2,
              arp_styles: %i[euclidean skip_up], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :euclidean, subdiv: 8, gate: 0.68, vel: 0.42 },
              fx: "acrusher=bits=12:samples=2:mix=0.1,lowpass=f=4600"),
  synth_patch(:nord_stage_lead, role: :lead, program: 88, weight: 2.3, fs_gain: 1.3, gate: 0.62, octave: 2,
              arp_styles: %i[updown quint_spread], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :updown, subdiv: 4, gate: 0.66, vel: 0.48 },
              fx: "aecho=0.42:0.38:90|170:0.22|0.12,lowpass=f=4000"),
  synth_patch(:rhodes_skank_lead, role: :lead, program: 4, weight: 2.0, fs_gain: 1.26, gate: 0.52, octave: 2,
              arp_styles: %i[donda_stab skip_up], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :donda_stab, subdiv: 8, gate: 0.5, vel: 0.54 },
              fx: "highpass=f=220,tremolo=f=0.55:d=0.07"),
  synth_patch(:tame_wobble_lead, role: :lead, program: 81, weight: 2.0, fs_gain: 1.32, gate: 0.58, octave: 2,
              arp_styles: %i[wonky_wobble spiral], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :spiral, subdiv: 8, gate: 0.56, vel: 0.46 },
              fx: "tremolo=f=0.65:d=0.14,aphaser=speed=0.16:decay=0.5,lowpass=f=5200"),
  # --- Scale-locked arp lead (continuous, same scale as each pad chord) ---
  synth_patch(:scale_arp_prophet, role: :scale_lead, program: 81, weight: 3.2, fs_gain: 1.28, gate: 0.62,
              arp_styles: %i[updown skip_up pingpong], octave: 2, midi_fx: MIDI_FX_SCALE_LEAD,
              fx: "chorus=0.38:0.58:30|40:0.16|0.12:0.2|0.18:0.9|1.15,aecho=0.45:0.38:120|220:0.22|0.12,lowpass=f=4200"),
  synth_patch(:scale_arp_moog, role: :scale_lead, program: 38, weight: 2.8, fs_gain: 1.25, gate: 0.58,
              arp_styles: %i[up downup fibonacci], octave: 2,
              fx: "lowpass=f=3600:width_type=q:width=0.8,tremolo=f=2.8:d=0.1,aecho=0.38:0.32:100|180:0.18|0.1"),
  synth_patch(:scale_arp_rhodes, role: :scale_lead, program: 4, weight: 2.4, fs_gain: 1.3, gate: 0.55,
              arp_styles: %i[updown quint_spread spiral], octave: 2,
              fx: "tremolo=f=0.35:d=0.05,aecho=0.4:0.45:80|150:0.2|0.1,lowpass=f=4800"),
  synth_patch(:scale_arp_supersaw, role: :scale_lead, program: 0, sf2: :supersaw, weight: 1.8, fs_gain: 1.22,
              gate: 0.6, arp_styles: %i[spiral random_walk up], octave: 2,
              fx: "chorus=0.45:0.65:34|44:0.2|0.16:0.24|0.2:1.05|1.3,lowpass=f=5000"),
  # --- Native additive fallbacks (no soundfont) ---
  synth_patch(:native_rhodes, role: :native, program: 0, weight: 2.5, native: { wave: :rhodes, detune: 0.005, bloom: 0.34 }),
  synth_patch(:native_rhodes_bleeding, role: :native, program: 0, weight: 1.8, native: { wave: :rhodes, detune: 0.005, bloom: 0.42 }),
  synth_patch(:native_juno, role: :native, program: 0, native: { wave: :juno, detune: 0.006, bloom: 0.18 }),
  synth_patch(:native_prophet, role: :native, program: 0, weight: 2.2, native: { wave: :prophet, detune: 0.005, bloom: 0.26 }),
  synth_patch(:native_moog, role: :native, program: 0, weight: 2.2, native: { wave: :moog, detune: 0.005, bloom: 0.24 }),
  synth_patch(:native_fm_glass, role: :native, program: 0, weight: 2.4,
              native: { wave: :fm, detune: 0.002, bloom: 0.35, fm_index: 2.0, fm_feedback: 0.14 }),
  # --- Native FM recipes: real operator-pair patches, not GM samples ---
  # DX7 EPiano ("FullTines") is algorithm 5 -- three parallel carrier/
  # modulator pairs: two near-1:1 pairs give the mellow tine body, a third
  # at 14:1 gives the metallic click on the attack that decays out fast.
  # fm_epiano_body is used twice in stack_fm_epiano (roles :ep + :warm) so
  # the layer stack's own unison-detune step stands in for that second
  # pair; fm_epiano_bell is the 14:1 pair, mixed low and decaying in
  # under half a second (pad_release: 3.2) under the sustained body.
  synth_patch(:fm_epiano_body, role: :native, program: 0, weight: 2.4,
              native: { wave: :fm, detune: 0.004, bloom: 0.12, fm_index: 1.3, fm_feedback: 0.04,
                        fm_ratio: { m: 1.0, target_m: 1.0, irrational: false }, pad_release: 0.09 }),
  synth_patch(:fm_epiano_bell, role: :native, program: 0, weight: 1.2,
              native: { wave: :fm, detune: 0.0, bloom: 0.04, fm_index: 2.8, fm_feedback: 0.0,
                        fm_ratio: { m: 14.0, target_m: 14.0, irrational: false }, pad_release: 3.2 }),
  # Bell/shimmer pad: single pair at a high non-integer ratio -- the
  # inharmonic sidebands (not overtones of the fundamental) are what read
  # as "bell" rather than "brass." Moderate decay, longer ring than the
  # e-piano tine but not sustained like a pad.
  synth_patch(:fm_bell_pad, role: :native, program: 0, weight: 2.0,
              native: { wave: :fm, detune: 0.006, bloom: 0.18, fm_index: 2.2, fm_feedback: 0.08,
                        fm_ratio: { m: 3.5, target_m: 3.5, irrational: true }, pad_release: 0.35 }),
  # Brass: ratio near 1:1 (harmonic, not metallic) -- the classic "wah"
  # attack comes from the modulation INDEX falling from a bright peak to a
  # duller sustain, which fm_mod_envelope(role: :pad) already shapes.
  synth_patch(:fm_brass_lead, role: :native, program: 0, weight: 2.2,
              native: { wave: :fm, detune: 0.003, bloom: 0.1, fm_index: 3.4, fm_feedback: 0.1,
                        fm_ratio: { m: 1.0, target_m: 1.0, irrational: false }, pad_release: 0.15 }),
  synth_patch(:native_organ, role: :native, program: 0, native: { wave: :organ, detune: 0.003, bloom: 0.12 }),
  # :analog_pad, not :triangle. The three-oscillator detuned saw stack that
  # native_waveform_body calls "the classic warm analog pad" was unreachable —
  # no patch anywhere set wave: :analog_pad, so the one lush pad in the engine
  # was dead code. This patch asked for :triangle, which is
  # 0.62*triangle(f) + 0.20*sin(f): a single frequency, and it discards the
  # detune: it was given. Measured over 6s at 220Hz, that produced 0.08 dB of
  # amplitude movement — a static tone. The saw stack gives 4.33 dB, because
  # the beating between detuned oscillators is the sound.
  synth_patch(:native_warm_pad, role: :native, program: 0, native: { wave: :analog_pad, detune: 0.005, bloom: 0.15 }),
  synth_patch(:native_string, role: :native, program: 0, native: { wave: :bowed, detune: 0.004, bloom: 0.2 }),
  synth_patch(:native_pwm, role: :native, program: 0, native: { wave: :pwm, detune: 0.005, bloom: 0.25 }),
  # --- Experimental electronic pads (musical, not noise) ---
  synth_patch(:glass_fm_pad, role: :warm, program: 98, weight: 2.6, mix: 0.72, fs_gain: 1.38,
              midi_fx: MIDI_FX_PAD_WARM,
              # speed=0.1, not 0.08: ffmpeg's aphaser accepts [0.1, 2.0] and
              # rejects anything below it, which fails the WHOLE chain, not just
              # the phaser -- so this patch rendered with no effects at all. It
              # went unnoticed because nothing could select the voice: it is only
              # reachable through stack_glass, which was one of the 24 pad voices
              # no rotation referenced. Widening DEMO_PAD_ROTATION reached it for
              # the first time and it failed immediately, twice.
              fx: "aecho=0.48:0.42:90|170:0.28|0.14,aphaser=speed=0.1:decay=0.55,lowpass=f=5200,equalizer=f=3200:t=h:w=1600:g=1.4"),
  synth_patch(:vapor_supersaw, role: :warm, program: 0, sf2: :supersaw, weight: 2.4, mix: 0.68, fs_gain: 1.36,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "chorus=0.55:0.75:40|50:0.28|0.24:0.32|0.28:1.2|1.5,lowpass=f=4800,aecho=0.4:0.36:140|260:0.22|0.12"),
  synth_patch(:crystal_pwm, role: :warm, program: 90, weight: 2.2, mix: 0.7, fs_gain: 1.34,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "tremolo=f=0.22:d=0.06,chorus=0.4:0.58:28|38:0.16|0.12:0.2|0.16:0.95|1.2,lowpass=f=4600"),
  synth_patch(:ice_string_pad, role: :warm, program: 50, weight: 2.3, mix: 0.66, fs_gain: 1.32,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "highpass=f=180,chorus=0.48:0.68:36|46:0.22|0.18:0.26|0.22:1.1|1.35,lowpass=f=4000"),
  synth_patch(:neon_ladder, role: :warm, program: 38, weight: 2.5, mix: 0.74, fs_gain: 1.4,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "lowpass=f=2400:width_type=q:width=0.85,tremolo=f=0.18:d=0.05,equalizer=f=160:t=o:w=1:g=2.4,aecho=0.36:0.3:80|150:0.16|0.08"),
  synth_patch(:acid_pluck_lead, role: :lead, program: 38, weight: 2.2, fs_gain: 1.3, gate: 0.48, octave: 1,
              arp_styles: %i[up skip_up euclidean], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :up, subdiv: 8, gate: 0.45, vel: 0.52 },
              fx: "lowpass=f=1800:width_type=q:width=1.1,equalizer=f=400:t=o:w=1.2:g=2.0"),
  synth_patch(:glass_arp_lead, role: :lead, program: 98, weight: 2.6, fs_gain: 1.28, gate: 0.55, octave: 3,
              arp_styles: %i[spiral quint_spread pingpong], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :spiral, subdiv: 6, gate: 0.58, vel: 0.46 },
              fx: "aecho=0.5:0.44:100|190:0.28|0.14,highpass=f=400,lowpass=f=6200"),
  synth_patch(:vapor_lead, role: :lead, program: 3, sf2: :supersaw, weight: 2.3, fs_gain: 1.3, gate: 0.6, octave: 2,
              arp_styles: %i[updown wonky_wobble], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :updown, subdiv: 4, gate: 0.62, vel: 0.48 },
              fx: "chorus=0.5:0.7:38|48:0.26|0.22:0.3|0.26:1.15|1.4,lowpass=f=5000"),
  synth_patch(:crystal_scale_lead, role: :scale_lead, program: 98, weight: 2.4, fs_gain: 1.24, gate: 0.58,
              arp_styles: %i[spiral updown], octave: 2,
              fx: "aecho=0.46:0.4:110|200:0.24|0.12,lowpass=f=5400"),
  # --- Character leads (scale-locked arps + strong FX identity) ---
  synth_patch(:jupiter_superlead, role: :lead, program: 81, weight: 3.4, fs_gain: 1.42, gate: 0.58, octave: 2,
              arp_styles: %i[spiral pingpong skip_up wonky_wobble], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :spiral, subdiv: 8, gate: 0.56, vel: 0.56 },
              fx: "chorus=0.55:0.75:42|54:0.28|0.24:0.32|0.28:1.2|1.5,aecho=0.52:0.46:160|300:0.3|0.16,aphaser=speed=0.18:decay=0.48,equalizer=f=3000:t=o:w=1.4:g=3.5,lowpass=f=6800"),
  synth_patch(:obxr_sync_lead, role: :lead, program: 87, weight: 3.1, fs_gain: 1.4, gate: 0.52, octave: 2,
              arp_styles: %i[euclidean ratchet skip_up], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :euclidean, subdiv: 8, gate: 0.5, vel: 0.58 },
              fx: "tremolo=f=5.5:d=0.1,chorus=0.4:0.6:32|44:0.2|0.16:0.24|0.2:1.05|1.3,aecho=0.45:0.38:120|220:0.26|0.12,equalizer=f=2400:t=o:w=1.2:g=2.8,lowpass=f=5600"),
  synth_patch(:cs80_brass_lead, role: :lead, program: 62, weight: 2.9, fs_gain: 1.38, gate: 0.64, octave: 1,
              arp_styles: %i[major_third_cycle_full updown quint_spread], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :major_third_cycle_full, subdiv: 6, gate: 0.66, vel: 0.54 },
              fx: "vibrato=f=0.48:d=0.014,chorus=0.42:0.62:28|38:0.18|0.14:0.2|0.18:1.0|1.25,aecho=0.48:0.42:180|320:0.28|0.14,equalizer=f=1800:t=o:w=1.1:g=2.2,lowpass=f=4800"),
  synth_patch(:mono_poly_lead, role: :lead, program: 80, weight: 3.0, fs_gain: 1.4, gate: 0.55, octave: 2,
              arp_styles: %i[up skip_up burst spiral], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :up, subdiv: 8, gate: 0.52, vel: 0.56 },
              fx: "lowpass=f=3200:width_type=q:width=0.9,tremolo=f=3.2:d=0.09,aecho=0.4:0.35:100|180:0.22|0.1,equalizer=f=900:t=o:w=1:g=1.8,equalizer=f=3500:t=h:w=1.3:g=2.5"),
  synth_patch(:dx7_glass_arp, role: :lead, program: 98, weight: 3.2, fs_gain: 1.36, gate: 0.5, octave: 3,
              arp_styles: %i[spiral fibonacci quint_spread], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :spiral, subdiv: 6, gate: 0.52, vel: 0.5 },
              fx: "aecho=0.55:0.48:110|200:0.32|0.16,aphaser=speed=0.11:decay=0.55,highpass=f=420,equalizer=f=4800:t=h:w=1.4:g=2.2,lowpass=f=7200"),
  synth_patch(:jp8_brass_arp, role: :scale_lead, program: 63, weight: 3.0, fs_gain: 1.32, gate: 0.6, octave: 2,
              arp_styles: %i[updown pingpong major_third_cycle_full], midi_fx: MIDI_FX_SCALE_LEAD,
              fx: "chorus=0.5:0.7:38|48:0.24|0.2:0.28|0.24:1.15|1.4,aecho=0.46:0.4:140|260:0.26|0.14,equalizer=f=2600:t=o:w=1.3:g=3.0,lowpass=f=6000"),
  synth_patch(:sh101_sequence, role: :scale_lead, program: 38, weight: 2.9, fs_gain: 1.3, gate: 0.48, octave: 2,
              arp_styles: %i[up euclidean skip_up], midi_fx: MIDI_FX_SCALE_LEAD,
              fx: "lowpass=f=2400:width_type=q:width=1.0,aecho=0.38:0.32:80|150:0.2|0.1,equalizer=f=400:t=o:w=1.2:g=2.4,equalizer=f=2800:t=h:w=1.2:g=2.0"),

  # --- Yamaha grand (lite SF2) — acoustic piano body GM never quite nails ---
  synth_patch(:yamaha_grand, role: :ep, program: 0, sf2: :yamaha, weight: 3.0, mix: 1.15, fs_gain: 1.55,
              color: "Yamaha C grand", midi_fx: MIDI_FX_PAD_EP,
              fx: "aecho=0.32:0.38:70|130:0.18|0.08,lowpass=f=6200,equalizer=f=220:t=o:w=1:g=1.4"),
  synth_patch(:yamaha_soft_pedal, role: :ep, program: 0, bank: 1, sf2: :yamaha, weight: 2.4, mix: 1.05, fs_gain: 1.48,
              color: "soft pedal grand", midi_fx: MIDI_FX_PAD_EP,
              fx: "lowpass=f=4200,tremolo=f=0.12:d=0.02,aecho=0.4:0.45:100|180:0.2|0.1"),
  synth_patch(:yamaha_honky, role: :ep, program: 3, sf2: :yamaha, weight: 1.8, mix: 1.0, fs_gain: 1.42,
              color: "honky-tonk edge", midi_fx: MIDI_FX_PAD_EP,
              fx: "acrusher=bits=12:samples=1.5:mix=0.08,equalizer=f=2800:t=h:w=1.2:g=1.6,lowpass=f=5000"),
  synth_patch(:yamaha_ballad_lead, role: :lead, program: 0, sf2: :yamaha, weight: 2.6, fs_gain: 1.28, gate: 0.72, octave: 2,
              arp_styles: %i[updown major_third_cycle_full], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :updown, subdiv: 4, gate: 0.74, vel: 0.44 },
              fx: "aecho=0.5:0.48:160|300:0.26|0.14,lowpass=f=4800"),
  synth_patch(:yamaha_scale_arp, role: :scale_lead, program: 0, sf2: :yamaha, weight: 2.5, fs_gain: 1.22, gate: 0.6, octave: 2,
              arp_styles: %i[updown skip_up], midi_fx: MIDI_FX_SCALE_LEAD,
              fx: "aecho=0.42:0.38:90|170:0.2|0.1,lowpass=f=5000"),

  # --- VintageDreams Waves (fluid-synth bundled SF2) — rare / wave-table colour ---
  synth_patch(:vintage_dream_pad, role: :warm, program: 88, sf2: :vintage_dreams, weight: 2.8, mix: 0.72, fs_gain: 1.4,
              color: "VintageDreams warm pad", midi_fx: MIDI_FX_PAD_WARM,
              fx: "chorus=0.5:0.7:36|46:0.22|0.18:0.26|0.22:1.1|1.35,lowpass=f=4000,aecho=0.35:0.4:100|190:0.2|0.1"),
  synth_patch(:vintage_dream_ep, role: :ep, program: 4, sf2: :vintage_dreams, weight: 2.2, mix: 1.05, fs_gain: 1.5,
              color: "VintageDreams EP", midi_fx: MIDI_FX_PAD_EP,
              fx: "tremolo=f=0.3:d=0.05,lowpass=f=4600"),
  synth_patch(:vintage_dream_lead, role: :lead, program: 81, sf2: :vintage_dreams, weight: 2.4, fs_gain: 1.32, gate: 0.58, octave: 2,
              arp_styles: %i[spiral updown], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :spiral, subdiv: 8, gate: 0.56, vel: 0.5 },
              fx: "chorus=0.48:0.68:34|44:0.22|0.18:0.26|0.22:1.1|1.35,lowpass=f=5200"),
  synth_patch(:vintage_dream_bell, role: :texture, program: 98, sf2: :vintage_dreams, mix: 0.18,
              color: "VintageDreams crystal", fx: "aecho=0.5:0.55:120|220:0.28|0.14,highpass=f=400"),
  synth_patch(:vintage_dream_choir, role: :warm, program: 52, sf2: :vintage_dreams, weight: 1.6, mix: 0.4, fs_gain: 1.18,
              color: "VintageDreams choir", midi_fx: MIDI_FX_PAD_WARM,
              fx: "highpass=f=200,aecho=0.48:0.52:110|200:0.28|0.14,lowpass=f=3600"),

  # --- Giga HQ FM GM — more of the FM bank beyond fm_bowed_pad ---
  synth_patch(:giga_fm_ep, role: :ep, program: 4, sf2: :giga_fm, weight: 2.5, mix: 1.08, fs_gain: 1.52,
              color: "Giga FM Rhodes", midi_fx: MIDI_FX_PAD_EP,
              fx: "tremolo=f=0.32:d=0.05,aecho=0.38:0.42:70|130:0.22|0.1,lowpass=f=4800"),
  synth_patch(:giga_fm_bell, role: :warm, program: 98, sf2: :giga_fm, weight: 2.3, mix: 0.7, fs_gain: 1.36,
              color: "Giga FM glass bell", midi_fx: MIDI_FX_PAD_WARM,
              fx: "aecho=0.5:0.45:100|190:0.3|0.16,aphaser=speed=0.1:decay=0.55,lowpass=f=5600"),
  synth_patch(:giga_fm_lead, role: :lead, program: 81, sf2: :giga_fm, weight: 2.4, fs_gain: 1.3, gate: 0.56, octave: 2,
              arp_styles: %i[spiral fibonacci], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :spiral, subdiv: 8, gate: 0.54, vel: 0.48 },
              fx: "aecho=0.48:0.42:110|200:0.28|0.14,lowpass=f=5400"),
  synth_patch(:giga_fm_bass_lead, role: :lead, program: 38, sf2: :giga_fm, weight: 2.2, fs_gain: 1.34, gate: 0.62, octave: 1,
              arp_styles: %i[up downup], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :up, subdiv: 4, gate: 0.64, vel: 0.54 },
              fx: "lowpass=f=2200,equalizer=f=120:t=o:w=0.9:g=2.8"),
  synth_patch(:giga_fm_choir, role: :warm, program: 52, sf2: :giga_fm, weight: 1.5, mix: 0.38, fs_gain: 1.15,
              color: "Giga FM choir", fx: "highpass=f=240,lowpass=f=3400,volume=0.85"),

  # --- Supersaw collection — more than three leads ---
  synth_patch(:supersaw_pad, role: :warm, program: 1, sf2: :supersaw, weight: 2.5, mix: 0.7, fs_gain: 1.38,
              color: "Supersaw pad bed", midi_fx: MIDI_FX_PAD_WARM,
              fx: "chorus=0.55:0.75:40|50:0.28|0.24:0.32|0.28:1.2|1.5,lowpass=f=4500"),
  synth_patch(:supersaw_4, role: :lead, program: 5, sf2: :supersaw, weight: 2.0, fs_gain: 1.3, gate: 0.55, octave: 2,
              arp_styles: %i[pingpong spiral], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :pingpong, subdiv: 8, gate: 0.54, vel: 0.5 },
              fx: "chorus=0.52:0.72:38|48:0.26|0.22:0.3|0.26:1.15|1.4,lowpass=f=5800"),
  synth_patch(:supersaw_5, role: :lead, program: 9, sf2: :supersaw, weight: 1.9, fs_gain: 1.28, gate: 0.52, octave: 2,
              arp_styles: %i[euclidean skip_up], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :euclidean, subdiv: 8, gate: 0.5, vel: 0.52 },
              fx: "tremolo=f=4.2:d=0.12,aecho=0.5:0.42:150|280:0.28|0.14"),
  synth_patch(:supersaw_scale, role: :scale_lead, program: 2, sf2: :supersaw, weight: 2.2, fs_gain: 1.24, gate: 0.58, octave: 2,
              arp_styles: %i[updown spiral], midi_fx: MIDI_FX_SCALE_LEAD,
              fx: "chorus=0.48:0.68:36|46:0.24|0.2:0.28|0.24:1.1|1.35,lowpass=f=5200"),

  # --- GM programs the catalog had never opened (harmonic/world/soul colour) ---
  synth_patch(:harmonica_soul, role: :lead, program: 22, weight: 2.0, fs_gain: 1.28, gate: 0.7, octave: 2,
              arp_styles: %i[updown motif], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :updown, subdiv: 4, gate: 0.72, vel: 0.46 },
              fx: "vibrato=f=0.55:d=0.016,aecho=0.45:0.4:140|260:0.24|0.12,lowpass=f=4200"),
  synth_patch(:accordion_waltz, role: :ep, program: 21, weight: 1.6, mix: 0.95, fs_gain: 1.4,
              color: "accordion ballroom", midi_fx: MIDI_FX_PAD_EP,
              fx: "chorus=0.4:0.55:28|38:0.16|0.12:0.2|0.16:0.95|1.15,lowpass=f=4000"),
  synth_patch(:nylon_guitar_pad, role: :ep, program: 24, weight: 2.1, mix: 1.0, fs_gain: 1.45,
              color: "nylon guitar chord", midi_fx: MIDI_FX_PAD_EP,
              fx: "aecho=0.38:0.4:80|150:0.2|0.1,lowpass=f=4800"),
  synth_patch(:steel_string, role: :lead, program: 25, weight: 2.0, fs_gain: 1.26, gate: 0.55, octave: 2,
              arp_styles: %i[skip_up up], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :skip_up, subdiv: 8, gate: 0.52, vel: 0.5 },
              fx: "highpass=f=180,lowpass=f=5000,aecho=0.35:0.35:60|110:0.18|0.08"),
  synth_patch(:clean_jazz_guitar, role: :lead, program: 26, weight: 2.3, fs_gain: 1.28, gate: 0.64, octave: 2,
              arp_styles: %i[updown major_third_cycle_full], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :updown, subdiv: 4, gate: 0.68, vel: 0.48 },
              fx: "chorus=0.35:0.5:26|34:0.14|0.1:0.16|0.14:0.9|1.1,lowpass=f=4600"),
  synth_patch(:overdrive_hook, role: :lead, program: 29, weight: 1.8, fs_gain: 1.32, gate: 0.5, octave: 1,
              arp_styles: %i[donda_stab skip_up], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :donda_stab, subdiv: 8, gate: 0.48, vel: 0.56 },
              fx: "acompressor=threshold=-18dB:ratio=3.5:attack=5:release=70,lowpass=f=4000"),
  synth_patch(:slap_bass_lead, role: :lead, program: 36, weight: 2.1, fs_gain: 1.3, gate: 0.48, octave: 1,
              arp_styles: %i[up skip_up], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :up, subdiv: 8, gate: 0.46, vel: 0.54 },
              fx: "equalizer=f=180:t=o:w=1:g=2.5,highpass=f=60,lowpass=f=2800"),
  synth_patch(:synth_bass_deep, role: :lead, program: 39, weight: 2.4, fs_gain: 1.35, gate: 0.7, octave: 1,
              arp_styles: %i[up downup], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :up, subdiv: 4, gate: 0.72, vel: 0.56 },
              fx: "lowpass=f=1800:width_type=q:width=0.9,equalizer=f=90:t=o:w=0.8:g=3.2"),
  synth_patch(:tremolo_strings, role: :warm, program: 44, weight: 2.2, mix: 0.68, fs_gain: 1.34,
              color: "tremolo strings", midi_fx: MIDI_FX_PAD_WARM,
              fx: "tremolo=f=5.5:d=0.14,lowpass=f=3800,aecho=0.4:0.42:120|220:0.22|0.1"),
  synth_patch(:pizzicato_scatter, role: :lead, program: 45, weight: 2.0, fs_gain: 1.24, gate: 0.35, octave: 2,
              arp_styles: %i[skip_up euclidean], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :skip_up, subdiv: 8, gate: 0.32, vel: 0.48 },
              fx: "aecho=0.4:0.38:70|130:0.22|0.1,highpass=f=200"),
  synth_patch(:harp_gliss, role: :texture, program: 46, mix: 0.16,
              color: "harp dust", fx: "aecho=0.5:0.55:90|170:0.28|0.14,highpass=f=300"),
  synth_patch(:orchestral_harp_pad, role: :warm, program: 46, weight: 1.7, mix: 0.55, fs_gain: 1.28,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "aecho=0.48:0.5:140|260:0.26|0.12,lowpass=f=4200"),
  synth_patch(:french_horn_pad, role: :warm, program: 60, weight: 2.0, mix: 0.62, fs_gain: 1.32,
              color: "horn bed", midi_fx: MIDI_FX_PAD_WARM,
              fx: "lowpass=f=3200,aecho=0.42:0.45:160|300:0.24|0.12"),
  synth_patch(:muted_trumpet_lead, role: :lead, program: 59, weight: 2.1, fs_gain: 1.28, gate: 0.66, octave: 2,
              arp_styles: %i[major_third_cycle_full updown], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :major_third_cycle_full, subdiv: 6, gate: 0.64, vel: 0.48 },
              fx: "vibrato=f=0.42:d=0.012,lowpass=f=3600"),
  synth_patch(:trombone_soul, role: :lead, program: 57, weight: 1.9, fs_gain: 1.3, gate: 0.7, octave: 1,
              arp_styles: %i[up major_third_cycle_full], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :up, subdiv: 4, gate: 0.72, vel: 0.5 },
              fx: "lowpass=f=3000,aecho=0.4:0.4:150|280:0.22|0.1"),
  synth_patch(:english_horn, role: :lead, program: 69, weight: 1.8, fs_gain: 1.24, gate: 0.72, octave: 2,
              arp_styles: %i[updown], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :updown, subdiv: 4, gate: 0.74, vel: 0.44 },
              fx: "vibrato=f=0.5:d=0.014,lowpass=f=3400"),
  synth_patch(:bassoon_dark, role: :lead, program: 70, weight: 1.7, fs_gain: 1.26, gate: 0.7, octave: 1,
              arp_styles: %i[up], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :up, subdiv: 4, gate: 0.72, vel: 0.48 },
              fx: "lowpass=f=2400,equalizer=f=200:t=o:w=1:g=1.8"),
  synth_patch(:piccolo_spark, role: :lead, program: 72, weight: 1.6, fs_gain: 1.2, gate: 0.4, octave: 3,
              arp_styles: %i[bubble_pop skip_up], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :bubble_pop, subdiv: 16, gate: 0.28, vel: 0.4 },
              fx: "highpass=f=600,aecho=0.45:0.4:60|110:0.24|0.1"),
  synth_patch(:bottle_blow, role: :texture, program: 76, mix: 0.14,
              fx: "aecho=0.5:0.55:180|320:0.28|0.14,lowpass=f=2800"),
  synth_patch(:shakuhachi_breath, role: :lead, program: 77, weight: 2.0, fs_gain: 1.26, gate: 0.75, octave: 2,
              arp_styles: %i[updown spiral], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :updown, subdiv: 4, gate: 0.78, vel: 0.42 },
              fx: "vibrato=f=0.6:d=0.02,aecho=0.55:0.5:200|360:0.3|0.16,lowpass=f=3800"),
  synth_patch(:ocarina_folk, role: :lead, program: 79, weight: 1.7, fs_gain: 1.22, gate: 0.6, octave: 3,
              arp_styles: %i[up skip_up], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :up, subdiv: 8, gate: 0.58, vel: 0.44 },
              fx: "aecho=0.42:0.4:90|160:0.22|0.1,lowpass=f=5000"),
  synth_patch(:sitar_drone, role: :lead, program: 104, weight: 2.0, fs_gain: 1.28, gate: 0.7, octave: 2,
              arp_styles: %i[spiral major_third_cycle_full], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :spiral, subdiv: 6, gate: 0.68, vel: 0.46 },
              fx: "aecho=0.5:0.48:130|240:0.28|0.14,lowpass=f=4200"),
  synth_patch(:shamisen_pluck, role: :lead, program: 106, weight: 1.9, fs_gain: 1.24, gate: 0.42, octave: 2,
              arp_styles: %i[skip_up euclidean], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :skip_up, subdiv: 8, gate: 0.4, vel: 0.5 },
              fx: "highpass=f=200,aecho=0.35:0.35:50|90:0.2|0.1"),
  synth_patch(:fiddle_reel, role: :lead, program: 110, weight: 1.8, fs_gain: 1.26, gate: 0.55, octave: 2,
              arp_styles: %i[updown skip_up], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :updown, subdiv: 8, gate: 0.52, vel: 0.48 },
              fx: "vibrato=f=0.7:d=0.015,lowpass=f=4800"),
  synth_patch(:steel_drums, role: :lead, program: 114, weight: 2.0, fs_gain: 1.26, gate: 0.5, octave: 2,
              arp_styles: %i[skip_up pingpong], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :skip_up, subdiv: 8, gate: 0.48, vel: 0.46 },
              fx: "aecho=0.45:0.42:100|180:0.26|0.12,lowpass=f=5600"),
  synth_patch(:tinkle_bell, role: :texture, program: 112, mix: 0.12,
              fx: "aecho=0.55:0.5:80|150:0.3|0.15,highpass=f=800"),
  synth_patch(:agogo_perc, role: :texture, program: 113, mix: 0.1,
              fx: "highpass=f=600,aecho=0.3:0.3:40|80:0.15|0.08"),
  synth_patch(:taiko_thud, role: :texture, program: 116, mix: 0.14,
              fx: "lowpass=f=800,equalizer=f=80:t=o:w=0.8:g=3"),
  synth_patch(:synth_drum_texture, role: :texture, program: 118, mix: 0.12,
              fx: "acrusher=bits=10:samples=2:mix=0.2,lowpass=f=2400"),
  synth_patch(:seashore_bed, role: :texture, program: 122, mix: 0.08,
              fx: "highpass=f=200,lowpass=f=4000,volume=0.6"),
  synth_patch(:breath_noise, role: :texture, program: 121, mix: 0.1,
              fx: "highpass=f=400,lowpass=f=3000,volume=0.55"),

  # --- Galaxy EP banks 5–8 (more of the bank already on disk) ---
  synth_patch(:galaxy_ep3, role: :ep, program: 4, bank: 5, sf2: :galaxy, weight: 2.1, mix: 1.1, fs_gain: 1.55,
              color: "Galaxy EP bank5", midi_fx: MIDI_FX_PAD_EP,
              fx: "tremolo=f=0.28:d=0.06,lowpass=f=4600"),
  synth_patch(:galaxy_ep4, role: :ep, program: 5, bank: 6, sf2: :galaxy, weight: 2.0, mix: 1.08, fs_gain: 1.52,
              color: "Galaxy EP bank6", midi_fx: MIDI_FX_PAD_EP,
              fx: "chorus=0.4:0.58:30|40:0.18|0.14:0.22|0.18:0.95|1.2,lowpass=f=4800"),
  synth_patch(:galaxy_lead, role: :lead, program: 4, bank: 2, sf2: :galaxy, weight: 2.3, fs_gain: 1.3, gate: 0.6, octave: 2,
              arp_styles: %i[skip_up updown], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :skip_up, subdiv: 8, gate: 0.58, vel: 0.48 },
              fx: "tremolo=f=0.3:d=0.04,aecho=0.42:0.4:90|160:0.22|0.1,lowpass=f=5000"),

  # ------------------------------------------------------- Nordic downtempo
  #
  # The third of the reference records had no patches at all. Dilla is covered
  # by the Rhodes and Moog families and Flying Lotus by four FM voices, but the
  # Melody A.M. palette -- Juno-106, a string ensemble, a vocoder and soft FM --
  # had nothing named for it, so a track reaching for that sound landed on a
  # Rhodes and a supersaw.
  #
  # These are the instruments, not transcriptions: what separates that record
  # from generic downtempo is that its pads are bucket-brigade chorus rather
  # than digital, its strings are a divide-down ensemble rather than sampled
  # strings, and its top end is FM bell rather than a filtered saw.

  # JUNO-106 held pad, the bed the whole record sits on. Two chorus stages
  # rather than one: the giveaway of a bucket-brigade line is that it detunes
  # unevenly and carries its own noise, which one clean chorus cannot fake.
  # Rolled at 6.8 kHz because the Juno's own VCF never had much above that.
  synth_patch(:royksopp_melody_pad, role: :warm, program: 89, weight: 2.7, mix: 0.9, fs_gain: 1.34,
              color: "Juno-106 chorus II bed", midi_fx: MIDI_FX_PAD_WARM,
              fx: "chorus=0.62:0.82:26|34:0.44|0.39:0.30|0.26:1.35|1.85," \
                  "chorus=0.7:0.5:11:0.22:0.18:0.6," \
                  "equalizer=f=300:t=q:w=1.4:g=2.0,highpass=f=80,lowpass=f=6800,volume=0.93"),

  # Solina-style divide-down string ensemble. A string machine is not strings:
  # every note comes off one master oscillator divided down, so the chorus is
  # the instrument rather than an effect on it. Three delay taps at once is what
  # gives the ensemble its width; the 160 Hz highpass keeps it from fighting the
  # pad, which is the mistake that makes stacked pads muddy.
  synth_patch(:royksopp_solina_strings, role: :texture, program: 48, weight: 2.2, mix: 0.82, fs_gain: 1.28,
              color: "divide-down ensemble",
              fx: "chorus=0.68:0.88:14|21|29:0.5|0.45|0.4:0.34|0.30|0.27:1.05|1.55|2.15," \
                  "highpass=f=160,equalizer=f=2200:t=q:w=1.8:g=2.2,lowpass=f=5200,volume=0.88"),

  # Vocoder wash. No carrier/modulator pair here, so this is the formant half of
  # the effect: three resonant peaks near the vowel formants over a soft voice
  # program. It reads as a choir that is almost speaking, which is the useful
  # part in a bed; a real vocoder needs a modulator the renderer does not have.
  synth_patch(:royksopp_vocoder_wash, role: :texture, program: 54, weight: 1.9, mix: 0.76, fs_gain: 1.22,
              color: "formant wash",
              fx: "equalizer=f=520:t=q:w=1.1:g=4.5,equalizer=f=1480:t=q:w=1.3:g=3.6," \
                  "equalizer=f=2520:t=q:w=1.5:g=2.8,chorus=0.5:0.7:19|27:0.3|0.26:0.24|0.2:0.9|1.4," \
                  "highpass=f=200,lowpass=f=6000,volume=0.8"),

  # Soft FM bell for the top line. Frequency modulation, so the attack is a
  # glassy partial that no filtered saw produces -- lifted at 3.2 kHz and hollowed
  # at 500 Hz, which is where an FM bell differs from a struck one. Short echo
  # only; long tails on a bell turn the arpeggio to porridge.
  synth_patch(:royksopp_glass_bell, role: :lead, program: 11, weight: 2.1, mix: 0.95, fs_gain: 1.3,
              gate: 0.55, octave: 3, arp_styles: %i[up updown], midi_fx: MIDI_FX_LEAD,
              color: "FM bell top line",
              fx: "equalizer=f=3200:t=q:w=1.2:g=4.2,equalizer=f=500:t=q:w=1.4:g=-3.0," \
                  "aecho=0.5:0.42:110|190:0.2|0.12,lowpass=f=9000"),

  # Filtered analogue pulse bass. The movement is a slow resonant peak walking
  # with the cutoff rather than a static lowpass, which is the difference between
  # a synth bass that breathes and one that sits still. asubboost restores the
  # fundamental the highpass in the chorus stage above would otherwise thin.
  synth_patch(:royksopp_filter_pulse, role: :bass, program: 38, weight: 2.4, mix: 1.0, fs_gain: 1.4,
              octave: 1, color: "resonant pulse bass",
              fx: "equalizer=f=180:t=q:w=1.1:g=3.4,lowpass=f=1400," \
                  "asubboost=dry=0.9:wet=0.45:decay=0.7:feedback=0.6:cutoff=85,volume=0.95"),
].freeze

SYNTH_PATCH_BY_ROLE = SYNTH_PATCH_CATALOG.group_by { |p| p[:role] }.freeze
SYNTH_PATCH_BY_ID = SYNTH_PATCH_CATALOG.each_with_object({}) { |p, h| h[p[:id]] = p }.freeze

# --- was patch_pools.rb -----------------------------------------------

#
# Patch pools and the timbre filters that keep flutes, choirs and metal out.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# GM chromatic percussion is struck metal — celesta, glockenspiel, music box,
# vibraphone, marimba, xylophone, tubular bells — and 94 is literally "metallic
# pad", 98 "crystal", 103 "FX 8 (sci-fi)". None of them belong in a Rhodes /
# Moog / Prophet record.
#
# 16 is deliberately absent: that is the drawbar organ, and a Hammond is not
# what anyone means by metallic. Excluding it would have cost stevie_organ_lead
# for no reason.
METALLIC_PROGRAMS = [9, 10, 11, 12, 13, 14, 15, 94, 98, 99, 103].freeze

def smooth_analog? = ENV.fetch("SMOOTH_ANALOG", "1") != "0"

def metallic_patch?(patch) = patch && METALLIC_PROGRAMS.include?(patch[:program])

# The GM pipe family: flute, recorder, pan flute, blown bottle, shakuhachi,
# whistle, ocarina. Operator, 2026-08-11: no flutes, skip those parts of the
# song -- so this rejects the whole family rather than the two patches whose
# names happen to say flute. ethnic_flute is a pan flute at 75 and would have
# survived an id-based list, and so would anything added later that is a flute
# without being called one.
PIPE_GM_PROGRAMS = (72..79).freeze

def flutes_allowed? = ENV["FLUTES"] == "1"

def flute_patch?(patch) = patch && PIPE_GM_PROGRAMS.include?(patch[:program])

# Same rule as reject_choral above: filter, but never down to an empty pool.
def reject_flutes(pool)
  return pool if flutes_allowed? || pool.empty?

  grounded = pool.reject { |p| flute_patch?(p) }
  grounded.empty? ? pool : grounded
end

# The backstop, at the only point that cannot be routed around: the byte that
# becomes a MIDI program change. Every FluidSynth voice in this engine passes
# through one of the three 0xC0 sites, so a flute that survives every pool
# filter still cannot reach the soundfont.
#
# This exists because filtering the pools was not enough twice. There are nine
# pipe-family patches and only three say flute in their name -- jazz_ballad_lead
# is program 73, and so are whistle_hook, piccolo_spark, shakuhachi_breath and
# ocarina_folk in their own registers. mellotron_flute_pad is also referenced
# directly as a texture rather than drawn from a pool, so no pool filter would
# ever have seen it.
#
# 89 is Pad 2 (warm), already in WARM_PAD_GM_PROGRAMS. A pipe patch is usually
# doing something soft and high, and a warm pad is the substitution least likely
# to turn into a harsh stab where a breathy line belongs.
NONFLUTE_SUBSTITUTE_PROGRAM = 89

def nonflute_program(program)
  prog = program.to_i
  return prog if flutes_allowed? || !PIPE_GM_PROGRAMS.include?(prog)

  @flute_substitutions = (@flute_substitutions || 0) + 1
  NONFLUTE_SUBSTITUTE_PROGRAM
end

def pick_patch_from_pool(pool, seed: 0)
  ids = Array(pool).compact.uniq
  return if ids.empty?

  # Filtered, but never to nothing. A pool that is entirely metallic still has
  # to return a patch — dropping to nil here would silence the voice rather than
  # change its colour, which is a worse outcome than one bright preset.
  if smooth_analog?
    warm = ids.reject { |i| metallic_patch?(synth_patch_by_id(i)) }
    ids = warm unless warm.empty?
  end
  unless choral_pads_allowed?
    grounded = ids.reject { |i| choral_patch?(synth_patch_by_id(i) || {}) }
    ids = grounded unless grounded.empty?
  end
  unless flutes_allowed?
    unpiped = ids.reject { |i| flute_patch?(synth_patch_by_id(i) || {}) }
    ids = unpiped unless unpiped.empty?
  end

  rng = Random.new(patch_cycle_seed(seed))
  synth_patch_by_id(ids[rng.rand(ids.length)])
end

def lush_synth_pools?
  ENV.fetch("LUSH_SYNTH", "1") != "0"
end

def ep_patch_pool(voice)
  lush_synth_pools? ? (LUSH_PATCH_CYCLE_EP[voice] || PATCH_CYCLE_EP[voice]) : PATCH_CYCLE_EP[voice]
end

def warm_patch_pool(voice)
  lush_synth_pools? ? (LUSH_PATCH_CYCLE_WARM[voice] || PATCH_CYCLE_WARM[voice]) : PATCH_CYCLE_WARM[voice]
end

def lead_patch_pool(voice)
  lush_synth_pools? ? (LUSH_LEAD_VOICE_POOLS[voice] || LEAD_VOICE_POOLS[voice]) : LEAD_VOICE_POOLS[voice]
end

def apply_lead_voice_preset!(seed: 0)
  voice = ENV["LEAD_VOICE"]&.downcase&.to_sym
  return unless voice
  if synth_cycle_enabled? && lead_patch_pool(voice)
    @render_lead_patch = pick_patch_from_pool(lead_patch_pool(voice), seed: seed + 41) ||
                        synth_patch_by_id(LEAD_VOICE_PRESETS[voice])
  else
    id = LEAD_VOICE_PRESETS[voice]
    @render_lead_patch = synth_patch_by_id(id) if id
  end
end

def apply_pad_voice_preset!(seed: 0)
  voice = ENV["PAD_VOICE"]&.downcase&.to_sym
  # Multi-layer stacks pin patches from PAD_LAYER_STACKS (rendered together).
  if voice && PAD_LAYER_STACKS[voice] && ENV.fetch("PAD_LAYERS", "1") != "0"
    stack = PAD_LAYER_STACKS[voice]
    @render_ep_patch = prefer_galaxy_ep(synth_patch_by_id(stack[0][:id])) if stack[0]
    @render_warm_patch = synth_patch_by_id(stack[1][:id]) if stack[1]
    @render_warm2_patch = synth_patch_by_id(stack[2][:id]) if stack[2]
    @render_texture_patch = synth_patch_by_id(stack[3][:id]) if stack[3]
    @render_skip_warm_pad = false
    return
  end
  if voice && PAD_VOICE_PRESETS[voice]
    preset = PAD_VOICE_PRESETS[voice]
    if pad_synth_cycle_enabled? && !PAD_LAYER_STACKS.key?(voice)
      ep_pool = ep_patch_pool(voice)
      warm_pool = warm_patch_pool(voice)
      if ep_pool&.any?
        @render_ep_patch = prefer_galaxy_ep(pick_patch_from_pool(ep_pool, seed:) ||
                                            synth_patch_by_id(preset[:ep]))
      elsif preset[:ep]
        @render_ep_patch = prefer_galaxy_ep(synth_patch_by_id(preset[:ep]))
      end
      if warm_pool&.any?
        @render_warm_patch = pick_patch_from_pool(warm_pool, seed: seed + 17)
        @render_skip_warm_pad = @render_warm_patch.nil?
      elsif preset[:warm]
        @render_warm_patch = synth_patch_by_id(preset[:warm])
        @render_skip_warm_pad = false
      else
        @render_skip_warm_pad = true
      end
      @render_warm2_patch = synth_patch_by_id(preset[:warm2]) if preset[:warm2]
    else
      @render_ep_patch = prefer_galaxy_ep(synth_patch_by_id(preset[:ep])) if preset[:ep]
      @render_warm_patch = synth_patch_by_id(preset[:warm]) if preset[:warm]
      @render_warm2_patch = synth_patch_by_id(preset[:warm2]) if preset[:warm2]
      @render_skip_warm_pad = preset[:warm].nil?
    end
    return
  end
  # Soul defaults: Rhodes + Moog + Prophet stack
  return if ENV["CREEPY_PATCHES"] == "1"
  @render_ep_patch = prefer_galaxy_ep(synth_patch_by_id(:rhodes_cafe_warm))
  @render_warm_patch = synth_patch_by_id(:moog_model_d)
  @render_warm2_patch = synth_patch_by_id(:prophet_5_pad)
  @render_skip_warm_pad = false
end

# Soulful EP/pad palette — no voices, supersaws, music boxes, or horror textures.
BEAUTIFUL_PATCH_IDS = {
  ep: PATCH_CYCLE_EP.values.flatten.uniq,
  warm: PATCH_CYCLE_WARM.values.flatten.uniq,
  scale_lead: PATCH_CYCLE_SCALE_LEAD,
  lead: LEAD_VOICE_POOLS.values.flatten.uniq,
  texture: PATCH_CYCLE_TEXTURE,
  native: %i[
    native_rhodes native_rhodes_bleeding native_juno native_prophet native_moog
    native_fm_glass native_organ native_warm_pad native_string native_pwm
  ],
}.freeze

# Experimental but musical leads — Wonky/Prophet/Moog/FM; not horror/novelty.
EXPERIMENTAL_LEAD_IDS = {
  lead: (LEAD_VOICE_POOLS.values.flatten + %i[
    jupiter_superlead obxr_sync_lead cs80_brass_lead mono_poly_lead dx7_glass_arp
    fifths_lead saw_lead supersaw_1 supersaw_2 prophet_bleeding_lead tame_wobble_lead
  ]).uniq,
  scale_lead: PATCH_CYCLE_SCALE_LEAD,
}.freeze

CREEPY_PATCH_IDS = %i[
  space_voice reverse_pad_ghost voice_lead whistle_hook charang_bite supersaw_1 supersaw_2
  supersaw_3 scale_arp_supersaw scale_arp_prophet prophet_bleeding_lead music_box fm_lead_bell
  dist_guitar banjo_pluck koto_pluck brass_synth square_lead ethnic_flute kalimba_dust
  choir_aahs voice_oohs bowed_glass harpsi_pluck
].freeze

def lead_patch_allowlist(role)
  return if ENV["CREEPY_PATCHES"] == "1"
  base = BEAUTIFUL_PATCH_IDS[role] || []
  if experimental_leads_enabled? && EXPERIMENTAL_LEAD_IDS[role]
    (base + EXPERIMENTAL_LEAD_IDS[role]).uniq
  else
    base
  end
end

# The General MIDI programs that are a CHOIR. Not strings, not horns.
#
# The first version of this list ran from 44 to 62 and took the string
# ensembles, the harp and the french horn out with the choirs. That was an
# overcorrection and it cost the thing it was protecting: strings are how a
# chord becomes beautiful, and removing them left the pads with nothing to be
# lush with. The complaint that followed -- no more beautiful chords -- was
# caused by this line.
#
# What actually made the tracks sound like a church was two things together: a
# literal Choir Aahs patch, and a nine-hundred-millisecond attack swelling under
# it. The envelope was the larger half. With that fixed, strings are welcome.
#
# So the list is now only the voices: Choir Aahs, Voice Oohs, Synth Voice, and
# the named choir patches caught by the same programs. Set CHORAL_PADS=1 to
# allow even those.
CHORAL_GM_PROGRAMS = [52, 53, 54].freeze

def choral_patch?(patch)
  CHORAL_GM_PROGRAMS.include?(patch[:program])
end

def choral_pads_allowed?
  ENV["CHORAL_PADS"] == "1"
end

# Filters a pool of patches, never down to nothing -- the same rule the other
# filters here follow, because an empty pool is a crash and a slightly wrong
# patch is a Tuesday.
def reject_choral(pool)
  return pool if choral_pads_allowed? || pool.empty?

  grounded = pool.reject { |p| choral_patch?(p) }
  grounded.empty? ? pool : grounded
end

def weighted_patch_pick(role, seed: nil, soulful: true)
  pool = SYNTH_PATCH_BY_ROLE.fetch(role, [])
  return if pool.empty?
  if soulful && ENV["CREEPY_PATCHES"] != "1"
    allowed = %i[lead scale_lead].include?(role) ? lead_patch_allowlist(role) : BEAUTIFUL_PATCH_IDS[role]
    if allowed&.any?
      pool = pool.select { |p| allowed.include?(p[:id]) }
      pool = SYNTH_PATCH_BY_ROLE.fetch(role, []).select { |p| allowed.include?(p[:id]) } if pool.empty?
    end
    pool = pool.reject { |p| CREEPY_PATCH_IDS.include?(p[:id]) }
  end
  # The metallic filter has to be here too, not only in pick_patch_from_pool.
  # This is a second, independent selection path — it is how crystal_scale_lead
  # kept being chosen after the pool filter went in. Same fallback rule: filter,
  # but never down to an empty pool.
  if smooth_analog?
    warm = pool.reject { |p| metallic_patch?(p) }
    pool = warm unless warm.empty?
  end
  # Both selection paths, for the reason the comment above gives: a filter
  # applied to only one of them is a filter that does not work.
  pool = reject_choral(pool)
  pool = reject_flutes(pool)
  return if pool.empty?
  rng = Random.new(seed || @render_seed || rand(1_000_000))
  total = pool.sum { |p| p[:weight] || 1.0 }
  roll = rng.rand * total
  pool.each do |patch|
    roll -= (patch[:weight] || 1.0)
    return patch if roll <= 0
  end
  pool.last
end

def pick_synth_patches!(cfg, bar: 0, n_bars: nil)
  seed = (stable_hash(cfg[:track].to_s) % 100_000) + (@render_seed || 0) +
         (pad_synth_cycle_enabled? ? (@stream_iterate_count || 0) * 997 + bar * 13 : 0)
  @render_skip_warm_pad = false
  roles = nil
  if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
    section = @composition_session.section_at(bar)
    roles = @composition_session.ensemble_roles(section)
  end
  pick_role = ->(role) { roles.nil? || roles.include?(role) }
  if pick_role.call(:ep) || pick_role.call(:warm)
    apply_pad_voice_preset!(seed:)
  end
  unless ENV["PAD_VOICE"] || ENV["CREEPY_PATCHES"] == "1"
    @render_ep_patch = weighted_patch_pick(:ep, seed:) if pick_role.call(:ep) && !@render_ep_patch
    @render_warm_patch = weighted_patch_pick(:warm, seed: seed + 17) if pick_role.call(:warm) && !@render_warm_patch
  end
  @render_texture_patch = nil
  if pad_texture_enabled? && pick_role.call(:texture)
    @render_texture_patch = weighted_patch_pick(:texture, seed: seed + 29)
  end
  apply_lead_voice_preset!(seed:) if ENV["LEAD_VOICE"] && !ENV["LEAD_VOICE"].empty?
  @render_lead_patch = weighted_patch_pick(:lead, seed: seed + 41) if pick_role.call(:lead) && !@render_lead_patch
  if pick_role.call(:scale_lead)
    @render_scale_lead_patch = weighted_patch_pick(:scale_lead, seed: seed + 79) ||
                               weighted_patch_pick(:lead, seed: seed + 79)
  end
  voice = ENV["PAD_VOICE"]&.downcase
  native_id = case voice
              when "moog" then :native_moog
              when "prophet" then :native_prophet
              when "rhodes", "blend", nil then :native_rhodes
              else nil
              end
  @render_native_patch = (native_id && synth_patch_by_id(native_id)) ||
                         weighted_patch_pick(:native, seed: seed + 53)
  @render_ep_patch ||= weighted_patch_pick(:ep, seed:)
  @render_warm_patch ||= weighted_patch_pick(:warm, seed: seed + 17)
  @render_lead_patch ||= weighted_patch_pick(:lead, seed: seed + 41)
  @render_scale_lead_patch ||= weighted_patch_pick(:scale_lead, seed: seed + 79) ||
                               weighted_patch_pick(:lead, seed: seed + 79)
  @render_arp_style = (@render_lead_patch&.dig(:arp_styles) || [:updown]).sample(random: Random.new(seed + 67))
  @render_scale_arp_style = (@render_scale_lead_patch&.dig(:arp_styles) || [:updown]).sample(random: Random.new(seed + 83))
end

def patch_sf2_path(sf2_key)
  cache = File.expand_path("~/.cache/dilla-soundfonts")
  case sf2_key
  when :galaxy
    File.join(cache, "galaxy-electric-pianos.sf2")
  when :supersaw
    File.join(cache, "supersaw-collection.sf2")
  when :giga_fm
    File.join(cache, "giga-hq-fm-gm.sf2")
  when :yamaha
    File.join(cache, "yamaha-grand-lite.sf2")
  when :vintage_dreams
    # Prefer a copy under the dilla cache (symlinked by fetch_assets!); else
    # fluid-synth's Homebrew-bundled test bank (public domain-ish demo SF2).
    cached = File.join(cache, "VintageDreamsWaves-v2.sf2")
    return cached if File.exist?(cached)

    Dir.glob("/opt/homebrew/Cellar/fluid-synth/*/share/fluid-synth/sf2/VintageDreamsWaves-v2.sf2").first ||
      Dir.glob("/usr/local/Cellar/fluid-synth/*/share/fluid-synth/sf2/VintageDreamsWaves-v2.sf2").first ||
      cached
  else
    pad_soundfont_path
  end
end

EXTERNAL_SF2_KEYS = %i[galaxy supersaw giga_fm yamaha vintage_dreams].freeze

def patch_voice_for(patch)
  return unless patch
  sf2 = patch[:sf2]
  path = if EXTERNAL_SF2_KEYS.include?(sf2)
           p = patch_sf2_path(sf2)
           File.exist?(p) ? p : pad_soundfont_path
         else
           pad_soundfont_path
         end
  { sf2: path, bank: patch[:bank], program: patch[:program], patch: }
end

# --- was patch_select.rb ----------------------------------------------

#
# Patch lookup, arp modes, and the morph voice/patch choices per chord.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

def synth_patch_by_id(id)
  SYNTH_PATCH_BY_ID[id]
end

def galaxy_ep_available?
  File.exist?(patch_sf2_path(:galaxy))
end

GALAXY_EP_SUBSTITUTES = %i[
  rhodes_mark1 rhodes_stage73 rhodes_tine_wurli rhodes_cafe_warm
  rhodes_vintage_tape rhodes_bleeding_edge rhodes_dx_blend
].freeze

# Presets that name a specific instrument on purpose — the substitution below
# would defeat the reason they exist.
GALAXY_EP_EXEMPT_VOICES = %i[rhodes_solo pad_madlib].freeze

def prefer_galaxy_ep(patch)
  return patch unless patch && galaxy_ep_available?
  # Patches already bound to :galaxy keep their bank/program; only GM-default
  # Rhodes ids get promoted to galaxy_ep1 when the bank is present.
  return patch if patch[:sf2] == :galaxy
  return patch unless GALAXY_EP_SUBSTITUTES.include?(patch[:id])
  # An explicitly chosen pad voice keeps the EP it names.
  #
  # This swap fires whenever the Galaxy soundfont is installed, so
  # PAD_VOICE=prophet (rhodes_mark1) and PAD_VOICE=rhodes silently rendered
  # galaxy_ep1 instead. Fine as a default upgrade; not fine as an override of
  # what was asked for — and fatal for pad_madlib, whose entire content is
  # "a Fender Rhodes Stage 73 and nothing else".
  return patch if GALAXY_EP_EXEMPT_VOICES.include?(ENV["PAD_VOICE"]&.downcase&.to_sym)
  return patch if USER_PINNED_ENV.key?("PAD_VOICE") && ENV["PAD_VOICE"] == USER_PINNED_ENV["PAD_VOICE"]

  synth_patch_by_id(:galaxy_ep1)
end

def pad_texture_enabled?
  # Style DNA defaults PAD_TEXTURE on; fetch default matches BEST/STYLE tables.
  ENV.fetch("PAD_TEXTURE", "1") == "1"
end

def experimental_leads_enabled?
  ENV.fetch("EXPERIMENTAL_LEADS", "1") != "0"
end

# Arp figure presets — PAD_ARP_MODE selects the lead-arp character; chord pads
# (EP/warm) always render held. Former per-layer routing (arp on Rhodes/Moog
# pads) moved to lead_arp.wav so pads stay lush and the figure sits up top.
PAD_ARP_LAYER_MODES = {
  held:   { ep: :held,    warm: :held },
  shimmer: { ep: :shimmer, warm: :held },
  pulse:  { ep: :held,    warm: :arp },
  blend:  { ep: :shimmer, warm: :arp },
  duo:    { ep: :arp,     warm: :arp },
  wash:   { ep: :held,    warm: :arp },
  figure: { ep: :arp,     warm: :held },
}.freeze

PAD_ARP_PRESETS = {
  ep_shimmer: { style: :skip_up, subdiv: 8, gate: 0.78, vel: 0.16,
                arp_styles: %i[skip_up euclidean quint_spread] },
  ep_figure:  { style: :fibonacci, subdiv: 6, gate: 0.74, vel: 0.22,
                arp_styles: %i[fibonacci spiral major_third_cycle_full] },
  warm_pulse: { style: :updown, subdiv: 4, gate: 0.86, vel: 0.24,
                arp_styles: %i[updown pingpong] },
  warm_wash:  { style: :pingpong, subdiv: 3, gate: 0.9, vel: 0.28,
                arp_styles: %i[pingpong major_third_cycle_full quint_spread] },
  warm_moog:  { style: :up, subdiv: 4, gate: 0.88, vel: 0.26,
                arp_styles: %i[up downup quint_spread] },
}.freeze

# NO_ARP=1 wins over everything, including a preset.
#
# PAD_ARP was only ever a fallback: this reads ENV["PAD_ARP_MODE"] first, which
# is what the style presets write, so setting PAD_ARP=held did nothing on the 48
# of 53 presets that name a mode — wash on 25, shimmer on 9, pulse on 6, figure
# and duo on 3 each. Only 5 are held. An operator asking for no arpeggiators was
# being overruled by the table, silently, on almost every track.
#
# Forcing :held here also stops the lead arp: lead_arp_mode is
# PAD_TO_LEAD_ARP[pad_arp_mode], and lead_arp_preset_key only reaches the legacy
# path when pad_arp_mode != :held. One switch, both layers, which is what "stop
# using arpeggiators" has to mean.
# Default ON. This was added when arpeggiators were asked to stop and then
# left opt-in, which meant the 48 presets that write PAD_ARP_MODE went
# straight back to arpeggiating. NO_ARP=0 restores them.
def no_arp? = ENV.fetch("NO_ARP", "1") != "0"

def pad_arp_mode
  return :held if no_arp?

  raw = ENV["PAD_ARP_MODE"]&.downcase
  sym = raw&.to_sym
  return sym if sym && PAD_ARP_LAYER_MODES.key?(sym)
  return :blend if ENV.fetch("PAD_CHORD_ARP", "0") != "0"
  fallback = (ENV["PAD_ARP"] || "held").to_s.downcase.to_sym
  PAD_ARP_LAYER_MODES.key?(fallback) ? fallback : :held
end

def lead_arp_mode
  raw = ENV["LEAD_ARP_MODE"]&.downcase
  sym = raw&.to_sym
  return sym if sym && LEAD_ARP_PRESETS.key?(sym)
  PAD_TO_LEAD_ARP[pad_arp_mode]
end

def lead_arp_preset_key
  lead_arp_mode ||
    (lead_arp_preset_for_pad_mode_legacy if pad_arp_mode != :held)
end

# Legacy PAD_ARP_MODE → PAD_ARP_PRESETS key (fallback when LEAD_ARP_MODE unset).
def lead_arp_preset_for_pad_mode_legacy(mode = nil)
  mode ||= pad_arp_mode
  case mode
  when :held then nil
  when :shimmer then :ep_shimmer
  when :pulse then :warm_pulse
  when :blend then :warm_pulse
  when :duo then :ep_figure
  when :wash then :warm_wash
  when :figure then :ep_figure
  else :warm_pulse
  end
end

def synth_cycle_enabled?
  ENV.fetch("SYNTH_CYCLE", "1") != "0"
end

def synth_morph_enabled?
  return false if ENV["SYNTH_MORPH"] == "0"
  return true if ENV["SYNTH_MORPH"] == "1"
  ENV["STREAM_SOUL"] == "1" || stream_iterate_enabled?
end

def pad_synth_cycle_enabled?
  synth_cycle_enabled? || synth_morph_enabled?
end

def morph_voice_at(event_idx)
  voices = PAD_VOICE_MORPH_VOICES
  base = ENV["PAD_VOICE"]&.downcase&.to_sym
  offset = voices.index(base) || 0
  voices[(offset + event_idx) % voices.length]
end

def morph_patch_pool(role:, voice:)
  pool = role == :ep ? ep_patch_pool(voice) : warm_patch_pool(voice)
  return pool unless role == :ep && synth_morph_enabled?
  Array(pool).reject { |id| id.to_s.start_with?("galaxy_") }
end

def morph_patch_for_chord(event_idx, role:)
  voice = morph_voice_at(event_idx)
  pool = morph_patch_pool(role:, voice:)
  preset = PAD_VOICE_PRESETS[voice] || PAD_VOICE_PRESETS[:moog]
  fallback_id = role == :ep ? preset[:ep] : preset[:warm]
  pick_patch_from_pool(pool, seed: event_idx * 311 + (role == :ep ? 0 : 17)) ||
    (fallback_id && synth_patch_by_id(fallback_id))
end

def lead_morph_enabled?
  return false if ENV["LEAD_MORPH"] == "0"
  return true if ENV["LEAD_MORPH"] == "1"
  synth_morph_enabled?
end

def morph_lead_voice_at(event_idx)
  voices = LEAD_MORPH_VOICES
  base = (ENV["LEAD_MORPH_VOICE"] || ENV["LEAD_VOICE"])&.downcase&.to_sym
  offset = voices.index(base) || 0
  voices[(offset + event_idx) % voices.length]
end

def morph_lead_patch_for_chord(event_idx)
  voice = morph_lead_voice_at(event_idx)
  pool = Array(MORPH_LEAD_PATCH_POOL[voice] || MORPH_LEAD_PATCH_POOL[:hard])
              .reject { |id| (p = synth_patch_by_id(id)) && p[:sf2] != :default }
  pick_patch_from_pool(pool, seed: event_idx * 503 + 91) || synth_patch_by_id(:saw_lead)
end

def morph_lead_arp_cfg_for_chord(event_idx, patch)
  preset_key = MORPH_LEAD_ARP_CYCLE[event_idx % MORPH_LEAD_ARP_CYCLE.length]
  base = EXPERIMENTAL_LEAD_ARP_PRESETS[preset_key]&.dup ||
         LEAD_ARP_PRESETS[:wonky_spiral]&.dup ||
         { style: :spiral, subdiv: 8, gate: 0.52, vel: 0.56, arp_styles: %i[spiral wonky_wobble] }
  styles = (base[:arp_styles] || []) + arp_styles_for_patch(patch, base[:style])
  base.merge(arp_styles: styles.uniq)
end

# Process.pid in the seed makes every render pick different patches, which is
# good for a stream that should not repeat itself and fatal for measurement:
# two renders differing only in one switch also differ in their entire synth
# voicing, so any A/B between them compares two variables and attributes the
# result to one. Large effects survive that noise; small ones do not, and
# several comparisons in this engine's history were probably reading patch
# variance rather than the change under test.
#
# RENDER_SEED pins it. Set it and renders are reproducible and comparable;
# leave it unset and the old per-process variation is unchanged.
def patch_cycle_seed(base = 0)
  pinned = ENV["RENDER_SEED"]
  entropy = pinned && !pinned.empty? ? pinned.to_i : Process.pid
  base + (@render_seed || 0) + (@stream_iterate_count || 0) * 7919 + entropy
end
