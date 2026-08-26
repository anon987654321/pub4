# frozen_string_literal: true
#
# Listening back: spectral, rhythmic and harmonic analysis of a finished file.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

INTERVAL_NAMES = {
  0 => "root", 1 => "b9", 2 => "9", 3 => "b3", 4 => "3", 5 => "11",
  6 => "b5", 7 => "5", 8 => "#5", 9 => "13", 10 => "b7", 11 => "maj7",
}.freeze

def study(kind, input = nil)
  input ||= prompt("audio path")
  abort "missing #{input}" unless File.exist?(input)
  return rhythm(input) if kind == "rhythm"
  return melody(input) if kind == "melody"
  return harmony(input) if kind == "harmony"
  return semantics(input) if kind == "semantics"
  abort "study kind must be rhythm, melody, harmony, or semantics"
end

def rhythm(input = nil)
  input ||= prompt("drum or full audio path")
  data = frame_energy(input, highpass: 90, lowpass: 8_000)
  peaks = peak_frames(data.fetch(:frames), data.fetch(:hop_seconds))
  puts JSON.pretty_generate(type: "rhythm", path: input, duration_seconds: data.fetch(:duration_seconds), peaks: peaks.first(128))
end

def melody(input = nil)
  input ||= prompt("melodic stem path")
  data = spectral_windows(input)
  puts JSON.pretty_generate(type: "melody", path: input, duration_seconds: data.fetch(:duration_seconds), windows: data.fetch(:windows).first(128))
end

def harmony(input = nil)
  input ||= prompt("harmonic stem path")
  profile = pitch_profile(input)
  pcs = profile.fetch(:pitch_classes)
  ranking = chord_candidates(pcs).first(16)
  coltrane_hits = DillaMusicGems.chord_candidates_from_pitch_classes(pcs, limit: 12) if defined?(DillaMusicGems)
  puts JSON.pretty_generate(
    type: "harmony", path: input, duration_seconds: profile.fetch(:duration_seconds),
    pitch_classes: pcs, chords: ranking,
    coltrane_candidates: coltrane_hits,
    pitch_class_set: DillaMusicGems.pitch_class_set(pcs)&.to_a
  )
end

def beauty_report(path = nil)
  chords = DillaHarmony.last_progression_chords
  if path && File.file?(path)
    sidecar = "#{path}.quality.json"
    if File.file?(sidecar)
      rep = JSON.parse(File.read(sidecar), symbolize_names: true)
      chords = rep[:progression_chords] if rep[:progression_chords]&.any?
    end
    dilla_quality(path) unless File.file?(sidecar)
  end
  if chords.nil? || chords.empty?
    cfg = dilla_resolve_config
    pads = dilla_progression(cfg[:progression])
    if pads.any?
      pads, = if curated_progression?(cfg)
                DillaHarmony.beautify_curated_pipeline(pads, cfg)
              else
                DillaHarmony.beautify_pipeline(pads, cfg)
              end
      chords = pads
      DillaHarmony.remember_progression(pads)
    end
  end
  abort "no progression — render first: TRACK=maj7_minor_cycle ruby dilla.rb dilla out.wav 8" if chords.nil? || chords.empty?
  breakdown = DillaHarmony.score_breakdown(chords)
  recs = DillaHarmony.recommendations(breakdown)
  symbols = chords.map { |c| c[:name].to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "") }
  analysis = DillaMusicGems.progression_analysis(symbols) if defined?(DillaMusicGems)
  puts "── Harmony beauty ──"
  breakdown.each { |k, v| puts format("%-12s %s", "#{k}:", v) }
  if analysis
    puts "── Coltrane progression (github.com/pedrozath/major_third_cycle_full) ──"
    puts "  #{analysis[:notation]} in #{analysis[:scale]} (#{analysis[:notes_out]} notes outside scale)"
  end
  puts "Recommendations:"
  recs.each { |r| puts "  • #{r}" }
  { breakdown:, recommendations: recs, progression_analysis: analysis }
end

def phone_preview(path = nil)
  path ||= File.join(OUTPUT_DIR, "beat.mp3")
  abort "missing #{path}" unless File.file?(path)
  out = DillaMaster.apply_phone_preview!(path)
  puts "phone preview → #{out}"
  play(out) if tool_available?("ffplay")
  out
end

def semantics(input = nil)
  input ||= prompt("audio path")
  rhythm_data = frame_energy(input, highpass: 60, lowpass: 12_000)
  loudness = rhythm_data.fetch(:frames).map(&:last)
  brightness = frame_energy(input, highpass: 2_400, lowpass: 12_000).fetch(:frames).map(&:last)
  density = peak_frames(rhythm_data.fetch(:frames), rhythm_data.fetch(:hop_seconds)).length.to_f / [rhythm_data.fetch(:duration_seconds), 1.0].max
  puts JSON.pretty_generate(type: "semantics", path: input, duration_seconds: rhythm_data.fetch(:duration_seconds), tags: semantic_tags(loudness, brightness, density))
end

def ears(path = File.join(OUTPUT_DIR, "full_track.mp3"))
  abort "missing #{path}" unless File.exist?(path)
  report = media_metadata(path).merge(volume_metadata(path)).merge(path:)
  report[:verdict] = ears_verdict(report)
  puts JSON.pretty_generate(report)
end

def frame_energy(path, highpass:, lowpass:)
  require_tools! "ffmpeg"
  raw = pipe_floats(path, "highpass=f=#{highpass},lowpass=f=#{lowpass},aformat=sample_fmts=flt:channel_layouts=mono")
  hop = 2_048
  frames = raw.each_slice(hop).with_index.map do |slice, index|
    next if slice.empty?
    [index * hop.to_f / SAMPLE_RATE, Math.sqrt(slice.sum { |value| value * value } / slice.length)]
  end.compact
  { frames:, hop_seconds: hop.to_f / SAMPLE_RATE, duration_seconds: raw.length.to_f / SAMPLE_RATE }
end

BAND_FILTER_PREFIX = "aformat=sample_fmts=flt:channel_layouts=mono"

# One ffmpeg pass, not a Ruby float array.
#
# This used to read the entire decoded stream into memory through pipe_floats:
# for demo.wav (47 minutes, 496 MB) that is a half-gigabyte String and a
# 124-million-element Float array, and mix_metrics called it five times over.
# It timed out MASTER's test_mix_metrics_returns_band_levels_when_demo_present
# and on vm23's 1 GB it would have taken the box with it.
#
# volumedetect computes the same 20·log10(rms) inside ffmpeg. The filter prefix
# is kept byte-identical to the pipe_floats one because the mono downmix gain
# depends on it — measured on a 10s slice, flt+mono reads -24.0 dB where s16
# reads -27.0, and only the former matches what this returned before.
def band_rms(path, highpass:, lowpass:)
  filter = "highpass=f=#{highpass},lowpass=f=#{lowpass},#{BAND_FILTER_PREFIX},volumedetect"
  _output, error, status = capture("ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", filter, "-f", "null", "-")
  return -Float::INFINITY unless status.success?

  level = error[/mean_volume:\s*(-?[\d.]+)/, 1]
  level ? level.to_f : -Float::INFINITY
end

def spectral_windows(path)
  raw = pipe_floats(path, "highpass=f=90,lowpass=f=5000,aformat=sample_fmts=flt:channel_layouts=mono")
  window = 4_096
  windows = raw.each_slice(window).with_index.map do |slice, index|
    next if slice.length < window
    zero_crossings = slice.each_cons(2).count { |left, right| (left.negative? && right.positive?) || (left.positive? && right.negative?) }
    estimated_hz = zero_crossings.to_f * SAMPLE_RATE / (2.0 * slice.length)
    [index * window.to_f / SAMPLE_RATE, estimated_hz.round(2), nearest_note(estimated_hz)]
  end.compact
  { duration_seconds: raw.length.to_f / SAMPLE_RATE, windows: }
end

def pitch_profile(path)
  raw = pipe_floats(path, "highpass=f=65,lowpass=f=5000,aformat=sample_fmts=flt:channel_layouts=mono")
  window = 2_048
  bins = Array.new(12, 0.0)
  raw.each_slice(window) do |slice|
    next if slice.length < window
    estimate = zero_crossing_hz(slice)
    next if estimate < 40.0 || estimate > 5_000.0
    bins[pitch_class_for(estimate)] += slice.sum(&:abs) / slice.length
  end
  total = bins.sum
  normalized = total.positive? ? bins.map { |value| (value / total).round(5) } : bins
  { duration_seconds: raw.length.to_f / SAMPLE_RATE, pitch_classes: PITCH_CLASSES.zip(normalized).to_h }
end

def chord_candidates(pitch_classes)
  values = PITCH_CLASSES.map { |name| pitch_classes.fetch(name, 0.0) }
  candidates = []
  PITCH_CLASSES.each_with_index do |root_name, root_index|
    CHORD_TEMPLATES.each do |suffix, intervals|
      score = intervals.sum { |interval| values[(root_index + interval) % 12] }
      candidates << { chord: "#{root_name}#{suffix}", score: score.round(5) }
    end
  end
  candidates.sort_by { |candidate| -candidate.fetch(:score) }
end

def zero_crossing_hz(slice)
  crossings = slice.each_cons(2).count { |left, right| (left.negative? && right.positive?) || (left.positive? && right.negative?) }
  crossings.to_f * SAMPLE_RATE / (2.0 * slice.length)
end

def pitch_class_for(frequency)
  (69 + (12 * Math.log2(frequency / 440.0))).round % 12
end

def semantic_tags(loudness, brightness, density)
  mean_loudness = average(loudness)
  mean_brightness = average(brightness)
  tags = []
  tags << (density > 2.5 ? "dense" : "spacious")
  tags << (mean_brightness > mean_loudness * 0.45 ? "bright" : "warm")
  tags << (standard_deviation(loudness) > mean_loudness * 0.8 ? "unstable" : "steady")
  tags << (mean_loudness < 0.03 ? "intimate" : "forward")
  tags
end

def pipe_floats(path, filter)
  output, error, status = capture("ffmpeg", "-v", "error", "-i", path, "-af", filter, "-f", "f32le", "-")
  abort error unless status.success?
  output.unpack("e*")
end

def peak_frames(frames, hop_seconds)
  return [] if frames.empty?
  values = frames.map(&:last)
  threshold = average(values) + standard_deviation(values)
  frames.each_cons(3).each_with_object([]) do |(left, middle, right), out|
    next unless middle.last > threshold && middle.last > left.last && middle.last > right.last
    out << { time: middle.first.round(3), strength: middle.last.round(5), grid: (middle.first / hop_seconds).round }
  end
end

def average(values)
  return 0.0 if values.empty?
  values.sum / values.length
end

def standard_deviation(values)
  mean = average(values)
  Math.sqrt(values.sum { |value| (value - mean) * (value - mean) } / [values.length, 1].max)
end

def nearest_note(frequency)
  return if frequency <= 0
  midi = (69 + (12 * Math.log2(frequency / 440.0))).round
  "#{PITCH_CLASSES[midi % 12]}#{(midi / 12) - 1}"
end

def media_metadata(path)
  output, error, status = capture("ffprobe", "-v", "error", "-show_entries", "format=duration,bit_rate", "-of", "json", path)
  abort error unless status.success?
  format = JSON.parse(output).fetch("format", {})
  { duration_seconds: format.fetch("duration", "0").to_f.round(3), bit_rate: format.fetch("bit_rate", "0").to_i }
rescue JSON::ParserError => error
  abort "ffprobe json parse failed: #{error.message}"
end

def volume_metadata(path)
  output, error, status = capture("ffmpeg", "-hide_banner", "-i", path, "-af", "volumedetect", "-f", "null", "-")
  abort error unless status.success?
  text = output + error
  { mean_volume_db: number_after(text, "mean_volume:"), max_volume_db: number_after(text, "max_volume:") }
end

def number_after(text, label)
  line = text.lines.find { |entry| entry.include?(label) }
  line ? line.split(label, 2).last.to_f : nil
end

def ears_verdict(report)
  return "too_short" if report[:duration_seconds] < 20.0
  return "too_quiet" if report[:mean_volume_db] && report[:mean_volume_db] < -28.0
  return "clips" if report[:max_volume_db] && report[:max_volume_db] > -0.2
  "usable"
end

# `dilla knobs` — the environment contract, derived from the engine.
#
#   knobs                one line per knob, grouped by type
#   knobs SAMPLE_LOOP    everything known about one, and where it is read
#   knobs conflicts      knobs whose default differs between files
#   knobs check          what is wrong with the environment right now
#
# Words rather than --flags: the global flag parser consumes anything starting
# with -- before dispatch ever runs, so `knobs --check` aborts with the flag list
# instead of reaching this method.
#
# There are 610 of them and until this existed the only way to learn what one
# did was to grep for it and read the coercion.
def knobs_report(argument = nil)
  case argument
  when nil, ""
    by_type = DillaKnobs.all.values.group_by(&:type)
    PRECEDENCE_ORDER.each do |type|
      found = by_type[type]
      next unless found

      puts "#{type} (#{found.length})"
      found.sort_by(&:name).each do |knob|
        detail = []
        detail << "default #{knob.default}" if knob.default
        detail << "#{knob.range.first}..#{knob.range.last}" if knob.range
        detail << "one of #{knob.accepted.join('|')}" if knob.type == :flag && knob.accepted.any?
        detail << "ENGINE-WRITTEN" if knob.derived?
        puts format("  %-32s %s", knob.name, detail.join(", "))
      end
    end
    puts "#{DillaKnobs.all.length} knobs across #{ENGINE_SOURCES.length} files " \
         "(#{DillaKnobs.inputs.length} you can set, #{DillaKnobs.all.length - DillaKnobs.inputs.length} the engine writes)"
  when "conflicts"
    conflicts = DillaKnobs.conflicts
    conflicts.each do |name, knob|
      puts format("%-24s %s", name, knob.defaults.compact.uniq.inspect)
      puts format("%-24s read in %s", "", knob.read_in.join(", "))
    end
    puts "#{conflicts.length} knob(s) whose default differs between files — whichever site runs first wins"
  when "check"
    problems = DillaKnobs.validate
    problems.each { |problem| puts "NOTE   #{problem}" }
    puts problems.empty? ? "environment ok" : "#{problems.length} note(s)"
  else
    knob = DillaKnobs[argument.upcase]
    return puts("no knob called #{argument} — try `dilla knobs` for the list") unless knob

    puts knob.name
    puts "  type      #{knob.type}#{knob.mixed? ? " (sites disagree: #{knob.types.uniq.join(', ')})" : ''}"
    puts "  default   #{knob.default || '(none in the source)'}"
    puts "  range     #{knob.range ? "#{knob.range.first}..#{knob.range.last} (clamped)" : '(unclamped)'}"
    puts "  accepts   #{knob.accepted.any? ? knob.accepted.join(', ') : '(any value)'}"
    puts "  read in   #{knob.read_in.join(', ')}"
    puts "  written   #{knob.written_in.any? ? knob.written_in.join(', ') : '(never — pure input)'}"
    puts "  NOTE: the engine writes this for itself; it is an output of a render, not an input to one" if knob.derived?
  end
end

PRECEDENCE_ORDER = DillaKnobs::PRECEDENCE

# `dilla where <name>` — which file owns a method, a constant or a knob.
#
# This is what namespacing the engine was wanted for. 79 files define methods on
# Object, so nothing declares ownership and grep is the only way to answer
# "where does this live" -- and grep answers it badly here, because a name is
# mentioned in prose far more often than it is defined, which is the same
# property that makes the wiring ratchets strip comments.
#
# Wrapping the engine in modules would answer it too, and would be a rewrite of
# 116 files whose load order is load-bearing (constants are computed at require
# time from ones above them) for no change in behaviour. This answers the
# question directly instead, from the AST for methods and from the source for
# constants, and it distinguishes a definition from a mention -- which is the
# part that actually helps.
def where_report(name)
  return puts("usage: dilla where <method|CONSTANT|KNOB>") if name.to_s.empty?

  needle = name.to_s
  # Hoisted: interpolating the needle into a literal recompiles the pattern on
  # every one of the ~42k lines below.
  assign_re = /^\s*#{Regexp.escape(needle)}\s*=[^=~]/
  hits = []
  mentions = []
  unreadable = []

  # One read per file feeds all three questions. Reading them once for the AST,
  # again for constants and a third time for mentions was 5.9 MB of I/O to
  # answer a question about 2 MB of source.
  ENGINE_SOURCES.each do |path|
    src = File.read(path)
    base = File.basename(path)
    mentions << base if src.include?(needle)

    src.each_line.with_index(1) do |line, number|
      hits << "constant #{base}:#{number}" if line.match?(assign_re)
    end

    begin
      body = RubyVM::AbstractSyntaxTree.parse(src).children[2]
      nodes = body.type == :BLOCK ? body.children : [body]
      nodes.each do |node|
        hits << "method   #{base}:#{node.first_lineno}" if node.type == :DEFN && node.children[0].to_s == needle
      end
    rescue SyntaxError, StandardError
      # SyntaxError is a ScriptError, not a StandardError — both are needed.
      unreadable << base
    end
  end

  if (knob = DillaKnobs[needle])
    hits << "knob     #{knob.type}#{knob.default ? ", default #{knob.default}" : ''} — read in #{knob.read_in.join(', ')}"
    hits << "         written by #{knob.written_in.join(', ')}" if knob.written_in.any?
  end

  puts hits

  # Mentions, only when nothing defines it. A name that appears in ten comments
  # and no definition is exactly the case this is for.
  if hits.empty?
    if mentions.empty?
      puts "nothing in the engine defines or mentions #{needle}"
    else
      puts "no definition. mentioned in: #{mentions.join(', ')}"
    end
  end

  # A file that would not parse is a file this could not answer for. Saying so
  # matters more here than anywhere: a silent skip turns "not defined" into a
  # confident wrong answer from the tool whose only job is that question.
  puts "could not parse (methods not searched): #{unreadable.join(', ')}" if unreadable.any?
end

# `dilla taste <kept...> vs <rejected...>` — what separates the two piles.
#
# The only honest way I have to tune this engine toward what the operator likes:
# they sort the takes, this measures both groups and reports only the dimensions
# where the groups genuinely separate. It names the knob that moves each one and
# then stops, because a rendered-sound default is theirs to set.
#
# `vs` and not `--`: the global flag parser consumes anything beginning with two
# dashes before dispatch runs, so a bare `--` separator aborts with the flag list.
def taste_report(argv)
  split = argv.index("vs") || argv.index("--")
  unless split
    puts "usage: dilla taste <kept.wav...> vs <rejected.wav...>"
    puts "  measures both piles and reports only where they separate."
    return
  end

  kept = argv[0...split]
  rejected = argv[(split + 1)..] || []
  result = DillaTaste.compare(kept, rejected)
  return puts("taste: #{result[:error]}") if result[:error]

  puts "#{result[:kept]} kept against #{result[:rejected]} rejected"
  strong, weak = result[:findings].partition { |f| f[:separation] >= 1.5 }

  if strong.empty?
    puts "Nothing separates these two piles measurably. That is a real answer: whatever you are"
    puts "hearing is not in the dimensions below, so do not let me tune against them."
  end
  strong.each do |f|
    k = f[:kept]
    r = f[:rejected]
    puts format("\n%s — kept %.2f%s (%.2f–%.2f), rejected %.2f%s (%.2f–%.2f)  [separation %.2f]",
                f[:dimension], k[:mean], f[:units], k[:min], k[:max],
                r[:mean], f[:units], r[:min], r[:max], f[:separation])
    direction = k[:mean] > r[:mean] ? "more" : "less"
    puts "  you keep the takes with #{direction} of it. moves with: #{f[:knob]}"
  end

  return if weak.empty?

  puts "\nno separation (the piles overlap):"
  weak.each { |f| puts format("  %-26s %.2f", f[:dimension], f[:separation]) }
end

# `dilla tracklist <file.dilla>` — what a compilation is made of.
#
# Reads the `assembly` block: each part, where it starts, how long it runs, and
# the recipe it was rendered from, copied in at join time so it survives the part
# being swept. For a plain render it says so rather than inventing a tracklist.
def tracklist_report(manifest_path)
  return puts("usage: dilla tracklist <file.dilla>") if manifest_path.to_s.empty?

  manifest_path = "#{manifest_path}#{DillaProvenance::MANIFEST_EXT}" unless manifest_path.end_with?(DillaProvenance::MANIFEST_EXT)
  return puts("no manifest at #{manifest_path}") unless File.file?(manifest_path)

  doc = JSON.parse(File.read(manifest_path))
  assembly = doc["assembly"]
  unless assembly
    puts "#{File.basename(manifest_path)} describes a single render, not an assembly."
    puts doc["note"]
    return
  end

  puts "#{assembly['parts']} part(s), #{format('%.1f', assembly['seconds'])}s — #{assembly['how']}"
  assembly["from"].each_with_index do |part, index|
    starts = part["starts_at"].to_f
    puts format("%2d. %s  %s  %.1fs", index + 1,
                format("%d:%02d", (starts / 60).to_i, (starts % 60).to_i),
                part["path"], part["seconds"].to_f)
    seed = part.dig("recipe", "render_seed")
    puts format("    seed %s%s", seed, part.dig("recipe", "pinned")&.any? ? "  #{part['recipe']['pinned'].map { |k, v| "#{k}=#{v}" }.join(' ')}" : "") if seed
  end
end

# `dilla assets` — is the crate the recipes name still here and still itself?
#
#   assets           check the recorded fingerprints against disk
#   assets record    write data/assets.json from the crate as it is now
def assets_report(argument = nil)
  if argument == "record"
    payload = DillaAssets.record!
    puts "wrote #{DillaAssets.manifest_path.sub("#{ROOT}/", '')} — #{payload['assets'].length} asset(s)"
    kit = payload["external_kit_cache"]
    puts(kit["present"] ? "external kits: #{kit['kits'].join(', ')} at #{kit['commit']&.slice(0, 12)}" : "external kits: absent")
    return
  end

  result = DillaAssets.verify
  result[:missing].each { |name| puts "MISSING  #{name}" }
  result[:changed].each { |name| puts "CHANGED  #{name}" }
  result[:unrecorded].each { |name| puts "NOTE     #{name} is in the crate and not recorded" }
  puts "#{result[:recorded]} recorded, #{result[:missing].length} missing, #{result[:changed].length} changed"

  kit = DillaAssets.external_kit_identity
  puts(kit["present"] ? "external kits: #{kit['kits'].join(', ')}" : "external kits: absent — renders fall back to the synthesized kit")

  live = DillaAssets.missing_inputs
  live.each { |problem| puts "INPUT    #{problem}" }
  exit(1) unless result[:missing].empty? && result[:changed].empty? && live.empty?
end

def debug
  scan
  puts "music gems: #{DillaMusicGems.status.inspect}" if defined?(DillaMusicGems)
  # Every source, not just the entry script. Checking dilla.rb alone would have
  # reported "ok" for a broken engine ever since the split moved 97% of it into
  # lib/engine/ -- and a syntax check that cannot fail is the worst kind.
  broken = ENGINE_SOURCES.filter_map do |path|
    _output, error, status = capture("ruby", "-c", path)
    error unless status.success?
  end
  puts(broken.empty? ? "ruby syntax: ok (#{ENGINE_SOURCES.length} files)" : broken.join("\n"))
end

def sweep
  output = File.join(OUTPUT_DIR, "sweep_check.mp3")
  previous = ENV["BARS"]
  ENV["BARS"] = "8"
  render(output)
  verify(output)
  ears(output) if tool_available?("ffprobe")
ensure
  previous ? ENV["BARS"] = previous : ENV.delete("BARS")
end

# ------------------------------------------------------------- arrangement
#
# Does a track have sections, and how strongly? Absorbed from arrangement.rb.
#
# It lives here rather than in spectral_audit.rb, which is the other file that
# reads spectrograms, for a reason worth stating: spectral_audit is not required
# by dilla.rb -- only by its own runner script -- so merging there would have
# made a loaded module depend on an unloaded one. This file is the engine's
# inspection surface, holds knobs_report and where_report, and is already in
# ENGINE_PARTS. `dilla arrangement` is the same kind of question as `dilla
# knobs`, asked about audio.
# Does this track have an arrangement, and how strong is it?
#
# The question this exists for is one I could not otherwise answer. dilla's
# section map is real -- the envelopes are in the emitted filtergraph -- and a
# default render still measures 1.4 dB from start to end. Asked how much harder
# the pads should drop, the honest answer was "that is the operator's number",
# and that is true of the FINAL choice and a cop-out as an analysis. There is a
# measurable question underneath it: how much do records move, and how much does
# this one.
#
# Two instruments, because they fail differently.
#
#   LEVEL     short-term loudness over time. Direct, standard, and blind to an
#             arrangement that changes instrumentation without changing level --
#             which is most of Melody A.M. and a good deal of Donuts.
#
#   NOVELTY   self-similarity of the spectrum, convolved with a checkerboard
#             kernel: Foote's method, the standard way to find section
#             boundaries in music information retrieval. It asks whether the
#             sound at minute two RESEMBLES the sound at minute one, which
#             catches a breakdown that stays at the same level, and is not
#             fooled by a track that merely gets louder.
#
# The spectrum comes from ffmpeg's showspectrumpic rather than an FFT written
# here. That is not laziness: spectral_audit.rb already renders spectrograms for
# auditing, WavMap already reads an image as a grid of numbers, and an FFT in
# Ruby over a five-minute file would be the slowest part of this by an order of
# magnitude. One ffmpeg pass produces the whole feature matrix.
#
# WHAT THIS CANNOT DO, stated plainly because the temptation is to forget it:
# none of this says whether a track is good. taste.rb makes the argument at
# length and it holds here -- a measurement is worth something once it is
# anchored to material an ear has already sorted. So `compare` exists, and the
# useful use of this module is measuring a render against records, not against a
# number somebody invented.
module Arrangement
  # A frame is a fixed number of SECONDS, and the column count follows from the
  # file's length. Getting this backwards invalidates every comparison this
  # module exists to make, so it is worth saying exactly how.
  #
  # The first version fixed the column count at 512 and let the duration decide
  # what a frame meant. An 87-second render then measured at 0.17 s per frame and
  # a 290-second record at 0.57 s -- so the render was being asked "does this
  # sixth of a second resemble the last one", which at 88 BPM is roughly one
  # eighth-note, while the record was asked about half-second spans. One reads
  # individual notes as novelty; the other reads phrases.
  #
  # That produced a confident and completely false result: records appeared to
  # have six times less frame-to-frame novelty than dilla, and three separate
  # hypotheses were built and tested against it -- the section map, the grain
  # cloud's randomisation, the Sonitex master chain -- all of which correctly
  # refuted, because there was nothing there to explain. Measured at equal
  # duration, 87 seconds each, the same files read: record 2.92 and 4.77, a
  # dilla release 2.45, a default dilla render 2.73. Indistinguishable.
  #
  # So the frame is half a second and the columns follow. Comparing two files of
  # different lengths still compares different spans of music, which is a real
  # limit -- but it no longer compares different QUESTIONS.
  FRAME_SEC = 0.5
  MIN_COLUMNS = 64
  MAX_COLUMNS = 2048
  BINS = 256

  def self.columns_for(duration)
    (duration.to_f / FRAME_SEC).round.clamp(MIN_COLUMNS, MAX_COLUMNS)
  end

  # Half-width of the checkerboard kernel, in frames. Foote's kernel compares the
  # block before a point with the block after it; this is how much "before" and
  # "after" mean. At a half-second frame, 24 frames is twelve seconds either side
  # -- four to eight bars at the tempos here, which is the unit an arrangement
  # actually turns on. A narrow kernel finds bar lines; a wide one finds movements.
  #
  # In frames rather than seconds only because the convolution counts in frames;
  # with FRAME_SEC fixed the two are the same statement.
  KERNEL = 24

  module_function

  # The spectrogram as columns of normalised band energy.
  #
  # Each column is L2-normalised, which is what makes the similarity below a
  # comparison of SPECTRAL SHAPE rather than of level. Without it a loud section
  # resembles every other loud section and the novelty curve becomes a worse
  # copy of the loudness curve -- two instruments measuring one thing.
  def features(path, columns: nil)
    return nil unless path && File.file?(path)

    columns ||= columns_for(duration_of(path))
    png = File.join(Dir.tmpdir, "arrangement_#{Process.pid}.png")
    ok = system("ffmpeg", "-v", "error", "-y", "-i", path,
                "-lavfi", "showspectrumpic=s=#{columns}x#{BINS}:mode=combined:scale=log:legend=0",
                "-frames:v", "1", png, out: File::NULL, err: File::NULL)
    return nil unless ok && File.file?(png)

    raw = IO.popen(["ffmpeg", "-v", "error", "-i", png, "-vf", "format=gray",
                    "-frames:v", "1", "-f", "rawvideo", "-"], "rb", err: File::NULL, &:read)
    File.unlink(png)
    return nil if raw.nil? || raw.bytesize < columns * BINS

    bytes = raw.unpack("C*")
    (0...columns).map do |x|
      col = (0...BINS).map { |y| bytes[(y * columns) + x].to_f }
      norm = Math.sqrt(col.sum { |v| v * v })
      norm.zero? ? col : col.map { |v| v / norm }
    end
  end

  def duration_of(path)
    `ffprobe -v error -show_entries format=duration -of csv=p=0 "#{path}"`.to_f
  end

  def cosine(a, b)
    sum = 0.0
    a.each_index { |i| sum += a[i] * b[i] }
    sum
  end

  # Foote novelty.
  #
  # At each point, compare the two blocks either side of it with the two blocks
  # ACROSS it. A boundary is where before-resembles-before, after-resembles-after,
  # and before does not resemble after. That is exactly a checkerboard: positive
  # on the two diagonal quadrants, negative on the two off-diagonal ones.
  #
  # Only the band near the diagonal is computed. The full matrix is 512x512 and
  # the kernel never looks further than KERNEL frames away, so the other 96% of
  # it would be built and discarded.
  def novelty(features, kernel: KERNEL)
    n = features.length
    curve = Array.new(n, 0.0)
    (kernel...(n - kernel)).each do |c|
      same = 0.0
      cross = 0.0
      (1..kernel).each do |i|
        (1..kernel).each do |j|
          # Gaussian taper. An untapered kernel rings -- every boundary grows
          # two smaller shoulders at +-kernel, and the peak picker then reports
          # three sections where there is one.
          w = Math.exp(-((i * i) + (j * j)) / (2.0 * (kernel / 2.0)**2))
          same += w * cosine(features[c - i], features[c - j])
          same += w * cosine(features[c + i - 1], features[c + j - 1])
          cross += 2.0 * w * cosine(features[c - i], features[c + j - 1])
        end
      end
      curve[c] = (same - cross) / (2.0 * kernel * kernel)
    end
    curve
  end

  # Peaks worth calling boundaries.
  #
  # A threshold relative to the curve's own spread rather than an absolute one:
  # novelty scales with how different a record's sections are from each other,
  # and a fixed cut would report every section of a varied record and none of a
  # subtle one. The minimum gap stops one boundary being counted three times.
# The noise floor of this instrument, measured rather than assumed.
#
# A relative threshold alone reports sections in material that has none: one
# bar looped fifteen times, which by construction has no boundary anywhere,
# came back with four -- because mean-plus-1.5-sigma always finds something,
# and in a flat curve what it finds is noise.
#
# So null cases were built and measured, at the half-second frame this module
# now uses everywhere:
#
#   one bar looped x15   peak 0.00137     no boundary exists
#   white noise          peak 0.00003     no boundary exists
#   pure tone            peak 0.00007     no boundary exists
#   a hard splice        peak 0.02021     one boundary, at a known second
#
# Fifteen times the loudest null. 0.005 is the midpoint on a log scale between
# the two populations, which is the honest place for a threshold separating
# them. It is a floor, not a calibration: a record whose sections differ only
# slightly falls under it and reports as one section, and that is the correct
# failure -- this says "I cannot see a boundary", not "there is none".
#
# The earlier value was 0.015, derived the same way from the same two files
# measured with a FIXED COLUMN COUNT rather than a fixed frame duration. That
# instrument separated the two populations by only 4.25x; this one separates
# them by 15x, on the same audio.
NOISE_FLOOR = 0.005

  def boundaries(curve, seconds_per_frame:, min_gap_sec: 8.0, sensitivity: 1.5, floor: NOISE_FLOOR)
    live = curve.reject(&:zero?)
    return [] if live.length < 8

    mean = live.sum / live.length
    sd = Math.sqrt(live.sum { |v| (v - mean)**2 } / live.length)
    cut = [mean + (sensitivity * sd), floor].max
    gap = (min_gap_sec / seconds_per_frame).round
    found = []
    curve.each_index do |i|
      next if curve[i] < cut
      next unless curve[i] == curve[[i - gap, 0].max..[i + gap, curve.length - 1].min].max
      next if found.any? && (i - found.last) < gap

      found << i
    end
    found
  end

  # Short-term loudness over time, from ffmpeg's own R128 meter.
  #
  # ebur128 prints a running M (momentary, 400 ms) and S (short-term, 3 s) to
  # stderr. S is the one that matters here: 400 ms tracks individual kicks and
  # would report a busy loop as dynamic, while 3 s is about a bar and tracks
  # what a section does.
  def loudness_envelope(path)
    out = IO.popen(["ffmpeg", "-hide_banner", "-nostats", "-i", path,
                    "-af", "ebur128=peak=none", "-f", "null", "-"],
                   err: %i[child out], &:read)
    out.scan(/t:\s*([\d.]+)\s+.*?S:\s*(-?[\d.inf]+)/).filter_map do |t, s|
      value = s.to_f
      # -inf and the first three seconds, where the 3 s window is not yet full.
      next if s.include?("inf") || value < -70.0 || t.to_f < 3.0

      [t.to_f, value]
    end
  end

  # Percentile spread of the short-term loudness, which is what "how much does
  # this move" means numerically.
  #
  # p10 to p90 rather than min to max: one clipped transient or one gap between
  # tracks would otherwise define the whole answer. This is the same reasoning
  # R128's own LRA uses, and the number is comparable to LRA without being it --
  # LRA gates at -20 LU relative and this does not, so a track with long quiet
  # passages reads wider here and that is the intent.
  def spread(envelope)
    return nil if envelope.length < 10

    values = envelope.map(&:last).sort
    p = ->(q) { values[(q * (values.length - 1)).round] }
    { p10: p.call(0.10), p50: p.call(0.50), p90: p.call(0.90),
      spread: (p.call(0.90) - p.call(0.10)).round(2) }
  end

  # Everything about one file.
  def analyse(path)
    duration = duration_of(path)
    return nil unless duration.positive?

    columns = columns_for(duration)
    feats = features(path, columns:) or return nil

    spf = duration / columns
    curve = novelty(feats)
    marks = boundaries(curve, seconds_per_frame: spf)
    env = loudness_envelope(path)
    live = curve.reject(&:zero?)
    {
      path:, duration:,
      seconds_per_frame: spf,
      boundaries: marks.map { |i| (i * spf).round(1) },
      sections: marks.length + 1,
      mean_section_sec: marks.empty? ? duration : (duration / (marks.length + 1)),
      novelty_peak: live.empty? ? 0.0 : live.max.round(4),
      novelty_mean: live.empty? ? 0.0 : (live.sum / live.length).round(4),
      # How far the strongest boundary stands above the ordinary run of the
      # curve. A record with real sections has a few tall peaks; a loop has a
      # curve that is all shoulder and no peak, whatever its absolute height.
      novelty_contrast: live.empty? || live.max.zero? ? 0.0 : (live.max / (live.sum / live.length)).round(2),
      loudness: spread(env),
    }
  end

  # One line per file, so a render and a record can be read side by side. This
  # is the point of the module: the target is what records do, not a number.
  def compare(paths)
    rows = paths.filter_map { |p| analyse(p) }
    header = format("%-34s %7s %7s %8s %9s %9s", "file", "mins", "sects", "mean s", "contrast", "LU p10-90")
    table = [header, "-" * header.length] + rows.map do |r|
      format("%-34s %7.1f %7d %8.1f %9.2f %9s",
             File.basename(r[:path])[0, 34], r[:duration] / 60.0, r[:sections],
             r[:mean_section_sec], r[:novelty_contrast],
             r[:loudness] ? r[:loudness][:spread] : "-")
    end
    table + duration_warning(rows)
  end

  # Say so when the files being compared are not the same length.
  #
  # The frame is a fixed duration now, so two files are at least asked the same
  # question -- but they are still asked it about different amounts of music, and
  # that alone moves the answer a long way. The same record measured over 87,
  # 145, 220 and 289 seconds reads contrast 4.28, 3.94, 3.68 and 12.18: flat
  # until the window happens to include its one real boundary at 276 s, then
  # triple. Comparing a 1.4-minute render against a 4.8-minute record is
  # therefore mostly comparing 1.4 minutes against 4.8 minutes.
  #
  # This warns rather than refusing, because the comparison is still worth
  # having -- it is not the comparison it looks like, and the reading here
  # went wrong in exactly that way before anyone excerpted the record.
  def duration_warning(rows)
    return [] if rows.length < 2

    longest = rows.map { |r| r[:duration] }.max
    shortest = rows.map { |r| r[:duration] }.min
    return [] if shortest.zero? || (longest / shortest) < 1.5

    ["",
     format("NOTE  these differ in length by %.1fx (%.1f min against %.1f min).",
            longest / shortest, longest / 60.0, shortest / 60.0),
     "      Contrast is roughly flat with duration until the window includes a real",
     "      boundary, and then it jumps. Excerpt them to the same length before",
     "      reading anything into the difference."]
  end
end
