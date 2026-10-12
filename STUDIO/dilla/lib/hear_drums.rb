# frozen_string_literal: true

# hear_drums: one pipeline from a source to a hashed drum dossier.
#
#   validate -> ingest -> separate -> analyze -> hints -> write
#
# Every stage fails closed. A missing executable, a nonzero exit, a timeout, an
# absent or empty stem, a malformed measurement and a failed dossier write each
# return status "failed" with the stage and the reason; nothing here returns a
# success-shaped "could not hear". The analysis itself is the engine's own
# (drum_step_grid_from_wav, injected as the analyzer by dilla.rb), and the
# hints are suggestions for the existing groove engine -- they never write a
# preset. The contract is MASTER/docs/hear_drums_skill_contract.md.
#
# Three seams are injectable so tests need no network, model or audio tool:
# the runner (executes an argv), the resolver (finds an executable) and the
# analyzer (measures the drums stem).

require "digest"
require "fileutils"
require "json"
require "open3"
require "time"
require "tmpdir"

module HearDrums
  SCHEMA_VERSION = 1
  STAGES = %w[validate ingest separate analyze hints write].freeze
  DEFAULT_SECONDS = 60
  HARD_MAX_SECONDS = 600
  MAX_TAGS = 16
  MAX_TAG_LENGTH = 40
  MAX_ARTIST_LENGTH = 120
  MODEL = "htdemucs"
  DEFAULT_ROOT = File.expand_path("../project/learnings/hear_drums", __dir__).freeze
  TIMEOUTS = { probe: 20, ingest: 300, trim: 120, separate: 900 }.freeze
  BPM_RANGE = (30.0..300.0)
  GRID_STEPS = 16
  # The engine clamps SWING to this range when it applies a measured value, so
  # a hint outside it would be a hint the engine never accepts.
  SWING_HINT_RANGE = (52..62)
  SWING_BY_LABEL = { "laid_back" => 60, "pushed" => 53, "straight" => 52 }.freeze

  class StageFailure < StandardError
    attr_reader :stage, :kind

    def initialize(stage, kind, reason)
      @stage = stage
      @kind = kind
      super(reason)
    end
  end

  Run = Struct.new(:output, :status, :timed_out, keyword_init: true)

  # The real runner: argv only, never a shell, killed on timeout.
  module Runner
    module_function

    def call(argv, timeout:)
      output = +""
      status = nil
      timed_out = false
      Open3.popen2e(*argv) do |stdin, io, wait|
        stdin.close
        reader = Thread.new { output = io.read.to_s }
        unless wait.join(timeout)
          timed_out = true
          kill(wait.pid, "TERM")
          kill(wait.pid, "KILL") unless wait.join(5)
          wait.join
        end
        reader.join
        status = wait.value.exitstatus
      end
      Run.new(output:, status:, timed_out:)
    rescue SystemCallError => e
      Run.new(output: e.message, status: nil, timed_out: false)
    end

    def kill(pid, signal)
      Process.kill(signal, pid)
    rescue Errno::ESRCH
      nil
    end
  end

  module Resolver
    module_function

    def call(name)
      return name if name.include?(File::SEPARATOR) && File.executable?(name)

      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
        candidate = File.join(dir, name)
        return candidate if File.file?(candidate) && File.executable?(candidate)
      end
      nil
    end
  end

  module_function

  def normalize_tags(tags)
    raise StageFailure.new("validate", "invalid_input", "style_tags must be an array") unless tags.is_a?(Array)

    list = tags.map do |tag|
      raise StageFailure.new("validate", "invalid_input", "style tag must be a string") unless tag.is_a?(String)

      tag.strip.downcase.gsub(/\s+/, "-").gsub(/[^a-z0-9_-]/, "")
    end
    list = list.reject(&:empty?).uniq
    if list.length > MAX_TAGS || list.any? { |t| t.length > MAX_TAG_LENGTH }
      raise StageFailure.new("validate", "invalid_input", "style_tags exceed #{MAX_TAGS} tags of #{MAX_TAG_LENGTH} characters")
    end

    list
  end

  def normalize_artist(artist)
    return nil if artist.nil?
    raise StageFailure.new("validate", "invalid_input", "artist must be a string") unless artist.is_a?(String)

    name = artist.strip
    return nil if name.empty?
    raise StageFailure.new("validate", "invalid_input", "artist longer than #{MAX_ARTIST_LENGTH}") if name.length > MAX_ARTIST_LENGTH

    name
  end

  # Everything that can be checked without spawning anything.
  def validate_request(source:, artist:, style_tags:, max_seconds:)
    unless source.is_a?(String) && !source.strip.empty? && !source.include?("\0")
      raise StageFailure.new("validate", "invalid_input", "source must be a non-empty string")
    end
    unless max_seconds.is_a?(Integer) && max_seconds.between?(1, HARD_MAX_SECONDS)
      raise StageFailure.new("validate", "invalid_input", "max_seconds must be an integer from 1 to #{HARD_MAX_SECONDS}")
    end

    ref = source.strip
    if ref.match?(%r{\Ahttps?://}i)
      kind = "url"
    elsif ref.match?(%r{\A[a-z][a-z0-9+.-]*://}i)
      raise StageFailure.new("validate", "invalid_input", "only http(s) URLs and local files are accepted")
    else
      kind = "file"
      ref = File.expand_path(ref)
      raise StageFailure.new("validate", "invalid_input", "source file not found: #{ref}") unless File.file?(ref)
      raise StageFailure.new("validate", "empty_output", "source file is empty: #{ref}") if File.zero?(ref)
    end
    { kind:, ref:, artist: normalize_artist(artist), style_tags: normalize_tags(style_tags), max_seconds: }
  end

  def sha256(path)
    Digest::SHA256.file(path).hexdigest
  end

  def non_empty!(path, stage, what)
    return if path && File.file?(path) && File.size(path).positive?

    raise StageFailure.new(stage, "empty_output", "#{what} is missing or empty")
  end

  def execute(runner, argv, timeout:, stage:, what:)
    run = runner.call(argv, timeout:)
    raise StageFailure.new(stage, "timeout", "#{what} timed out after #{timeout}s") if run.timed_out
    return run if run.status&.zero?

    tail = run.output.to_s.lines.last.to_s.strip
    raise StageFailure.new(stage, "tool_failed", "#{what} exited #{run.status.inspect}#{tail.empty? ? "" : ": #{tail}"}")
  end

  # Identity of each tool: path and the version it reports, or an explicit
  # unavailable state. Never a guessed version.
  def probe_tools(runner:, resolver:, commands:)
    commands.to_h do |name, prefix|
      exe = resolver.call(prefix.first)
      next [name.to_s, { "available" => false, "path" => nil, "version" => nil }] unless exe

      entry = { "available" => true, "path" => exe, "version" => nil }
      flag = { ytdlp: ["--version"], ffmpeg: ["-version"] }[name]
      if flag
        run = runner.call([exe, *prefix.drop(1), *flag], timeout: TIMEOUTS[:probe])
        if run.status&.zero? && !run.timed_out
          entry["version"] = run.output.to_s.lines.first.to_s.strip[0, 120]
          entry["version"] = nil if entry["version"].empty?
        else
          entry["available"] = false
        end
      end
      [name.to_s, entry]
    end
  end

  def require_tool!(tools, name, stage)
    return if tools.dig(name, "available")

    raise StageFailure.new(stage, "tool_unavailable", "#{name} is unavailable")
  end

  def ingest(request, tools:, runner:, work:)
    require_tool!(tools, "ffmpeg", "ingest")
    require_tool!(tools, "ytdlp", "ingest") if request[:kind] == "url"
    require_tool!(tools, "demucs", "separate")
    if request[:kind] == "url"
      template = File.join(work, "source.%(ext)s")
      sections = "*0-#{request[:max_seconds]}"
      execute(runner, [tools["ytdlp"]["path"], "--no-playlist", "-x", "--audio-format", "wav",
                       "--download-sections", sections, "-o", template, "--", request[:ref]],
              timeout: TIMEOUTS[:ingest], stage: "ingest", what: "yt-dlp")
      source = Dir.glob(File.join(work, "source.*")).min
    else
      source = request[:ref]
    end
    non_empty!(source, "ingest", "ingested source")
    clip = File.join(work, "clip.wav")
    execute(runner, [tools["ffmpeg"]["path"], "-y", "-v", "error", "-t", request[:max_seconds].to_s,
                     "-i", source, "-ac", "2", "-ar", "44100", clip],
            timeout: TIMEOUTS[:trim], stage: "ingest", what: "ffmpeg trim")
    non_empty!(clip, "ingest", "analysis clip")
    [source, clip]
  end

  def separate(clip, tools:, runner:, demucs_argv:, work:)
    out = File.join(work, "stems")
    execute(runner, [*demucs_argv, "--two-stems=drums", "-n", MODEL, "-o", out, clip],
            timeout: TIMEOUTS[:separate], stage: "separate", what: "demucs")
    drums = File.join(out, MODEL, File.basename(clip, ".*"), "drums.wav")
    non_empty!(drums, "separate", "drums stem")
    drums
  end

  def integer_steps?(list)
    list.is_a?(Array) && list.all? { |s| s.is_a?(Integer) && s.between?(0, GRID_STEPS - 1) }
  end

  # The measurement must be complete and plausible, or it is not a measurement.
  def drum_pattern(measured)
    unless measured.is_a?(Hash) && !measured.key?(:error) && !measured.key?("error")
      reason = measured.is_a?(Hash) ? (measured[:error] || measured["error"]) : measured.class
      raise StageFailure.new("analyze", "malformed_measurement", "analyzer reported #{reason}")
    end

    m = measured.transform_keys(&:to_sym)
    bpm = m[:bpm_estimate]
    unless bpm.is_a?(Numeric) && BPM_RANGE.cover?(bpm.to_f)
      raise StageFailure.new("analyze", "malformed_measurement", "bpm missing or outside #{BPM_RANGE}")
    end

    grid = (m[:step_grid] || {}).transform_keys(&:to_sym)
    roles = %i[kicks snares hats]
    unless roles.all? { |role| integer_steps?(grid[role]) }
      raise StageFailure.new("analyze", "malformed_measurement", "step_grid roles must be steps 0..#{GRID_STEPS - 1}")
    end
    density = m[:drum_density]
    unless density.is_a?(Hash) && !density.empty? && density.values.all? { |v| v.is_a?(Numeric) }
      raise StageFailure.new("analyze", "malformed_measurement", "drum_density missing or non-numeric")
    end

    {
      "bpm" => bpm.to_f.round(1),
      "swing_hint" => m[:swing_hint].nil? ? nil : m[:swing_hint].to_s,
      "step_grid" => roles.to_h { |role| [role.to_s, grid[role].sort] }.merge("bar_steps" => GRID_STEPS),
      "density" => density.transform_keys(&:to_s).sort.to_h,
      "residuals" => m[:residuals]
    }
  end

  # Bounded, explained suggestions. Nothing here is applied: the operator or a
  # caller decides, and a preset is only ever changed by that decision.
  def engine_hints(pattern)
    swing = SWING_BY_LABEL[pattern["swing_hint"]]
    hints = {
      "applied" => false,
      "bpm" => pattern["bpm"].round.clamp(40, 220),
      "swing" => swing&.clamp(SWING_HINT_RANGE.min, SWING_HINT_RANGE.max),
      "step_grid" => pattern["step_grid"].slice("kicks", "snares", "hats"),
      "rationale" => ["bpm is the analyzer's estimate rounded and clamped to 40..220"]
    }
    hints["rationale"] << if swing
                            "swing #{swing} follows the measured #{pattern["swing_hint"]} label, within the engine's #{SWING_HINT_RANGE} clamp"
                          else
                            "no swing hint: the analyzer reported none"
                          end
    hints
  end

  # A new file per version, never an overwrite: the link fails if the name
  # exists, so a concurrent writer cannot replace earlier evidence.
  def write_dossier(dossier, root:)
    dir = File.join(root, dossier["source_hash"])
    FileUtils.mkdir_p(dir)
    tmp = File.join(dir, ".tmp-#{Process.pid}-#{Digest::SHA256.hexdigest(dossier.to_json)[0, 8]}")
    File.write(tmp, JSON.pretty_generate(dossier) << "\n")
    version = Dir.children(dir).grep(/\Av\d{4}\.json\z/).length
    loop do
      version += 1
      path = File.join(dir, format("v%04d.json", version))
      begin
        File.link(tmp, path)
        return path
      rescue Errno::EEXIST
        next
      end
    end
  rescue SystemCallError => e
    raise StageFailure.new("write", "write_failed", "dossier write failed: #{e.message}")
  ensure
    FileUtils.rm_f(tmp) if tmp
  end

  def stage_failure(error, request:, tools:, completed:, source_hash:)
    {
      "status" => "failed", "stage" => error.stage, "kind" => error.kind, "reason" => error.message,
      "diagnostics" => {
        "completed_stages" => completed, "tools" => tools, "source_hash" => source_hash,
        "artist" => request&.fetch(:artist, nil), "style_tags" => request&.fetch(:style_tags, nil)
      }
    }
  end

  def hear_drums(source:, artist: nil, style_tags: [], max_seconds: DEFAULT_SECONDS,
                 analyzer:, demucs_argv: ["demucs"], root: DEFAULT_ROOT,
                 runner: Runner, resolver: Resolver, clock: -> { Time.now.utc })
    completed = []
    tools = nil
    request = nil
    source_hash = nil
    request = validate_request(source:, artist:, style_tags:, max_seconds:)
    completed << "validate"
    commands = { ytdlp: ["yt-dlp"], demucs: demucs_argv, ffmpeg: ["ffmpeg"] }
    tools = probe_tools(runner:, resolver:, commands:)
    Dir.mktmpdir("hear-drums") do |work|
      source_path, clip = ingest(request, tools:, runner:, work:)
      source_hash = sha256(source_path)
      clip_hash = sha256(clip)
      completed << "ingest"
      drums = separate(clip, tools:, runner:, demucs_argv: [tools["demucs"]["path"], *demucs_argv.drop(1)], work:)
      stem_hashes = { "drums.wav" => sha256(drums) }
      completed << "separate"
      pattern = begin
        drum_pattern(analyzer.call(drums))
      rescue StageFailure
        raise
      rescue StandardError => e
        raise StageFailure.new("analyze", "tool_failed", "analyzer raised #{e.class}: #{e.message}")
      end
      completed << "analyze"
      hints = engine_hints(pattern)
      completed << "hints"
      dossier = {
        "schema_version" => SCHEMA_VERSION,
        "source_hash" => source_hash,
        "source" => { "kind" => request[:kind], "ref" => request[:kind] == "url" ? request[:ref] : File.basename(request[:ref]) },
        "analysis_window" => { "start_seconds" => 0, "max_seconds" => request[:max_seconds], "clip_hash" => clip_hash },
        "stem_hashes" => stem_hashes,
        "tools" => tools.transform_values { |t| t.slice("available", "path", "version") }.sort.to_h,
        "model" => MODEL,
        "drum_pattern" => pattern,
        "engine_hints" => hints,
        "style_tags" => request[:style_tags],
        "artist" => request[:artist],
        "recorded_at" => clock.call.iso8601
      }
      path = write_dossier(dossier, root:)
      { "status" => "ok", "stage" => "write", "dossier_path" => path, "dossier" => dossier }
    end
  rescue StageFailure => e
    stage_failure(e, request:, tools:, completed:, source_hash:)
  end

  # Per-source records, filtered by label. A profile is selected by artist or
  # style tag; records are never merged into one anonymous average.
  def learned_records(root: DEFAULT_ROOT, artist: nil, style_tag: nil)
    Dir.glob(File.join(root, "*", "v*.json")).sort.filter_map do |path|
      record = JSON.parse(File.read(path))
      next if artist && record["artist"] != artist
      next if style_tag && !record["style_tags"].to_a.include?(style_tag)

      record.merge("path" => path)
    rescue JSON::ParserError
      nil
    end
  end

  # ruby dilla.rb hear-drums <source> [--artist NAME] [--style a,b] [--max-seconds N] [--root DIR]
  # One JSON object on the last stdout line; exit 0 only for status "ok".
  def cli(argv, analyzer:, demucs_argv: ["demucs"], out: $stdout, **injected)
    args = argv.dup
    opts = { artist: nil, style_tags: [], max_seconds: DEFAULT_SECONDS, root: DEFAULT_ROOT }
    positional = []
    until args.empty?
      arg = args.shift
      case arg
      when "--artist" then opts[:artist] = args.shift
      when "--style" then opts[:style_tags] = args.shift.to_s.split(",")
      when "--max-seconds" then opts[:max_seconds] = Integer(args.shift.to_s, exception: false)
      when "--root" then opts[:root] = File.expand_path(args.shift.to_s)
      else positional << arg
      end
    end
    result = hear_drums(source: positional.first, **opts, analyzer:, demucs_argv:, **injected)
    out.puts JSON.generate(result)
    result["status"] == "ok" ? 0 : 1
  end
end
