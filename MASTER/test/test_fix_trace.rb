# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "stringio"
require "fix/visual_pass"
require "fix/fix_trace"
require "operator/fix_tail"

class FixTraceTest < Minitest::Test
  Trace = Master::Fix::FixTrace
  Transcript = Master::Fix::Transcript

  def setup
    @root = Dir.mktmpdir("fixtrace")
    @saved = ENV.to_h.slice("MASTER_FIX_TRANSCRIPT_ROOT", "MASTER_FIX_RUN_ID", "MASTER_FIX_VERBOSE")
    ENV["MASTER_FIX_TRANSCRIPT_ROOT"] = @root
    ENV["MASTER_FIX_RUN_ID"] = "run1"
    ENV.delete("MASTER_FIX_VERBOSE")
    Trace.reset!
  end

  def teardown
    %w[MASTER_FIX_TRANSCRIPT_ROOT MASTER_FIX_RUN_ID MASTER_FIX_VERBOSE].each { |key| ENV.delete(key) }
    @saved.each { |key, value| ENV[key] = value }
    Trace.reset!
    FileUtils.rm_rf(@root)
  end

  def lines
    out = StringIO.new
    original = $stdout
    $stdout = out
    yield
    out.string.lines.map(&:chomp)
  ensure
    $stdout = original
  end

  def records(name)
    File.readlines(File.join(@root, ".master/fix_transcripts/run1/#{name}.ndjson")).map { |line| JSON.parse(line) }
  end

  def test_unanchored_pick_says_why
    pick = "surface: home viewport: mobile selector .hero laws: #{Master::Fix::VisualUsability.ids.first}: header overlaps"
    out = lines { assert_nil Trace.pick(pick, nil, [], {}) }
    assert_match(/\Acrit0: pick laws=\S+ home\/mobile anchor=\.hero unanchored \(selector \.hero has no source file\): /, out.first)
    row = records("critique").last
    assert_equal false, row["anchored"]
    assert_match(/no source file/, row["reason"])
  end

  def test_pick_without_surface_is_unanchored_with_reason
    out = lines { Trace.pick("make it nicer", nil, [], {}) }
    assert_includes out.first, "unanchored (no surface)"
  end

  def test_anchored_pick_names_file_and_trims_text
    finding = { file: "app/views/a.erb", line: 7 }
    out = lines { Trace.pick("surface: a viewport: desktop #x laws: #{Master::Fix::VisualUsability.ids.first} #{"y" * 400}", finding, [], {}) }
    assert_includes out.first, "anchored app/views/a.erb:7"
    assert_operator out.first.length, :<, 420
  end

  def test_round_summary_line_and_record
    result = Master::Result.ok({ feedback: "raw", issues: %w[a b], cherry_picks: %w[p], status: nil })
    capture = { surface: Struct.new(:id).new("home") }
    out = lines { Trace.round(result, captures: [capture], images: [{ name: "x.png" }], context: "ctx") }
    assert_equal ["crit0: council round, 1 surfaces, 1 images, 2 findings, 1 picks"], out
    assert_equal "ctx", records("critique").last["prompt"]
  end

  def test_fix_lines_and_transcript
    file = File.join(@root, "a.rb")
    File.write(file, "a = 1\nb = 2\n")
    Trace.begin_attempt("LAW_X", file)
    Trace.prompt("the prompt")
    Trace.reply("the reply")
    out = lines do
      Trace.proposed("LAW_X", file, "a = 1\nb = 3\nc = 4\n")
      Trace.accepted("LAW_X", file)
    end
    assert_equal ["fix0: LAW_X a.rb proposed +2 -1", "fix0: LAW_X a.rb accepted"], out
    row = records("fixes").last
    assert_equal "the prompt", row["prompts"].first
    assert_equal "accepted", row["outcome"]
    assert_includes row["patch"], "+c = 4"
  end

  def test_rejection_and_verbose_diff
    ENV["MASTER_FIX_VERBOSE"] = "1"
    file = File.join(@root, "a.rb")
    File.write(file, "a = 1\n")
    Trace.begin_attempt("LAW_X", file)
    out = lines do
      Trace.proposed("LAW_X", file, "a = 2\n")
      Trace.rejected("LAW_X", file, "test_failed")
    end
    assert_includes out, "fix0: -a = 1"
    assert_equal "fix0: LAW_X a.rb rejected: test_failed", out.last
  end

  def test_transcript_redacts_caps_and_prunes
    transcript = Transcript.new(root: @root, run_id: "r", max_bytes: 600, keep: 2)
    secret = "sk-ant-#{"a" * 30}"
    assert transcript.append("fixes", { prompt: "key #{secret}", token: "x" })
    text = File.read(File.join(transcript.dir, "fixes.ndjson"))
    refute_includes text, secret
    assert_includes text, "[REDACTED]"
    # Words, not one long run: a 2000-character token reads as a secret and is redacted to fit.
    refute transcript.append("fixes", { prompt: "word " * 400 })
    assert_includes File.read(File.join(transcript.dir, "critique.ndjson")), "truncated"

    %w[old1 old2 old3].each_with_index do |name, i|
      dir = File.join(@root, Transcript::DIR, name)
      FileUtils.mkdir_p(dir)
      File.utime(Time.now - 1000 + i, Time.now - 1000 + i, dir)
    end
    Transcript.new(root: @root, run_id: "new", keep: 2).append("critique", { a: 1 })
    assert_equal %w[new r], Dir.children(File.join(@root, Transcript::DIR)).sort
  end

  def test_tail_prints_history_then_new_lines
    dir = File.join(@root, ".master", "fix_transcripts", "r")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "fixes.ndjson")
    File.write(path, "#{JSON.generate({ at: "t", kind: "attempt", law: "L", file: "a.rb", outcome: "accepted" })}\n")
    out = StringIO.new
    sleeps = 0
    sleeper = lambda do |_|
      sleeps += 1
      File.open(path, "a") { |io| io.puts(JSON.generate({ at: "t2", kind: "attempt", law: "M", file: "b.rb", outcome: "rejected: x" })) }
    end
    Operator::FixTail.run(["--transcript"], roots: [File.join(@root)], io: out, sleeper:, rounds: 1)
    assert_equal 2, out.string.lines.size
    assert_includes out.string, "attempt L a.rb accepted"
    assert_includes out.string, "attempt M b.rb rejected: x"
  end
  # The transcript is the run's audit record, so an edit, a deletion or a reorder
  # has to show when it is read back.
  def ledger_path(transcript, name) = File.join(transcript.dir, "#{name}.ndjson")

  def test_a_transcript_chain_verifies_and_links_each_line_to_the_one_before
    transcript = Transcript.new(root: @root, run_id: "chain")
    3.times { |n| transcript.append("fixes", { n: }) }

    rows = File.readlines(ledger_path(transcript, "fixes")).map { |line| JSON.parse(line) }

    assert_equal Transcript::GENESIS, rows.first["prev"]
    assert_equal rows[0]["hash"], rows[1]["prev"]
    assert_equal rows[1]["hash"], rows[2]["prev"]
    verdict = Transcript.verify(ledger_path(transcript, "fixes"))
    assert verdict.ok, verdict.reason
    assert_equal 3, verdict.lines
  end

  # A patch is git's output and arrives BINARY; json warned on every accepted fix.
  def test_a_binary_patch_is_written_as_utf8_without_a_warning
    transcript = Transcript.new(root: @root, run_id: "binary")
    patch = "-# Søknad\n+# Søknad, kø\n".b

    _out, err = capture_io { transcript.append("fixes", { patch: }) }

    refute_match(/BINARY/, err)
    assert_equal "-# Søknad\n+# Søknad, kø\n", JSON.parse(File.read(ledger_path(transcript, "fixes")))["patch"]
  end

  def test_an_edited_line_breaks_the_chain_at_that_line
    transcript = Transcript.new(root: @root, run_id: "edit")
    3.times { |n| transcript.append("fixes", { n: }) }
    path = ledger_path(transcript, "fixes")
    lines = File.readlines(path)
    lines[1] = lines[1].sub('"n":1', '"n":9')
    File.write(path, lines.join)

    verdict = Transcript.verify(path)

    refute verdict.ok
    assert_equal 2, verdict.broken_at
    assert_match(/hash does not match/, verdict.reason)
  end

  def test_a_dropped_line_breaks_the_chain_at_the_next_line
    transcript = Transcript.new(root: @root, run_id: "drop")
    3.times { |n| transcript.append("fixes", { n: }) }
    path = ledger_path(transcript, "fixes")
    lines = File.readlines(path)
    File.write(path, [lines[0], lines[2]].join)

    verdict = Transcript.verify(path)

    refute verdict.ok
    assert_equal 2, verdict.broken_at
    assert_match(/prev does not match/, verdict.reason)
  end

  def test_a_resumed_run_continues_the_chain_from_the_files_last_line
    Transcript.new(root: @root, run_id: "resume").append("fixes", { n: 1 })
    resumed = Transcript.new(root: @root, run_id: "resume")
    resumed.append("fixes", { n: 2 })

    assert Transcript.verify(ledger_path(resumed, "fixes")).ok
  end

  def test_a_truncation_marker_stays_on_the_chain
    transcript = Transcript.new(root: @root, run_id: "cap", max_bytes: 700)
    20.times { |n| transcript.append("critique", { n:, text: "x" * 40 }) }
    path = ledger_path(transcript, "critique")

    assert_includes File.read(path), "truncated"
    assert Transcript.verify(path).ok
  end
end
