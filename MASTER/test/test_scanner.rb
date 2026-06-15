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

  class BoomScanner < Master::Judge::Scan::Scanner
    private

    def scan_one(dir:, path:, depth:, stream:, index: nil)
      raise "boom #{index}"
    end
  end

  class PathScanner < Master::Judge::Scan::Scanner
    attr_reader :seen

    def initialize(*args, **kwargs)
      super
      @seen = []
    end

    private

    def scan_one(dir:, path:, depth:, stream:, index: nil)
      @seen << path
      [path, Master::Result.ok([])]
    end
  end

  def test_scan_reads_file_and_publishes_completion
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, "puts 'ok'\n")
      bus = FakeBus.new
      scanner = Master::Judge::Scan::Scanner.new(rules: [build_rule], event_bus: bus)

      result = scanner.scan(path)

      assert result.ok?
      assert_empty result.value!
      assert bus.events.any? { |name, payload| name == "scan:file_read" && payload[:path] == path }
      assert bus.events.any? { |name, payload| name == "scan:complete" && payload[:count].zero? }
    end
  end

  def test_scan_documents_and_enforces_preconditions
    scanner = Master::Judge::Scan::Scanner.new(rules: [build_rule])

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
      scanner = Master::Judge::Scan::Scanner.new(rules: [build_rule(findings: [
        { rule: "Style/One" },
        { rule_id: "Lint/Two" },
        { "rule" => "Style/One" },
        { "rule_id" => "Naming/Three" },
        { rule: "Lint/Two" },
        { rule: "Metrics/Four" }
      ])], event_bus: bus)

      result = scanner.scan(path)

      assert result.ok?
      complete = bus.events.find { |name, _payload| name == "scan:complete" }
      assert_equal({ "Lint/Two" => 2, "Style/One" => 2, "Metrics/Four" => 1 }, complete.last[:top_rules])
    end
  end

  def test_scan_dir_surfaces_thread_errors_via_bus
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, "puts 'ok'\n")
      bus = FakeBus.new
      scanner = BoomScanner.new(rules: [build_rule], event_bus: bus)

      result = scanner.scan_dir(dir)

      assert result.ok?
      file_path, file_result = result.value!.first
      assert_equal path, file_path
      assert file_result.err?
      assert bus.events.any? { |name, payload| name == "scanner:thread_error" && payload[:path] == path }
    end
  end

  def test_scan_dir_streams_per_file_violation_progress
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, "puts 'ok'\n")
      scanner = Master::Judge::Scan::Scanner.new(
        rules: [build_rule(findings: [{ rule: "STYLE", line: 1, message: "issue" }])]
      )

      out, = capture_io { scanner.scan_dir(dir, stream: true) }

      assert_includes out, "scan: sample.rb 1 violation(s)"
    end
  end

  def test_scan_dir_appends_cross_file_dry_findings
    Dir.mktmpdir do |dir|
      3.times do |idx|
        File.write(File.join(dir, "sample#{idx}.rb"), "DATA = File.read(\"config/app.yml\")\n")
      end
      scanner = Master::Judge::Scan::Scanner.new(rules: [])

      result = scanner.scan_dir(dir)
      findings = result.value!.flat_map { |_path, file_result| Master::Result.wrap(file_result).value_or([]) }

      assert findings.any? { |finding| finding[:rule] == "CROSS_FILE_DRY" }
    end
  end

  def test_semantic_rule_skipped_when_static_errors_exist
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, "puts 'ok'\n")
      semantic = Class.new do
        def id = "semantic"
        def check(_code, path:) = raise "semantic should not run"
      end.new
      static_error = build_rule(findings: [{ rule: "STATIC", severity: :error, line: 1, message: "stop" }])
      scanner = Master::Judge::Scan::Scanner.new(rules: [static_error, semantic])

      result = scanner.scan(path)

      assert result.ok?
      assert_equal ["STATIC"], result.value!.map { |finding| finding[:rule] }
    end
  end

  def test_scan_since_includes_changed_master_lib_alongside_requested_dir
    Dir.mktmpdir do |repo|
      web_path = File.join(repo, "web", "app.rb")
      master_path = File.join(repo, "MASTER", "lib", "engine.rb")
      deploy_path = File.join(repo, "DEPLOY", "skip.rb")
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
      scanner = PathScanner.new(rules: [])

      result = scanner.scan_since("HEAD~1", dir: File.join(repo, "web"))
      paths = result.value!.map(&:first)

      assert_includes paths, web_path
      assert_includes paths, master_path
      refute_includes paths, deploy_path
    end
  end

  private

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
end
