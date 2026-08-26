# frozen_string_literal: true
#
# Applying a genre, track or soul profile to the environment.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.
require_relative "../frozen_state"

# One word for genre.
#
# Genre was spread across RENDER_MODE, a preset's feel:, GROOVE_DNA, PERFORMER,
# SONITEX, ANALOG_CHAIN, POCKET_SET, VOICING and five separate CLI commands, so
# "make this one sound like jazz" meant knowing which six knobs to move and in
# which order. GENRE names the bundle.
#
# What this is NOT: a renderer switch. GENRE=techno colours a render and turns
# on the harmonic path; it does not route to render_hate_techno. Routing on a
# genre name would rebuild the fork this whole direction exists to remove,
# through a new door -- `dilla.rb hate` is still how you ask for that engine,
# and it now shares the progression with everything else.
#
# Soft-filled, so every value here loses to anything the operator set. That is
# the point of a bundle: a starting position, not a lock. Only knobs whose valid
# values are enumerable in this file are included -- GROOVE_DNA and PERFORMER
# are deliberately absent because their pools are assembled at runtime and a
# wrong constant here would fall back silently, which is the exact failure this
# tree keeps producing.
GENRE_DEFAULTS = {
  # The house lean. Named so it can be asked for explicitly rather than only
  # being what you get by not asking.
  hiphop: { "POCKET_SET" => "neo_soul", "SONITEX" => "donuts_warm",
            "SONITEX_PRESET" => "donuts_warm", "ANALOG_CHAIN" => "vinyl_hot",
            "VOICING" => "rootless" },
  soul: { "POCKET_SET" => "neo_soul", "SONITEX" => "hi_fi_soul",
          "SONITEX_PRESET" => "hi_fi_soul", "ANALOG_CHAIN" => "cassette",
          "VOICING" => "bill_evans" },
  jazz: { "POCKET_SET" => "classic", "SONITEX" => "subtle",
          "SONITEX_PRESET" => "subtle", "ANALOG_CHAIN" => "broadcast",
          "VOICING" => "kenny_barron" },
  # GENRE_HARMONY on, because a techno colour over a progression is the whole
  # reason this axis exists.
  techno: { "POCKET_SET" => "industrial", "SONITEX" => "heavy",
            "SONITEX_PRESET" => "heavy", "ANALOG_CHAIN" => "lo_fi",
            "VOICING" => "quartal", "GENRE_HARMONY" => "1" },
  lofi: { "POCKET_SET" => "dusty", "SONITEX" => "sp1200",
          "SONITEX_PRESET" => "sp1200", "ANALOG_CHAIN" => "cassette",
          "VOICING" => "drop2" },
}.freeze

def apply_genre!
  raw = ENV["GENRE"].to_s.strip.downcase
  return if raw.empty?

  table = GENRE_DEFAULTS[raw.to_sym]
  # Aborts rather than falling through. An unknown genre that quietly renders
  # the default is the failure mode this file is full of: the operator asks for
  # something, gets something else, and nothing says so.
  abort "unknown GENRE=#{raw} — known: #{GENRE_DEFAULTS.keys.join(', ')}" unless table

  soft_fill_env!(table, label: "GENRE_DEFAULTS[#{raw}]")
  DillaDmesg.style!("genre=#{raw}") if ENV["DILLA_STREAMING"] != "1"
end

def apply_render_mode!
  apply_genre!
  normalize_render_mode!
  mode = ENV["RENDER_MODE"]&.downcase&.to_sym
  return unless mode
  table = if mode == :dilla
            DILLA_STYLE_DEFAULTS
          else
            RENDER_MODE_DEFAULTS[mode]
          end
  return unless table
  soft_fill_env!(table, label: table.equal?(DILLA_STYLE_DEFAULTS) ? "DILLA_STYLE_DEFAULTS" : "RENDER_MODE_DEFAULTS[#{mode}]")
  DillaDmesg.style!("mode=#{mode}") if ENV["DILLA_STREAMING"] != "1"
end

def motif_recall_enabled?
  ENV.fetch("MOTIF_RECALL", composition_enabled? ? "1" : "0") != "0"
end

def apply_motif_recall!(bar)
  return unless motif_recall_enabled?
  return unless composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
  return unless bar.positive? && (bar % 16).zero?
  sess = @composition_session
  cb = sess.callbacks.select { |c| c[:motif_id] == "hook" }.max_by { |c| c[:bar] }
  state = cb ? cb[:state] : :A
  sess.record_callback!(bar, "hook", state)
end

def promote_progression_hook!(track, beauty, report: nil, path: nil)
  return if track.to_s.empty?
  min = (ENV["PROMOTION_BEAUTY_MIN"] || "85").to_f
  return unless beauty >= min
  gate = DillaMaster.passes_loss_gates?(report, path:)
  unless gate[:pass]
    warn "progression promotion blocked (loss gates): #{gate[:failures].join('; ')}"
    return
  end
  chords = DillaHarmony.last_progression_chords
  distinct = chords ? chords.map { |c| c[:name].to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "") }.uniq.length : 0
  return unless distinct >= 6
  FileUtils.mkdir_p(DillaComposition::PROJECT_DIR)
  promoted = begin
    File.exist?(PROMOTED_PROFILES_PATH) ? JSON.parse(File.read(PROMOTED_PROFILES_PATH)) : {}
  rescue JSON::ParserError => e
    # A corrupt file used to hit the blanket `rescue StandardError` below and
    # return without ever rewriting it -- permanently disabling promotion
    # learning from that point on. Reset and self-repair on the next write
    # instead of staying wedged forever.
    warn "promoted_profiles.json corrupt (#{e.message}), resetting"
    {}
  end
  key = track.to_s.downcase.tr("-", "_")
  promoted[key] = (promoted[key] || 0) + 1
  promoted["_last"] = { "track" => key, "beauty" => beauty.round(1), "at" => Time.now.utc.iso8601 }
  DillaFrozen.write_json(PROMOTED_PROFILES_PATH, promoted)
  remove_instance_variable(:@radio_bergen_learnings) if instance_variable_defined?(:@radio_bergen_learnings)
rescue StandardError => e
  warn "progression promotion failed: #{e.message}"
end

def apply_profile_mash!(cfg)
  mash = ENV["PROFILE_MASH"]
  return cfg unless mash&.include?("+")
  harm_key, drum_key = mash.split("+", 2).map { |s| s.strip.downcase.tr("-", "_").to_sym }
  harm_preset = track_preset(harm_key)
  drum_preset = track_preset(drum_key)
  return cfg unless harm_preset && drum_preset
  harm_sonic = sonic_profile_for(harm_key)
  feel = drum_preset[:feel] || cfg[:feel]
  cfg.merge(
    track: :"#{harm_key}_x_#{drum_key}",
    progression: (ENV["PROGRESSION"] || harm_preset.fetch(:progression, harm_key)).to_s.downcase.tr("-", "_").to_sym,
    bpm: resolve_bpm(harm_preset, harm_key, harm_sonic),
    feel:,
    timing: drum_preset[:timing] || cfg[:timing],
    style_family: style_family(drum_key, feel:),
    mashed: { harmony: harm_key, drums: drum_key },
  )
end

def slash_bass_enabled?(cfg)
  ENV["SLASH_BASS"] == "1" ||
    SLASH_BASS_PROFILES.include?(cfg[:progression].to_sym) ||
    cfg[:track].to_s.include?("slash")
end

def slash_bass_pads_for(pads, cfg)
  return if pads.empty?
  root = pads.first[:hz].min * 0.5
  generate_slash_progression(root_hz: root, length: pads.length, seed: stable_hash(cfg[:track].to_s))
end

def ghost_tier_for(bar, section)
  forced = ENV["GHOST_TIER"]&.to_sym
  return forced if forced && GHOST_TIERS.key?(forced)
  if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
    sect = @composition_session.section_at(bar)
    prof = @composition_session.profile_at(bar)
    case sect
    when :intro, :breakdown then :whisper
    when :hook, :solo then :accent
    else prof[:fill_rate].to_f > 0.4 ? :accent : :pocket
    end
  else
    case section
    when :intro, :breakdown then :whisper
    when :build then :accent
    else :pocket
    end
  end
end

def apply_ghost_tier_vel(vel, tier)
  (vel * GHOST_TIERS.fetch(tier, GHOST_TIERS[:pocket])[:mul]).clamp(0.03, 0.72).round(3)
end

# Stems are written unless STEM_EXPORT=0 or KEEP_STEMS=0.
#
# It was opt-in, so the default was that a render you might want to remix
# arrived flattened and the parts were gone. Nothing here changes what the
# mix sounds like — it writes files beside it — which is why this one can be
# turned on without an ear on it. The cost is disk, and the crate is the
# place that has been expensive rather than this.
def export_render_stems!(destination, drum_tmp, harmonic_tmp, events, duration, cfg, use_stem_harmony:)
  return unless ENV["STEM_EXPORT"] != "0" || ENV["KEEP_STEMS"] != "0"
  stem_dir = File.join(File.dirname(destination), "#{File.basename(destination, '.*')}_stems")
  FileUtils.mkdir_p(stem_dir)
  FileUtils.cp(drum_tmp, File.join(stem_dir, "drums.wav")) if File.exist?(drum_tmp)
  unless use_stem_harmony
    FileUtils.cp(harmonic_tmp, File.join(stem_dir, "harmonic.wav")) if File.exist?(harmonic_tmp)
    bass_tmp = File.join(stem_dir, ".bass_layer.wav")
    render_harmonic_wav(bass_tmp, [], [], events[:bass] || [], duration, cfg:)
    FileUtils.cp(bass_tmp, File.join(stem_dir, "bass.wav")) if File.exist?(bass_tmp)
    FileUtils.rm_f(bass_tmp)
    if events[:melody]&.any?
      mel_tmp = File.join(stem_dir, ".melody_layer.wav")
      render_harmonic_wav(mel_tmp, [], [], [], duration, melody_events: events[:melody], cfg:)
      FileUtils.cp(mel_tmp, File.join(stem_dir, "melody.wav")) if File.exist?(mel_tmp)
      FileUtils.rm_f(mel_tmp)
    end
  end
  FileUtils.cp(destination, File.join(stem_dir, "master#{File.extname(destination)}")) if File.exist?(destination)
  FileUtils.cp(DillaComposition::SESSION_PATH, File.join(stem_dir, "session.json")) if File.exist?(DillaComposition::SESSION_PATH)
  FileUtils.cp(DillaComposition::MOTIFS_PATH, File.join(stem_dir, "motifs.json")) if File.exist?(DillaComposition::MOTIFS_PATH)
  puts "stems: #{stem_dir}"
end

# How many voices a track is allowed to put in the air. dilla's default stack is
# pads + texture + EP + warm + scale lead + lead arp + harmony lead + xlead +
# granular cloud + choir + melody + chops, and everything after the first few is
# fighting the rest for the same space -- audibly "too much going on", and the
# reason a sample bed could not be pushed forward no matter what weight it was
# given: the master limiter was already flattening a crowded mix.
#
# A recreation should carry only what the source has. The 92 BPM Ableton set
# behind :four_seven is four elements -- a sampled loop, an FM bass, a kick and
# a clap -- so everything dilla would otherwise pile on top is turned off, and
# the loop is left to be the harmony, which is its job in the original.
#
# Twelve tracks carry a sampled bed; two had a profile. The other ten got
# dilla's full stack on top of the record, and in the 34-track demo those ten
# held the bottom of the measured enjoyment ranking -- ubrukte_samples_01 last
# of thirty-three. dmaj_open and sheger_01 below are four_seven's shape applied
# to two of them. MASTER_CHAIN is deliberately not copied: that is a mastering
# change, not an arrangement one.
#
# Measured caveat, so nobody reads more into these than is there: with only the
# twelve knobs that survive into demo-all (see apply_track_layer_profile!'s
# caller), adding this profile moved nothing -- lo_borges -0.08, sheger_01
# +0.04 on audiobox-aesthetics content-enjoyment, against a within-arm spread
# of 0.05-0.09 over three seeds. The nine layer-stripping knobs were untestable
# until the re-assert in demo_all landed alongside this.
TRACK_LAYER_PROFILES = {
  four_seven: {
    "PAD_TEXTURE" => "0", "PAD_GRANULAR" => "0", "CHOIR_VOX" => "0",
    "LEAD_ARP" => "0", "SCALE_LEAD" => "0", "HARMONY_LEAD" => "0",
    "CREATIVE_LEAD" => "0", "MELODIC_LEAD" => "0", "EXPERIMENTAL_LEADS" => "0",
    "LEAD_MORPH" => "0", "SYNTH_MORPH" => "0", "PAD_LAYERS" => "0",
    "DRUM_CHOPS" => "0", "ECLECTIC_PERC" => "0", "SELF_SAMPLE" => "0",
    # SPEAK stays off — the source set has no speech in it. RAP_VOCAL does not:
    # the point of this track now is gunnhild over the sampled loop, and a
    # profile default that silently discarded an explicit RAP_VOCAL on the
    # command line made the render look like it had ignored the request.
    "SPEAK" => "0",
    # The loop carries the chords; the synth pad only shades under it.
    "PAD_VOL" => "34", "HARM_MIX_WEIGHT" => "0.55",
    "SAMPLE_LOOP_VOL" => "1.25", "SAMPLE_LOOP_WEIGHT" => "1.6",
    "MASTER_CHAIN" => "akmd",
  },
  # Same shape as four_seven -- the loop carries the harmony, the synths shade
  # under it -- but this source is denser and sits higher, so the pad is pulled
  # further back and the loop is not pushed as hard.
  nightbus: {
    "PAD_TEXTURE" => "0", "CHOIR_VOX" => "0", "SPEAK" => "0",
    "LEAD_ARP" => "0", "SCALE_LEAD" => "0", "HARMONY_LEAD" => "0",
    "CREATIVE_LEAD" => "0", "MELODIC_LEAD" => "0", "EXPERIMENTAL_LEADS" => "0",
    "LEAD_MORPH" => "0", "SYNTH_MORPH" => "0", "PAD_LAYERS" => "0",
    "DRUM_CHOPS" => "0", "ECLECTIC_PERC" => "0", "SELF_SAMPLE" => "0",
    "PAD_VOL" => "26", "HARM_MIX_WEIGHT" => "0.45",
    "SAMPLE_LOOP_VOL" => "1.1", "SAMPLE_LOOP_WEIGHT" => "1.45",
    "MASTER_CHAIN" => "akmd",
  },
  # lo_borges -- a hand-cut record, so the loop is the harmony here too.
  dmaj_open: {
    "PAD_TEXTURE" => "0", "PAD_GRANULAR" => "0", "CHOIR_VOX" => "0",
    "LEAD_ARP" => "0", "SCALE_LEAD" => "0", "HARMONY_LEAD" => "0",
    "CREATIVE_LEAD" => "0", "MELODIC_LEAD" => "0", "EXPERIMENTAL_LEADS" => "0",
    "LEAD_MORPH" => "0", "SYNTH_MORPH" => "0", "PAD_LAYERS" => "0",
    "DRUM_CHOPS" => "0", "ECLECTIC_PERC" => "0", "SELF_SAMPLE" => "0",
    "SPEAK" => "0",
    "PAD_VOL" => "34", "HARM_MIX_WEIGHT" => "0.55",
    "SAMPLE_LOOP_VOL" => "1.25", "SAMPLE_LOOP_WEIGHT" => "1.6",
  },
  # ubrukte_samples_01 -- cut from the Sheger broadcast by `chop`.
  sheger_01: {
    "PAD_TEXTURE" => "0", "PAD_GRANULAR" => "0", "CHOIR_VOX" => "0",
    "LEAD_ARP" => "0", "SCALE_LEAD" => "0", "HARMONY_LEAD" => "0",
    "CREATIVE_LEAD" => "0", "MELODIC_LEAD" => "0", "EXPERIMENTAL_LEADS" => "0",
    "LEAD_MORPH" => "0", "SYNTH_MORPH" => "0", "PAD_LAYERS" => "0",
    "DRUM_CHOPS" => "0", "ECLECTIC_PERC" => "0", "SELF_SAMPLE" => "0",
    "SPEAK" => "0",
    "PAD_VOL" => "34", "HARM_MIX_WEIGHT" => "0.55",
    "SAMPLE_LOOP_VOL" => "1.25", "SAMPLE_LOOP_WEIGHT" => "1.6",
  },
}.freeze

def apply_track_layer_profile!(track, force: true)
  # Same aliasing as the loop registry: the profiles are still keyed by the
  # names these were ingested under, so a render asked for by song title has to
  # resolve to them or it silently loses its layer settings.
  key = track.to_s.downcase.tr("-", "_").to_sym
  key = TRACK_SAMPLE_LOOP_ALIASES.key(key) || key unless TRACK_LAYER_PROFILES.key?(key)
  profile = TRACK_LAYER_PROFILES[key] or return []
  applied = []
  profile.each do |env_key, value|
    applied << env_key if style_env_write!(env_key, value, force:, label: "TRACK_LAYER_PROFILE")
  end
  dmesg("layer profile #{track}: #{applied.size} knobs (strip to source arrangement)",
        unit: "style0", parent: "dilla0") if applied.any?
  applied
end

def apply_track_soul_profile!(track, force: false)
  key = track.to_s.downcase.tr("-", "_").to_sym
  apply_track_layer_profile!(key, force:)
  [TRACK_SOUL_PAD_PROFILES[key], TRACK_SOUL_LEAD_PROFILES[key]].compact.each do |profile|
    profile.each do |env_key, value|
      # Never demote multi-layer stacks to single-voice presets mid-stream.
      next if env_key == "PAD_VOICE" && ENV["PAD_VOICE"].to_s.start_with?("stack_")

      style_env_write!(env_key, value, force:, label: "TRACK_SOUL_PROFILE")
    end
  end
end

def apply_dilla_style!(force: false)
  normalize_render_mode!
  ENV["RENDER_MODE"] = DEFAULT_RENDER_MODE if ENV["RENDER_MODE"].to_s.empty?
  apply_render_mode!
  # Full style DNA only on the dilla path. warp/long_soul/golden/… already
  # soft-filled their own RENDER_MODE_DEFAULTS tables above.
  return unless dilla_style?

  # Every stream boot calls this with force: true via
  # apply_stream_listenability_defaults!, and this loop used to write ENV
  # directly. Measured: launching with `PAD_VOICE=prophet LEAD_ARP=0
  # SYNTH_CYCLE=0 SYNTH_MORPH=0 STREAM_ROTATE_SYNTH=0` came out of one pass as
  # `stack_soul / 1 / 1 / 1 / 1` — five pins reverted. The re-enabled rotation
  # then moved the pad to `blend` and the re-enabled patch cycle picked
  # rhodes_bleeding_edge/jp8_brass_arp: harsh voices nobody asked for, chosen
  # because the request had been discarded. style_env_write! holds the pin rule.
  DILLA_STYLE_DEFAULTS.each do |key, value|
    style_env_write!(key, value, force:, label: "DILLA_STYLE_DEFAULTS")
  end
  track = ENV["TRACK"].to_s
  track = "pedal_e_descent" if track.empty?
  apply_track_soul_profile!(track, force:)
  apply_concrete_soul_mix!(track)
  reassert_dilla_style_locks! if force
  reassert_pad_lead_locks!
  ensure_learned_engine_seeded!
  apply_learned_env_for_track!(track)
  apply_comfort_style!(force:)
end
alias apply_camel_profile! apply_dilla_style!

def pick_default_track!
  return if ENV["TRACK"] && !ENV["TRACK"].empty?
  mode = ENV["RENDER_MODE"].to_s.downcase
  # Leave TRACK empty for dilla/camel/comfort/empty so DILLA_STYLE_DEFAULTS
  # soft-fill can supply pedal_e_descent. Random deep rotation is for stream
  # after style force, or non-style modes only.
  return if mode.empty? || %w[dilla camel comfort].include?(mode)

  if deep_render?
    pool = stream_track_pool
    seed = Time.now.to_i + Process.pid + (@render_seed || 0)
    ENV["TRACK"] = pool[Random.new(seed).rand(pool.length)]
  else
    ENV["TRACK"] = DillaLofiMachine::DEFAULT_PROFILE.to_s
  end
end

def apply_best_defaults!
  return if ENV["DILLA_RAW"] == "1"
  apply_render_mode!
  soft_fill_env!(DILLA_BEST_DEFAULTS, label: "DILLA_BEST_DEFAULTS")
  soft_fill_env!(DILLA_DEEP_DEFAULTS, label: "DILLA_DEEP_DEFAULTS") if deep_render?
  pick_default_track!
end

def apply_stream_listenability_defaults!
  apply_best_defaults!
  # One engine DNA. Optional mix knobs only (STREAM_COMFORT / RENDER_MODE=warp).
  soft_fill_env!(STREAM_EXTRA_DEFAULTS, label: "STREAM_EXTRA_DEFAULTS")
  if stream_deep?
    ENV["DILLA_DEEP"] = "1" if ENV["DILLA_DEEP"].to_s.empty?
    soft_fill_env!(DILLA_DEEP_DEFAULTS, label: "DILLA_DEEP_DEFAULTS")
  else
    fast = STREAM_FAST_DEFAULTS.dup
    STREAM_ITERATE_OVERRIDE_KEYS.each { |key| fast.delete(key) } if stream_iterate_enabled?
    soft_fill_env!(fast, label: "STREAM_FAST_DEFAULTS")
  end
  soft_fill_iterate!(STREAM_ITERATE_TUNING, locked_keys: DILLA_STYLE_LOCK_KEYS) if stream_iterate_enabled?
  if ENV.fetch("STREAM_SOUL", "1") != "0"
    soft_fill_env!(STREAM_SOUL_DEFAULTS, label: "STREAM_SOUL_DEFAULTS")
  end
  ensure_learned_engine_seeded!
  apply_learned_env_for_track!(ENV["TRACK"]) if ENV["TRACK"] && !ENV["TRACK"].empty?
  normalize_render_mode!
  ENV["RENDER_MODE"] = DEFAULT_RENDER_MODE if ENV["RENDER_MODE"].to_s.empty?
  apply_dilla_style!(force: true)
  # Optional sofa mix knob — not a separate "style".
  force_env!(DILLA_COMFORT_DEFAULTS.reject { |k, _| k.start_with?("SPEAK") }, label: "DILLA_COMFORT_DEFAULTS") if comfort_mode?
  unless comfort_mode?
    # Default: style DNA wins. Creative max only when STREAM_CREATIVE=1 or STREAM_PUNCH=1.
    force_env!(STREAM_STYLE_SAFE, label: "STREAM_STYLE_SAFE")
    if stream_creative_mode?
      force_env!(STREAM_CREATIVE_MAX, label: "STREAM_CREATIVE_MAX")
      force_env!(STREAM_ITERATE_TUNING, label: "STREAM_ITERATE_TUNING") if stream_iterate_enabled?
    elsif stream_iterate_enabled?
      # Mild iterate without wild LUFS/vinyl/LA-beat overrides.
      force_env!(
        STREAM_ITERATE_TUNING.reject do |k, _|
          %w[STREAM_ANALOG_WILD STREAM_ANALOG_EVERY].include?(k)
        end,
        label: "STREAM_ITERATE_TUNING",
      )
    end
  end
  ENV["PLAY_VOL"] = "1" if ENV["PLAY_VOL"].to_s.empty?
  ENV["DILLA_STREAMING"] = "1"
  record_config_provenance!("DILLA_STREAMING", "apply_stream_listenability_defaults!", "force")
end
