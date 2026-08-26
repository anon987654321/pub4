# frozen_string_literal: true
#
# The rap vocal catalogue: ingest, isolate, clean, measure.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.
require_relative "../frozen_state"

RAP_VOCAL_DIR = File.join(DillaSourceLearn::LEARNINGS_DIR, "vocals").freeze
RAP_VOCAL_CATALOG = File.join(RAP_VOCAL_DIR, "catalog.json").freeze

def rap_vocal_slug(artist)
  artist.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_|_\z/, "")
end

def rap_vocal_load_catalog
  return { "vocals" => [], "updated_at" => nil } unless File.file?(RAP_VOCAL_CATALOG)
  JSON.parse(File.read(RAP_VOCAL_CATALOG))
rescue StandardError
  { "vocals" => [], "updated_at" => nil }
end

def rap_vocal_save_catalog!(cat)
  DillaSourceLearn.ensure_dir!
  FileUtils.mkdir_p(RAP_VOCAL_DIR)
  cat["updated_at"] = Time.now.utc.iso8601
  DillaFrozen.write_json(RAP_VOCAL_CATALOG, cat)
end

def rap_vocal_phrase_onsets(path)
  rhythm = frame_energy(path, highpass: 300, lowpass: 6000)
  peaks = peak_frames(rhythm[:frames], rhythm[:hop_seconds])
  return [] if peaks.empty?
  phrases = []
  cluster = [peaks.first]
  peaks[1..].each do |pk|
    if pk[:time] - cluster.last[:time] < 0.35
      cluster << pk
    else
      phrases << { "start" => cluster.first[:time].round(3), "end" => cluster.last[:time].round(3),
                   "strength" => cluster.map { |p| p[:strength] }.max.round(4) }
      cluster = [pk]
    end
  end
  phrases << { "start" => cluster.first[:time].round(3), "end" => cluster.last[:time].round(3),
               "strength" => cluster.map { |p| p[:strength] }.max.round(4) }
  phrases
end

def rap_vocal_atempo_chain(ratio)
  r = ratio.to_f.clamp(0.25, 4.0)
  parts = []
  while r > 2.0
    parts << 2.0
    r /= 2.0
  end
  while r < 0.5
    parts << 0.5
    r /= 0.5
  end
  parts << r
  parts.map { |t| "atempo=#{t.round(4)}" }.join(",")
end

# Voice-only chain for demucs "vocals" stems.
# Goal: hear Jonas V (speech/rap), never residual kick/bass/hats from the source beat.
# Demucs always leaves some kit bleed; we kill it hard then denoise the floor.
def rap_vocal_isolation_filter
  [
    "aformat=sample_rates=#{SAMPLE_RATE}:channel_layouts=stereo",
    # Center-bias: voice is mid; kit/pads often wider — collapse residual sides.
    "pan=stereo|c0=0.72*c0+0.28*c1|c1=0.72*c1+0.28*c0",
    # Kill everything below speech fundamentals (kit sub lives here).
    "highpass=f=175:width_type=q:width=0.707",
    "equalizer=f=55:t=h:w=1.0:g=-24",
    "equalizer=f=90:t=h:w=1.2:g=-18",
    "equalizer=f=130:t=o:w=1.4:g=-12",
    "equalizer=f=200:t=o:w=1.3:g=-6",
    # Soft top air for consonants; no crash/hat glare.
    "lowpass=f=7200:width_type=q:width=0.8",
    "equalizer=f=3200:t=o:w=1.5:g=2.2",
    "equalizer=f=5500:t=h:w=1.2:g=-2.5",
    # FFT denoise residual kit hiss / cymbal wash left in demucs vocals.
    "afftdn=nr=14:nf=-28:tn=1",
    # Hard gate: only pass when voice is present (no quiet snare ghosts).
    # release/range deliberately gentle. At release=55 with range=0.0008 this
    # slammed to near-silence between syllables -- measured 4 gaps under 150ms
    # (median 93ms) inside a single 20s phrase, which is the "chopping". The
    # gate is here to suppress kit bleed BETWEEN phrases, not to articulate
    # words, so it now ducks by ~24 dB over a quarter second instead of cutting.
    "agate=threshold=0.022:ratio=4:attack=6:release=260:range=0.06:makeup=1.5",
    "acompressor=threshold=-24dB:ratio=2.4:attack=4:release=90:makeup=3.5",
    # Second gate after makeup so boosted floor does not reappear.
    "agate=threshold=0.012:ratio=3:attack=4:release=200:range=0.10:makeup=1",
  ].join(",")
end

# Light polish for already-isolated stems (no heavy makeup that re-lifts bleed).
def rap_vocal_voice_polish_filter
  base = [
    "aformat=sample_rates=#{SAMPLE_RATE}:channel_layouts=stereo",
    "highpass=f=165:width_type=q:width=0.707",
    "equalizer=f=80:t=h:w=1.0:g=-14",
    "lowpass=f=7400",
  ]
  # This gate+compressor+denoise stack was tuned for spoken rap phrasing
  # (gaps between bars, percussive onsets); on a sung/harmony vocal it can
  # gate mid-note and read as choppy/robotic. RAP_VOCAL_RAW=1 skips it for
  # a minimal pass -- same "unprocessed beats over-processed" pattern that
  # fixed audibility on the original rap vocal chain.
  return base.join(",") if ENV["RAP_VOCAL_RAW"] == "1"
  (base + [
    "afftdn=nr=8:nf=-32:tn=1",
    "agate=threshold=0.02:ratio=5:attack=2:release=50:range=0.0006:makeup=1.2",
    "acompressor=threshold=-24dB:ratio=2:attack=5:release=100:makeup=2",
  ]).join(",")
end

# First substantial phrase — skip instrumental intro left in the "vocals" stem.
# Start of the densest stretch of actual singing, given how much audio the fit
# needs. Choosing the *earliest* strong phrase is wrong for any stem with gaps:
# gunnhild has a short pocket of singing at 0-16s, then 80 seconds of nothing,
# then its real verse at 96-128s. Starting at the earliest phrase (1.7s) drags
# a 32-bar fit straight through the dead middle. Scoring windows by voiced
# coverage picks the verse instead, and needs no threshold tuned per stem.
def rap_vocal_content_offset(path, needed_sec)
  r = begin
    frame_energy(path, highpass: 200, lowpass: 6_000)
  rescue StandardError
    nil
  end
  return unless r && r[:frames].is_a?(Array) && r[:frames].any?

  hop = r[:hop_seconds].to_f
  return unless hop.positive?

  vals = r[:frames].map { |f| f.is_a?(Array) ? f.last.to_f : f.to_f }
  peak = vals.max.to_f
  return unless peak.positive?

  voiced = vals.map { |v| v > peak * 0.06 ? 1 : 0 }
  # Score a modest window, not the full length the fit needs. A long render can
  # need more continuous singing than the stem physically contains -- gunnhild
  # holds ~32s of real verse against the 88s a 32-bar fit consumes -- and
  # scoring at that length picks the least-bad window spanning the dead middle
  # (measured: 25% voiced) instead of the verse. Locating the densest short
  # region lands on the verse every time; the crossfade loop in rap_vocal_fit!
  # is what covers the remaining duration.
  win = [[(([needed_sec, 16.0].min) / hop).round, 1].max, voiced.size - 1].min
  return 0.0 if win < 1

  # Rolling sum: best-scoring window start, ties going to the earlier one.
  sum = voiced.first(win).sum
  best_sum = sum
  best_i = 0
  (win...voiced.size).each do |i|
    sum += voiced[i] - voiced[i - win]
    if sum > best_sum
      best_sum = sum
      best_i = i - win + 1
    end
  end
  (best_i * hop).round(3)
end

# Earliest phrase strong enough to be real speech rather than residual bleed.
# The threshold is RELATIVE to the strongest phrase in this stem, because
# onset strength scales with the stem's level and stems vary by tens of dB.
# A fixed 0.22 floor meant a quiet stem had almost nothing clear it: gunnhild
# had 2 of 16 phrases qualify, both near the very end, so the fit started at
# 116.5s of a 128s file and looped the last 11s over and over. Scaling to the
# stem keeps the same intent -- skip the weak stuff, start at real singing --
# without assuming a level.
def rap_vocal_phrase_start(phrases, min_strength: nil)
  entries = Array(phrases).filter_map do |p|
    s = (p["start"] || p[:start]).to_f
    st = (p["strength"] || p[:strength]).to_f
    next if s < 1.0
    [s, st]
  end
  return if entries.empty?

  peak = entries.map(&:last).max.to_f
  floor = min_strength || (peak.positive? ? [peak * 0.6, 0.22].min : 0.0)
  strong = entries.select { |(_, st)| st <= 0.0 || st >= floor }
  (strong.empty? ? entries : strong).map(&:first).min
end

# Level the isolation chain expects to see. Its two agate stages fire on
# ABSOLUTE thresholds (0.028 and 0.016), so they only mean anything if the stem
# arrives somewhere near this. Demucs output level varies enormously between
# sources -- measured here: slum_village -9.8 dB, jonas_v -18.0 dB, gunnhild
# -46.8 dB -- and a stem whose PEAK (0.0245) sits below the first gate's
# threshold is erased in its entirety. That is what happened to gunnhild: its
# main verse went from 98% voiced in the raw demucs stem to 5% after cleaning,
# and because the result overwrote the source and set isolated: true, the
# damage looked like a bad recording rather than a bad gate.
RAP_VOCAL_CLEAN_TARGET_DB = (ENV["RAP_VOCAL_CLEAN_TARGET_DB"] || -18.0).to_f

def rap_vocal_clean_stem!(src, dest = nil, aggressive: true)
  dest ||= src.sub(/\.wav\z/i, ".clean.wav")
  dest = "#{src}.clean.wav" if dest == src
  chain = aggressive ? rap_vocal_isolation_filter : rap_vocal_voice_polish_filter
  pre = ""
  if aggressive
    measured = begin
      band_rms(src, highpass: 200, lowpass: 6_000)
    rescue StandardError
      nil
    end
    if measured&.finite? && measured < RAP_VOCAL_CLEAN_TARGET_DB
      gain = (RAP_VOCAL_CLEAN_TARGET_DB - measured).clamp(0.0, 36.0)
      pre = "volume=#{gain.round(2)}dB,"
      dmesg("vocal clean: stem at #{measured.round(1)}dB, pre-gain +#{gain.round(1)}dB into gate range",
            unit: "vox0", parent: "dilla0")
    end
  end
  sh! "ffmpeg", "-y", "-i", src,
      "-af", "#{pre}#{chain},loudnorm=I=-17:TP=-2.5:LRA=7,alimiter=limit=0.93:level_out=0.94",
      "-ar", SAMPLE_RATE.to_s, "-ac", "2", "-c:a", "pcm_s16le", dest
  dest
end

# Finds the offset, in the vocal's OWN timeline, whose bar grid best lines up
# with where the singing actually lands.
#
# It used to grid against the *target* bar length while scoring *source-time*
# onsets. Those are only the same length when the vocal is already at the beat's
# tempo. gunnhild is 87 against a 92 BPM beat, so the search compared onsets
# spaced ~2.759s to a 2.609s grid: 5.7% out, accumulating to most of a bar over
# 16, and the offset it returned was meaningless. That is the whole of "not beat
# matched" — atempo got the tempo right and the phase was never right.
#
# source_bpm is the vocal's tempo; the caller stretches by beat_bpm/source_bpm
# afterwards, which maps this source grid exactly onto the beat's.
def rap_vocal_best_bar_offset(vocal_path, source_bpm, phrases: nil)
  phrase_times = Array(phrases).filter_map { |p| p["start"] || p[:start] }
  if phrase_times.empty?
    rhythm = frame_energy(vocal_path, highpass: 300, lowpass: 6000)
    phrase_times = peak_frames(rhythm[:frames], rhythm[:hop_seconds]).map { |p| p[:time] }
  end
  return 0.0 if phrase_times.empty?

  bar_sec = (60.0 / source_bpm.to_f) * 4.0
  beat_sec = bar_sec / 4.0
  # Tolerance scales with tempo rather than a fixed 60ms: at 87 BPM a beat is
  # 690ms, so 60ms is ~9% of a beat here and a different fraction at any other
  # tempo.
  window = beat_sec * 0.08
  best = 0.0
  best_score = -1.0

  # Search one whole bar in 5ms steps. The old loop stepped 25ms over a range
  # derived from the bar length, which at slower tempos ran well past a bar and
  # scored the same phase repeatedly.
  steps = (bar_sec / 0.005).round
  (0..steps).each do |i|
    offset = i * 0.005
    # Weight downbeats above backbeats above the other beats: a vocal phrase
    # starting on beat 1 is worth more evidence than one starting on beat 4.
    score = phrase_times.sum do |t|
      rel = (t - offset) % bar_sec
      dist_to_beat = [rel % beat_sec, beat_sec - (rel % beat_sec)].min
      next 0.0 if dist_to_beat > window

      beat_index = ((rel / beat_sec).round % 4)
      case beat_index
      when 0 then 1.0
      when 2 then 0.6
      else 0.3
      end
    end
    next unless score > best_score

    best_score = score
    best = offset
  end
  best.round(4)
end

def rap_vocal_resolve(slug_or_path)
  raw = slug_or_path.to_s
  return raw if raw.end_with?(".wav", ".mp3", ".m4a") && File.file?(raw)
  cat = rap_vocal_load_catalog
  vocals = Array(cat["vocals"])
  return if vocals.empty?
  if raw.empty? || raw == "auto"
    # Was `vocals[iterate_count % vocals.length]`, which rotated the stream
    # through every catalogued voice -- slum_village, jonas_v, singers_unlimited
    # -- so "auto" meant "whoever is next", not "the vocal".
    return vocals.find { |v| v["slug"] == RAP_VOCAL_SOURCE } || vocals.first
  end
  vocals.find { |v| v["slug"] == raw || v["artist"].to_s.casecmp(raw).zero? } ||
    vocals.find { |v| v["slug"].to_s.include?(raw) }
end

# Never auto-fallback to random catalog entries (that pulled in sirkel_sag).
RAP_VOCAL_BLOCKLIST = %w[sirkel_sag].freeze

# Same-song vocal-stem overrides (used to route pedal_e_descent to the
# slum_village stem). Emptied on request: gunnhild is the only vocal source;
# the mechanism stays for when that decision changes.
TRACK_MATCHED_VOCAL_SLUG = {}.freeze

def rap_vocal_stream_slug
# Beats the presets: an operator who said 0 gets 0.
return if VOCALS_EXPLICITLY_OFF
  slug = ENV["RAP_VOCAL"].to_s.strip
  return if slug.empty? || slug == "0"
  return if RAP_VOCAL_BLOCKLIST.include?(slug)
  if slug == "auto" || slug == "gunnhild"
    track = ENV["TRACK"].to_s.downcase.tr("-", "_")
    matched = TRACK_MATCHED_VOCAL_SLUG[track]
    return matched if matched
  end
  if slug == "auto"
    cat = rap_vocal_load_catalog
    pick = Array(cat["vocals"]).find do |v|
      s = v["slug"].to_s
      next false if RAP_VOCAL_BLOCKLIST.include?(s)
      next false unless File.file?(v["vocal_path"].to_s)
      peak = band_rms(v["vocal_path"], highpass: 80, lowpass: 8_000) rescue -90.0
      peak >= -45.0
    end
    return pick&.dig("slug")
  end
  cat = rap_vocal_load_catalog
  entry = Array(cat["vocals"]).find { |v| v["slug"] == slug }
  unless entry && entry["vocal_path"] && File.file?(entry["vocal_path"])
    warn "rap-vocal: #{slug} missing from catalog — skipping vocals"
    return
  end
  peak = band_rms(entry["vocal_path"], highpass: 80, lowpass: 8_000) rescue -90.0
  if peak < -55.0
    warn "rap-vocal: #{slug} too quiet (≈#{peak.round(1)} dB) — skipping (no fallback)"
    return
  end
  slug
end

def rap_vocal_ingest!(artist, src)
  ensure_demucs_ready!
  DillaSourceLearn.ensure_dir!
  slug = rap_vocal_slug(artist)
  out_dir = File.join(RAP_VOCAL_DIR, slug)
  FileUtils.mkdir_p(out_dir)
  stem_dir = demux_vocal_isolate(src)
  vocal_src = File.join(stem_dir, "vocals.wav")
  unless File.file?(vocal_src)
    warn "rap-vocal ingest: demucs produced no vocals.wav in #{stem_dir}"
    return
  end
  vocal_dest = File.join(out_dir, "vocals.wav")
  # Demucs "vocals" still carries kit/bass bleed — voice-only isolate before catalog.
  # Never catalog drums/bass/other stems — only this cleaned vocals.wav path is mixed.
  rap_vocal_clean_stem!(vocal_src, vocal_dest, aggressive: true)
  analysis = RadioBergenStudy::DeepAudio.analyze(vocal_dest)
  phrases = rap_vocal_phrase_onsets(vocal_dest)
  entry = {
    "slug" => slug, "artist" => artist.to_s, "source" => src.to_s,
    "vocal_path" => vocal_dest, "stem_dir" => stem_dir,
    "bpm_estimate" => analysis[:bpm_estimate],
    "phrases" => phrases, "ingested_at" => Time.now.utc.iso8601,
    "isolated" => true, "voice_only" => true
  }
  cat = rap_vocal_load_catalog
  cat["vocals"] = Array(cat["vocals"]).reject { |v| v["slug"] == slug } + [entry]
  rap_vocal_save_catalog!(cat)
  File.write(File.join(out_dir, "meta.json"), JSON.pretty_generate(entry) + "\n")
  puts "rap-vocal ingest: #{artist} → #{vocal_dest} bpm=#{analysis[:bpm_estimate]} phrases=#{phrases.length}"
  entry
end

# Fold raw onset BPM into the stream pocket (≈76–100). Avoids the 66.7 trap
# where *2 → 133 and /2 → 66.7 forever (never lands in-range).
# Folds a measured tempo to the octave nearest the beat it has to sit against.
#
# Octaves only. The pool used to include b*1.5, b/1.5, b*4/3 and b*3/4, and
# those do not preserve where the beats are — they re-grid the whole take at a
# different meter. That is how gunnhild came to be catalogued at 87 BPM: the
# analyser measured ~116, 116 * 3/4 = 87.0 landed inside the 74-100 window and
# won for being nearest 90. Every fit since has been stretching a 120 BPM vocal
# as though it were 87, which no phase correction downstream can rescue.
#
# Folding toward `target` rather than a fixed 90 also picks the smaller stretch:
# a 120 BPM vocal over a 92 BPM beat is a 0.77x slowdown at 120, or a 1.53x
# speedup at 60. Both are legal; the first does far less damage to the voice.
def rap_vocal_fold_bpm(raw, target: nil)
  b = raw.to_f
  return unless b.positive?

  pool = (-2..2).map { |k| b * (2.0**k) }.select { |x| x.between?(40.0, 220.0) }
  return b.round(2) if pool.empty?

  aim = target.to_f.positive? ? target.to_f : 90.0
  # Nearest in log space: the cost of a stretch is its ratio, not its
  # difference in BPM.
  pool.min_by { |x| (Math.log(x / aim)).abs }.round(2)
end

# Measures a vocal's tempo from its own onsets: for each candidate BPM, take the
# best phase and count onsets landing within 10% of a beat. The true tempo spikes
# well clear of the field; a take with no steady pulse produces no spike, which
# is worth knowing before trying to stretch it onto a grid.
#
# Verified against a synthesised 100 BPM click: 39/39 onsets on grid at 100,
# 20/39 at the neighbours.
def rap_vocal_measure_bpm(vocal_path, range: (60..180))
  # Memoised: the fit path asks twice per render -- once for the tempo, once for
  # "does this take have a pulse at all" -- and the sweep is a few hundred phase
  # searches over the whole onset list.
  @rap_vocal_bpm_cache ||= {}
  key = [vocal_path, range]
  return @rap_vocal_bpm_cache[key] if @rap_vocal_bpm_cache.key?(key)

  @rap_vocal_bpm_cache[key] = rap_vocal_measure_bpm_uncached(vocal_path, range:)
end

def rap_vocal_measure_bpm_uncached(vocal_path, range: (60..180))
  onsets = rap_vocal_onset_times(vocal_path)
  return nil if onsets.size < 8

  scored = range.map do |bpm|
    beat = 60.0 / bpm
    tol = beat * 0.10
    best = 0
    (0..(beat / 0.005).to_i).each do |i|
      phase = i * 0.005
      hits = onsets.count { |t| r = (t - phase) % beat; [r, beat - r].min < tol }
      best = hits if hits > best
    end
    [bpm.to_f, best]
  end

  bpm, hits = scored.max_by { |(_, h)| h }
  # A random phase hits ~20% at this tolerance, so an absolute floor alone is
  # too easy to clear. A real pulse also stands clear of its neighbours: the
  # 100 BPM click scores 100% at the true tempo against 51% either side. Gunnhild
  # scores 35% at 96 with 34% at 168 and 32% at 147 — no winner, noise with
  # a lean, and returning 96 from that produced a "beat match" no better than
  # chance. Require both the floor and real separation from the best unrelated
  # rival, or admit there is no tempo here.
  return nil if hits < onsets.size * 0.32

  related = ->(other) { r = other / bpm; [0.25, 0.5, 1.0, 2.0, 4.0].any? { |k| (r - k).abs < 0.04 } }
  rival = scored.reject { |(b, _)| related.call(b) }.map(&:last).max.to_i
  return nil if rival.positive? && hits < rival * 1.25

  bpm
end

def rap_vocal_onset_times(vocal_path, hop: 0.010)
  rate = 8000
  raw = IO.popen(["ffmpeg", "-v", "error", "-i", vocal_path, "-ac", "1",
                  "-ar", rate.to_s, "-f", "s16le", "-"], "rb", &:read)
  samples = raw.to_s.unpack("s<*")
  return [] if samples.empty?

  frame = (rate * hop).to_i
  env = samples.each_slice(frame).map { |c| Math.sqrt(c.sum { |s| (s / 32_768.0)**2 } / c.size) }

  window = 12
  last = -1.0
  env.each_with_index.filter_map do |e, i|
    next if i < window

    floor = env[(i - window)...i].sum / window
    t = i * hop
    next unless e > floor * 2.2 && e > 0.004
    next if t - last < 0.12

    last = t
  end
end

# Prefer ENV override, then a real measurement, then the stored estimate.
def rap_vocal_source_bpm(entry, vocal_path, target: nil)
  forced = ENV["RAP_VOCAL_BPM"].to_f
  return forced if forced.positive?

  # Measurement first. The stored bpm_estimate is whatever the ingest analyser
  # said once, already folded — gunnhild sat at 87 for weeks against a source
  # that measures 120, and nothing downstream could tell.
  measured = rap_vocal_measure_bpm(vocal_path)
  return rap_vocal_fold_bpm(measured, target:) if measured

  candidates = []
  if entry.is_a?(Hash)
    candidates << entry["bpm_estimate"].to_f
    candidates << entry.dig("last_fit", "source_bpm").to_f
  end
  if candidates.none?(&:positive?)
    analysis = RadioBergenStudy::DeepAudio.analyze(vocal_path) rescue nil
    candidates << analysis&.dig(:bpm_estimate).to_f
    candidates << analysis&.dig(:bpm_estimate_kick).to_f
    candidates << analysis&.dig(:bpm_estimate_snare).to_f
  end
  rap_vocal_fold_bpm(candidates.find { |b| b&.positive? }, target:)
end
