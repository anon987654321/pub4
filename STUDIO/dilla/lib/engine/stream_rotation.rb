# frozen_string_literal: true
#
# What the stream plays next: track, drum, voice and arp rotation.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# Non-stop: one engine (dilla.rb DNA). Rotates progressions + drums only.
# Ctrl-C to stop. Pin one track: STREAM_LOCK=1 + STREAM_TRACK=…

DILLA_STREAM_PRIORITY = %w[
  pedal_e_descent db_major_minor_fall eb_minor_two_chord e_major_third_rise d_add9_soul_arc
  maj7_minor_cycle alternating_minor7_pair syncopated_slash_ninth
  neo_soul neo_soul_pocket warm_minor_vamp
].freeze

STREAM_HEAD_TRACKS = %w[
  pedal_e_descent
  d_add9_soul_arc
  neo_soul
  neo_soul_pocket
  chromatic_mediant_drift
  baroque
  minor_two_five_chain
].freeze

def stream_progression_order
  all = stream_track_pool.map(&:to_s).uniq
  # Head/priority lists may name tracks outside the active pool (e.g. with
  # DILLA_PROGRESSIONS_ONLY) — never let them reintroduce filtered tracks.
  head = STREAM_HEAD_TRACKS.map(&:to_s).select { |t| all.include?(t) }
  priority = DILLA_STREAM_PRIORITY.select { |t| all.include?(t) && !head.include?(t) }
  rest = all.reject { |t| head.include?(t) || priority.include?(t) }
  head + priority + rest
end

def stream_track_order
  lock = ENV["STREAM_TRACK"] || (ENV["STREAM_LOCK"] == "1" ? ENV["TRACK"] : nil)
  if lock && !lock.to_s.empty? && ENV["STREAM_LOCK"] == "1"
    key = lock.to_s.downcase.tr("-", "_").to_sym
    known = STREAM_TRACKS.include?(key) || DillaLofiMachine.harmony_profile?(key) ||
            TRACK_PRESETS.key?(key)
    return [key] if known
    dmesg_warn("stream unknown lock #{lock} — full rotation")
  end
  stream_progression_order.map(&:to_sym)
end

def stream_drum_rotate_enabled?
  ENV.fetch("STREAM_DRUM_ROTATE", "1") != "0"
end

# Rotate drum grid / pocket / kit after DNA force so beats actually change.
# The curated rotation, then every other kit.
#
# STREAM_DRUM_ROTATION is hand-built combinations of preset, pocket and kit, and
# hand-built for a reason: the pairings matter, and a busy grid under a drunk
# pocket is two kinds of drunk at once. But 62 drum presets exist and the table
# names ten, so 52 never played -- dilla_donuts, dilla_fantastic,
# dilla_lopsided, questlove_pocket, knxwledge_haze, every euclid_* and push_*.
#
# The curated pairings stay first and in order, so a demo of eight still opens
# on the house sound. The tail follows with a pocket chosen from each preset's
# own declared mode rather than at random -- that pairing knowledge is exactly
# what the curated table encodes, and the reason not to shuffle everything.
def drum_rotation_full
  @drum_rotation_full ||= begin
    named = STREAM_DRUM_ROTATION.map { |d| d[:preset] }
    tail = DillaLofiMachine::DRUM_PRESETS.keys.map(&:to_s).sort - named
    STREAM_DRUM_ROTATION + tail.filter_map do |preset|
      spec = DillaLofiMachine::DRUM_PRESETS[preset.to_sym] or next
      pocket = case spec[:mode].to_s
               when /dilla/ then "neo_soul"
               when /straight/ then "classic"
               else "dusty"
               end
      { preset:, pocket:, kit: "03-soulful-vintage",
        wonky: preset.start_with?("wonky") ? "1" : "0" }
    end
  end
end

def stream_rotate_drums!(index)
  return unless stream_drum_rotate_enabled?

  # DRUM_ROTATE_CURATED is separate from DEMO_CURATED_ONLY on purpose: that one
  # also narrows the TRACK list, so asking for the house kit meant giving up
  # most of the catalogue.
  #
  # Why a demo wants it. drum_rotation_full is the 13 hand-built pairings
  # followed by every other preset SORTED BY NAME, and the index walks it
  # straight through. Measured on a 34-slot demo: 31 different presets in 34
  # slots, nothing repeating, and past slot 13 the running order is alphabetical
  # -- afro_clave, boom_808, dembow_lite, then the whole euclid_* and wonky_*
  # runs. Five euclidean grids, a reggaeton dembow and an afro-cuban clave in a
  # hiphop demo, each heard once. Operator verdict: "the drums seem to go
  # without rhythm or purpose", which is what a kit that never repeats sounds
  # like -- no groove survives one encounter.
  #
  # The curated table is 13 entries and deliberately repeats dilla_slight,
  # mpc3000 and dilla_drunk, so over 34 slots a listener hears each pocket
  # several times and it registers as the record's groove.
  curated = ENV["DEMO_CURATED_ONLY"] == "1" || ENV.fetch("DRUM_ROTATE_CURATED", "0") == "1"
  table = curated ? STREAM_DRUM_ROTATION : drum_rotation_full
  d = table[index % table.length]
  ENV["DRUM_PRESET"] = d[:preset]
  ENV["POCKET_SET"] = d[:pocket]
  ENV["EXTERNAL_KIT"] = d[:kit] if d[:kit] && !d[:kit].empty?
  ENV["FM_DRUMS"] = d[:fm] if d[:fm] == "1" && !USER_PINNED_ENV.key?("FM_DRUMS")
  ENV["WONKY_DRUM_OVERLAY"] = d[:wonky] || "0"
  ENV["DRUM_CHOPS"] = "0" unless ENV["FORCE_DRUM_CHOPS"] == "1"
  ENV["ECLECTIC_PERC"] ||= "0"
  ENV["RAW_KICK"] = "1"
  ENV["DRUM_SAMPLE_RAW"] = "1"
  preset = DillaLofiMachine::DRUM_PRESETS[d[:preset].to_sym]
  ENV["SWING"] = preset[:swing].to_s if ENV["STREAM_DRUM_SWING"] == "1" && preset && !USER_PINNED_ENV.key?("SWING")
  ENV["BPM"] = preset[:bpm].to_s if ENV["STREAM_DRUM_BPM"] == "1" && preset&.dig(:bpm)
  @current_external_kit = nil
  record_config_provenance!("DRUM_PRESET", "stream_rotate_drums![#{index}]", "force")
  d
end

# Per-track variety: rotate lead arp mode, lead/pad voice, force true arps + synth cycle.
# Switches the operator set on the command line, captured before any rotation
# or profile runs.
#
# stream_rotate_voices_and_arps! force-sets LEAD_VOICE, LEAD_ARP, SCALE_LEAD,
# HARMONY_LEAD, CREATIVE_LEAD, EXPERIMENTAL_LEADS, LEAD_MORPH and MELODIC_LEAD
# every track. It is guarded by user_lead_locked, but that only becomes true
# when LEAD_VOICE or LEAD_ARP_MODE is set -- so launching with
# `HARMONY_LEAD=0 SCALE_LEAD=0 CREATIVE_LEAD=0 LEAD_ARP=0` and no LEAD_VOICE
# left the guard false and every one of those zeroes was overwritten with a 1
# on the first track. Asking for pads with no leads produced full arps.
#
# Same failure as the track presets overwriting RAP_VOCAL=0: a guard that
# infers intent from one key instead of reading what was actually asked for.
#
# Read from USER_PINNED_ENV rather than re-reading ENV: that constant already
# answers "what did the operator actually ask for", and in a supervisor child it
# answers it correctly. A second raw ENV capture treats the parent's own
# apply_best_defaults! values as operator intent and re-pins them after every
# rotation -- the same laundering the DILLA_USER_PINNED_KEYS declaration exists
# to stop.
STREAM_EXPLICIT_ENV = USER_PINNED_ENV.slice(
  *%w[
    PAD_VOICE PAD_ARP_MODE PAD_LAYERS PAD_VOL
    LEAD_VOICE LEAD_ARP_MODE LEAD_ARP LEAD_FORCE_ARP LEAD_MORPH MELODIC_LEAD
    SCALE_LEAD HARMONY_LEAD CREATIVE_LEAD EXPERIMENTAL_LEADS
    ANALOG_PAD_DETUNE_CENTS
  ]
).reject { |_, v| v.to_s.empty? }.freeze

# What this process tells a child process is genuinely pinned.
#
# Both relaunch paths (the supervisor loop and the mtime exec-restart) declare
# this, and they used to spell it differently -- the supervisor dropped
# DILLA_STREAM* keys, the restart did not -- so a bug could reproduce on one
# restart route and not the other. DILLA_STREAM_LAUNCHED / _SUPERVISOR are this
# file's own plumbing, never operator intent, so they never belong in the pin set.
def dilla_pinned_keys_decl
  USER_PINNED_ENV.keys.reject { |k| k.start_with?("DILLA_STREAM") }.join(",")
end

# One demo slot's pad identity. Two call sites wrote these four keys inline, so
# the rotation and the key list had to be kept in step by hand.
#
# PAD_LAYERS was `ENV["PAD_VOICE"].start_with?("stack_") ? "1" : "1"` -- both arms
# the same value, so the condition never meant anything.
# The outboard chain each demo slot is printed through.
#
# lib/outboard.rb holds seven racks of measured emulations and demo-all was using
# exactly one of them, 86 times -- the same signal path on every track in a demo
# whose entire job is to show range. The pads, arps and voicings already rotate
# per slot (right below); the analog stage did not, so every slot's character
# came from the front of the chain and none from the back.
#
# Rotated on a different modulus to the pad rotation so the two do not lock into
# a repeating pair. 7 racks against DEMO_PAD_ROTATION's length share no factor
# unless that length is a multiple of 7, so the combination walks rather than
# cycles.
#
# RACK is read by the render at dilla.rb's rack resolution and falls back to
# Outboard::DEFAULT_RACK on an unknown name, so a rack removed from the table
# degrades to the default rather than failing the slot.
DEMO_RACK_ROTATION = Outboard::RACKS.keys.map(&:to_s).freeze

def demo_slot_rack(idx)
  DEMO_RACK_ROTATION[idx % DEMO_RACK_ROTATION.length]
end

def demo_slot_pad_env(idx)
  {
    "PAD_VOICE" => DEMO_PAD_ROTATION[idx % DEMO_PAD_ROTATION.length],
    "PAD_ARP_MODE" => DEMO_PAD_ARP_ROTATION[idx % DEMO_PAD_ARP_ROTATION.length],
    "VOICING" => DEMO_VOICING_ROTATION[idx % DEMO_VOICING_ROTATION.length],
    "PAD_LAYERS" => "1",
    "RACK" => demo_slot_rack(idx),
  }
end

# Put the operator's values back after anything that rewrites them.
def restore_explicit_stream_env!
  STREAM_EXPLICIT_ENV.each { |k, v| ENV[k] = v }
end

def stream_rotate_voices_and_arps!(track_index)
  stream_rotate_macros!(track_index)
  return if ENV["STREAM_ROTATE_LEAD"] == "0" && ENV["STREAM_ROTATE_SYNTH"] == "0"
  @stream_iterate_count = (@stream_iterate_count || 0)
  i = track_index + @stream_iterate_count
  if ENV.fetch("STREAM_ROTATE_LEAD", "1") != "0"
    ENV["LEAD_ARP_MODE"] = STREAM_LEAD_ARP_ROTATION[i % STREAM_LEAD_ARP_ROTATION.length].to_s
    ENV["LEAD_VOICE"] = STREAM_LEAD_VOICE_ROTATION[i % STREAM_LEAD_VOICE_ROTATION.length]
    ENV["SCALE_LEAD"] = "1"
    ENV["HARMONY_LEAD"] = "1"
    ENV["CREATIVE_LEAD"] = (i % 2).zero? ? "1" : "0"
    ENV["EXPERIMENTAL_LEADS"] = "1"
    ENV["LEAD_MORPH"] = "1"
    ENV["STREAM_LEAD_MIDI_RICH"] = "1"
    # Louder lead stems so arps cut through pads.
    ENV["HARMONIC_LEAD_ARP_WEIGHT"] = format("%.2f", 1.65 + (i % 5) * 0.05)
    ENV["HARMONIC_LEAD_ARP_VOLUME"] = "1.95"
    ENV["HARMONIC_SCALE_LEAD_WEIGHT"] = "1.25"
    ENV["HARMONIC_SCALE_LEAD_VOLUME"] = "1.55"
  end
  if ENV.fetch("STREAM_ROTATE_SYNTH", "1") != "0"
    ENV["SYNTH_CYCLE"] = "1"
    ENV["SYNTH_MORPH"] = "1"
    ENV["PAD_TEXTURE"] = "1"
    # Mostly held pads; occasional pad figure for variety.
    ENV["PAD_ARP_MODE"] = (i % 5).zero? ? "figure" : "held"
    ENV["PAD_VOICE"] = STREAM_PAD_VOICE_ROTATION[i % STREAM_PAD_VOICE_ROTATION.length]
    # Cycle analog color + sonitex when wild mode on.
    if ENV["STREAM_ANALOG_WILD"] == "1"
      chains = %w[broadcast acetate cassette vinyl_hot summing_phasy lo_fi sp1200]
      ENV["ANALOG_CHAIN"] = chains[i % chains.length]
      soni = %w[donuts_soul donuts_warm vinyl_lab sp1200_crunch]
      ENV["SONITEX"] = soni[i % soni.length]
      ENV["SONITEX_PRESET"] = ENV["SONITEX"]
    end
  end
  # Rotation writes ENV directly. Operator pins captured in STREAM_EXPLICIT_ENV
  # have to win after that, or `LEAD_ARP=0` on the command line still produces
  # full arps — the guard above only looks at STREAM_ROTATE_LEAD, not at what
  # was asked for.
  restore_explicit_stream_env!
  # Clears the patch cache too, so pick_synth_patches! re-rolls for this track.
  pick_render_seed!
end

# Integrated loudness match so every stream track (and vocals) lands at the same level.
def normalize_track_loudness!(path, lufs: nil)
  return path unless path && File.file?(path)
  return path if ENV["DEBUG_NO_LOUDNORM"] == "1"

  # Single-pass loudnorm is a dynamic ride. Measure then apply a static
  # volume= the way normalise_master! already does on the main bus.
  target = (lufs || ENV["STREAM_LUFS"] || ENV["MASTER_LUFS"] || "-16.5").to_f
  previous = ENV["MASTER_LUFS"]
  ENV["MASTER_LUFS"] = target.to_s
  begin
    # Both, and neither is redundant. normalise_master! reads ENV["MASTER_LUFS"]
    # ahead of cfg, so the assignment above is what actually carries the stream
    # target through — but the second argument is not optional, and calling with
    # one raised ArgumentError on every render that reached this line, which is
    # every render: render_dilla:761 -> here -> master_chain:164. The engine
    # could not finish a single track.
    normalise_master!(path, { master_lufs: target })
  ensure
    if previous.nil?
      ENV.delete("MASTER_LUFS")
    else
      ENV["MASTER_LUFS"] = previous
    end
  end
  path
end

# STREAM_MACROS=1 — vary a stream slot by a WORD rather than by six numbers.
#
# Everything else in this file rotates knobs: LEAD_VOICE, LEAD_ARP_MODE,
# HARMONIC_LEAD_ARP_WEIGHT, DRUM_PRESET. That works and it is why the rotation
# reads as a list of assignments -- each slot differs from the last by a handful
# of numbers nobody can hear individually.
#
# DillaMacros exists to say those in musical terms: `dust`, `drift`, `air`,
# `weight`. This walks a small cycle of them so consecutive slots differ by an
# idea instead of by arithmetic, and so the difference is one a listener can
# name. Off by default; the rotation's current behaviour is unchanged without it.
#
# apply! does not overwrite a knob the operator set by hand -- macros are the
# coarse control and an explicit export is the fine one -- so a pinned stream
# stays pinned.
STREAM_MACRO_CYCLE = [
  { dust: 0.25, air: 0.55 },
  { drift: 0.45, density: 0.4 },
  { weight: 0.65, glue: 0.7 },
  { dust: 0.6, drift: 0.3 },
  { density: 0.7, air: 0.35 },
  { chaos: 0.3, drift: 0.55 },
].freeze

def stream_rotate_macros!(track_index)
  return unless ENV["STREAM_MACROS"] == "1"

  settings = STREAM_MACRO_CYCLE[track_index % STREAM_MACRO_CYCLE.length]
  result = DillaMacros.apply!(settings)
  return if result[:applied].empty?

  dmesg("macros: #{settings.map { |k, v| "#{k}=#{v}" }.join(' ')} -> #{result[:applied].join(' ')}",
        unit: "style0", parent: "dilla0")
end
