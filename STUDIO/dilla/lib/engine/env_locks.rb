# frozen_string_literal: true
#
# Environment provenance: who pinned which knob, and what may overwrite it.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# Style-lock keys — reassert after track soul / iterate so the mix doesn't drift.
# Exclude lead/synth/progression-rotation keys so stream can cycle voices + arps.
DILLA_STYLE_LOCK_KEYS = (
  DILLA_STYLE_DEFAULTS.keys - %w[
    TRACK PROGRESSION LEAD_VOICE LEAD_ARP_MODE LEAD_ARP PAD_VOICE
    MELODIC_LEAD SCALE_LEAD CREATIVE_LEAD HARMONY_LEAD
    SYNTH_MORPH SYNTH_CYCLE LEAD_MORPH EXPERIMENTAL_LEADS
    ARTIST_VERIFIED_ONLY STREAM_CREATIVE_FREEDOM STREAM_ROTATE_SYNTH STREAM_ROTATE_LEAD
    DRUM_PRESET POCKET_SET EXTERNAL_KIT FM_DRUMS SWING WONKY_DRUM_OVERLAY
  ]
).freeze

# Pad stack only — do NOT lock lead voice / arp mode (stream rotates those).
DILLA_PAD_LEAD_LOCK_KEYS = %w[
  PAD_LAYERS PAD_VOL PAD_ARP_MODE
  LEARNED_PROGRESSION VOICE_LEAD_PADS VOICING
  HARMONIC_PADS_WEIGHT HARMONIC_PADS_VOLUME
  HARMONIC_LEAD_ARP_WEIGHT HARMONIC_LEAD_ARP_VOLUME
  HARMONIC_SCALE_LEAD_WEIGHT HARMONIC_SCALE_LEAD_VOLUME
  HARMONIC_HARMONY_LEAD_WEIGHT HARMONIC_HARMONY_LEAD_VOLUME
  HARMONIC_LEAD_WEIGHT HARMONIC_LEAD_VOLUME
].freeze

# Drum DNA cycled each stream slot (preset grid + pocket set + sample kit).
# Applied after style force so DRUM_PRESET locks cannot pin dilla_slight forever.
# Soulful hip-hop only — no boom_808 / industrial / hard-trap rotation.
# The kits every stream and every demo track draws from.
#
# This was eight entries, all boom-bap, every one wonky: "0" -- so the eleven
# Flying Lotus presets in DRUM_PRESETS (wonky_abstract, wonky_cosmogramma,
# wonky_zodiac, wonky_burst, wonky_warp and the rest), the WONKY_DRUM_OVERLAY
# switch, and the whole learn-wonky command that transcribes a grid from a
# record, were unreachable from anything that actually renders. The presets
# existed and nothing could pick them. A demo of eight tracks came out
# boom-bap eight times, by construction rather than by choice.
#
# Five Wonky entries added. They are placed at odd indices so a run of
# consecutive tracks alternates rather than arriving in a block, since the
# rotation is indexed by track number.
#
# The pockets differ from the boom-bap half on purpose. wonky_abstract and
# wonky_burst are busier and want the straighter pocket under them; dilla_drunk
# with a Wonky grid on top is two kinds of drunk at once.
STREAM_DRUM_ROTATION = [
  { preset: "dilla_slight",      pocket: "neo_soul", kit: "03-soulful-vintage", fm: "0", wonky: "0" },
  { preset: "wonky_abstract",    pocket: "classic",  kit: "02-bounce",          fm: "0", wonky: "1" },
  { preset: "dilla_drunk",       pocket: "neo_soul", kit: "03-soulful-vintage", fm: "0", wonky: "0" },
  { preset: "wonky_cosmogramma", pocket: "classic",  kit: "03-soulful-vintage", fm: "0", wonky: "1" },
  { preset: "mpc3000",           pocket: "neo_soul", kit: "03-soulful-vintage", fm: "0", wonky: "0" },
  { preset: "wonky_zodiac",      pocket: "dusty",    kit: "03-soulful-vintage", fm: "0", wonky: "1" },
  { preset: "madlib_dusty",      pocket: "dusty",    kit: "03-soulful-vintage", fm: "0", wonky: "0" },
  { preset: "wonky_warp",        pocket: "classic",  kit: "02-bounce",          fm: "1", wonky: "1" },
  { preset: "sp1200",            pocket: "classic",  kit: "03-soulful-vintage", fm: "0", wonky: "0" },
  { preset: "wonky_burst",       pocket: "classic",  kit: "02-bounce",          fm: "0", wonky: "1" },
  { preset: "dilla_slight",      pocket: "classic",  kit: "02-bounce",          fm: "0", wonky: "0" },
  { preset: "mpc3000",           pocket: "classic",  kit: "02-bounce",          fm: "0", wonky: "0" },
  { preset: "dilla_drunk",       pocket: "dusty",    kit: "03-soulful-vintage", fm: "0", wonky: "0" },
].freeze

# Lead arp modes cycled each stream track (real figures, not held wash).
STREAM_LEAD_ARP_ROTATION = %i[
  wonky_spiral neo_quartal soul_wash moog_funk prophet_glass
  donuts_shimmer pocket_stab glass_spin vapor_wave acid_run
  crystal_scatter erykah_dust gospel_lift ballad_bloom melodic_soul
].freeze

# All 32 of LEAD_VOICE_PRESETS, not the 15 this used to name. capability_audit!
# reported 17 defined-but-unreachable lead voices: a voice nothing rotates is a
# voice no demo can play, and minimoog/supersaw/sitar/steelpan/brass are not
# near-duplicates of what was already here. The first 15 keep their order so the
# front of the rotation sounds as it did; the rest follow.
STREAM_LEAD_VOICE_ROTATION = %w[
  soul_prophet wonky moog prophet neo_pluck glass vapor
  crystal acid soft ballad gospel erykah donuts cs
  minimoog pluck neon yamaha vintage giga supersaw harmonica
  guitar steel sitar world horn brass bass steelpan watermelon
].freeze

STREAM_PAD_VOICE_ROTATION = %w[blend rhodes moog prophet juno].freeze

# Which defaults table last touched each ENV key, and how (fill vs force) —
# multiple tables (DILLA_BEST_DEFAULTS, RENDER_MODE_DEFAULTS,
# DILLA_STYLE_DEFAULTS, STREAM_EXTRA_DEFAULTS/STREAM_CREATIVE_MAX) apply in
# sequence, soft-fill only wins races when nothing set the key first, and
# that ordering has caused real, silent bugs (a style table's setting
# permanently losing to an earlier table because apply_render_mode! hadn't
# run yet). See "config-provenance" command.
def config_provenance
  @config_provenance ||= {}
end

def record_config_provenance!(key, label, verb)
  return unless label
  config_provenance[key] = "#{label} (#{verb})"
end

def comfort_mode?
  return false if ENV["STREAM_PUNCH"] == "1"
  return false if ENV["STREAM_COMFORT"] == "0" || ENV["DILLA_COMFORT"] == "0"
  return true if ENV["STREAM_COMFORT"] == "1" || ENV["DILLA_COMFORT"] == "1"
  return true if ENV["RENDER_MODE"].to_s.downcase == "comfort"

  false
end

def apply_comfort_style!(force: true)
  return unless comfort_mode?

  DILLA_COMFORT_DEFAULTS.each do |key, value|
    style_env_write!(key, value, force:, label: "DILLA_COMFORT_DEFAULTS")
  end
end

def soft_fill_env!(table, label: nil)
  table.each { |key, value| style_env_write!(key, value, force: false, label:) }
end

# Overwrite ENV keys (stream creative layer after style force-locks).
# One writer for every defaults/profile table, so the user-pin rule lives in one
# place instead of being re-implemented per loop.
#
# force_env! got the rule when USER_PINNED_ENV was introduced. Four other loops
# did not, and each kept its own bare `ENV[k] = v`: apply_dilla_style!'s
# DILLA_STYLE_DEFAULTS pass, reassert_dilla_style_locks!,
# apply_track_soul_profile!'s pad/lead profiles, and apply_track_layer_profile!.
# Every stream boot runs all four through apply_dilla_style!(force: true), so a
# pinned PAD_VOICE/LEAD_ARP/SYNTH_CYCLE was reverted before the first render and
# the documented environment variables were, again, advisory.
def style_env_write!(key, value, force:, label: nil)
  k = key.to_s
  return false if value.nil?
  return false unless force || ENV[k].to_s.empty?

  if USER_PINNED_ENV.key?(k) && ENV[k] == USER_PINNED_ENV[k]
    record_config_provenance!(k, label, "user-pinned")
    return false
  end

  ENV[k] = value.to_s
  record_config_provenance!(k, label, force ? "force" : "fill")
  true
end

def force_env!(table, label: nil)
  table.each { |key, value| style_env_write!(key, value, force: true, label:) }
end

def print_config_provenance
  if config_provenance.empty?
    puts "config-provenance: empty — run a render first (soft_fill_env!/force_env! haven't been called with labels yet)"
    return
  end
  width = config_provenance.keys.map(&:length).max
  config_provenance.sort.each { |key, source| puts "#{key.ljust(width)}  #{source}  = #{ENV[key].inspect}" }
end

def soft_fill_iterate!(tuning, locked_keys: [])
  locked = locked_keys.map(&:to_s)
  tuning.each do |key, value|
    next if value.nil?
    next if locked.include?(key.to_s)
    next if ENV[key] && !ENV[key].empty?
    ENV[key] = value.to_s
  end
end

def reassert_pad_lead_locks!
  return unless dilla_style?
  DILLA_PAD_LEAD_LOCK_KEYS.each do |key|
    next unless DILLA_STYLE_DEFAULTS.key?(key)

    style_env_write!(key, DILLA_STYLE_DEFAULTS[key], force: true, label: "DILLA_PAD_LEAD_LOCK")
  end
end

def reassert_dilla_style_locks!
  return unless dilla_style?
  # Same bypass as apply_dilla_style!'s loop: this reasserts on every track when
  # STREAM_LOCK=1, so a pin that survived boot was reverted one track later.
  DILLA_STYLE_LOCK_KEYS.each do |key|
    next unless DILLA_STYLE_DEFAULTS.key?(key)

    style_env_write!(key, DILLA_STYLE_DEFAULTS[key], force: true, label: "DILLA_STYLE_LOCK")
  end
  # A ceiling, not just a floor.
  #
  # These two lines took the LARGER of the setting and the style default, so the
  # pad envelope could only ever get slower. Progression presets asking for a
  # 1400 ms attack won every time, and the style that is supposed to sound like
  # a played Rhodes chord came out as a swell -- nine tenths of a second to
  # speak, three seconds to die away. Held stacked chords swelling like that is
  # a church organ, which is what the tracks sounded like.
  #
  # A struck electric piano speaks in a few milliseconds and is gone inside a
  # bar. The floor still applies, so nothing gets unnaturally clicky, but the
  # ceiling now stops a preset from turning the kit's own style into ambient
  # music.
  atk = [ENV["PAD_ATTACK"].to_i, DILLA_STYLE_DEFAULTS["PAD_ATTACK"].to_i].max
  rel = [ENV["PAD_RELEASE"].to_i, DILLA_STYLE_DEFAULTS["PAD_RELEASE"].to_i].max
  ENV["PAD_ATTACK"] = [atk, DILLA_PAD_ATTACK_CEILING].min.to_s
  ENV["PAD_RELEASE"] = [rel, DILLA_PAD_RELEASE_CEILING].min.to_s
end
alias reassert_camel_beauty_locks! reassert_dilla_style_locks!
