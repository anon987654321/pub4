# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "stringio"
require "digest"
require_relative "../dilla/lib/hear_drums"

# Every external tool is a fake: the runner writes the files the real tool
# would, the resolver says which executables exist, the analyzer returns a
# canned measurement. Nothing touches the network, a model or real audio.
class TestDillaHearDrums < Minitest::Test
  GOOD = {
    bpm_estimate: 88.04,
    swing_hint: "laid_back",
    drum_density: { kick_transients_per_min: 80.0, snare_transients_per_min: 60.0 },
    step_grid: { kicks: [12, 0, 8], snares: [4, 12], hats: [2, 6], bar_steps: 16 }
  }.freeze

  class FakeRig
    attr_reader :calls
    attr_accessor :present, :fail_on, :stem, :write_clip, :timeout_on

    def initialize
      @calls = []
      @present = %w[yt-dlp ffmpeg demucs]
      @fail_on = nil
      @stem = "DRUMS"
      @write_clip = true
      @timeout_on = nil
    end

    def resolver = ->(name) { present.include?(name) ? "/fake/#{name}" : nil }

    def runner
      lambda do |argv, timeout:|
        calls << argv
        tool = File.basename(argv.first)
        return HearDrums::Run.new(output: "late", status: nil, timed_out: true) if timeout_on == tool && !probe?(argv)
        return HearDrums::Run.new(output: "boom", status: 3, timed_out: false) if fail_on == tool && !probe?(argv)

        HearDrums::Run.new(output: simulate(tool, argv), status: 0, timed_out: false)
      end
    end

    def probe?(argv) = %w[--version -version].include?(argv[1])

    def simulate(tool, argv)
      case tool
      when "yt-dlp"
        return "2025.01.01\n" if probe?(argv)

        File.write(argv[argv.index("-o") + 1].sub("%(ext)s", "wav"), "DOWNLOADED")
        ""
      when "ffmpeg"
        return "ffmpeg version 7.0 Copyright\nmore\n" if probe?(argv)

        File.write(argv.last, "CLIP") if write_clip
        ""
      else
        out = argv[argv.index("-o") + 1]
        clip = argv.last
        dir = File.join(out, HearDrums::MODEL, File.basename(clip, ".*"))
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, "drums.wav"), stem) unless stem.nil?
        ""
      end
    end
  end

  def setup
    @rig = FakeRig.new
    @root = Dir.mktmpdir("hear-drums-root")
    @src_dir = Dir.mktmpdir("hear-drums-src")
    @src = File.join(@src_dir, "break.wav")
    File.binwrite(@src, "exact source bytes\x00\x01")
  end

  def teardown
    FileUtils.rm_rf([@root, @src_dir])
  end

  def run_pipeline(source: @src, analyzer: ->(_) { GOOD }, **opts)
    HearDrums.hear_drums(source:, analyzer:, root: @root, runner: @rig.runner, resolver: @rig.resolver,
                         demucs_argv: ["demucs"], clock: -> { Time.utc(2026, 10, 12) }, **opts)
  end

  def assert_failed(result, stage, kind)
    assert_equal "failed", result["status"]
    assert_equal stage, result["stage"]
    assert_equal kind, result["kind"]
    refute result.key?("dossier")
    assert_empty Dir.glob(File.join(@root, "*", "v*.json")), "a failed run must leave no dossier"
  end

  def test_success_writes_a_complete_hashed_dossier
    result = run_pipeline(artist: "J Dilla", style_tags: ["Boom Bap", "Soul"])
    assert_equal "ok", result["status"]
    d = result["dossier"]
    assert_equal Digest::SHA256.hexdigest("exact source bytes\x00\x01".b), d["source_hash"]
    assert_equal({ "drums.wav" => Digest::SHA256.hexdigest("DRUMS") }, d["stem_hashes"])
    assert_equal Digest::SHA256.hexdigest("CLIP"), d["analysis_window"]["clip_hash"]
    assert_equal %w[ffmpeg ytdlp demucs].sort, d["tools"].keys.sort
    assert_equal "ffmpeg version 7.0 Copyright", d["tools"]["ffmpeg"]["version"]
    assert_nil d["tools"]["demucs"]["version"], "a version the tool did not report must stay unknown"
    assert_equal 88.0, d["drum_pattern"]["bpm"]
    assert_equal [0, 8, 12], d["drum_pattern"]["step_grid"]["kicks"]
    assert_nil d["drum_pattern"]["residuals"]
    assert_equal false, d["engine_hints"]["applied"]
    assert_equal JSON.parse(File.read(result["dossier_path"])), d
  end

  def test_schema_is_deterministic
    first = run_pipeline["dossier"]
    second = run_pipeline["dossier"]
    assert_equal first, second
    assert_equal first.keys, second.keys
    assert_equal %w[schema_version source_hash source analysis_window stem_hashes tools model drum_pattern
                    engine_hints style_tags artist recorded_at], first.keys
  end

  def test_prior_evidence_is_never_overwritten
    first = run_pipeline
    second = run_pipeline
    assert_match(/v0001\.json\z/, first["dossier_path"])
    assert_match(/v0002\.json\z/, second["dossier_path"])
    assert File.file?(first["dossier_path"])
    assert_empty Dir.glob(File.join(@root, "*", ".tmp-*"))
  end

  def test_style_tags_are_normalized_and_artist_stays_separate
    d = run_pipeline(artist: "  Slum Village ", style_tags: ["Boom Bap", " boom bap ", "Lo-Fi!", ""])["dossier"]
    assert_equal %w[boom-bap lo-fi], d["style_tags"]
    assert_equal "Slum Village", d["artist"]
    refute_includes d["style_tags"], "slum-village"
  end

  def test_duration_is_bounded_before_anything_runs
    [0, -5, HearDrums::HARD_MAX_SECONDS + 1, "60", nil, 1.5].each do |bad|
      result = run_pipeline(max_seconds: bad)
      assert_failed result, "validate", "invalid_input"
    end
    assert_empty @rig.calls, "validation failures must not spawn anything"
  end

  def test_max_seconds_reaches_ffmpeg_as_the_clip_limit
    run_pipeline(max_seconds: 7)
    trim = @rig.calls.find { |c| File.basename(c.first) == "ffmpeg" && c.include?("-t") }
    assert_equal "7", trim[trim.index("-t") + 1]
  end

  def test_bad_sources_fail_validation_without_spawning
    ["", "   ", nil, 42, File.join(@src_dir, "missing.wav"), "ftp://example.com/x.wav", @src_dir].each do |bad|
      assert_failed run_pipeline(source: bad), "validate", "invalid_input"
    end
    empty = File.join(@src_dir, "empty.wav")
    File.write(empty, "")
    assert_failed run_pipeline(source: empty), "validate", "empty_output"
    assert_empty @rig.calls
  end

  def test_bad_tags_and_artist_fail_validation
    assert_failed run_pipeline(style_tags: "soul"), "validate", "invalid_input"
    assert_failed run_pipeline(style_tags: [1]), "validate", "invalid_input"
    assert_failed run_pipeline(style_tags: Array.new(17) { |i| "t#{i}" }), "validate", "invalid_input"
    assert_failed run_pipeline(artist: 5), "validate", "invalid_input"
  end

  def test_url_source_uses_ytdlp_with_argv_and_no_shell
    result = run_pipeline(source: "https://example.com/watch?v=a b;rm -rf")
    assert_equal "ok", result["status"]
    call = @rig.calls.find { |c| File.basename(c.first) == "yt-dlp" && c.include?("--no-playlist") }
    assert_equal "--", call[-2]
    assert_equal "https://example.com/watch?v=a b;rm -rf", call.last
    assert_equal Digest::SHA256.hexdigest("DOWNLOADED"), result["dossier"]["source_hash"]
    assert_equal "url", result["dossier"]["source"]["kind"]
  end

  def test_missing_ffmpeg_fails_closed
    @rig.present = %w[yt-dlp demucs]
    assert_failed run_pipeline, "ingest", "tool_unavailable"
  end

  def test_missing_demucs_fails_closed_before_any_work
    @rig.present = %w[yt-dlp ffmpeg]
    result = run_pipeline
    assert_failed result, "separate", "tool_unavailable"
    refute(@rig.calls.any? { |c| c.include?("-y") }, "no clip is cut when demucs is absent")
    assert_equal false, result["diagnostics"]["tools"]["demucs"]["available"]
  end

  def test_missing_ytdlp_fails_only_for_url_sources
    @rig.present = %w[ffmpeg demucs]
    assert_failed run_pipeline(source: "https://example.com/a"), "ingest", "tool_unavailable"
    assert_equal "ok", run_pipeline["status"]
  end

  def test_nonzero_exits_fail_at_their_stage
    @rig.fail_on = "ffmpeg"
    assert_failed run_pipeline, "ingest", "tool_failed"
    @rig.fail_on = "demucs"
    assert_failed run_pipeline, "separate", "tool_failed"
    @rig.fail_on = "yt-dlp"
    assert_failed run_pipeline(source: "https://example.com/a"), "ingest", "tool_failed"
  end

  def test_timeouts_fail_at_their_stage
    @rig.timeout_on = "demucs"
    assert_failed run_pipeline, "separate", "timeout"
    @rig.timeout_on = "ffmpeg"
    assert_failed run_pipeline, "ingest", "timeout"
  end

  def test_missing_or_empty_drums_stem_cannot_succeed
    @rig.stem = nil
    assert_failed run_pipeline, "separate", "empty_output"
    @rig.stem = ""
    assert_failed run_pipeline, "separate", "empty_output"
  end

  def test_missing_clip_fails_ingest
    @rig.write_clip = false
    assert_failed run_pipeline, "ingest", "empty_output"
  end

  def test_malformed_measurements_fail_analyze
    bad = [
      nil, "text", { error: "ffprobe missing" }, GOOD.merge(bpm_estimate: nil), GOOD.merge(bpm_estimate: 900),
      GOOD.merge(step_grid: { kicks: [99], snares: [], hats: [] }), GOOD.merge(step_grid: nil),
      GOOD.merge(drum_density: nil), GOOD.merge(drum_density: { kick: "many" })
    ]
    bad.each { |m| assert_failed run_pipeline(analyzer: ->(_) { m }), "analyze", "malformed_measurement" }
    raised = run_pipeline(analyzer: ->(_) { raise "ffmpeg died" })
    assert_failed raised, "analyze", "tool_failed"
  end

  def test_dossier_write_failure_is_a_write_stage_failure
    blocker = File.join(Dir.mktmpdir("hear-drums-blocked"), "file")
    File.write(blocker, "not a directory")
    result = HearDrums.hear_drums(source: @src, analyzer: ->(_) { GOOD }, root: File.join(blocker, "sub"),
                                  runner: @rig.runner, resolver: @rig.resolver, demucs_argv: ["demucs"])
    assert_equal "failed", result["status"]
    assert_equal "write", result["stage"]
    assert_equal "write_failed", result["kind"]
  end

  def test_failure_keeps_partial_diagnostics_apart_from_a_dossier
    @rig.stem = nil
    result = run_pipeline(artist: "A", style_tags: ["x"])
    diag = result["diagnostics"]
    assert_equal %w[validate ingest], diag["completed_stages"]
    assert_equal Digest::SHA256.hexdigest("exact source bytes\x00\x01".b), diag["source_hash"]
    assert_equal "A", diag["artist"]
  end

  def test_hints_are_bounded_and_not_applied
    hints = run_pipeline["dossier"]["engine_hints"]
    assert_equal false, hints["applied"]
    assert_includes HearDrums::SWING_HINT_RANGE, hints["swing"]
    assert_equal 60, hints["swing"]
    fast = run_pipeline(analyzer: ->(_) { GOOD.merge(bpm_estimate: 290.0, swing_hint: nil) })["dossier"]["engine_hints"]
    assert_equal 220, fast["bpm"]
    assert_nil fast["swing"]
  end

  def test_learned_records_keep_labels_and_filter_by_profile
    run_pipeline(artist: "J Dilla", style_tags: %w[boom-bap soul])
    other = File.join(@src_dir, "other.wav")
    File.write(other, "different bytes")
    run_pipeline(source: other, artist: "Madlib", style_tags: %w[loop-digger])
    all = HearDrums.learned_records(root: @root)
    assert_equal 2, all.length
    assert(all.all? { |r| r.key?("artist") && r["style_tags"].is_a?(Array) })
    assert_equal ["J Dilla"], HearDrums.learned_records(root: @root, artist: "J Dilla").map { |r| r["artist"] }
    assert_equal ["Madlib"], HearDrums.learned_records(root: @root, style_tag: "loop-digger").map { |r| r["artist"] }
    assert_equal 2, all.map { |r| r["source_hash"] }.uniq.length
  end

  def test_probe_reports_unavailable_tools_explicitly
    tools = HearDrums.probe_tools(runner: @rig.runner, resolver: ->(_) { nil },
                                  commands: { ytdlp: ["yt-dlp"], demucs: ["demucs"], ffmpeg: ["ffmpeg"] })
    assert(tools.values.all? { |t| t == { "available" => false, "path" => nil, "version" => nil } })
  end

  def test_cli_exit_codes_follow_status_and_output_is_one_json_line
    out = StringIO.new
    code = HearDrums.cli([@src, "--artist", "A", "--style", "Soul,Boom Bap", "--max-seconds", "30", "--root", @root],
                         analyzer: ->(_) { GOOD }, out:, runner: @rig.runner, resolver: @rig.resolver)
    assert_equal 0, code
    assert_equal %w[soul boom-bap], JSON.parse(out.string)["dossier"]["style_tags"]
    @rig.stem = nil
    out = StringIO.new
    code = HearDrums.cli([@src, "--root", @root], analyzer: ->(_) { GOOD }, out:, runner: @rig.runner, resolver: @rig.resolver)
    assert_equal 1, code
    assert_equal "failed", JSON.parse(out.string)["status"]
  end

  def test_the_module_opens_no_network_and_builds_no_shell_strings
    source = File.read(File.expand_path("../dilla/lib/hear_drums.rb", __dir__))
    refute_match(/Net::HTTP|open-uri|URI\.open|`|system\(|%x/, source)
  end
end
