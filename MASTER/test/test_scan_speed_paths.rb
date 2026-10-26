# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "open3"
require "json"
require File.join(Master::ROOT, "law", "definition")

# The scan's per-file costs were a git subprocess and a soul.yml parse for
# every file. These tests hold the answers equal to the per-file computation
# they replaced, and the new timing and cross-file paths in working order.
class TestScanSpeedPaths < Minitest::Test
  def git(root, *args)
    out, status = Open3.capture2e("git", "-C", root, "-c", "user.email=t@t", "-c", "user.name=t", *args)
    assert status.success?, out
    out
  end

  def write(root, rel, text)
    path = File.join(root, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def repo
    Dir.mktmpdir do |root|
      git(root, "init", "-q")
      write(root, "a.rb", "class A\n  def one; end\n  def two; end\nend\n")
      write(root, "b.rb", "class B\n  def keep; end\nend\n")
      write(root, "c.rb", "class C\n  def old; end\nend\n")
      git(root, "add", ".")
      git(root, "commit", "-qm", "one")
      write(root, "a.rb", "class A\n  def one; end\nend\n")
      git(root, "commit", "-qam", "drop two")
      write(root, "d.rb", "class D\n  def x; end\nend\n")
      git(root, "add", ".")
      git(root, "commit", "-qm", "add d")
      yield root
    end
  end

  def test_commit_guard_reports_the_same_omissions_as_the_unskipped_comparison
    repo do |root|
      write(root, "c.rb", "class C\nend\n")
      guard = Master::Review::CommitGuard.new(root:, depth: 3)
      fast = guard.check(paths: %w[a.rb b.rb c.rb d.rb])
      slow = %w[a.rb b.rb c.rb d.rb].flat_map { |rel| unskipped(root, rel) }

      assert_equal slow.map { |o| o.to_h.values.map(&:to_s) }.sort, fast.map { |o| o.to_h.values.map(&:to_s) }.sort
      assert_equal %w[A#two C#old], fast.map(&:name).sort
    end
  end

  def test_commit_guard_sees_an_edit_made_after_the_index_was_taken
    repo do |root|
      guard = Master::Review::CommitGuard.new(root:, depth: 3)
      guard.check(paths: %w[b.rb])
      sleep 0.05
      write(root, "b.rb", "class B\nend\n")
      File.utime(Time.now + 5, Time.now + 5, File.join(root, "b.rb"))

      assert_equal ["B#keep"], guard.check(paths: %w[b.rb]).map(&:name)
    end
  end

  def test_file_collector_asks_git_for_the_root_once
    repo do |root|
      3.times { |i| write(root, "f#{i}.rb", "x = #{i}\n") }
      calls = 0
      collector = Master::Fix::FixLoop::FileCollector.new(root:)
      original = Master::Io::Exec.method(:capture3)
      counter = lambda do |*argv, **opts|
        calls += 1 if argv.include?("rev-parse")
        original.call(*argv, **opts)
      end
      Master::Io::Exec.stub(:capture3, counter) { collector.collect(root) }

      assert_equal 1, calls
    end
  end

  def test_law_timing_is_silent_unless_asked_and_ranks_when_asked
    timing = Master::Fix::Scan::LawTiming
    law = Struct.new(:id).new("SLOW")
    timing.drain
    ENV.delete("MASTER_SCAN_TIMING")
    assert_equal 7, timing.measure(law) { 7 }
    assert_empty timing.drain
    ENV["MASTER_SCAN_TIMING"] = "1"
    timing.measure(law) { sleep 0.01 }

    assert_match(/\ASLOW /, timing.drain.first)
  ensure
    ENV.delete("MASTER_SCAN_TIMING")
  end

  def test_scan_progress_reports_the_active_law_and_nested_laws_yml_detector
    # Declared here so the ensure below can reach them.
    processor = token = monitor = nil
    previous_path = ENV["CHECK_PROGRESS_FILE"]
    previous_enabled = ENV["MASTER_SCAN_PROGRESS"]

    Dir.mktmpdir do |dir|
      progress = File.join(dir, "progress.json")
      ENV["CHECK_PROGRESS_FILE"] = progress
      ENV["MASTER_SCAN_PROGRESS"] = "1"

      processor = Master::Fix::Scan::FileProcessor.new
      law = Struct.new(:id).new("LAW_BRIDGE")
      token = processor.send(
        :begin_law_progress, pass: :lexical, law:, index: 3, total: 12,
        path: File.join(Master::ROOT, "lib", "sample.rb")
      )
      monitor = processor.instance_variable_get(:@progress_thread)
      sleep 1.2
      row = JSON.parse(File.read(progress))
      assert_equal ["scan", "running", "lexical", "LAW_BRIDGE", "MASTER/lib/sample.rb", 3, 12],
                   row.values_at("kind", "state", "pass", "law", "file", "n", "total")

      Thread.current.thread_variable_get(:master_scan_progress_callback).call(
        inner_pass: "laws.yml/violation", inner_law: "ROBUSTNESS", index: 2, total: 7,
        path: File.join(Master::ROOT, "data", "laws.yml")
      )
      sleep 1.2
      row = JSON.parse(File.read(progress))
      assert_equal ["laws.yml/violation", "ROBUSTNESS", "MASTER/data/laws.yml", 2, 7],
                   row.values_at("pass", "law", "file", "n", "total")
    end
  ensure
    processor&.send(:end_law_progress, token) if processor && token
    monitor&.join(4) if monitor
    previous_path ? ENV["CHECK_PROGRESS_FILE"] = previous_path : ENV.delete("CHECK_PROGRESS_FILE")
    previous_enabled ? ENV["MASTER_SCAN_PROGRESS"] = previous_enabled : ENV.delete("MASTER_SCAN_PROGRESS")
  end

  def test_cross_file_findings_build_with_the_law_key
    Dir.mktmpdir do |root|
      %w[a b c].each { |name| write(root, "#{name}.rb", "x = ENV.fetch(\"SHARED_KEY\")\n") }
      rows = Master::Fix::Scan::CrossFileAnalysis.new(root:).call(Dir.glob(File.join(root, "*.rb")))

      assert_equal ["SCATTERED_CONFIG"], rows.flat_map { |_, result| result.value! }.map { |finding| finding[:law] }
    end
  end

  def test_file_processor_line_guard_preserves_eof_and_limit_semantics
    Dir.mktmpdir do |dir|
      processor = Master::Fix::Scan::FileProcessor.new(skip_semantic: true)
      max_lines = Master::Fix::Scan::FileProcessor::MAX_LINES
      allowed = {
        "empty.rb" => "",
        "no_final_newline.rb" => "one line",
        "final_newline.rb" => "one line\n",
        "max_without_newline.rb" => ("x\n" * (max_lines - 1)) + "x",
        "max_with_newline.rb" => "x\n" * max_lines,
      }

      allowed.each do |name, source|
        path = File.join(dir, name)
        File.write(path, source)
        result = processor.send(:read_file, path)

        assert result.ok?, -> { "#{name}: #{result.message}" }
        assert_equal source, result.value!, name
      end

      too_long = File.join(dir, "too_long.rb")
      File.write(too_long, "x\n" * (max_lines + 1))
      result = processor.send(:read_file, too_long)

      assert result.err?
      assert_equal :validation, result.category
      assert_match(/file too long/, result.message)
    end
  end

  def test_structured_data_budget_covers_dilla_catalogue_and_stays_bounded
    path = File.expand_path("../../STUDIO/dilla/data/dilla.json", __dir__)
    assert File.file?(path), "the canonical Dilla catalogue must remain present"

    processor = Master::Fix::Scan::FileProcessor.new(skip_semantic: true)
    assert_equal 20_000, Master::Fix::Scan::FileProcessor.max_lines_for(path)
    assert_operator File.foreach(path, encoding: "UTF-8").count, :<=,
                    Master::Fix::Scan::FileProcessor::STRUCTURED_DATA_MAX_LINES

    result = processor.send(:read_file, path)
    assert result.ok?, "Dilla catalogue was refused by the scanner: #{result.message}"
  end

  def test_structured_data_budget_rejects_files_over_its_ceiling
    Dir.mktmpdir do |dir|
      path = File.join(dir, "too_long.json")
      count = Master::Fix::Scan::FileProcessor::STRUCTURED_DATA_MAX_LINES + 1
      File.write(path, JSON.pretty_generate(Array.new(count, "x")))
      processor = Master::Fix::Scan::FileProcessor.new(skip_semantic: true)

      result = processor.send(:read_file, path)
      assert result.err?
      assert_equal :validation, result.category
      assert_match(/file too long/, result.message)
    end
  end

  def test_law_scan_matches_the_per_line_reading_it_replaced
    css = "/* a !important\n   !important in a comment */\na { color: red !important; }\n" \
          "b { x: 1 !important; } /* scan: intentional */\n// !important\n"
    rb = "# puts 1\nputs 2\nputs 3 # scan: intentional\n"
    pattern = /!important|puts/
    [["x.scss", css], ["x.rb", rb]].each do |file, text|
      [false, true].each do |reads|
        definition = probe_definition(reads, pattern)
        got = definition.scan(text, file:).map(&:line)

        assert_equal per_line_reading(definition, text, file, reads, pattern), got, "#{file} reads_comments=#{reads}"
        assert_equal got, definition.scan(text.dup, file:).map(&:line)
      end
    end
  end

  private

  def probe_definition(reads, pattern)
    Law::Definition.new(id: :probe, source: nil, severity: :warn, mode: :violation, languages: [], scope: :line,
                        surfaces: nil, law_scope: nil, lifecycle: :active, autofix: :review, path: nil, path_exclude: nil,
                        absent: nil, detect: ->(line) { line.match?(pattern) }, ask: nil, practice: nil,
                        reads_comments: reads, fix: "f", bad: "b", good: "g")
  end

  # The line-by-line reading scan_lines did before the subject view.
  def per_line_reading(definition, text, file, reads, pattern)
    leaders = reads ? [] : Law.comment_leaders(file)
    continued = reads ? [] : definition.send(:continued_comment_lines, text, file)
    text.each_line.with_index(1).filter_map do |line, n|
      next if continued.include?(n - 1) || leaders.any? { |l| line.lstrip.start_with?(l) }
      next if line.match?(/scan:\s*intentional\b/)

      n if line.match?(pattern)
    end
  end

  # The comparison CommitGuard made for every file before it skipped unchanged ones.
  def unskipped(root, rel)
    current = Master::Review::AstSignature.from_source(File.read(File.join(root, rel)))
    3.downto(1).flat_map do |n|
      hist = Master::Review::AstSignature.from_git(rel, ref: "HEAD~#{n}", root:)
      Master::Review::AstSignature.diff(hist, current).map do |sig|
        Master::Review::CommitGuard::Omission.new(path: rel, name: sig.name, type: sig.type, last_seen_at: "HEAD~#{n}")
      end
    end.uniq { |o| [o.path, o.name] }
  end
end
