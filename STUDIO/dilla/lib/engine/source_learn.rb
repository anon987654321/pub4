# frozen_string_literal: true
#
# Ingest a source track and turn it into engine hints.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# YouTube/local ingest → demucs → rhythm/harmony analysis → engine hints (inlined).
module DillaSourceLearn
  LEARNINGS_DIR = File.expand_path("project/learnings", ROOT).freeze
  LAST_REPORT_PATH = File.join(LEARNINGS_DIR, "last_learn.json").freeze
  PLAYLIST_CATALOG_PATH = File.join(LEARNINGS_DIR, "playlist_catalog.json").freeze
  PLAYLIST_BATCH_STATE_PATH = File.join(LEARNINGS_DIR, "playlist_batch_state.json").freeze
  PLAYLIST_TRACKS_DIR = File.join(LEARNINGS_DIR, "tracks").freeze
  LEARNED_ENGINE_PATH = File.join(LEARNINGS_DIR, "learned_engine.json").freeze
  DOSSIER_DIFF_PATH = File.join(LEARNINGS_DIR, "dossier_diff.json").freeze
  PLAYLIST_BATCH_LOG = File.join(LEARNINGS_DIR, "playlist_batch.log").freeze

  HARMONY_STEMS = %w[piano.wav other.wav guitar.wav].freeze
  VOICING_ROTATION = %i[spread drop2 rootless kenny_barron bill_evans quartal].freeze
  SONITEX_ROTATION = %i[donuts_warm cassette sp1200 subtle scuzz].freeze

  module_function

  def ensure_dir!
    FileUtils.mkdir_p(LEARNINGS_DIR)
  end

  def compose_report(source:, stem_dir:, stem_analysis:, full_analysis: nil)
    harmonic = stem_analysis.values_at(*HARMONY_STEMS).compact
    chords = harmonic.flat_map { |s| s[:top_chords] || [] }
    major_third_cycle_full = harmonic.filter_map { |s| s[:coltrane_candidates] }.flatten(1)
    merged_pcs = harmonic.flat_map { |s| s[:pitch_classes] || [] }.tally.sort_by { |_, c| -c }.map(&:first)
    progression_symbols = (chords + major_third_cycle_full).map { |c| c[:name] || c["name"] }.compact.uniq.first(8)
    progression_insight = nil
    if defined?(DillaHarmony) && progression_symbols.length >= 2
      progression_insight = DillaHarmony.progression_insight(progression_symbols.map { |n| { name: n } })
    end
    bpm_est = stem_analysis["drums.wav"]&.fetch(:bpm_estimate, nil) ||
              full_analysis&.dig(:bpm_estimate) ||
              stem_analysis.values.map { |s| s[:bpm_estimate] }.compact.first
    semantics = full_analysis&.dig(:semantics) || stem_analysis["other.wav"]&.fetch(:semantics, nil)
    {
      source:, stem_dir:, analyzed_at: Time.now.utc.iso8601,
      bpm_estimate: bpm_est, progression_symbols:,
      progression_insight:, pitch_classes: merged_pcs.first(12),
      stems: stem_analysis, semantics:,
      engine_hints: suggest_engine_patch(progression_symbols:,
                                       progression_insight:, bpm: bpm_est, semantics:),
      drum_pattern: stem_analysis["drums.wav"]&.slice(:step_grid, :bpm_estimate, :swing_hint, :drum_density),
      melody_hints: harmonic.map { |s| s.slice(:pitch_classes, :top_chords) }.reject(&:empty?),
      copyable_dna: nil
    }.tap { |rep| rep[:copyable_dna] = copyable_dna(rep) }
  rescue StandardError => e
    warn "learn report: #{e.message}" if ENV["DILLA_DEBUG"]
    { source:, stem_dir:, analyzed_at: Time.now.utc.iso8601, error: e.message,
      engine_hints: suggest_engine_patch(progression_symbols: [], progression_insight: nil, bpm: nil, semantics: nil) }
  end

  def suggest_engine_patch(progression_symbols:, progression_insight:, bpm:, semantics:)
    track = map_progression_to_track(progression_symbols, progression_insight)
    voicing = VOICING_ROTATION[(stable_hash(progression_symbols.join)) % VOICING_ROTATION.length]
    sonitex = semantics&.include?("vinyl") || semantics&.include?("dusty") ? :donuts_warm : :cassette
    sonitex = SONITEX_ROTATION[(bpm.to_f.round * 3).to_i % SONITEX_ROTATION.length] if bpm
    analog = semantics&.include?("warm") ? :acetate : :vinyl_hot
    { track:, voicing:, sonitex_preset: sonitex, analog_chain: analog, bpm: bpm&.round,
      groove_dna: bpm && bpm < 88 ? "endtroducing" : "donuts", performer: "yancey",
      notes: [progression_insight ? "major_third_cycle_full=#{progression_insight[:notation]} in #{progression_insight[:scale]}" : nil,
              progression_symbols.any? ? "chords=#{progression_symbols.first(4).join('-')}" : nil].compact }
  end

  def map_progression_to_track(symbols, _insight)
    joined = symbols.map { |s| s.to_s.downcase }.join(" ")
    return :maj7_minor_cycle if joined.include?("db") && joined.include?("fm") && joined.include?("bbm")
    return :neo_soul_pocket if joined.include?("dm") && joined.include?("eb") && joined.include?("gm")
    return :minor_iv_loop if joined.include?("bbm") && joined.include?("fm")
    return :fourth_third_sixth_second_turn if symbols.length >= 6
    return :timeless_authentic if joined.include?("fm") && symbols.length >= 5
    :maj7_minor_cycle
  end

  def save_report!(report, path: LAST_REPORT_PATH)
    ensure_dir!
    File.write(path, JSON.pretty_generate(report) + "\n")
    archive = File.join(LEARNINGS_DIR, "learn_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json")
    File.write(archive, JSON.pretty_generate(report) + "\n")
    { last: path, archive: }
  end

  def load_last_report(path: LAST_REPORT_PATH)
    return unless File.file?(path)
    JSON.parse(File.read(path), symbolize_names: true)
  rescue StandardError
    nil
  end

  def copyable_dna(report)
    drums = report[:drum_pattern] || {}
    grid = drums[:step_grid] || {}
    symbols = Array(report[:progression_symbols])
    insight = report[:progression_insight]
    hints = report[:engine_hints] || {}
    {
      drums: grid.any? ? {
        bpm: drums[:bpm_estimate] || hints[:bpm], swing: drums[:swing_hint],
        kicks: grid[:kicks], snares: grid[:snares], hats: grid[:hats], density: drums[:drum_density]
      }.compact : nil,
      harmony: { progression: symbols, notation: insight&.dig(:notation), scale: insight&.dig(:scale) }.compact,
      melody: Array(report[:pitch_classes]).first(8),
      engine: hints.slice(:track, :voicing, :sonitex_preset, :analog_chain, :groove_dna, :performer, :bpm),
    }
  end

  def load_playlist_catalog(path: PLAYLIST_CATALOG_PATH)
    return { "tracks" => [], "updated_at" => nil } unless File.file?(path)
    JSON.parse(File.read(path))
  rescue StandardError
    { "tracks" => [], "updated_at" => nil }
  end

  def save_playlist_entry!(entry, catalog_path: PLAYLIST_CATALOG_PATH)
    ensure_dir!
    FileUtils.mkdir_p(PLAYLIST_TRACKS_DIR)
    slug = entry[:id] || entry["id"] || "track_#{Time.now.to_i}"
    track_path = File.join(PLAYLIST_TRACKS_DIR, "#{slug}.json")
    File.write(track_path, JSON.pretty_generate(entry) + "\n")
    catalog = load_playlist_catalog(path: catalog_path)
    tracks = Array(catalog["tracks"]).reject { |t| t["id"] == slug.to_s }
    tracks << entry.transform_keys(&:to_s)
    catalog["tracks"] = tracks.sort_by { |t| [t["artist"].to_s, t["title"].to_s] }
    catalog["updated_at"] = Time.now.utc.iso8601
    catalog["track_count"] = tracks.length
    File.write(catalog_path, JSON.pretty_generate(catalog) + "\n")
    { track: track_path, catalog: catalog_path }
  end

  def load_batch_state(path: PLAYLIST_BATCH_STATE_PATH)
    return { "completed_ids" => [], "failed" => {} } unless File.file?(path)
    JSON.parse(File.read(path))
  rescue StandardError
    { "completed_ids" => [], "failed" => {} }
  end

  def save_batch_state!(state, path: PLAYLIST_BATCH_STATE_PATH)
    ensure_dir!
    File.write(path, JSON.pretty_generate(state) + "\n")
  end

  def apply_hints_to_env!(hints)
    return [] unless hints.is_a?(Hash)
    applied = []
    { track: "TRACK", voicing: "VOICING", sonitex_preset: "SONITEX_PRESET",
      analog_chain: "ANALOG_CHAIN", bpm: "BPM", groove_dna: "GROOVE_DNA", performer: "PERFORMER" }.each do |k, env|
      val = hints[k] || hints[k.to_s]
      next if val.nil? || val.to_s.empty?
      ENV[env] = val.to_s
      applied << "#{env}=#{val}"
    end
    applied
  end
end
