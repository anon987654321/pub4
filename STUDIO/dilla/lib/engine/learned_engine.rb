# frozen_string_literal: true
#
# The learned engine: what listening to sources taught, and promoting it.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.
require_relative "../frozen_state"

# Sparse boom-bap base. Bar-to-bar phrase rotation is DillaGroove.pocket_* when
# POCKET_DNA=1. Keep this simple — dense grids are why the kit sounded wrong.
# Was t6SXXx1Fu_4, which is not the id radio_bergen_tracks.yml gives for Flying
# Lotus "Camel". Corrected to match the manifest, but kept as a literal rather
# than read from it: this file stays runnable on its own, and a citation is not
# worth a load-time dependency on a sidecar. Corrects the CITATION only -- the
# grid below was transcribed by ear, and if it came off the wrong video no id
# change repairs it.
WONKY_CAMEL_SOURCE_URL = "https://www.youtube.com/watch?v=fU9YRGLPDQ8".freeze
POLY_TEMPORAL_DRUM_GRID = {
  "bpm" => 86,
  "swing" => 60,
  "source" => "pocket_dna_simple",
  "source_url" => WONKY_CAMEL_SOURCE_URL,
  "wonky_kicks" => [0, 6, 10],
  "wonky_snares" => [4, 12],
  "wonky_ghost_snares" => [7],
  "wonky_hats" => [0, 2, 4, 6, 8, 10, 12, 14],
  "wonky_hat_ghosts" => [],
  "wonky_perc" => [],
  "wonky_claps" => [4, 12],
}.freeze
CAMEL_PROGRESSION_SYMS = %w[Dm9 Cm11nc AbMaj13s11 Gm7 Eb7 A7nc Dmaj9nc DMaj7overG].freeze

BUILTIN_LEARNED_ENGINE = {
  "progressions" => {
    "chromatic_mediant_drift" => CAMEL_PROGRESSION_SYMS,
    "quartal_west_coast" => CAMEL_PROGRESSION_SYMS,
    "wonky_camel" => CAMEL_PROGRESSION_SYMS,
    "camel_bridge" => CAMEL_BRIDGE_SYMS,
    "camel_functional" => CAMEL_FUNCTIONAL_SYMS,
  },
  "drum_grids" => {
    "chromatic_mediant_drift" => POLY_TEMPORAL_DRUM_GRID,
    "quartal_west_coast" => POLY_TEMPORAL_DRUM_GRID,
    "wonky_camel" => POLY_TEMPORAL_DRUM_GRID,
  },
  "calibrations" => {},
  "track_aliases" => {
    "wonky_camel" => "chromatic_mediant_drift",
    "quartal_west_coast" => "chromatic_mediant_drift",
  },
  "top_track" => nil,
  "promoted_at" => nil,
}.freeze

def deep_merge_learned_engine!(base, overlay)
  overlay.each do |key, val|
    if val.is_a?(Hash) && base[key].is_a?(Hash)
      val.each { |k, v| base[key][k] = v }
    elsif !base.key?(key)
      base[key] = val
    else
      base[key] = val unless val.nil?
    end
  end
  base
end

def load_learned_engine(refresh: false)
  remove_instance_variable(:@learned_engine_cache) if refresh && instance_variable_defined?(:@learned_engine_cache)
  return @learned_engine_cache if instance_variable_defined?(:@learned_engine_cache) && @learned_engine_cache
  base = JSON.parse(JSON.generate(BUILTIN_LEARNED_ENGINE))
  if File.file?(DillaSourceLearn::LEARNED_ENGINE_PATH)
    file_data = JSON.parse(File.read(DillaSourceLearn::LEARNED_ENGINE_PATH))
    deep_merge_learned_engine!(base, file_data)
  end
  @learned_engine_cache = base
rescue StandardError
  @learned_engine_cache = JSON.parse(JSON.generate(BUILTIN_LEARNED_ENGINE))
end

def ensure_learned_engine_seeded!
  return if File.file?(DillaSourceLearn::LEARNED_ENGINE_PATH)
  DillaSourceLearn.ensure_dir!
  save_learned_engine!(JSON.parse(JSON.generate(load_learned_engine)))
end

def save_learned_engine!(data)
  DillaSourceLearn.ensure_dir!
  data["promoted_at"] = Time.now.utc.iso8601
  DillaFrozen.write_json(DillaSourceLearn::LEARNED_ENGINE_PATH, data)
  @learned_engine_cache = data
  data
end

def learned_chord_pad(sym)
  PAD_CHORD_LOOKUP[sym] || MODAL_MINOR_CHORDS.find { |c| c[:name] == sym } ||
    (DillaLofiMachine.chord_from_symbol(sym) rescue nil)
end

def learned_progression_pads(key)
  syms = load_learned_engine.dig("progressions", key.to_s)
  return unless syms.is_a?(Array) && syms.length >= 2
  syms.filter_map { |n| learned_chord_pad(n) }
end

def learned_drum_steps(role)
  track = (ENV["TRACK"] || "").to_s
  eng = load_learned_engine
  grid = eng.dig("drum_grids", track) || eng.dig("drum_grids", eng.dig("track_aliases", track))
  return unless grid.is_a?(Hash)
  case role
  when :kicks then Array(grid["kicks"] || grid["wonky_kicks"] || grid["flylo_kicks"] || grid[:kicks])
  when :snares then Array(grid["snares"] || grid["wonky_snares"] || grid["flylo_snares"] || grid[:snares])
  when :hats then Array(grid["hats"] || grid["wonky_hats"] || grid["flylo_hats"] || grid[:hats])
  end
end

def apply_learned_env_for_track!(track)
  return unless track && !track.to_s.empty?
  eng = load_learned_engine
  t = track.to_s
  alias_key = eng.dig("track_aliases", t)
  # Never remap a curated catalog TRACK onto a learned promo progression.
  # Opt in with LEARNED_PROGRESSION=1 when you want that behavior.
  allow_learned_prog = ENV.fetch("LEARNED_PROGRESSION", "0") != "0"
  has_catalog = CHORD_PROGRESSIONS.key?(t.to_sym) ||
                DillaLofiMachine.harmony_profile?(t.to_sym) ||
                CHORD_PROGRESSIONS.key?(ENV["PROGRESSION"].to_s.downcase.tr("-", "_").to_sym)
  if allow_learned_prog && !has_catalog
    prog_keys = [alias_key, t, eng["top_track"]].compact.uniq
    prog_keys.each do |pk|
      next unless eng.dig("progressions", pk.to_s)&.length.to_i >= 2
      ENV["PROGRESSION"] = pk.to_s if ENV["PROGRESSION"].nil? || ENV["PROGRESSION"].empty?
      break
    end
  end
  grid = eng.dig("drum_grids", t) || (alias_key && eng.dig("drum_grids", alias_key))
  if grid.is_a?(Hash)
    ENV["BPM"] = grid["bpm"].to_s if grid["bpm"] && (ENV["BPM"].nil? || ENV["BPM"].empty?)
  end
  cal = eng.dig("calibrations", "global")
  return unless cal.is_a?(Hash)
    ENV["SWING"] = cal["swing"].to_s if cal["swing"] && (ENV["SWING"].nil? || ENV["SWING"].empty?)
    ENV["BPM"] = cal["bpm"].to_s if cal["bpm"] && (ENV["BPM"].nil? || ENV["BPM"].empty?)

end

def learn_catalog_top_hint
  eng = load_learned_engine
  if eng["top_track"]
    return { track: eng["top_track"], voicing: :kenny_barron, performer: "yancey", groove_dna: "donuts" }
  end
  cat = DillaSourceLearn.load_playlist_catalog
  tally = Hash.new(0)
  Array(cat["tracks"]).each do |row|
    eh = row["engine_hints"]
    cd = row["copyable_dna"]
    hint = (eh.is_a?(Hash) ? (eh["track"] || eh[:track]) : nil) ||
           (cd.is_a?(Hash) && cd["engine"].is_a?(Hash) ? (cd["engine"]["track"] || cd["engine"][:track]) : nil)
    tally[hint.to_s] += 1 if hint && !hint.to_s.empty?
  end
  top = tally.max_by { |_, c| c }&.first
  top ? { track: top.to_sym, performer: "yancey", groove_dna: "donuts" } : nil
end

def playlist_row_key(row)
  id = row[:youtube_id].to_s.strip
  id.empty? ? RadioBergenStudy.slug(row[:artist], row[:title]) : id
end

def learn_promote!(min_chords: 4)
  DillaSourceLearn.ensure_dir!
  catalog = DillaSourceLearn.load_playlist_catalog
  eng = load_learned_engine(refresh: true)
  promoted = 0
  Array(catalog["tracks"]).each do |raw|
    t = raw.transform_keys(&:to_s)
    next if t["id"] == "test_slug"
    dna = t["copyable_dna"] || {}
    harm = (dna["harmony"].is_a?(Hash) ? dna["harmony"]["progression"] : nil) || t["progression_symbols"]
    harm = Array(harm).map(&:to_s).reject(&:empty?)
    next unless harm.length >= min_chords
    slug = t["id"].to_s
    prog_key = "learned_#{slug}"
    eng["progressions"][prog_key] = harm
    eh = t["engine_hints"]
    engine_track = (eh.is_a?(Hash) ? (eh["track"] || eh[:track]) : nil) ||
                   (dna["engine"].is_a?(Hash) ? (dna["engine"]["track"] || dna["engine"][:track]) : nil) || slug
    eng["track_aliases"][engine_track.to_s] = prog_key
    eng["track_aliases"][slug] = prog_key
    drums = dna["drums"]
    if drums.is_a?(Hash) && (drums["kicks"] || drums["snares"])
      eng["drum_grids"][engine_track.to_s] = drums
      eng["drum_grids"][slug] = drums
    end
    promoted += 1
  end
  eng["top_track"] = learn_catalog_top_hint&.dig(:track)&.to_s || eng["top_track"]
  save_learned_engine!(eng)
  warn "learn-promote: #{promoted} progression(s) → #{DillaSourceLearn::LEARNED_ENGINE_PATH}" unless ENV["DILLA_QUIET"] == "1"
  { promoted:, path: DillaSourceLearn::LEARNED_ENGINE_PATH }
end

def learn_calibrate!(audio_root: nil)
  data = RadioBergenStudy.dossiers!(audio_root:)
  eng = load_learned_engine(refresh: true)
  bpms = []
  swings = Hash.new(0)
  Array(data[:tracks]).each do |row|
    measured = row[:analysis]
    ref = row[:production_dossier]
    next unless measured&.dig(:measured)
    id = row[:id].to_s
    eng["calibrations"][id] = {
      bpm_measured: measured[:bpm_estimate],
      bpm_curated: ref&.dig(:bpm),
      swing_hint: measured.dig(:dynamics, :swing_hint),
    }.compact
    bpms << measured[:bpm_estimate] if measured[:bpm_estimate]
    sh = measured.dig(:dynamics, :swing_hint)
    swings[sh] += 1 if sh
  end
  if bpms.any?
    eng["calibrations"]["global"] = {
      "bpm" => (bpms.sum / bpms.length).round,
      "swing" => (DillaLofiMachine::DRUM_PRESETS[:dilla_slight][:swing] + (swings["laid_back"] || 0) * 2 -
                  (swings["pushed"] || 0)).clamp(52, 62),
    }
  end
  save_learned_engine!(eng)
  puts "learn-calibrate: #{eng['calibrations'].length} entries (global bpm=#{eng.dig('calibrations', 'global', 'bpm')})"
  eng
end

def learn_diff_dossiers!(audio_root: nil)
  dossiers = RadioBergenStudy.dossiers!(audio_root:)
  catalog = DillaSourceLearn.load_playlist_catalog
  cat_by_id = Array(catalog["tracks"]).to_h { |t| [t["id"], t] }
  diffs = []
  Array(dossiers[:tracks]).each do |row|
    id = row[:id].to_s
    ref = row[:production_dossier]
    measured = row[:analysis]
    learned = cat_by_id[id]
    entry = {
      id:, artist: row[:artist], title: row[:title],
      curated_bpm: ref&.dig(:bpm), measured_bpm: measured&.dig(:bpm_estimate),
      curated_harmony: ref&.dig(:harmony), curated_drums: ref&.dig(:drums),
      measured_swing: measured&.dig(:dynamics, :swing_hint),
      learned_progression: (lp = learned&.[]("copyable_dna")) && lp["harmony"].is_a?(Hash) ? lp["harmony"]["progression"] : nil,
      learned_drums: (lp = learned&.[]("copyable_dna")) ? lp["drums"] : nil,
      calibration_notes: row[:calibration_notes]
    }
    if ref && measured&.dig(:bpm_estimate) && ref[:bpm]
      entry[:bpm_delta] = (measured[:bpm_estimate] - ref[:bpm]).round(1)
    end
    diffs << entry
  end
  payload = { generated_at: Time.now.utc.iso8601, tracks: diffs }
  DillaSourceLearn.ensure_dir!
  DillaFrozen.write_json(DillaSourceLearn::DOSSIER_DIFF_PATH, payload)
  puts "learn-diff: #{diffs.length} tracks → #{DillaSourceLearn::DOSSIER_DIFF_PATH}"
  payload
end

def composition_feed_from_learn!(sess)
  return unless sess
  apply_learned_env_for_track!(sess.track.to_s)
  eng = load_learned_engine
  prog_key = eng.dig("track_aliases", sess.track.to_s) || sess.track.to_s
  syms = eng.dig("progressions", prog_key)
  return unless syms.is_a?(Array) && syms.length >= 2
  sess.instance_variable_set(:@learned_progression, syms)
end
