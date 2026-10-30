# frozen_string_literal: true

require_relative "test_helper"

class TestScanner < Minitest::Test
  class FakeBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(name, payload = nil, **kwargs)
      @events << [name, payload || kwargs]
    end
  end

  # **kwargs, not the signature spelled out. scan_dir wraps every error from
  # scan_one in a Result it is free to ignore, so when the real method gained
  # autofix:, autofix_root: and rules:, these doubles raised ArgumentError on
  # every file and the walk reported nothing — a stale double that reads as a
  # tree with no files in it.
  class BoomScanner < Master::Fix::Scanner
    private

    def scan_one(dir:, path:, depth:, stream:, index: nil, **)
      raise "boom #{index}"
    end
  end

  class PathScanner < Master::Fix::Scanner
    attr_reader :seen

    def initialize(*args, **kwargs)
      super
      @seen = []
    end

    private

    def scan_one(dir:, path:, depth:, stream:, index: nil, **)
      @seen << path
      [path, Master::Result.ok([])]
    end
  end

  def test_scan_reads_file_and_publishes_completion
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, "puts 'ok'\n")
      bus = FakeBus.new
      scanner = Master::Fix::Scanner.new(laws: [build_rule], event_bus: bus)

      result = scanner.scan(path)

      assert result.ok?
      assert_empty result.value!
      assert bus.events.any? { |name, payload| name == "scan:file_read" && payload[:path] == path }
      assert bus.events.any? { |name, payload| name == "scan:complete" && payload[:count].zero? }
    end
  end

  def test_scan_documents_and_enforces_preconditions
    scanner = Master::Fix::Scanner.new(laws: [build_rule])

    missing = scanner.scan("/tmp/master-missing-file.rb")

    assert missing.err?
    assert_equal :validation, missing.category
    assert_raises(ArgumentError) { scanner.scan(__FILE__, depth: :quick) }
  end

  def test_scan_complete_event_includes_top_rule_breakdown
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, "puts 'ok'\n")
      bus = FakeBus.new
      scanner = Master::Fix::Scanner.new(laws: [build_rule(findings: [
        { law: "Style/One" },
        { law_id: "Lint/Two" },
        { "law" => "Style/One" },
        { "law_id" => "Naming/Three" },
        { law: "Lint/Two" },
        { law: "Metrics/Four" },
      ])], event_bus: bus)

      result = scanner.scan(path)

      assert result.ok?
      complete = bus.events.find { |name, _payload| name == "scan:complete" }
      assert_equal({ "Lint/Two" => 2, "Style/One" => 2, "Metrics/Four" => 1 }, complete.last[:top_laws])
    end
  end

  def test_scan_dir_skips_refused_files_without_failing_the_batch
    Dir.mktmpdir do |dir|
      path = File.join(dir, "binary.rb")
      File.binwrite(path, "\x00binary")

      scanner = Master::Fix::Scanner.new(laws: [])
      result = scanner.scan_dir(dir)

      assert result.ok?
      pair = result.value!.find { |item| item.first == path }
      assert pair
      assert pair.last.err?
      assert_equal :validation, pair.last.category
    end
  end

  # STUDIO/dilla/data/dilla.json is over the line limit; refusing it failed the whole STUDIO walk.
  def test_scan_dir_skips_a_file_over_the_line_limit_without_failing_the_batch
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "long.json"), "1\n2\n3\n")

      result = Master::Fix::Scan::FileProcessor.stub(:max_lines_for, 2) do
        Master::Fix::Scanner.new(laws: []).scan_dir(dir, glob: "*.json")
      end

      assert result.ok?, result.to_s
    end
  end

  def test_scan_dir_surfaces_thread_errors_via_bus
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, "puts 'ok'\n")
      bus = FakeBus.new
      scanner = BoomScanner.new(laws: [build_rule], event_bus: bus)

      result = scanner.scan_dir(dir)

      refute result.ok?
      assert_match(/1 file\(s\) failed measurement/, result.message)
      assert bus.events.any? { |name, payload| name == "scanner:thread_error" && payload[:path] == path }
    end
  end

  def test_scan_dir_streams_per_file_violation_progress
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, "puts 'ok'\n")
      scanner = Master::Fix::Scanner.new(
        laws: [build_rule(findings: [{ law: "STYLE", line: 1, message: "issue" }])],
      )

      out, = capture_io { scanner.scan_dir(dir, stream: true) }

      # dmesg-style progress: attach line, per-file hit, checkpoint, completion.
      assert_includes out, "scan0 at master0: 1 file"
      assert_includes out, "scan0: 1/1 sample.rb, 1 finding"
      assert_match(/^scan0: done, 1 file, 1 violation in 1 file, \d+s$/, out)
    end
  end

  def test_large_scan_hit_detail_is_quiet_unless_verbose
    scanner = Master::Fix::Scanner.new(laws: [])
    args = {
      unit: "obs0",
      done: 1,
      total: 1757,
      rel: "lib/example.rb",
      count: 42,
      eta_s: 120,
    }

    previous = ENV["MASTER_SCAN_VERBOSE"]
    quiet, = capture_io { scanner.send(:log_scan_hit, **args) }
    assert_empty quiet, "broad scans use checkpoints, not one console line per dirty file"

    ENV["MASTER_SCAN_VERBOSE"] = "1"
    verbose, = capture_io { scanner.send(:log_scan_hit, **args) }
    assert_includes verbose, "obs0: 1/1757 lib/example.rb, 42 findings"
  ensure
    previous ? ENV["MASTER_SCAN_VERBOSE"] = previous : ENV.delete("MASTER_SCAN_VERBOSE")
  end

  def test_scan_dir_includes_recognized_extensionless_shebang_scripts
    Dir.mktmpdir do |dir|
      bin = File.join(dir, "bin")
      FileUtils.mkdir_p(bin)
      path = File.join(bin, "doctor")
      File.write(path, "#!/usr/bin/env ruby\nputs :ok\n")
      File.write(File.join(dir, "notes.toml"), "key = \"value\"\n")
      scanner = PathScanner.new(laws: [])

      result = scanner.scan_dir(dir)

      assert result.ok?
      assert_includes scanner.seen, path
      refute_includes scanner.seen, File.join(dir, "notes.toml")
    end
  end

  def test_scan_dir_skips_runtime_generated_and_vendor_segments
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "vendor", "bundle", "gems"))
      FileUtils.mkdir_p(File.join(dir, "app"))
      FileUtils.mkdir_p(File.join(dir, "tmp"))
      FileUtils.mkdir_p(File.join(dir, ".master"))
      FileUtils.mkdir_p(File.join(dir, "runtime"))
      FileUtils.mkdir_p(File.join(dir, "web", "public", "assets"))
      FileUtils.mkdir_p(File.join(dir, "web", "public"))
      FileUtils.mkdir_p(File.join(dir, "RAILS", "master", "script", "three_build"))
      File.write(File.join(dir, "vendor", "bundle", "gems", "bad.rb"), "puts 'vendor'\n")
      File.write(File.join(dir, "app", "good.rb"), "puts 'app'\n")
      File.write(File.join(dir, "tmp", "scratch.rb"), "puts 'tmp'\n")
      File.write(File.join(dir, ".master", "cache.rb"), "puts 'cache'\n")
      File.write(File.join(dir, "runtime", "event.rb"), "puts 'runtime'\n")
      File.write(File.join(dir, "web", "public", "assets", "face-123.js"), "console.log('asset')\n")
      File.write(File.join(dir, "web", "public", "face.js"), "console.log('source')\n")
      File.write(File.join(dir, "RAILS", "master", "script", "three_build", "vendor.js"), "console.log('vendor')\n")
      FileUtils.mkdir_p(File.join(dir, "RAILS", "amber", "public", "assets"))
      File.write(File.join(dir, "RAILS", "amber", "public", "assets", "application-1a2b.js"), "console.log('digest')\n")
      FileUtils.mkdir_p(File.join(dir, "db", "schema"))
      File.write(File.join(dir, "db", "schema", "module.rb"), "puts 'authored'\n")
      scanner = PathScanner.new(laws: [])

      result = scanner.scan_dir(dir)

      # The Result first: an empty `seen` reads the same whether the filter
      # excluded everything or the walk died on the first file.
      assert result.ok?, -> { "scan_dir failed: #{result.message}" }
      assert_equal [File.join(dir, "app", "good.rb"), File.join(dir, "db", "schema", "module.rb"),
                    File.join(dir, "web", "public", "face.js")].sort,
        scanner.seen.sort
    end
  end

  def test_scan_dir_appends_cross_file_dry_findings
    Dir.mktmpdir do |dir|
      3.times do |idx|
        File.write(File.join(dir, "sample#{idx}.rb"), "DATA = File.read(\"config/app.yml\")\n")
      end
      scanner = Master::Fix::Scanner.new(laws: [])

      result = scanner.scan_dir(dir)
      findings = result.value!.flat_map { |_path, file_result| Master::Result.wrap(file_result).value_or([]) }

      assert findings.any? { |finding| finding[:law] == "CROSS_FILE_DRY" }
    end
  end

  def recording_semantic_law(ran)
    law = Class.new
    law.define_method(:id) { "semantic" }
    law.define_method(:check) { |_code, path:| ran << path && [] }
    law.new
  end

  def test_semantic_rule_still_runs_when_static_errors_exist
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, "puts 'ok'\n")
      ran = []
      static_error = build_rule(findings: [{ law: "STATIC", severity: :error, line: 1, message: "stop" }])
      scanner = Master::Fix::Scanner.new(laws: [static_error, recording_semantic_law(ran)])

      result = scanner.scan(path)

      assert result.ok?
      assert_equal ["STATIC"], result.value!.map { |finding| finding[:law] }
      assert_equal [path], ran, "a static error hid the semantic read of the same file"
    end
  end

  def test_scan_since_includes_changed_master_lib_alongside_requested_dir
    Dir.mktmpdir do |repo|
      web_path = File.join(repo, "web", "app.rb")
      master_path = File.join(repo, "MASTER", "lib", "engine.rb")
      deploy_path = File.join(repo, "OPENBSD", "skip.rb")
      FileUtils.mkdir_p(File.dirname(web_path))
      FileUtils.mkdir_p(File.dirname(master_path))
      FileUtils.mkdir_p(File.dirname(deploy_path))
      File.write(web_path, "puts 'base'\n")
      File.write(master_path, "puts 'base'\n")
      File.write(deploy_path, "puts 'base'\n")
      git(repo, "init")
      git(repo, "config", "user.email", "test@example.invalid")
      git(repo, "config", "user.name", "Test")
      git(repo, "add", ".")
      git(repo, "commit", "-m", "base")
      File.write(web_path, "puts 'changed web'\n")
      File.write(master_path, "puts 'changed master'\n")
      File.write(deploy_path, "puts 'changed deploy'\n")
      git(repo, "add", ".")
      git(repo, "commit", "-m", "change")
      scanner = PathScanner.new(laws: [])

      result = scanner.scan_since("HEAD~1", dir: File.join(repo, "web"))
      paths = result.value!.map(&:first)

      normalized = paths.map { |path| File.realpath(path) }
      assert_includes normalized, File.realpath(web_path)
      assert_includes normalized, File.realpath(master_path)
      refute_includes normalized, File.realpath(deploy_path)
    end
  end

  def test_findings_flattens_path_onto_each_hash
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, "puts 'ok'\n")
      scanner = Master::Fix::Scanner.new(
        laws: [build_rule(findings: [{ law: "STYLE", line: 1, message: "issue" }])],
      )

      hits = scanner.findings([path, dir])

      assert hits.all? { |item| item[:path] && item[:law] == "STYLE" }
      assert hits.any? { |item| item[:path] == path }
    end
  end

  # Forked workers answer what one process would, in order, and a dead worker is redone here.
  def test_fork_map_matches_one_process_and_redoes_a_failed_worker
    scanner = Master::Fix::Scanner.new
    items = (1..450).to_a
    double = ->(slice) { slice.map { |n| { n:, law: :X } } }

    forked = with_processes("3") { scanner.fork_map(items, &double) }
    redone = with_processes("3") { scanner.fork_map(items) { |slice| fail_in_child(slice, &double) } }

    assert_equal [double.call(items)] * 2, [forked, redone]
  end

  # A walk asks a Markdown file the laws a lone scan of it asks, not the Ruby-only ones.
  def test_a_walk_dispatches_laws_by_language_as_a_lone_scan_does
    Dir.mktmpdir do |dir|
      path = File.join(dir, "notes.md").tap { |file| File.write(file, "# notes\n") }
      asked = []
      laws = [language_law(:ruby, asked), language_law(nil, asked)]

      Master::Fix::Scanner.new(laws:).scan_dir(dir)

      assert_equal [[path, "ANY"]], asked
    end
  end

  private

  def language_law(lang, asked)
    law = Class.new do
      define_method(:languages) { Array(lang).map(&:to_s) }
      define_method(:id) { lang ? lang.to_s.upcase : "ANY" }
      define_method(:check) { |_code, path:| (asked << [path, id]) && [] }
    end
    law.new
  end

  def git(repo, *args)
    assert system("git", "-C", repo, *args, out: File::NULL, err: File::NULL)
  end

  def build_rule(findings: [])
    Class.new do
      define_method(:initialize) do |rule_findings|
        @rule_findings = rule_findings
      end

      def check(_code, path:)
        @rule_findings
      end
    end.new(findings)
  end
  def fail_in_child(slice, &work)
    exit!(1) unless Process.pid == MASTER_TEST_PID

    work.call(slice)
  end

  def with_processes(count)
    previous = ENV.fetch("MASTER_SCAN_PROCESSES", nil)
    ENV["MASTER_SCAN_PROCESSES"] = count
    yield
  ensure
    ENV["MASTER_SCAN_PROCESSES"] = previous
  end
end
