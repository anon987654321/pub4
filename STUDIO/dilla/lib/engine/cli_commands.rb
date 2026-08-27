# frozen_string_literal: true
#
# CLI commands: scan, render, verify, stems, chords and the wiring ratchet.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

def scan(groove: false)
  groove_pid, groove_tmp = groove ? start_groove_preview : [nil, nil]
  puts JSON.pretty_generate(
    root: ROOT,
    bpm:,
    bars:,
    seconds: render_seconds,
    files: {
      ruby: File.exist?(ENGINE_FILE),
      html: File.exist?(File.join(ROOT, "dilla.html")),
      clean_harmonic: File.exist?(SAMPLE_CLEAN),
    },
    tools: {
      ffmpeg: tool_available?("ffmpeg"),
      ffprobe: tool_available?("ffprobe"),
      yt_dlp: tool_available?("yt-dlp"),
      demucs: tool_available?("demucs"),
    },
    commands: COMMANDS,
  )
ensure
  if groove_pid
    Process.kill("TERM", groove_pid) rescue nil
    Process.wait(groove_pid) rescue nil
  end
  FileUtils.rm_f(groove_tmp) if groove_tmp
end

def council
  puts "MASTER council"
  puts "preserve existing command surface"
  puts "separate source capture, demucs, rhythm study, melody study"
  puts "add harmony and semantic texture evidence"
  puts "feed ears metrics into MASTER before aesthetic judgment"
  puts "keep render, clean, stems, chords intact"
end

def source(input = nil, output = nil)
  input ||= prompt("audio path or URL")
  output ||= File.join(SAMPLE_DIR, "source.wav")
  FileUtils.mkdir_p(File.dirname(output))
  return convert_audio(input, output) if File.exist?(input)
  download_track(input, output)
end

def livestream(input = nil, output = nil)
  input ||= prompt("livestream URL")
  output ||= File.join(SAMPLE_DIR, "livestream.wav")
  seconds_to_capture = (ENV["LIVE_SECONDS"] || 600).to_i
  require_tools! "yt-dlp", "ffmpeg"
  media_url = direct_media_url(input)
  FileUtils.mkdir_p(File.dirname(output))
  sh! "ffmpeg", "-y", "-t", seconds_to_capture.to_s, "-i", media_url, "-ac", "2", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", output
  puts "wrote #{output}"
  output
end

def sample
  path = source(nil, File.join(SAMPLE_DIR, "source.wav"))
  separated = separate(path)
  harmonic = separated.fetch("other")
  clean(harmonic, SAMPLE_CLEAN)
end

def separate(input = nil)
  input ||= prompt("audio path or URL")
  wav = File.exist?(input) ? input : source(input, File.join(SAMPLE_DIR, "source.wav"))
  require_tools! "demucs"
  FileUtils.mkdir_p(STEM_DIR)
  sh! "demucs", "-n", "htdemucs_ft", "-o", STEM_DIR, wav
  map = latest_stems
  puts JSON.pretty_generate(map)
  map
end

def latest_stems
  files = Dir[File.join(STEM_DIR, "**", "*.wav")]
  abort "no stems found" if files.empty?
  newest_directory = files.group_by { |path| File.dirname(path) }.max_by { |_directory, paths| paths.map { |path| File.mtime(path) }.max }.first
  stem_paths(Dir[File.join(newest_directory, "*.wav")])
end

def download_track(url, output)
  require_tools! "yt-dlp", "ffmpeg"
  temporary = File.join(SAMPLE_DIR, "download.%(ext)s")
  sh! "yt-dlp", "-f", "bestaudio", "--extract-audio", "--audio-format", "wav", url, "-o", temporary
  downloaded = Dir[File.join(SAMPLE_DIR, "download.wav")].max_by { |path| File.mtime(path) }
  abort "download produced no wav" unless downloaded
  FileUtils.mv(downloaded, output)
  puts "wrote #{output}"
  output
end

def direct_media_url(url)
  output, error, status = capture("yt-dlp", "-g", "-f", "bestaudio", url)
  abort error unless status.success?
  media_url = output.lines.first&.strip
  abort "yt-dlp returned no media URL" if media_url.nil? || media_url.empty?
  media_url
end

def convert_audio(input, output)
  require_tools! "ffmpeg"
  sh! "ffmpeg", "-y", "-i", input, "-ac", "2", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", output
  puts "wrote #{output}"
  output
end

# The five-oscillator sketch, not the engine.
#
# This is `ruby dilla.rb render`, and the name is a trap: it builds a fixed
# ep/bass/kick/snare/hats graph and writes it straight out, with no progression,
# no arrangement, no vocal and -- the part that misleads most -- no master bus, so
# its output lands around -19 dBFS peak while a real render is loudnormed to
# STREAM_LUFS. Comparing two of these to test a master-chain change gives two
# byte-identical files and proves nothing, because the master chain was never in
# this path.
#
# The engine is `ruby dilla.rb dilla` (render_dilla), which is what stream uses.
def render(destination = File.join(OUTPUT_DIR, "full_track.mp3"))
  require_tools! "ffmpeg"
  dmesg("sketch renderer — no progression, no master bus; `dilla` is the engine",
        unit: "render0", parent: "dilla0")
  FileUtils.mkdir_p(File.dirname(destination))
  duration = render_seconds
  kick_period = (beat_seconds * 2.0).round(6)
  command = ["ffmpeg", "-y"]
  command += ["-f", "lavfi", "-i", "aevalsrc='#{chord_expression}':d=#{duration}:s=#{SAMPLE_RATE}"]
  command += ["-f", "lavfi", "-i", "aevalsrc='0.16*sin(2*PI*49*t)*exp(-mod(t,#{beat_seconds.round(6)})*3.1)':d=#{duration}:s=#{SAMPLE_RATE}"]
  command += ["-f", "lavfi", "-i", "aevalsrc='0.58*sin(2*PI*(45+90*exp(-mod(t,#{kick_period})*18))*t)*exp(-mod(t,#{kick_period})*9)':d=#{duration}:s=#{SAMPLE_RATE}"]
  command += ["-f", "lavfi", "-i", "aevalsrc='0.13*(random(0)-0.5)*lt(mod(t+#{beat_seconds.round(6)},#{kick_period}),0.08)*exp(-mod(t+#{beat_seconds.round(6)},#{kick_period})*28)':d=#{duration}:s=#{SAMPLE_RATE}"]
  command += ["-f", "lavfi", "-i", "aevalsrc='0.035*(random(0)-0.5)*lt(mod(t,#{(beat_seconds / 2.0).round(6)}),0.035)*exp(-mod(t,#{(beat_seconds / 2.0).round(6)})*80)':d=#{duration}:s=#{SAMPLE_RATE}"]
  sample_input = nil
  if File.exist?(SAMPLE_CLEAN)
    sample_input = 5
    command += ["-stream_loop", "-1", "-i", SAMPLE_CLEAN]
  end
  command += ["-filter_complex", render_filter(duration, sample_input), "-map", "[out]", "-t", duration.to_s, *codec_for(destination), destination]
  sh!(*command)
  puts "wrote #{destination}"
end

def render_filter(duration, sample_input)
  filter = []
  filter << "[0:a]aformat=channel_layouts=stereo,lowpass=f=3300,adelay=7|13[ep]"
  filter << "[1:a]aformat=channel_layouts=stereo,lowpass=f=160[bass]"
  filter << "[2:a]aformat=channel_layouts=stereo,lowpass=f=140[kick]"
  filter << "[3:a]aformat=channel_layouts=stereo,highpass=f=900,lowpass=f=5000[snare]"
  filter << "[4:a]aformat=channel_layouts=stereo,highpass=f=6500[hats]"
  labels = %w[[ep] [bass] [kick] [snare] [hats]]
  weights = %w[1.00 0.80 0.72 0.55 0.24]
  if sample_input
    filter << "[#{sample_input}:a]aformat=channel_layouts=stereo,atrim=0:#{duration},asetpts=PTS-STARTPTS,highpass=f=70,lowpass=f=12000[sample]"
    labels << "[sample]"
    weights << "0.85"
  end
  filter << "#{labels.join}amix=inputs=#{labels.length}:weights=#{weights.join(' ')}:duration=first,acompressor=threshold=-18dB:ratio=2.4:attack=24:release=130,acrusher=bits=13:samples=2:mix=0.12,alimiter=limit=0.94:level_out=0.96[out]"
  filter.join(";")
end

def codec_for(destination)
  return ["-codec:a", "libmp3lame", "-b:a", "320k"] if File.extname(destination).downcase == ".mp3"
  ["-c:a", "pcm_s16le"]
end

def verify(path = File.join(OUTPUT_DIR, "full_track.mp3"))
  abort "missing #{path}" unless File.exist?(path)
  output, error, status = capture("ffmpeg", "-hide_banner", "-i", path, "-af", "volumedetect", "-f", "null", "-")
  text = output + error
  puts text.lines.grep(/Duration|bitrate|mean_volume|max_volume/).join
  abort "verify failed" unless status.success? && text.include?("mean_volume:")
end

def dilla_quality(path, baseline_path = nil)
  abort "missing #{path}" unless File.file?(path)
  loud_out, loud_err, loud_status = capture(
    "ffmpeg", "-hide_banner", "-i", path, "-af", "loudnorm=I=-14:TP=-1:LRA=11:print_format=json", "-f", "null", "-"
  )
  abort loud_err unless loud_status.success?
  json_text = (loud_out + loud_err)[/\{\s*"input_i".*?\}/m]
  loudness = json_text ? JSON.parse(json_text) : {}
  spectrum = render_spectrum(path)
  mono = band_rms(path, highpass: 28, lowpass: 16_000)
  phase = DillaMaster.min_phase_correlation(path)
  # last_progression_chords is render-time state, so auditing a file this
  # process did not render finds nil -- and score_beauty(nil) returns 50, which
  # the report then printed as a harmony score next to real measurements. Every
  # `quality` run on an existing mp3 has been reporting a fabricated 50 with an
  # empty breakdown; the number looked like a measurement and was a default.
  #
  # Absent is now absent. A null says "not measured" and cannot be averaged,
  # plotted or compared by mistake, which a 50 can.
  chords = DillaHarmony.last_progression_chords
  harmony_measured = chords&.any?
  harmony_score = harmony_measured ? DillaHarmony.score_beauty(chords) : nil
  harmony_breakdown = harmony_measured ? DillaHarmony.score_breakdown(chords) : nil
  harshness = DillaMaster.analyze_harshness(spectrum)
  sub_kick = DillaMaster.sub_kick_balance(spectrum, harmony_score)
  report = media_metadata(path).merge(
    schema: "dilla.master.v1", path: File.expand_path(path), delivery: File.extname(path).delete_prefix(".").downcase,
    integrated_lufs: loudness["input_i"]&.to_f, true_peak_dbtp: loudness["input_tp"]&.to_f,
    harmony_score:, harmony_breakdown:,
    progression_chord_names: chords&.map { |c| c[:name] },
    harshness:, sub_kick_balance: sub_kick,
    ml_notes: (ENV["DILLA_ML"] == "1" ? [DillaMl.ddsp_stub_note] : nil),
    loudness_range_lu: loudness["input_lra"]&.to_f, mono_rms_db: mono, spectral_rms_db: spectrum,
    # MASTER_LUFS_BY_STYLE targets -17..-20 (dilla/donuts as low as -20) --
    # deliberately pulled down from a "-14..-11 radio-ready" figure after
    # direct feedback that the louder target was "way too loud"/fatiguing
    # (see MASTER_LUFS_BY_STYLE's own comment). This target/warning used to
    # still check the old broadcast-loud range, so it flagged a false
    # "too quiet" warning on every single correctly-targeted dilla render.
    stereo_phase_correlation: phase,
    target: { integrated_lufs: DILLA_QUALITY_LUFS_TARGET, true_peak_max_dbtp: -1.0 }, warnings: [],
    capabilities: Master::Io::AnalogCapabilities.for(:dilla).last(5).map { |entry| entry[:id] }
  )
  report[:warnings] << "true peak exceeds -1 dBTP" if report[:true_peak_dbtp] && report[:true_peak_dbtp] > -1.0
  report[:warnings] << "master is outside the #{DILLA_QUALITY_LUFS_TARGET} LUFS range" if report[:integrated_lufs] && !DILLA_QUALITY_LUFS_TARGET.cover?(report[:integrated_lufs])
  min_phase = DillaMaster.loss_gates["stereo_phase_correlation_min"]
  if phase && min_phase && phase < min_phase
    report[:warnings] << "stereo phase correlation #{phase.round(2)} < #{min_phase} (mono cancellation risk)"
  end
  if baseline_path && File.file?(baseline_path)
    baseline = JSON.parse(File.read(baseline_path), symbolize_names: true)
    old = baseline[:spectral_rms_db] || {}
    report[:spectral_delta_db] = spectrum.to_h { |band, value| [band, (value - old.fetch(band, value).to_f).round(3)] }
    report[:warnings] << "spectral balance moved more than 4 dB" if report[:spectral_delta_db].values.any? { |delta| delta.abs > 4.0 }
  end
  sidecar = "#{path}.quality.json"
  File.write(sidecar, JSON.pretty_generate(report) + "\n")

  # Say the warnings out loud, not only inside a JSON blob.
  #
  # These were computed correctly and written to a sidecar nobody opens, then
  # printed as part of a forty-line pretty-printed hash where a warning reads as
  # one more field. techno1.mp3.quality.json has carried "master is outside the
  # -20.5..-15.5 LUFS range" since 2026-08-11 and the take shipped at -14.0 LUFS
  # anyway. Eleven of thirty-four renders sit at or above -1.0 dBTP with the same
  # warning recorded and unread.
  #
  # This does not block a render — a gate that refuses to write a file the
  # operator asked for is a different decision, and one for the operator. It
  # makes the finding visible at the moment it is produced.
  Array(report[:warnings]).each do |warning|
    dmesg_warn("quality: #{warning}")
  end

  puts JSON.pretty_generate(report.merge(sidecar:))
  report
end

def clean(input, output)
  abort "missing input" unless input && File.exist?(input)
  FileUtils.mkdir_p(File.dirname(output))
  sh! "ffmpeg", "-y", "-i", input, "-af", "highpass=f=28,lowpass=f=15500,afftdn=nf=-25,adeclick,loudnorm=I=-18:TP=-1.5:LRA=10", "-c:a", "pcm_s16le", output
  puts "wrote #{output}"
end

# --- Stems rack (manifest in stems/) ---

def stems_load_manifest
  return { "active" => "default", "sets" => {} } unless File.exist?(STEM_MANIFEST)
  JSON.parse(File.read(STEM_MANIFEST, encoding: "utf-8"))
end

def stems_write_manifest(manifest)
  FileUtils.mkdir_p(File.dirname(STEM_MANIFEST))
  File.write(STEM_MANIFEST, JSON.pretty_generate(manifest) + "\n")
  puts "manifest -> #{STEM_MANIFEST}"
end

def stems_scan_set(dir)
  Dir.children(dir).select { |f| STEM_EXTS.include?(File.extname(f).downcase) }.sort
end

def stems_register(name, dir, bpm: nil, source: nil)
  rel = dir.sub(%r{\A#{Regexp.escape(STEM_DIR)}/?}, "")
  rel = "." if rel.empty?
  files = stems_scan_set(dir)
  abort "no stems in #{dir}" if files.empty?
  m = stems_load_manifest
  m["sets"][name] = { "dir" => rel, "bpm" => bpm, "source" => source, "files" => files }.compact
  m["active"] ||= name
  stems_write_manifest(m)
end

# Writes the manifest stems_load_manifest reads, in the shape it reads.
#
# The two halves of this subsystem never met. `stems scan` wrote
# samples/manifest.json with sets as an ARRAY and repo-relative stem paths;
# stems_load_manifest reads STEM_MANIFEST (stems/manifest.json) and every
# consumer -- render_liveset is the only one -- wants sets as a HASH with
# `dir` + `files`. STEM_DIR does not exist in the tree either, so the loader
# always returned its empty default and render_liveset aborted with "no stem
# set". Scanning produced a file nothing could read, at a path nothing looked at.
#
# `dir` is relative to ROOT rather than STEM_DIR because the stems live under
# samples/demux; render_liveset resolves it against ROOT for that reason.
#
# bpm is deliberately nil. A bare `bpm` is not a parameter here -- it is the
# method returning the RENDER's configured tempo, which records all seven demucs
# sets at 88.32 whatever the record ran at. A stem
# stretched by that ratio drifts. cd8e6850f settled the principle when it
# rejected two of four vocal tempos rather than write a number that would drift:
# no bpm is a question, a wrong bpm is a silent fault.
def stems_scan(root = File.join(SAMPLE_DIR, "demux"), manifest = STEM_MANIFEST)
  grouped = Dir.glob(File.join(root, "**", "*.{wav,mp3,flac,ogg,m4a}"), File::FNM_EXTGLOB)
               .group_by { |path| File.dirname(path) }
  existing = File.exist?(manifest) ? JSON.parse(File.read(manifest, encoding: "utf-8")) : {}
  sets = grouped.each_with_object({}).with_index do |((directory, files), acc), index|
    name = File.basename(directory)
    acc[name] = {
      "dir" => directory.sub(%r{\A#{Regexp.escape(ROOT)}/?}, ""),
      "bpm" => existing.dig("sets", name, "bpm"),
      "files" => files.map { |path| File.basename(path) }.sort,
      "stems" => stem_paths(files),
      "prime_swell" => ANALOG_PRIMES[index % ANALOG_PRIMES.length],
    }
  end
  FileUtils.mkdir_p(File.dirname(manifest))
  File.write(manifest, JSON.pretty_generate({
    "version" => 5,
    "active" => existing["active"] || sets.keys.first,
    "sets" => sets,
  }) + "\n")
  puts "manifest -> #{manifest} (#{sets.size} sets, #{sets.sum { |_, s| s['files'].size }} stems)"
end

def stems(*args)
  case args[0]
  when "scan"
    # Defer to stems_scan's own defaults rather than restating them. This line
    # carried a second copy that disagreed with it twice over: samples/demucs,
    # which is not the folder (it is samples/demux, so a bare `stems scan` found
    # nothing and said so by writing an empty manifest), and samples/manifest.json,
    # which is not where stems_load_manifest reads.
    stems_scan(*args[1, 2].compact)
  when "add"
    name = args[1] or abort "usage: ruby dilla.rb stems add <name> <dir> [bpm]"
    dir = args[2] or abort "usage: ruby dilla.rb stems add <name> <dir> [bpm]"
    stems_register(name, File.expand_path(dir), bpm: (args[3] && args[3].to_f))
  when nil
    stems_register("default", STEM_DIR, bpm: 90, source: "Sirkel Sag · Voicemails")
  else
    stems_scan(args[0], args[1] || STEM_MANIFEST)
  end
end

def stem_paths(files)
  files.each_with_object({}) { |path, map| map[stem_key(path)] = path.sub(ROOT + "/", "") }
end

def stem_key(path)
  basename = File.basename(path).downcase
  # no_vocals BEFORE vocals, and sub_bass before bass: these are substring tests
  # into one hash, so "no_vocals.wav" keyed as "vocals" and overwrote the real
  # vocal stem -- whichever the glob reached last won. Two of the demucs sets are
  # vocals + no_vocals only, so the instrumental, the only usable non-vocal
  # material in them, was discarded on the way into the manifest.
  return "no_vocals" if basename.include?("no_vocals")
  return "sub_bass" if basename.include?("sub_bass")
  return "drums" if basename.include?("drums")
  return "bass" if basename.include?("bass")
  return "vocals" if basename.include?("vocals")
  return "other" if basename.include?("other")
  File.basename(path, ".*")
end

def chords
  PAD_CHORDS.each_with_index { |chord, number| puts "%02d %s %s" % [number + 1, chord[:name], chord[:hz].map { |frequency| frequency.round(2) }.join(" ")] }
end

# Does every chord symbol the tables name actually come back as that chord?
#
# Nothing downstream asks. resolve_pad_chord_symbol answers nil on a symbol it
# cannot build and progression_for's filter_map drops it without a word, so a
# progression can render a chord short forever; and a symbol that resolves to
# the WRONG notes never even loses a chord, it sounds subtly incorrect in
# a way no gate measures. Both failures were live when this was written:
#
#   Abdim          nil -- chromatic_descent_sixteen's bass walk had a hole in it
#   C7#9 Hendrix   a minor third and a b9: Cm7b9 under the Hendrix chord's name
#   D/E            no F#, so the "9" in the E9sus4 it is documented as was gone
#   Fm11           a b9 where the fifth goes (six-note gem voicing, top 5 kept)
#   G13            no fifth, no D, an added 9 instead -- in 11 progressions
#   Eb9            root doubled where the b7 belongs, so a triad with a ninth
#
# The rule is DillaLofiMachine::CORE_TONES: the intervals that, if absent, make
# the symbol name a different chord. A slash chord is judged more leniently on
# purpose -- trim_slash_voicing spends one of five voices on the bass note and
# drops a chord tone (nearly always the fifth) to make room, which is the
# ordinary jazz omission and not a defect.
def chord_check
  tables = {
    "CHORD_PROGRESSIONS" => CHORD_PROGRESSIONS.transform_values { |v| Array(v) },
    "ARTIST_VERIFIED" => ARTIST_VERIFIED_PROGRESSIONS.to_h { |k, v| [k, Array(v[:chords])] },
  }
  seen = {}
  tables.each_value { |progs| progs.each { |name, syms| syms.each { |s| (seen[s] ||= []) << name } } }
  # The named voicing tables are checked too: four of the six bugs above were
  # hand-written entries in them, not parser output.
  (PAD_CHORD_LOOKUP.keys + DillaLofiMachine::CHORD_VOICINGS.keys).each { |s| seen[s] ||= [] }

  errors = []
  thin = []
  seen.keys.sort.each do |sym|
    chord = resolve_pad_chord_symbol(sym)
    if chord.nil? || Array(chord[:hz]).empty?
      errors << [sym, "does not resolve", seen[sym]]
      next
    end
    base = DillaLofiMachine.normalize_chord_symbol(sym)
    slash = base.include?("/")
    upper = slash ? base.split("/", 2).first.strip : base
    m = upper.match(/\A([A-G][#b]?)(.*)\z/) or next
    want = DillaLofiMachine::CORE_TONES[m[2].sub(/low\z/i, "")] or next
    root = DillaLofiMachine::NOTE_PC[m[1]] or next
    got = Array(chord[:hz]).map { |h| DillaLofiMachine.pitch_class_of(h) }.uniq
    absent = want.reject { |iv| got.include?((root + iv) % 12) }
    next if absent.empty?
    names = absent.map { |iv| INTERVAL_NAMES.fetch(iv % 12, iv.to_s) }.join(", ")
    # One omission in a slash chord is the voice the bass note took.
    (slash && absent.length == 1 ? thin : errors) << [sym, "missing #{names}", seen[sym]]
  end

  (thin + errors).each do |sym, why, used_by|
    where = used_by.empty? ? "voicing table" : used_by.first(3).join(", ")
    puts format("%-6s %-16s %-28s %s", errors.include?([sym, why, used_by]) ? "BROKEN" : "thin", sym, why, where)
  end
  puts "#{seen.size} symbols checked, #{errors.length} broken, #{thin.length} thin (slash-chord omission)"
  errors.length
end

# The same question asked of the melodic figures: does every builder in the
# table actually produce a usable line for every chord size it will be handed?
#
# arp_degrees_for calls these blind -- `builder.call(tone_count)` with whatever
# the chord happens to have -- and takes the result modulo the tone count, so a
# builder that returns an empty array, a nil, or the same degree over and over
# does not raise. It renders. As a held note, or as silence, in the middle of a
# track, once, for one chord, on one render.
def arp_check
  problems = 0
  ARP_PATTERN_BUILDERS.each do |name, builder|
    (2..7).each do |tones|
      raw = builder.arity >= 2 ? builder.call(tones, Random.new(9)) : builder.call(tones)
      unless raw.is_a?(Array) && raw.any? && raw.all?(Integer)
        puts format("BROKEN %-18s %d tones -> %s", name, tones, raw.inspect)
        problems += 1
        next
      end
      degrees = raw.map { |d| d % tones }
      next if degrees.uniq.length > 1
      puts format("FLAT   %-18s %d tones -> one pitch, %s", name, tones, degrees.first)
      problems += 1
    end
  end
  puts "#{ARP_PATTERN_BUILDERS.length} arp figures checked, #{problems} problem(s)"
  problems
end

# And of the drum grids. A step outside 0..15 lands in the next bar or before
# the start of this one; a role with no pattern at all takes drum_pattern_pick's
# fetch straight to KeyError mid-render.
def drum_check
  problems = 0
  DRUM_PATTERN_SETS.each do |feel, set|
    %i[kicks snares ghosts hats].each do |role|
      pool = set[role]
      unless pool.is_a?(Array) && pool.any?
        puts format("BROKEN %-20s %s: no patterns", feel, role)
        problems += 1
        next
      end
      pool.each do |steps|
        stray = Array(steps).reject { |s| s.is_a?(Integer) && s.between?(0, 15) }
        next if stray.empty?
        puts format("BROKEN %-20s %s: step(s) outside the bar %s", feel, role, stray.inspect)
        problems += 1
      end
    end
    stray = Array(set[:opens]).reject { |s| s.is_a?(Integer) && s.between?(0, 15) }
    next if stray.empty?
    puts format("BROKEN %-20s opens: %s", feel, stray.inspect)
    problems += 1
  end
  # A preset naming a feel or a progression that does not exist fails silently:
  # drum_feel_key swallows the first into :default, and the second into whatever
  # the fallback progression is.
  TRACK_PRESETS.each do |track, preset|
    if preset[:feel] && !DRUM_PATTERN_SETS.key?(preset[:feel])
      puts format("BROKEN %-20s names feel :%s, which does not exist", track, preset[:feel])
      problems += 1
    end
    # A preset's :progression is legal in either of two namespaces -- a key in
    # the table, or the name of a generator (:planing, :negative_harmony and the
    # rest of GENERATED_STYLES, which pad_progression routes before it ever
    # consults the table). Checking only the first reports nine working presets
    # as broken, which is worse than not checking at all.
    prog = preset[:progression]
    next unless prog
    next if CHORD_PROGRESSIONS.key?(prog) || GENERATED_STYLES.include?(prog) || prog == :generated
    puts format("BROKEN %-20s names progression :%s, which is neither a table entry nor a generator", track, prog)
    problems += 1
  end
  # Every feel has to be reachable by SOME door, or it is a grid nobody can
  # play. There are two doors and they are easy to confuse: TRACK=<name> picks
  # a preset, which names a feel; --drum-preset=<name> reaches anything merged
  # in from DillaLofiMachine::DRUM_PRESETS. Checked 2026-07-31 when the table
  # grew 56 -> 78 while TRACK_PRESETS stayed at 61, which looked like 22 new
  # orphans and was not — all of them came in through the lofi merge, so they
  # answer to --drum-preset. Nothing enforced that, though, and a feel added
  # straight into DRUM_PATTERN_SETS without a preset would be reachable only by
  # someone who already knew its name.
  #
  # There is a THIRD door, and reporting four working feels as BROKEN is how it
  # was found. DillaLofiMachine.profile_preset does `preset[:feel] = drum_key`
  # where drum_key is ENV["DRUM_PRESET"] unvalidated, and drum_feel_key accepts
  # any DRUM_PATTERN_SETS key — so `--drum-preset=liquid_dnb` plays liquid_dnb
  # even though liquid_dnb is not in DRUM_PRESETS at all. Verified against
  # profile_preset directly: it returns feel: :liquid_dnb.
  #
  # liquid_dnb, one_drop, dilla_canon and wonky_canon were all added on purpose
  # as opt-in ("nothing changes unless asked"), so a check calling them broken
  # was arguing with a decision. What is still worth saying is that nothing
  # NAMES them: you reach them only if you already know the word.
  reachable = TRACK_PRESETS.values.filter_map { |p| p[:feel] }.to_set | LOFI_DRUM_FEELS.to_set | Set[:default]
  (DRUM_PATTERN_SETS.keys - reachable.to_a).each do |feel|
    puts format("NOTE   feel :%s is reachable only as --drum-preset=%s — no preset or listing names it", feel, feel)
  end
  puts "#{DRUM_PATTERN_SETS.length} drum feels and #{TRACK_PRESETS.length} presets checked, #{problems} problem(s)"
  problems
end

# Chords, figures, grids. Everything the engine composes FROM, as opposed to
# everything it composes -- the vocabulary rather than the sentences. Cheap
# enough (no audio, no ffmpeg) to run on every change to any of the tables.
def vocab_check
  failures = chord_check + arp_check + drum_check + wiring_check
  puts failures.zero? ? "vocabulary ok" : "#{failures} problem(s)"
  exit(1) unless failures.zero?
end

# Constants read from somewhere this tree cannot see, so absence of a reader
# here is not absence of a reader.
WIRING_EXTERNAL_READERS = %w[
  SAMPLE_LOOPS_OUT_OF_ROTATION
  STREAM_ROTATION
].freeze

# How many declarations may have no reader. Zero, and it stays zero: the check
# fails the moment the number goes up, which is the only moment anyone can act
# on it cheaply.
#
# It was 23 for one day. Those 23 were the survivors of the sweep that added
# this check — the console emulation's transformer corners, MASTER_TARGET_LRA,
# the warm-pad program rotation, ninth voicings marked for fourteen presets,
# HIP_HOP_BPM/_BARS beside the live TECHNO_ pair, the RG69_* aliases, WAVES,
# SOUL_QUALITIES, NOTE_NAMES — and the baseline was set there rather than at
# zero because wiring any of them changes how a render SOUNDS, which is not a
# checker's call.
#
# Operator's call, 2026-08-12: delete them. Every one described a feature
# nobody had written, and a constant that describes a feature is indexed,
# grepped and read exactly like one that sets it — which is pub4's dominant
# defect class, and the reason a declaration with no reader is worse than no
# declaration at all. Deleting the twenty-three uncovered a twenty-fourth,
# DELICIOUS_REFERENCE_BPM, whose only reader had been one of them; it went too.
# What the deleted ones knew is in the git history and, where it was worth
# keeping, in the comment left where they stood.
#
# So there is no allowance left to spend. Adding a constant and its reader in
# the same commit is the only way past this line.
WIRING_DEAD_BASELINE = 0

def wiring_dead_constants
  # ENGINE_SOURCES, not just the entry script: most of the engine's constants
  # live in lib/engine/ since the split, and reading only dilla.rb would report
  # every one of them as undeclared and every reader as the only mention.
  # It used to append Dir[lib/*.rb] here by hand, in two places, because
  # ENGINE_SOURCES excluded them. It no longer does -- see lib/engine_sources.rb.
  sources = ENGINE_SOURCES
  defined_at = {}
  bodies = sources.to_h do |path|
    text = File.read(path)
    text.each_line.with_index(1) do |line, number|
      next unless (match = line.match(/^\s*([A-Z][A-Z0-9_]{2,})\s*=[^=~]/))

      defined_at[match[1]] ||= "#{File.basename(path)}:#{number}"
    end
    # Comments are where a dead constant is most often MENTIONED, which is why
    # a plain grep says everything is wired. `#{` is NOT a comment: a heredoc
    # line that is nothing but an interpolation starts with whitespace and a
    # hash, and stripping it hides a real reader. (Found by running the same
    # rule over STUDIO/lora, where it reported token_block dead when line 315
    # is `#{token_block(options)}`.)
    [path, text.gsub(/^\s*#(?!\{).*$/, "")]
  end
  code = bodies.values.join("\n")

  defined_at.reject do |name, _|
    next true if WIRING_EXTERNAL_READERS.include?(name)

    # `Mod::NAME` counts as a reader. `.` is deliberately NOT excluded: no
    # constant is ever reached through a dot, but `when ..LEAD_STEP_SEMITONES`
    # is a beginless range and excluding `.` reported that live constant dead —
    # the checker's own first false positive, found by reading its output
    # against the source rather than trusting the count.
    code.scan(/(?<![\w@$])#{name}(?![\w])/).length > 1
  end
end

# Called by nothing in the engine, but named by MASTER's test suite, which is
# not in the corpus below. The constant ratchet needs the same escape hatch and
# calls it WIRING_EXTERNAL_READERS.
WIRING_EXTERNAL_CALLERS = %w[engine_source].freeze

# The same ratchet as WIRING_DEAD_BASELINE, for methods.
#
# A constant with no reader and a method with no caller are the same defect.
# One designed stage remains uncalled on purpose:
#
#   dilla_mix_preprocess_filters   NY parallel + sub bump + mix low-pass.
#                                  mix_bass_chord_balance_filter's numbers were
#                                  tuned by ear against the master that actually
#                                  shipped (without this stage). Wiring it would
#                                  double-correct. Not a tidy-up's call.
#
# sample_modern_chain now runs on the sample loop bus. log_progression! is the
# writer log_progression_phases! calls. Wiring the remaining stage still
# changes how renders SOUND — operator's call. The baseline is the count, not
# a target.
WIRING_DEAD_METHOD_BASELINE = 1

def wiring_dead_methods
  defined_at = {}
  ENGINE_SOURCES.each do |path|
    body = RubyVM::AbstractSyntaxTree.parse_file(path).children[2]
    nodes = body.type == :BLOCK ? body.children : [body]
    nodes.each do |node|
      next unless node.type == :DEFN

      defined_at[node.children[0].to_s] ||= "#{File.basename(path)}:#{node.first_lineno}"
    end
  end
  # Same corpus and the same comment-stripping as the constant ratchet: a
  # method named only in prose is not called. `.` is excluded here where the
  # constant rule keeps it -- a constant is never reached through a dot, but a
  # method often is, and `foo.bar` is a call on something else entirely.
  code = ENGINE_SOURCES.map { |path| File.read(path).gsub(/^\s*#(?!\{).*$/, "") }.join("\n")
  defined_at.reject do |name, _|
    next true if WIRING_EXTERNAL_CALLERS.include?(name)

    code.scan(/(?<![\w@$.])#{Regexp.escape(name)}(?![\w])/).length > 1
  end
end

def wiring_check
  dead = wiring_dead_constants
  dead.sort_by { |_, where| where }.each { |name, where| puts format("NOTE   %-32s declared at %s, no reader", name, where) }
  puts "#{dead.length} declaration(s) with no reader (baseline #{WIRING_DEAD_BASELINE})"

  orphans = wiring_dead_methods
  orphans.sort_by { |_, where| where }.each { |name, where| puts format("NOTE   %-32s defined at %s, no caller", name, where) }
  puts "#{orphans.length} method(s) with no caller (baseline #{WIRING_DEAD_METHOD_BASELINE})"

  status = 0
  if dead.length > WIRING_DEAD_BASELINE
    puts "BROKEN dead declarations rose #{WIRING_DEAD_BASELINE} -> #{dead.length}; wire it or say why in WIRING_DEAD_BASELINE"
    status = 1
  end
  if orphans.length > WIRING_DEAD_METHOD_BASELINE
    puts "BROKEN uncalled methods rose #{WIRING_DEAD_METHOD_BASELINE} -> #{orphans.length}; " \
         "call it or say why in WIRING_DEAD_METHOD_BASELINE"
    status = 1
  end
  missing = SECTION_LAYERS_APPLIED - SECTION_LAYERS_DECLARED
  unread = SECTION_LAYERS_DECLARED - SECTION_LAYERS_APPLIED
  if missing.any? || unread.any?
    puts "BROKEN section layers applied-not-declared=#{missing.inspect} declared-not-applied=#{unread.inspect}"
    status = 1
  end
  status
end

# ============================================================================
# THE DEVICES, FROM THE COMMAND LINE
#
# Absorbed from device_cmds.rb, which was a second file of exactly this kind
# created in the same change as the commands it held. Every device can be run
# on its own, on a file the operator names, before it is wired into anything --
# which is the lesson behind `dilla audit`: 24 pad voices, 209 of 250
# progressions and a pad whose effect chain had never opened all shipped
# complete, correct and unreachable. A device with no way to hear it alone is a
# device nobody can tell is broken.
#
# Options are BARE WORDS -- `copies=8`, `describe` -- not --flags. dilla.rb's
# global flag parser consumes every argument starting with -- before dispatch
# runs and aborts on any it does not recognise, so `dilla wav-map pic.png
# describe` would die printing a list of 104 flags. knobs_report hit this first
# and its header says the same thing.
# ============================================================================
# key=value pairs and declared switches out of an argv tail, positionals in order.
def device_flags(argv, switches: [])
  flags = {}
  rest = []
  known = switches.map(&:to_s)
  argv.each do |arg|
    if arg.include?("=") && !File.exist?(arg)
      key, value = arg.split("=", 2)
      flags[key.delete_prefix("--").tr("-", "_").to_sym] = value
    elsif known.include?(arg)
      flags[arg.tr("-", "_").to_sym] = ""
    else
      rest << arg
    end
  end
  [flags, rest]
end

def device_float(flags, key, default) = flags.key?(key) ? flags[key].to_f : default
def device_int(flags, key, default) = flags.key?(key) ? flags[key].to_i : default

# ---------------------------------------------------------------- copy machine
#
#   dilla copy-machine in.wav out.wav copies=8 family=spray duration=12
#   dilla copy-machine describe copies=8 family=harmonic
def copy_machine_cli!(argv)
  flags, rest = device_flags(argv, switches: %w[describe])
  plan = CopyMachine.plan(
    copies: device_int(flags, :copies, 6),
    family: (flags[:family] || "harmonic").to_sym,
    reverse: device_float(flags, :reverse, 0.25),
    width: device_float(flags, :width, 0.8),
    drift: device_float(flags, :drift, 220.0),
    tilt: device_float(flags, :tilt, 0.55),
    seed: device_int(flags, :seed, 4242)
  )
  if flags.key?(:describe) || rest.length < 2
    puts CopyMachine.describe(plan)
    puts "families: #{CopyMachine::RATIOS.keys.join(', ')}"
    return puts("usage: dilla copy-machine <in> <out> [copies=N family=… duration=S]") if rest.length < 2
  end

  src, dest = rest
  out = CopyMachine.build!(
    src:, dest:,
    copies: device_int(flags, :copies, 6),
    family: (flags[:family] || "harmonic").to_sym,
    reverse: device_float(flags, :reverse, 0.25),
    width: device_float(flags, :width, 0.8),
    drift: device_float(flags, :drift, 220.0),
    tilt: device_float(flags, :tilt, 0.55),
    seed: device_int(flags, :seed, 4242),
    duration: flags.key?(:duration) ? flags[:duration].to_f : nil,
    rate: SAMPLE_RATE
  )
  puts out ? "copy-machine: #{plan.length} copies -> #{out}" : "copy-machine: no such source #{src}"
end

# --------------------------------------------------------------------- hocket
#
# Runs on the progression the engine would render, so what it prints is what a
# real part would be split into rather than a demonstration on invented notes.
#
#   dilla hocket voices=4 mode=pendulum hold=2
def hocket_cli!(argv)
  flags, = device_flags(argv, switches: %w[write])
  cfg = dilla_resolve_config
  events = hocket_source_events(cfg)
  return puts("hocket: the current track produced no note events to split") if events.empty?

  split = MidiDevices::Hocket.split(
    events,
    voices: device_int(flags, :voices, 4),
    mode: (flags[:mode] || "pendulum").to_sym,
    hold: device_int(flags, :hold, 1),
    seed: device_int(flags, :seed, 4242)
  )
  puts "hocket: #{events.length} note(s) from #{cfg[:track]} across #{split.length} voice(s), " \
       "mode=#{flags[:mode] || 'pendulum'} hold=#{device_int(flags, :hold, 1)}"
  puts MidiDevices::Hocket.describe(split).map { |l| "  #{l}" }
  return unless flags.key?(:write)

  # One SMF per voice, so the split can be heard rather than read. midi_smf's
  # writer is reused as-is; nothing here invents a MIDI byte.
  dir = flags[:write].to_s.empty? ? File.join(SCRATCH_DIR, "hocket") : flags[:write]
  FileUtils.mkdir_p(dir)
  split.each_with_index do |voice, i|
    next if voice.empty?

    path = File.join(dir, "voice_#{i + 1}.mid")
    write_smf(path, voice, program: EP_GM_PROGRAMS[i % EP_GM_PROGRAMS.length], channel: i)
    puts "  wrote #{path}"
  end
end

# The notes a hocket has to work with. The harmonic arp is the engine's most
# note-dense part and the one a hocket is actually for -- splitting a pad across
# voices moves sustained chords around, which is a different and duller effect.
def hocket_source_events(cfg)
  chords = dilla_progression(cfg[:progression])
  return [] if chords.nil? || chords.empty?

  bar = 60.0 / cfg[:bpm].to_f * 4.0
  step = bar / 8.0
  (0...(chords.length * 8)).map do |i|
    chord = chords[(i / 8) % chords.length]
    [i * step, 0.55 + ((i % 4).zero? ? 0.25 : 0.0), chord, step * 0.9]
  end
end

# ------------------------------------------------------------------- midi bag
#
#   dilla midi-bag order=walk rests=0.25 fit-chords
def midi_bag_cli!(argv)
  flags, = device_flags(argv, switches: %w[write fit-chords fit_chords])
  cfg = dilla_resolve_config
  pitches = hocket_source_events(cfg)
  return puts("midi-bag: the current track produced no pitches to bag") if pitches.empty?

  # The timing comes from the drum grid, which is the whole point: the melody's
  # notes land where the kit lands rather than where the melody put them.
  timing = midi_bag_timing_events(cfg)
  return puts("midi-bag: no drum grid to take timing from") if timing.empty?

  chord_at = if flags.key?(:fit_chords)
               bar = 60.0 / cfg[:bpm].to_f * 4.0
               chords = dilla_progression(cfg[:progression])
               ->(t) { chords[((t / bar).floor) % chords.length] }
             end
  out = MidiDevices::Bag.apply(
    pitches:, timing:,
    order: (flags[:order] || "cycle").to_sym,
    velocity_from: (flags[:velocity_from] || "timing").to_sym,
    rests: device_float(flags, :rests, 0.0),
    seed: device_int(flags, :seed, 4242),
    chord_at:
  )
  puts "midi-bag: #{pitches.length} pitch(es) from #{cfg[:track]}, " \
       "#{timing.length} timing slot(s) from the kit -> #{out.length} note(s)"
  out.first(12).each do |t, v, chord, sustain|
    puts format("  %6.2fs  vel %.2f  %-22s sus %.2f", t, v,
                Array(chord[:hz]).first(3).map { |hz| hz.round(1) }.join("/"), sustain)
  end
  puts "  …#{out.length - 12} more" if out.length > 12
  return unless flags.key?(:write)

  path = flags[:write].to_s.empty? ? File.join(SCRATCH_DIR, "midi_bag.mid") : flags[:write]
  FileUtils.mkdir_p(File.dirname(path))
  write_smf(path, out, program: PAD_GM_PROGRAM)
  puts "  wrote #{path}"
end

# The kit's onsets, as timing slots. Velocities come with them, which is what
# makes the bagged part inherit the drums' accents.
def midi_bag_timing_events(cfg)
  bar = 60.0 / cfg[:bpm].to_f * 4.0
  step = bar / 16.0
  (0...32).filter_map do |i|
    beat = i % 16
    # A sixteenth grid with the offbeats thinned, so what comes out is a part
    # rather than a machine gun. Downbeats and the two-and-four accent.
    next if [3, 7, 11, 15].include?(beat) && i.even?

    [i * step, [0, 4, 8, 12].include?(beat) ? 0.9 : 0.55, { hz: [110.0] }, step * 0.85]
  end
end

# -------------------------------------------------------------------- wav map
#
#   dilla wav-map picture.png out.wav hz=110 path=lissajous duration=8
#   dilla wav-map picture.png describe
def wav_map_cli!(argv)
  flags, rest = device_flags(argv, switches: %w[describe])
  image = rest.shift
  return puts("usage: dilla wav-map <image> [out.wav] [hz=110 path=#{WavMap::PATHS.join('|')}]") unless image

  path = (flags[:path] || "circle").to_sym
  if flags.key?(:describe) || rest.empty?
    puts WavMap.describe(image, path:, lobes: device_int(flags, :lobes, 5))
    return if rest.empty?
  end
  out = WavMap.render!(image, rest.first,
                       hz: device_float(flags, :hz, 110.0),
                       duration: device_float(flags, :duration, 8.0),
                       path:, lobes: device_int(flags, :lobes, 5),
                       rate: SAMPLE_RATE,
                       drift_cents: device_float(flags, :drift_cents, 6.0),
                       seed: device_int(flags, :seed, 4242))
  puts out ? "wav-map: #{File.basename(image)} via #{path} -> #{out}" : "wav-map: could not read #{image}"
end

# --------------------------------------------------------------------- macros
#
#   dilla macro                      what there is
#   dilla macro dust=0.7 weight=0.6  what those would set, without setting it
#   dilla macro dust=0.7 apply
def macro_cli!(argv)
  flags, rest = device_flags(argv, switches: %w[apply force])
  settings = rest.take_while { |a| a.include?("=") }.to_h do |pair|
    name, value = pair.split("=", 2)
    [name.to_sym, value.to_f]
  end
  if settings.empty?
    puts "macros — #{DillaMacros::MACROS.length} words for #{DillaKnobs.all.length} knobs"
    DillaMacros::MACROS.each do |name, targets|
      puts format("  %-9s %s", name, targets.map(&:knob).join(", "))
    end
    return puts("\nusage: dilla macro dust=0.7 weight=0.6 [apply] [force]")
  end

  values, collisions = DillaMacros.resolve_all(settings)
  settings.each_key { |name| puts DillaMacros.describe(name, settings[name]) }
  collisions.each do |knob, names|
    puts "  NOTE #{knob} is set by more than one macro (#{names.join(', ')}); the last one wins"
  end
  return puts("\n#{values.length} knob(s) — add `apply` to set them for this process") unless flags.key?(:apply)

  result = DillaMacros.apply!(settings, force: flags.key?(:force))
  puts "\napplied: #{result[:applied].join(' ')}"
  puts "kept your own: #{result[:skipped].join(' ')}" if result[:skipped].any?
end

# ----------------------------------------------------------------- modulation
#
# Prints and proves a matrix rather than rendering with one. Wiring modulation
# into a render changes how every take sounds, and that is not a decision this
# command makes -- it is here so the mechanism can be measured before it is.
#
#   dilla modulate in.wav out.wav lfo=0.5 target=lowpass.frequency base=900
def modulate_cli!(argv)
  flags, rest = device_flags(argv, switches: %w[describe])
  target = (flags[:target] || "lowpass.frequency").split(".")
  filter, param = target
  matrix = DillaModulation::Matrix.new
  matrix.lfo(:lfo1, rate_hz: device_float(flags, :lfo, 0.5),
                    family: (flags[:family] || "curved").to_sym,
                    morph: device_float(flags, :morph, 0.33))
  begin
    matrix.route(:lfo1, instance: "mod", filter:, param:,
                        base: flags.key?(:base) ? flags[:base].to_f : nil,
                        depth: device_float(flags, :depth, 1.0),
                        mode: (flags[:mode] || "modulate").to_sym)
  rescue ArgumentError => e
    return puts("modulate: #{e.message}")
  end
  puts matrix.describe.map { |l| "  #{l}" }

  src, dest = rest
  return puts("usage: dilla modulate <in> <out> [lfo=Hz target=filter.param base=N depth=0..1]") unless src && dest
  return puts("modulate: no such file #{src}") unless File.file?(src)

  duration = audio_duration_sec(src).to_f
  return puts("modulate: could not read a duration from #{src}") unless duration.positive?

  cmds = File.join(SCRATCH_DIR, "modulation.cmds")
  FileUtils.mkdir_p(SCRATCH_DIR)
  prefix = DillaModulation.prefix_for(matrix, path: cmds, duration:)
  route = matrix.routes.first
  chain = "#{prefix},#{matrix.instance_name(route)}=#{route.param}=#{matrix.initial(route)}"
  sh! "ffmpeg", "-y", "-i", src, "-af", chain, "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", dest
  puts "modulate: #{File.readlines(cmds).length} command(s) over #{duration.round(1)}s -> #{dest}"
end

# --------------------------------------------------------------- arrangement
#
# Does this have an arrangement, and how does it compare with a record?
#
#   dilla arrangement out.mp3
#   dilla arrangement out.mp3 crate/sources/kembara_rindu/source.wav
#
# Two files or more prints the comparison table, which is the only use of this
# worth much: the numbers mean nothing on their own and everything against
# material somebody has already judged.
def arrangement_cli!(argv)
  flags, rest = device_flags(argv, switches: %w[detail])
  paths = rest.reject(&:empty?)
  if paths.empty?
    return puts("usage: dilla arrangement <file> [reference…]   " \
                "(add `detail` for boundaries and the loudness spread)")
  end

  missing = paths.reject { |p| File.file?(p) }
  puts "no such file: #{missing.join(', ')}" if missing.any?
  paths -= missing
  return if paths.empty?

  puts Arrangement.compare(paths)
  return unless flags.key?(:detail)

  puts
  paths.each do |path|
    r = Arrangement.analyse(path) or next

    puts "#{File.basename(path)}"
    puts format("  boundaries   %s", r[:boundaries].empty? ? "(none above the noise floor)" : r[:boundaries].join(", "))
    puts format("  novelty      peak %.4f  mean %.4f  contrast %.2f " \
                "(null cases: one-bar loop peaks #{format('%.5f', 0.00137)}, " \
                "the floor is #{format('%.3f', Arrangement::NOISE_FLOOR)})",
                r[:novelty_peak], r[:novelty_mean], r[:novelty_contrast])
    if (l = r[:loudness])
      puts format("  short-term   p10 %.1f  p50 %.1f  p90 %.1f  spread %.1f LU",
                  l[:p10], l[:p50], l[:p90], l[:spread])
    end
  end
end

# ------------------------------------------------------------------------ ab
#
#   dilla ab COPY_MACHINE=6 bars=16 track=semua_untuk_mu
#   dilla ab SONITEX=donuts_soul bars=48 detail
#
# UPPERCASE is a knob to change; lowercase is an option for the comparison
# itself. That is dillas own convention -- every knob in the engine is uppercase
# -- and it means no separator, which matters because the global flag parser
# consumes `--` before dispatch runs and aborts on it.
#
# Two renders differing in exactly the stated knobs, level-matched, measured.
#
# This was done by hand a dozen times over one session and got the answer wrong
# more than once, always the same way: an arm that differed in something other
# than the variable. A 16-bar comparison whose windows did not overlap the change
# proved nothing and was reported as a negative; a "same settings" pair turned
# out to use two different section maps. Both would have been caught by the two
# things this does automatically -- pin the seed and freeze the learned state on
# both arms, and print the render-to-render noise floor beside the difference.
#
# The noise floor is the part worth having. Two identical-seed renders of this
# engine still differ (RENDER_SEED does not fully pin; the measured spread is
# about 0.15 on the novelty metrics and a few hundredths of a dB on level), so a
# difference smaller than that is not a finding. Without a control arm there is
# no way to know which side of that line a number falls on -- and a no-kit
# reference built four minutes too late is what six hypotheses died for.
# What a render legitimately needs from the surrounding process. Everything
# else is dropped, so neither arm can inherit a booted style.
AB_PASSTHROUGH = %w[PATH HOME TMPDIR LANG SHELL USER].freeze

def ab_cli!(argv)
  # Split on case rather than handing everything to device_flags, which treats
  # every key=value as an option and would swallow the knobs being compared.
  changes = argv.select { |a| a =~ /\A[A-Z][A-Z0-9_]*=/ }
  flags, = device_flags(argv - changes, switches: %w[detail keep])
  return puts("usage: dilla ab KNOB=value [KNOB=value…] [-- bars=16 track=… detail]") if changes.empty?

  bars = device_int(flags, :bars, 16)
  out = flags[:out] || File.join(SCRATCH_DIR, "ab")
  FileUtils.mkdir_p(out)
  # A CLEAN environment, not this process's.
  #
  # `dilla ab` runs inside dilla.rb, which sets style-lock knobs during its own
  # boot -- env_locks.rb reasserts them so the mix does not drift. A child
  # spawned with the parent's environment inherits all of that, and the first
  # version of this command produced three arms of identical file size because
  # the inherited style pinned SONITEX over the very knob under test.
  #
  # That is exactly the failure this command exists to prevent -- arms differing
  # in more than the variable -- so it must not commit it itself. Only what a
  # render legitimately needs from the process is carried through, and the spawn
  # below passes unsetenv_others so nothing else can leak in.
  base = AB_PASSTHROUGH.to_h { |k| [k, ENV.fetch(k, nil)] }.compact
  base.merge!("DILLA_FROZEN" => "1",
              "RENDER_SEED" => flags.fetch(:seed, "20260825").to_s,
              "DILLA_SH_TIMEOUT" => ENV.fetch("DILLA_SH_TIMEOUT", "900"))
  base["TRACK"] = flags[:track] if flags[:track]

  # Three arms, not two. The control is a second render of the BASELINE, which
  # is what turns "these differ by 0.3 dB" into "these differ by 0.3 dB and the
  # noise is 0.2".
  arms = {
    "baseline" => base,
    "control" => base,
    "changed" => base.merge(changes.to_h { |c| c.split("=", 2) }),
  }
  rendered = arms.to_h do |name, env|
    path = File.join(out, "ab_#{name}.mp3")
    puts "rendering #{name}#{name == 'changed' ? " (#{changes.join(' ')})" : ''}…"
    system(env, RbConfig.ruby, DillaSources.entry, "dilla", path, bars.to_s,
           unsetenv_others: true, out: File::NULL, err: File::NULL)
    [name, path]
  end
  missing = rendered.reject { |_, p| File.file?(p) }
  return puts("ab: #{missing.keys.join(', ')} failed to render") if missing.any?

  report_ab(rendered, changes, flags.key?(:detail))
  FileUtils.rm_rf(out) unless flags.key?(:keep)
end

# What differs, against what differs anyway.
def report_ab(rendered, changes, detail)
  vals = rendered.transform_values { |p| ab_measure(p) }
  noise = (vals["control"][:lufs] - vals["baseline"][:lufs]).abs
  puts
  puts "changed: #{changes.join(' ')}"
  puts format("%-12s %9s %9s %9s %9s", "arm", "LUFS", "LRA", "peak", "crest")
  vals.each do |name, v|
    puts format("%-12s %9.2f %9.2f %9.2f %9.2f", name, v[:lufs], v[:lra], v[:peak], v[:crest])
  end
  puts
  d = vals["changed"][:lufs] - vals["baseline"][:lufs]
  puts format("level     %+.2f LUFS against a %.2f LUFS noise floor -- %s",
              d, noise,
              d.abs > [noise * 2, 0.05].max ? "real" : "inside the noise")

  # Level is a weak discriminator here and saying so is the point: the engine
  # normalises every render to a fixed integrated loudness, so a change that
  # alters the TONE and not the level reports +0.00 LUFS and reads as nothing.
  # A preset swap is exactly that. Bands are the metric that separates them --
  # a level change moves every band together, and an instrumentation or tone
  # change does not, which is what "spread" measures.
  bands = ab_bands(rendered)
  puts
  puts format("%-12s %8s %8s %8s %8s %8s %8s", "arm", "30-120", "120-300", "300-800", "800-2k", "2k-5k", "5k-12k")
  bands.each { |name, v| puts format("%-12s %8.1f %8.1f %8.1f %8.1f %8.1f %8.1f", name, *v) }
  ctl = bands["control"].each_with_index.map { |v, i| (v - bands["baseline"][i]).abs }.max
  chg = bands["changed"].each_with_index.map { |v, i| v - bands["baseline"][i] }
  puts format("bands     largest change %+.1f dB, spread %.1f dB, against %.1f dB of render noise -- %s",
              chg.max_by(&:abs), chg.max - chg.min, ctl,
              chg.map(&:abs).max > [ctl * 2, 0.3].max ? "real" : "inside the noise")
  return unless detail

  puts
  puts "arrangement (same instrument, same frame duration on both arms):"
  puts Arrangement.compare([rendered["baseline"], rendered["changed"]])
end

# Octave-ish bands, cascaded twice each so the skirts are steep enough that a
# neighbouring band does not leak into the reading.
AB_BANDS = [[30, 120], [120, 300], [300, 800], [800, 2000], [2000, 5000], [5000, 12_000]].freeze

def ab_bands(rendered)
  rendered.transform_values do |path|
    AB_BANDS.map do |lo, hi|
      o = IO.popen(["ffmpeg", "-hide_banner", "-i", path, "-af",
                    "highpass=f=#{lo},highpass=f=#{lo},lowpass=f=#{hi},lowpass=f=#{hi},volumedetect",
                    "-f", "null", "-"], err: %i[child out], &:read)
      o[/mean_volume: (-?[\d.]+)/, 1].to_f
    end
  end
end

def ab_measure(path)
  o = IO.popen(["ffmpeg", "-hide_banner", "-i", path, "-af", "volumedetect", "-f", "null", "-"],
               err: %i[child out], &:read)
  e = IO.popen(["ffmpeg", "-hide_banner", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"],
               err: %i[child out], &:read)
  peak = o[/max_volume: (-?[\d.]+)/, 1].to_f
  rms = o[/mean_volume: (-?[\d.]+)/, 1].to_f
  { peak:, rms:, crest: (peak - rms).round(2),
    lufs: e.scan(/I:\s*(-?[\d.]+) LUFS/).flatten.last.to_f,
    lra: e.scan(/LRA:\s*(-?[\d.]+) LU/).flatten.last.to_f }
end
