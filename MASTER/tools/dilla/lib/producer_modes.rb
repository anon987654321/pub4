# frozen_string_literal: true

# Named producer modes for the stream/render stack.
#
# Research notes (forums / Reddit / KVR / production writeups — 2026 session):
#
# J Dilla — MPC3000 as instrument; unquantized or lightly quantized finger drums;
#   snare often early, hats late ("Dilla time"); soul/jazz extensions (m7, m9, maj7,
#   m11); Donuts = short dusty loops, selection over polish. Forum consensus: turn
#   quantize off and play — a single swing % is not the secret.
#
# Flying Lotus — Dilla-inspired off-grid drums + denser perc; ethereal keys/saws;
#   overt sidechain so pads pump under the kick (Tea Leaf Dancers etc.); abstract
#   broken-beat hybrid. Camel: rhythmic hook, not a polite grid sketch. KVR/Reddit
#   producers chase sidechain drama + non-traditional perc layers.
#
# Madlib — SP-303 / SP-1200 culture; sample first; mud and vinyl as character;
#   short found loops; polish is suspicious. Beat Konducta energy: dusty, mono-ish
#   glue, imperfect chops. KVR: Donuts/Madlib sample study as hip-hop foundation.
#
# Afta-1 (afta) — post-Dilla instrumental / soulful beat-tape seat: patient chords,
#   warm Rhodes/EP beds, drums that support the loop, less IDM chaos than FlyLo,
#   more restraint than Madlib mud. Forum lineage: ShunGu/Kiefer/post-Dilla beat
#   tapes that prioritize head-nod harmony over maximalist design.
#
# Default stream = afta (camel is an alias for compatibility).
module DillaProducerModes
  MODES = %w[afta dilla flylo madlib camel].freeze

  # Shared pad-first base (afta / default camel stream).
  AFTA = {
    "PRODUCER_MODE" => "afta",
    "TRACK" => "chromatic_mediant_drift",
    "PROGRESSION" => "chromatic_mediant_drift",
    "BPM" => "86",
    "BARS" => "32",
    "FORM" => "camel_32",
    "COMPOSITION" => "1",
    "GROOVE_DNA" => "wonky",
    "PERFORMER" => "glasper",
    "VOICING" => "quartal",
    "PAD_VOICE" => "blend",
    "PAD_ARP_MODE" => "wash",
    "PAD_ATTACK" => "1600",
    "PAD_RELEASE" => "4200",
    "PAD_LEGATO_VAR" => "1",
    "LUSH_SYNTH" => "1",
    "LONG_STRIPDOWN" => "0",
    "MOTIF_RECALL" => "1",
    "KICKS" => "0",
    "POCKET_KICKS" => "0",
    "FLYLO_DRUMS_ONLY" => "1",
    "FLYLO_DRUM_OVERLAY" => "1",
    "FLYLO_QUINT_HATS" => "0",
    "FLYLO_KICK_GAIN" => "1.35",
    "KICK_SAMPLE_GAIN" => "0.95",
    "KICK_GAIN" => "0.9",
    "RAP_VOCAL" => "0",
    "LA_BEAT_PROGRESSION" => "0",
    "LINEAR_CHORD_INDEX" => "1",
    "HARMONY_LEAD" => "0",
    "LEAD_ARP" => "0",
    "EXPERIMENTAL_LEADS" => "0",
    "SYNTH_MORPH" => "0",
    "LEAD_MORPH" => "0",
    "FM_NATIVE" => "0",
    "SIDECHAIN_STYLE" => "flylo",
    "SONITEX" => "donuts_soul",
    "SONITEX_PRESET" => "donuts_soul",
    "ANALOG_CHAIN" => "broadcast",
    "DRUM_PRESET" => "flylo_abstract",
    "FLYLO_OVERLAY_GAIN" => "1.15",
    "FLYLO_SUB_MIX" => "0.95",
    "FLYLO_TOP_MIX" => "0.75",
    "FLYLO_MERGE_BOOST" => "1.55",
    "FLYLO_BASE_DRUM_VOL" => "0.12",
    "DRUM_BUS_VOL" => "1.2",
    "DRUM_BUS_GAIN" => "1.25",
    "DRUM_MIX_WEIGHT" => "1.25",
    "DRUM_PEAK_DB" => "-2.0",
    "HARM_MIX_WEIGHT" => "1.55",
    "HARM_BUS_VOL" => "1.85",
    "SIDECHAIN_DRUM_WEIGHT" => "1.35",
    "SIDECHAIN_HARM_WEIGHT" => "1.4",
    "FLYLO_CHORD_DUCK" => "0.97",
    "HARMONIC_PADS_WEIGHT" => "1.7",
    "HARMONIC_PADS_VOLUME" => "1.55",
    "HARMONIC_SCALE_LEAD_WEIGHT" => "0.12",
    "HARMONIC_SCALE_LEAD_VOLUME" => "0.35",
    "HARMONIC_LEAD_ARP_WEIGHT" => "0.12",
    "HARMONIC_LEAD_ARP_VOLUME" => "0.35",
    "HARMONIC_XLEAD_WEIGHT" => "0.08",
    "HARMONIC_XLEAD_VOLUME" => "0.25",
    "HARMONIC_HARMONY_LEAD_WEIGHT" => "0.15",
    "HARMONIC_HARMONY_LEAD_VOLUME" => "0.4",
    "HARMONIC_LEAD_WEIGHT" => "0.12",
    "HARMONIC_LEAD_VOLUME" => "0.35",
    "STREAM_CREATIVE_FREEDOM" => "0",
    "STREAM_ANALOG_WILD" => "0",
    "STREAM_ANALOG_EVERY" => "0",
    "STREAM_ITERATE" => "0",
    "PHONE_PREVIEW_GATE" => "0",
    "CAMEL_LOCK_COLOR" => "1",
    "CAMEL_DRUM_LOCK" => "1",
    "CAMEL_NO_BREAK" => "1",
    "CAMEL_CLEAN_MASTER" => "1",
    "CAMEL_NO_REVERB" => "1",
    "CAMEL_DRY_DRUMS" => "0",
    "CAMEL_CHOPS" => "0",
    "CONV_REVERB" => "0",
    "VINYL" => "0",
    "SELF_SAMPLE" => "0",
    "RADIO_BERGEN" => "0",
    "STREAM_CONTINUOUS" => "1",
    "STREAM_GAP" => "0.55",
    "STREAM_CROSSFADE" => "0.12",
    "STREAM_DEMO" => "demo.wav",
    "NO_QUANTIZE" => "0",
    "SWING" => "54"
  }.freeze

  # Dilla time: pocket humanize, soul extensions, light dust, shorter loops.
  DILLA = AFTA.merge(
    "PRODUCER_MODE" => "dilla",
    "TRACK" => "maj7_minor_cycle",
    "PROGRESSION" => "maj7_minor_cycle",
    "BPM" => "92",
    "BARS" => "16",
    "FORM" => "soul_16",
    "GROOVE_DNA" => "donuts",
    "PERFORMER" => "yancey",
    "VOICING" => "kenny_barron",
    "PAD_VOICE" => "rhodes",
    "PAD_ARP_MODE" => "wash",
    "PAD_ATTACK" => "900",
    "PAD_RELEASE" => "2800",
    "KICKS" => "1",
    "POCKET_KICKS" => "1",
    "FLYLO_DRUMS_ONLY" => "0",
    "FLYLO_DRUM_OVERLAY" => "0",
    "CAMEL_DRUM_LOCK" => "0",
    "DRUM_PRESET" => "dilla_slight",
    "NO_QUANTIZE" => "1",
    "SWING" => "58",
    "SONITEX" => "donuts_warm",
    "SONITEX_PRESET" => "donuts_warm",
    "ANALOG_CHAIN" => "cassette",
    "VINYL" => "18",
    "SIDECHAIN_STYLE" => "dilla",
    "SIDECHAIN_DRUM_WEIGHT" => "1.2",
    "SIDECHAIN_HARM_WEIGHT" => "1.45",
    "HARM_BUS_VOL" => "1.7",
    "DRUM_MIX_WEIGHT" => "1.35",
    "STREAM_GAP" => "0.35"
  ).freeze

  # FlyLo abstract: Camel grid + stem chops + stronger pad pump.
  FLYLO = AFTA.merge(
    "PRODUCER_MODE" => "flylo",
    "TRACK" => "quartal_west_coast",
    "PROGRESSION" => "chromatic_mediant_drift",
    "BPM" => "86",
    "BARS" => "32",
    "GROOVE_DNA" => "wonky",
    "PERFORMER" => "glasper",
    "VOICING" => "quartal",
    "PAD_VOICE" => "prophet",
    "FLYLO_DRUMS_ONLY" => "1",
    "FLYLO_DRUM_OVERLAY" => "1",
    "FLYLO_QUINT_HATS" => "1",
    "CAMEL_DRUM_LOCK" => "1",
    "CAMEL_CHOPS" => "1",
    "SIDECHAIN_STYLE" => "flylo",
    "SIDECHAIN_DRUM_WEIGHT" => "1.85",
    "SIDECHAIN_HARM_WEIGHT" => "0.95",
    "FLYLO_KICK_GAIN" => "1.5",
    "FLYLO_OVERLAY_GAIN" => "1.25",
    "DRUM_MIX_WEIGHT" => "1.55",
    "HARM_BUS_VOL" => "1.55",
    "HARMONIC_PADS_WEIGHT" => "1.35",
    "SONITEX" => "donuts_soul",
    "ANALOG_CHAIN" => "summing_phasy",
    "LEAD_ARP" => "1",
    "HARMONY_LEAD" => "0",
    "HARMONIC_LEAD_ARP_WEIGHT" => "0.45",
    "HARMONIC_LEAD_ARP_VOLUME" => "0.7",
    "STREAM_GAP" => "0.4"
  ).freeze

  # Madlib dust: sample bias, dirt, short loops, SP-ish color.
  MADLIB = AFTA.merge(
    "PRODUCER_MODE" => "madlib",
    "TRACK" => "minor_iv_loop",
    "PROGRESSION" => "minor_iv_loop",
    "BPM" => "88",
    "BARS" => "16",
    "FORM" => "soul_16",
    "GROOVE_DNA" => "madvillainy",
    "PERFORMER" => "madlib",
    "VOICING" => "spread",
    "PAD_VOICE" => "rhodes",
    "PAD_ATTACK" => "600",
    "PAD_RELEASE" => "1800",
    "KICKS" => "1",
    "POCKET_KICKS" => "1",
    "FLYLO_DRUMS_ONLY" => "0",
    "FLYLO_DRUM_OVERLAY" => "0",
    "CAMEL_DRUM_LOCK" => "0",
    "DRUM_PRESET" => "dilla_slight",
    "NO_QUANTIZE" => "1",
    "SWING" => "56",
    "SONITEX" => "donuts_warm",
    "SONITEX_PRESET" => "donuts_warm",
    "ANALOG_CHAIN" => "acetate",
    "VINYL" => "42",
    "SELF_SAMPLE" => "1",
    "STREAM_LEARN_BIAS" => "1",
    "SIDECHAIN_STYLE" => "dilla",
    "SIDECHAIN_DRUM_WEIGHT" => "1.15",
    "SIDECHAIN_HARM_WEIGHT" => "1.35",
    "HARM_BUS_VOL" => "1.45",
    "DRUM_MIX_WEIGHT" => "1.4",
    "STREAM_GAP" => "0.25",
    "STREAM_CROSSFADE" => "0.05"
  ).freeze

  TABLES = {
    "afta" => AFTA,
    "camel" => AFTA, # alias — Camel stream = Afta-1 seat
    "dilla" => DILLA,
    "flylo" => FLYLO,
    "madlib" => MADLIB
  }.freeze

  module_function

  def normalize(mode)
    m = mode.to_s.strip.downcase.tr("-", "_")
    m = "afta" if m.empty?
    TABLES.key?(m) ? m : "afta"
  end

  def table_for(mode)
    TABLES.fetch(normalize(mode), AFTA)
  end

  def apply!(mode, force: false)
    tbl = table_for(mode)
    ENV["PRODUCER_MODE"] = normalize(mode)
    ENV["RENDER_MODE"] = "camel" if %w[afta camel flylo].include?(normalize(mode))
    tbl.each do |key, value|
      next if value.nil?
      next if !force && ENV[key] && !ENV[key].empty?
      ENV[key] = value.to_s
    end
    normalize(mode)
  end

  def beauty_lock_keys
    AFTA.keys
  end
end
