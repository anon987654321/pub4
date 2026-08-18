# frozen_string_literal: true
#
# Deep, creative and fast stream tuning, and the quality gates.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

SLASH_BASS_PROFILES = %i[
  syncopated_slash_ninth syncopated_slash_alt slash_neo_soul slash_ninth_cycle
  minor_dominant_slash_cycle
].freeze

PROMOTED_PROFILES_PATH = File.join(DillaComposition::PROJECT_DIR, "promoted_profiles.json").freeze

# Deep render — quality gates + pocket jitter. Do NOT put pad/mix DNA here
# (attack/release/vol/reverb/stripdown): BEST soft-fills DEEP before style
# soft-fill, and first-writer-wins would block DILLA_STYLE_DEFAULTS.
# PHONE_PREVIEW_GATE stays out: STYLE defaults it off; force on with
# PHONE_PREVIEW_GATE=1 when you want that extra quality pass.
DILLA_DEEP_DEFAULTS = {
  "DILLA_QUALITY_GATE" => "1",
  "RENDER_RETRIES" => "2",
  "LISTEN_PASSES" => "1",
  "QUALITY_REPORT" => "1",
  "RENDER_BEAUTY_MIN" => "70",
  "QUINTUPLET" => "1",
  "SWING_JITTER" => "1",
  "EVOLVE_HARMONY_W" => "0.18",
}.freeze

# Keys shared verbatim with DILLA_STYLE_DEFAULTS are inherited, not copied:
# soft-fill is first-writer-wins, so a copy that drifts from the style table
# silently shadows the style DNA. Inheriting makes that drift impossible.
STREAM_EXTRA_DEFAULTS = DILLA_STYLE_DEFAULTS.slice(
  "POCKET_KICKS", "FLYLO_DRUMS_ONLY", "FLYLO_DRUM_OVERLAY",
  "BACKBEAT_CLAP", "FLYLO_KICK_GAIN", "FLYLO_OVERLAY_GAIN",
  "FLYLO_SUB_MIX", "FLYLO_TOP_MIX", "FLYLO_MERGE_BOOST",
  "FLYLO_BASE_DRUM_VOL", "DRUM_BUS_VOL", "DRUM_BUS_GAIN",
  "DRUM_MIX_WEIGHT", "DRUM_AIR_DB", "DRUM_PRESENCE_DB",
  "RADIO_BERGEN", "RAP_VOCAL_STYLE", "RAP_VOCAL_MIX",
  "RAP_VOCAL_WEIGHT", "RAP_VOCAL_BED_WEIGHT", "RAP_VOCAL_DUCK",
  "RAP_VOCAL_SIDECHAIN", "STREAM_NORMALIZE",
  "STREAM_LUFS",
  "STREAM_ROTATE_LEAD", "STREAM_ROTATE_SYNTH", "STREAM_LEAD_MIDI_RICH",
  "MELODIC_LEAD", "LEAD_ARP", "EXPERIMENTAL_LEADS",
  "LEAD_MORPH", "SYNTH_MORPH", "SYNTH_CYCLE",
  "STREAM_ANALOG_WILD", "STREAM_ANALOG_EVERY", "LA_BEAT_PROGRESSION",
  "LUSH_SYNTH", "PAD_TEXTURE", "FM_NATIVE",
  "SELF_SAMPLE", "CONV_REVERB", "CAMEL_CLEAN_MASTER",
  "CAMEL_NO_REVERB", "CAMEL_NO_BREAK", "PHONE_PREVIEW_GATE",
  "PAD_VOL", "HARM_MIX_WEIGHT", "HARM_BUS_VOL",
  "HARMONIC_PADS_WEIGHT", "HARMONIC_PADS_VOLUME",
).merge(
  "DRUM_VOL" => "0.85",
  "DILLA_STREAMING" => "1",
  "PLAY_VOL" => "1",
  # Speech overlay disabled — beat only until re-enabled (SPEAK=1 or --speak=1).
  "SPEAK" => "0",
  "SPEAK_VOICE" => "en-US-AndrewNeural",
  "SPEAK_RATE" => "-48%",
  "SPEAK_PITCH" => "+8Hz",
  "SPEAK_VOL" => "0.82",
  "SPEAK_QUIRK" => "0.12",
  # Stream kit — quieter than before (matches DILLA_STYLE drum step-back).
  "KICKS" => "1",
  "KICK_GAIN" => "0.68",
  "STREAM_ITERATE" => "1",
  "SPEECH_MAX_SEGMENTS" => "1",
  "SPEECH_TALK_STREAM" => "14",
  "STREAM_CONTINUOUS" => "1",
  # Stream UX — aligned with DILLA_STYLE_DEFAULTS (no soft-fill conflicts).
  "STREAM_BARS" => "12",
  "STREAM_GAP" => "0.15",
  "STREAM_CROSSFADE" => "0.12",
  "STREAM_TRACK_TIMEOUT" => "300",
  "STREAM_DRUM_ROTATE" => "1",
  # Jonas V vocals — loud, tempo-matched.
  # gunnhild is the only vocal source (operator decision). It is also the harder
  # one -- two usable pockets in 128s, needing pre-gain to survive the isolation
  # chain -- which is why this default had drifted to sa_g. Defaulting to the
  # easy source hid that problem rather than fixing it; the isolation and fit
  # path has to handle this voice, so this is what it runs against.
  # Vocals off by default. RAP_VOCAL=<slug> or CHOIR_VOX=1 re-enables.
  "RAP_VOCAL" => "0",
  "LEAD_FORCE_ARP" => "0",
  "ARTIST_VERIFIED_ONLY" => "0",
  # Stay aligned with style DNA — creative wildness is opt-in (STREAM_CREATIVE=1).
  "STREAM_CREATIVE_FREEDOM" => "1",
  "EVOLVE_EVERY" => "1",
  "STREAM_HARMONY_EVERY" => "1",
  "STREAM_EVOLVE_PERFORMER" => "1",
  "STREAM_LEARN_BIAS" => "1",
  "VINYL" => "0",
).freeze

# Opt-in creative layer (STREAM_CREATIVE=1 or STREAM_PUNCH=1). Never the default —
# it used to force LA_BEAT/VINYL/hot LUFS over clean style DNA.
STREAM_CREATIVE_MAX = {
  "STREAM_CREATIVE_FREEDOM" => "1",
  "STREAM_ANALOG_WILD" => "1",
  "STREAM_ANALOG_EVERY" => "1",
  "STREAM_HARMONY_EVERY" => "1",
  "STREAM_EVOLVE_PERFORMER" => "1",
  "STREAM_LEARN_BIAS" => "1",
  "EVOLVE_EVERY" => "1",
  "LA_BEAT_PROGRESSION" => "1",
  "VINYL" => "1",
  "SELF_SAMPLE" => "1",
  "CONV_REVERB" => "chamber",
  "STREAM_LUFS" => "-14.5",
  "CAMEL_CLEAN_MASTER" => "0",
  "CAMEL_NO_REVERB" => "0",
  "CAMEL_NO_BREAK" => "0",
  "LEAD_MORPH" => "1",
  "SYNTH_MORPH" => "1",
  "SYNTH_CYCLE" => "1",
  "EXPERIMENTAL_LEADS" => "1",
}.freeze

# Re-asserted after style force on normal stream (style DNA wins on mix keys).
STREAM_STYLE_SAFE = {
  "STREAM_ITERATE" => "1",
  "STREAM_ROTATE_LEAD" => "1",
  "STREAM_ROTATE_SYNTH" => "1",
  "STREAM_DRUM_ROTATE" => "1",
  "STREAM_LEAD_MIDI_RICH" => "1",
  "STREAM_NORMALIZE" => "1",
  "STREAM_CROSSFADE" => "0.12",
  "STREAM_GAP" => "0.15",
  "DILLA_STREAMING" => "1",
  "PLAY_VOL" => "1",
}.freeze

def stream_creative_mode?
  ENV["STREAM_CREATIVE"] == "1" || ENV["STREAM_PUNCH"] == "1"
end

def stream_track_timeout_sec
  sec = (ENV["STREAM_TRACK_TIMEOUT"] || "420").to_i
  sec.positive? ? sec : nil
end

# Light auto-iterate during stream — beauty retry, mix/groove nudges, lead freedom.
STREAM_ITERATE_TUNING = {
  "RENDER_RETRIES" => "1",
  "RENDER_BEAUTY_MIN" => "55",
  "EVOLVE_EVERY" => "1",
  "EXPERIMENTAL_LEADS" => "1",
  "SYNTH_CYCLE" => "1",
  "SYNTH_MORPH" => "1",
  "LEAD_MORPH" => "1",
  "LUSH_SYNTH" => "1",
  "STREAM_EVOLVE_PERFORMER" => "1",
  "STREAM_CREATIVE_FREEDOM" => "1",
  "PHONE_PREVIEW_GATE" => "0",
  "EVOLVE_GROOVE_W" => "0.35",
  "EVOLVE_HARMONY_W" => "0.32",
  "GROOVE_SCORE_MIN" => "70",
  "MOTIF_RECALL" => "1",
  "STREAM_HARMONY_EVERY" => "1",
  "STREAM_ANALOG_EVERY" => "1",
  "STREAM_ANALOG_WILD" => "1",
  "STREAM_LEARN_BIAS" => "1",
}.freeze

# STREAM_FAST_DEFAULTS must not clobber these when iterate is on.
STREAM_ITERATE_OVERRIDE_KEYS = %w[
  RENDER_RETRIES LISTEN_PASSES RENDER_BEAUTY_MIN EVOLVE_EVERY
  LEAD_ARP EXPERIMENTAL_LEADS STREAM_EVOLVE_PERFORMER STREAM_CREATIVE_FREEDOM
  STREAM_HARMONY_EVERY STREAM_ANALOG_EVERY STREAM_ANALOG_WILD STREAM_LEARN_BIAS
].freeze

# In scratch/, not the project root. Both stream logs are regenerated output and
# belong with the rest of it -- writing them beside dilla.rb put two files in the
# root that look like source until you open them, and no amount of moving them by
# hand helps while the code keeps recreating them there.
STREAM_ITERATE_LOG = File.join(SCRATCH_DIR, "stream_iterate.log").freeze

# Fast stream — render+play without quality gate / listen refine (~15–30s/track).
STREAM_FAST_DEFAULTS = {
  "DILLA_DEEP" => "0",
  "DILLA_QUALITY_GATE" => "0",
  "PHONE_PREVIEW_GATE" => "0",
  "RENDER_RETRIES" => "0",
  "LISTEN_PASSES" => "0",
  "QUALITY_REPORT" => "0",
  "CONV_REVERB" => "0",
  "LEAD_ARP" => "0",
}.freeze

def deep_render?
  ENV.fetch("DILLA_DEEP", "0") != "0"
end

def stream_deep?
  ENV["STREAM_DEEP"] == "1"
end

# On unless switched off, which is the opposite of how this shipped.
#
# It read `== "1"`, so a bare `ruby dilla.rb out.wav` rendered with no quality
# gate at all — only `record`, `perform` and the stream-soul path opted in. That
# left the engine's own judgement of a mix as something you had to remember to
# ask for, while COMPOSITION and STREAM_ITERATE were both on unless disabled. A
# feature defaulting on while the check on its output defaults off is backwards:
# the cost of a gated render is time, the cost of an ungated one is not knowing.
#
# STREAM_FAST_DEFAULTS still sets "0" explicitly for the ~15-30s/track stream
# path, and that stays deliberate — a broadcast that pauses to re-render is
# worse than one that occasionally plays a thin track.
def quality_gate_enabled?
  ENV.fetch("DILLA_QUALITY_GATE", "1") != "0"
end

def stream_iterate_enabled?
  ENV.fetch("STREAM_ITERATE", "1") != "0" && ENV["DILLA_STREAMING"] == "1"
end

def stream_creative_freedom_enabled?
  stream_iterate_enabled? && ENV.fetch("STREAM_CREATIVE_FREEDOM", "1") != "0"
end

def play_render_attempts
  if quality_gate_enabled?
    [STREAM_MAX_RETRIES, (ENV["RENDER_RETRIES"] || "2").to_i].max + 1
  elsif stream_iterate_enabled?
    retries = [(ENV["RENDER_RETRIES"] || "1").to_i, 1].max
    retries + 1
  else
    1
  end
end

def stream_iterate_acceptable?(path)
  return true unless stream_iterate_enabled?
  return true unless File.file?(path)
  beauty = DillaHarmony.score_beauty(DillaHarmony.last_progression_chords)
  spectrum = render_spectrum(path)
  harsh = DillaMaster.analyze_harshness(spectrum)
  min = (ENV["RENDER_BEAUTY_MIN"] || "65").to_f
  ok = beauty >= min && !harsh[:needs_notch]
  if ok && phone_preview_gate_enabled?
    phone_path = DillaMaster.apply_phone_preview!(path)
    phone_spec = render_spectrum(phone_path)
    phone = DillaMaster.phone_preview_acceptable?(phone_spec)
    unless phone[:ok]
      warn "stream iterate phone gate: mid=#{phone[:mid_db]} dB low-mid=#{phone[:low_mid_delta]} dB"
      ok = false
    end
    FileUtils.rm_f(phone_path) if phone_path != path && phone_path.end_with?(".phone.wav")
  end
  ok
end
