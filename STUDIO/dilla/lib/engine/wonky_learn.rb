# frozen_string_literal: true
#
# Learning drum grids from stems, and the demux/chop pipeline.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.
require_relative "../frozen_state"

WONKY_LEARNINGS_DIR = File.join(DillaSourceLearn::LEARNINGS_DIR, "wonky_drums").freeze

def wonky_quantize_onsets(onsets, bpm, window: 0.05)
  bar_frames = ((60.0 / bpm) * 4.0 / window).round
  step_frames = [bar_frames / 16.0, 1.0].max
  tally = Hash.new(0)
  onsets.each { |f| tally[((f % bar_frames) / step_frames).round % 16] += 1 }
  tally
end

def wonky_pick_steps(tally, role:, max_sec: 90, bpm: 86)
  max_steps = { kick: 6, snare: 6, hat: 12, perc: 5 }.fetch(role, 5)
  bars = (max_sec / ((60.0 / bpm) * 4.0)).ceil
  min_hits = case role
             when :kick then [bars / 3, 2].max
             when :snare then [bars / 4, 2].max
             when :hat then [bars / 2, 3].max
             else [bars / 4, 2].max
             end
  picks = tally.sort_by { |_, c| -c }.select { |_, c| c >= min_hits }.first(max_steps).map(&:first).sort
  picks.empty? ? tally.sort_by { |_, c| -c }.first(max_steps).map(&:first).sort : picks
end

def wonky_onsets_adaptive(path, filter, role:, bpm:, max_sec: 90)
  da = RadioBergenStudy::DeepAudio
  rms = da.band_rms(path, filter, window: 0.05, max_sec:)
  return [] if rms.empty?
  sorted = rms.sort
  median = sorted[sorted.length / 2]
  peak = sorted[(sorted.length * 0.88).to_i]
  span = [peak - median, 8.0].max
  thresh, min_gap = case role
                    when :kick then [median + span * 0.52, 7]
                    when :snare then [median + span * 0.46, 5]
                    when :hat then [median + span * 0.28, 2]
                    else [median + span * 0.38, 4]
                    end
  onsets = []
  rms.each_with_index do |val, i|
    next if val < thresh
    prev = i.positive? ? rms[i - 1] : nil
    nxt = rms[i + 1]
    next if prev && val <= prev
    next if nxt && val <= nxt
    onsets << i if onsets.empty? || (i - onsets.last) >= min_gap
  end
  wonky_pick_steps(wonky_quantize_onsets(onsets, bpm), role:, max_sec:, bpm:)
end

def wonky_drum_grid_blend_fallback!(grid)
  base = DillaLofiMachine::DRUM_PRESETS[:wonky_abstract]
  {
    wonky_kicks: :kicks, wonky_snares: :snares, wonky_hats: :hats, wonky_perc: :perc
  }.each do |grid_key, preset_key|
    steps = Array(grid[grid_key] || grid[grid_key.to_s])
    next if steps.length >= 3
    fb = Array(base[preset_key])
    grid[grid_key] = (steps + fb).uniq.sort if fb.any?
  end
  grid
end

def wonky_drum_grid_from_stems(stem_dir, bpm: nil, analyze_sec: 120)
  drums = File.join(stem_dir, "drums.wav")
  return unless File.file?(drums)
  da = RadioBergenStudy::DeepAudio
  unless bpm
    kick_rms = da.band_rms(drums, "lowpass=f=220,highpass=f=50", max_sec: [analyze_sec, 90].min)
    bpm = da.estimate_bpm(da.detect_onsets(kick_rms, threshold_db: -12, min_gap: 6)) || 86
    bpm = 86 if bpm < 80 || bpm > 95
  end
  grid = {
    bpm: bpm.round,
    swing: DillaLofiMachine::DRUM_PRESETS[:wonky_abstract][:swing],
    source_stem: drums,
    wonky_kicks: wonky_onsets_adaptive(drums, "lowpass=f=220,highpass=f=50", role: :kick,
                                        bpm:, max_sec: analyze_sec),
    wonky_snares: wonky_onsets_adaptive(drums, "lowpass=f=5000,highpass=f=900", role: :snare,
                                         bpm:, max_sec: analyze_sec),
    wonky_hats: wonky_onsets_adaptive(drums, "lowpass=f=14000,highpass=f=5000", role: :hat,
                                      bpm:, max_sec: analyze_sec),
    wonky_perc: wonky_onsets_adaptive(drums, "lowpass=f=8000,highpass=f=2000", role: :perc,
                                      bpm:, max_sec: analyze_sec),
  }
  wonky_drum_grid_blend_fallback!(grid)
end

def learn_wonky_drums!(src, track: :quartal_west_coast, slug: "wonky_camel", apply: false, deep: true)
  DillaSourceLearn.ensure_dir!
  FileUtils.mkdir_p(WONKY_LEARNINGS_DIR)
  audio_path = if File.exist?(src.to_s)
                 File.expand_path(src)
               else
                 demux_fetch_audio(src, duration_sec: 180)
               end
  stem_candidate = File.join(DEMUX_DIR, "demux", DEMUX_MODEL, File.basename(audio_path, ".*"))
  stem_dir = if File.file?(File.join(stem_candidate, "drums.wav"))
               puts "wonky learn: reusing stems #{stem_candidate}"
               stem_candidate
             else
               demux_six(audio_path)
             end
  demux_deep_bands!(stem_dir) if deep && !File.directory?(File.join(stem_dir, "bands"))
  grid = wonky_drum_grid_from_stems(stem_dir)
  abort "wonky drum learn: could not extract grid from #{stem_dir}" unless grid.is_a?(Hash) && grid[:wonky_kicks]&.any?

  grid[:learned_at] = Time.now.utc.iso8601
  grid[:source] = src.to_s
  grid[:slug] = slug.to_s
  out_path = File.join(WONKY_LEARNINGS_DIR, "#{slug}.json")
  DillaFrozen.write_json(out_path, grid.transform_keys(&:to_s))

  eng = load_learned_engine(refresh: true)
  track_s = track.to_s
  eng["drum_grids"][track_s] = grid.transform_keys(&:to_s)
  eng["drum_grids"][slug.to_s] = grid.transform_keys(&:to_s)
  eng["track_aliases"]["wonky_camel"] = track_s unless eng["track_aliases"]["wonky_camel"]
  save_learned_engine!(eng)
  remove_instance_variable(:@learned_engine_cache) if instance_variable_defined?(:@learned_engine_cache)

  if apply
    ENV["TRACK"] = track_s
    ENV["WONKY_DRUM_OVERLAY"] = "1"
    ENV["BPM"] = grid[:bpm].to_s if grid[:bpm]
    ENV["SWING"] = grid[:swing].to_s if grid[:swing]
    ENV["STREAM_LEARN_BIAS"] = "1"
  end
  puts "wonky drums learned: #{slug} → #{track_s} kicks=#{grid[:wonky_kicks].join(',')} " \
       "snares=#{grid[:wonky_snares].join(',')} hats=#{grid[:wonky_hats].join(',')} bpm=#{grid[:bpm]}"
  puts "saved: #{out_path}"
  grid
end

def drum_step_grid_from_wav(path, bpm: nil, analyze_sec: 90)
  return unless path && File.file?(path)
  da = RadioBergenStudy::DeepAudio
  window = 0.05
  duration = da.ffprobe(path).dig("format", "duration").to_f
  analyze_sec = [[duration * 0.6, analyze_sec].min, 30].max
  analyze_sec = duration if duration.positive? && duration < analyze_sec

  kick_rms = da.band_rms(path, "lowpass=f=200,highpass=f=60", window:, max_sec: analyze_sec)
  snare_rms = da.band_rms(path, "lowpass=f=4000,highpass=f=800", window:, max_sec: analyze_sec)
  hat_rms = da.band_rms(path, "lowpass=f=12000,highpass=f=4000", window:, max_sec: analyze_sec)

  kick_on = da.detect_onsets(kick_rms, threshold_db: -14.0, min_gap: 4)
  snare_on = da.detect_onsets(snare_rms, threshold_db: -16.0, min_gap: 4)
  hat_on = da.detect_onsets(hat_rms, threshold_db: -18.0, min_gap: 2)

  bpm ||= da.estimate_bpm(kick_on) || da.estimate_bpm(snare_on) || 90
  bar_frames = ((60.0 / bpm) * 4.0 / window).round
  bar_frames = [bar_frames, 16].max
  step_frames = [bar_frames / 16.0, 1.0].max

  quantize = lambda do |onsets|
    onsets.map { |f| ((f % bar_frames) / step_frames).round % 16 }.uniq.sort
  end

  analysis = da.analyze(path)
  {
    bpm_estimate: bpm,
    swing_hint: analysis&.dig(:dynamics, :swing_hint),
    drum_density: analysis&.dig(:drum_density),
    step_grid: {
      kicks: quantize.call(kick_on),
      snares: quantize.call(snare_on),
      hats: quantize.call(hat_on).first(14),
      bar_steps: 16,
    },
  }
rescue StandardError => e
  { error: e.message }
end

def demux_six(src)
  audio = demux_fetch_audio(src)
  out = File.join(DEMUX_DIR, "demux")
  FileUtils.mkdir_p(out)
  cmd = demucs_cmd or abort "demucs required — pip install demucs"
  sh!(*cmd, "-n", DEMUX_MODEL, "-o", out, audio)
  stem_dir = File.join(out, DEMUX_MODEL, File.basename(audio, ".*"))
  puts "stems -> #{stem_dir}"
  if stem_dir.start_with?(STEM_DIR) && Dir.exist?(stem_dir) && !stems_scan_set(stem_dir).empty?
    name = File.basename(audio, ".*").gsub(/[^A-Za-z0-9_-]/, "_")[0, 32]
    stems_register(name, stem_dir, source: src)
  end
  stem_dir
end

# Vocal-only counterpart to demux_six: htdemucs_ft (fine-tuned, 4-stem) with
# --shifts averaging instead of the shared htdemucs_6s used for full stem
# splits elsewhere. Both are documented demucs quality knobs over the default
# single-pass htdemucs_6s call -- real bleed reduction at a real time cost,
# acceptable because this only runs once per ingested vocal source.
def demux_vocal_isolate(src)
  audio = demux_fetch_audio(src)
  out = File.join(DEMUX_DIR, "demux")
  FileUtils.mkdir_p(out)
  cmd = demucs_cmd or abort "demucs required — pip install demucs"
  shifts = ENV.fetch("DEMUX_VOCAL_SHIFTS", "2")
  sh!(*cmd, "-n", DEMUX_VOCAL_MODEL, "--shifts", shifts, "--float32", "-o", out, audio)
  stem_dir = File.join(out, DEMUX_VOCAL_MODEL, File.basename(audio, ".*"))
  puts "vocal stems -> #{stem_dir}"
  stem_dir
end

def demux_slice_band(src, dest, label, eq:)
  mix_render "band: #{label}", dest, inputs: ["-i", src], map: "[out]", filter: "[0:a]#{eq}[out]"
end

def demux_deep_bands!(stem_dir)
  bands = File.join(stem_dir, "bands")
  FileUtils.mkdir_p(bands)
  bass = File.join(stem_dir, "bass.wav"); drums = File.join(stem_dir, "drums.wav")
  guitar = File.join(stem_dir, "guitar.wav"); piano = File.join(stem_dir, "piano.wav"); other = File.join(stem_dir, "other.wav")
  demux_slice_band bass,  File.join(bands, "sub_bass.wav"),    "sub_bass",    eq: "lowpass=f=60"
  demux_slice_band bass,  File.join(bands, "bass_mid.wav"),    "bass_mid",    eq: "highpass=f=60,lowpass=f=200"
  demux_slice_band drums, File.join(bands, "kick.wav"),        "kick",        eq: "lowpass=f=100"
  demux_slice_band drums, File.join(bands, "snare.wav"),       "snare",       eq: "highpass=f=200,lowpass=f=500"
  demux_slice_band drums, File.join(bands, "hats.wav"),        "hats",        eq: "highpass=f=5000"
  demux_slice_band other, File.join(bands, "mids.wav"),        "mids",        eq: "highpass=f=500,lowpass=f=2000"
  demux_slice_band other, File.join(bands, "highs_pluck.wav"), "highs_pluck", eq: "highpass=f=2000,lowpass=f=5000"
  demux_slice_band other, File.join(bands, "air.wav"),         "air",         eq: "highpass=f=5000"
  inst = File.join(bands, "instrumental.wav")
  mix_render "instrumental sum", inst, inputs: ["-i", bass, "-i", drums, "-i", guitar, "-i", piano, "-i", other],
    map: "[out]", filter: "[0:a][1:a][2:a][3:a][4:a]amix=inputs=5:duration=longest[out]"
  demux_slice_band inst, File.join(bands, "center.wav"), "center", eq: "pan=stereo|c0=c0+c1|c1=c0+c1"
  demux_slice_band inst, File.join(bands, "sides.wav"),  "sides",  eq: "pan=stereo|c0=c0-c1|c1=c1-c0"
  puts "bands -> #{bands}"
  bands
end

def demux_deep(src)
  stem_dir = demux_six(src)
  demux_deep_bands!(stem_dir)
  stem_dir
end

# =============================================================================
# CHOP (long recording → drumless, vocal-less registered sample loops)
# =============================================================================
#
# The analysis lives in lib/radio_chop.rb; this is the wiring. Both external
# dependencies are injected rather than reached for from inside the module:
# demucs_cmd because it has three fallbacks and only this file knows them, and
# sample_key because the Krumhansl tables and the Goertzel chroma are here.

def chop_dispatch!
  case ARGV.first
  when "list" then ARGV.shift; chop_list
  else chop_ingest!
  end
end

def chop_ingest!
  src = ARGV.find { |a| !a.start_with?("-") }
  ARGV.delete(src) if src
  cmd = demucs_cmd or abort "demucs required — " \
    "python3 -m venv #{DEMUX_VENV_DIR} && " \
    "#{DEMUX_VENV_DIR}/bin/pip install demucs"

  RadioChop.ingest!(
    src ? File.expand_path(src) : RadioChop::DEFAULT_SOURCE,
    demucs: cmd,
    deep: RadioBergenStudy::DeepAudio,
    key_probe: method(:sample_key),
    label: ENV["CHOP_LABEL"],
    candidates: ENV.fetch("CHOP_CANDIDATES", "16").to_i,
    keep: ENV.fetch("CHOP_KEEP", "8").to_i,
    # Wide enough that a loop can be found rather than assumed: the length
    # search correlates a candidate against the material that follows it, so a
    # 30s window is what makes a 14s loop answerable at all.
    span: ENV.fetch("CHOP_SPAN", "30").to_f,
    scratch: scratch_path("chop_work"),
    # Separation is the expensive step and its output is keyed by the window it
    # came from, so a re-run to re-tune the scoring reuses it. CHOP_FRESH=1
    # throws it away, which is what you want after changing the span or the
    # source. Not a `--flag`: apply_flags! validates the whole `--` namespace
    # before dispatch and rejects anything not in its table.
    fresh: ENV["CHOP_FRESH"] == "1",
  )
  chop_list
rescue RuntimeError => e
  abort "chop: #{e.message}"
end

def chop_list
  loops = Array(RadioChop.registry["loops"])
  if loops.empty?
    puts "chop: nothing registered — run: ruby dilla.rb chop [path]"
    return
  end

  puts format("%-22s %6s %5s %6s %-9s %6s %7s %7s  %s",
              "slug", "bpm", "bars", "len", "key", "selfsim", "rejoin", "score", "at")
  loops.each do |l|
    puts format("%-22s %6s %5s %6s %-9s %6s %7s %7s  %s",
                l["slug"], l["bpm"].to_f.positive? ? l["bpm"] : "native", l["bars"] || "-",
                l["duration_sec"], l["key"] || "-", l["self_similarity"],
                l["rejoin_db"], l["score"],
                format("%d:%02d", l["source_start_sec"].to_i / 60, l["source_start_sec"].to_i % 60))
  end
  puts "rack: TRACK=<slug> to render over one, CHOP_BED=1 to let the engine pick by key"
end

def top_pitch_class_indices(pitch_class_hash, limit: 6)
  PITCH_CLASSES.each_with_index
               .sort_by { |name, _| -pitch_class_hash.fetch(name, 0.0).to_f }
               .first(limit)
               .map { |_, idx| idx }
end

def analyze_stem_for_learn(path, stem_name)
  return unless path && File.file?(path)
  result = { path:, stem: stem_name }
  case stem_name
  when "drums.wav", "bass.wav"
    analysis = RadioBergenStudy::DeepAudio.analyze(path)
    if analysis
      result[:bpm_estimate] = analysis[:bpm_estimate]
      result[:swing_hint] = analysis.dig(:dynamics, :swing_hint)
      result[:texture_hints] = analysis[:texture_hints]
      result[:drum_density] = analysis[:drum_density]
    end
    if stem_name == "drums.wav"
      grid = drum_step_grid_from_wav(path, bpm: result[:bpm_estimate])
      result.merge!(grid) if grid.is_a?(Hash)
    end
  when "piano.wav", "guitar.wav", "other.wav", "vocals.wav"
    profile = pitch_profile(path)
    pcs_hash = profile.fetch(:pitch_classes)
    top_pcs = top_pitch_class_indices(pcs_hash)
    ranking = chord_candidates(pcs_hash).first(8)
    result[:pitch_classes] = top_pcs
    result[:top_chords] = ranking.map { |c| { name: c[:chord], score: c[:score] } }
    if defined?(DillaMusicGems) && DillaMusicGems.coltrane?
      result[:coltrane_candidates] = DillaMusicGems.chord_candidates_from_pitch_classes(top_pcs, limit: 8)
    end
  end
  if %w[other.wav vocals.wav].include?(stem_name)
    rhythm_data = frame_energy(path, highpass: 60, lowpass: 12_000)
    loudness = rhythm_data.fetch(:frames).map(&:last)
    brightness = frame_energy(path, highpass: 2_400, lowpass: 12_000).fetch(:frames).map(&:last)
    density = peak_frames(rhythm_data.fetch(:frames), rhythm_data.fetch(:hop_seconds)).length.to_f /
              [rhythm_data.fetch(:duration_seconds), 1.0].max
    result[:semantics] = semantic_tags(loudness, brightness, density)
  end
  result
rescue StandardError => e
  { path:, stem: stem_name, error: e.message }
end
