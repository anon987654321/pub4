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
# bpm is deliberately nil. It used to be `bpm`, which is not a parameter here --
# it is the method returning the RENDER's configured tempo, so all seven demucs
# sets were recorded at 88.32 whatever the record actually ran at. A stem
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
    dir  = args[2] or abort "usage: ruby dilla.rb stems add <name> <dir> [bpm]"
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
# the WRONG notes never even loses a chord, it just sounds subtly incorrect in
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
  # liquid_dnb, one_drop, dilla_canon and flylo_canon were all added on purpose
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
  # method very often is, and `foo.bar` is a call on something else entirely.
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
