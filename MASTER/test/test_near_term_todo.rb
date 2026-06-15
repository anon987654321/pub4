# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

class TestNearTermTodo < Minitest::Test
  class FakeBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(name, payload = nil, **kwargs)
      @events << [name, payload || kwargs]
    end
  end

  def test_result_err_carries_context_hash
    err = Master::Result.err("boom", category: :validation,
                              context: { file: "x.rb", method: "call", attempted: "scan" })
    assert_equal "x.rb", err.context[:file]
    assert_equal "call", err.context[:method]
    assert_equal "scan", err.context[:attempted]
  end

  def test_semantic_cache_persists_index_yaml
    Dir.mktmpdir do |dir|
      cache = Master::Reach::SemanticCache.new(root: dir, ttl: 300)
      cache.fetch("prompt", "model") { Master::Result.ok("cached-body") }
      index_path = File.join(dir, ".master", "llm_cache.yml")
      assert File.exist?(index_path)
      rows = Master.load_yaml(index_path)
      assert_equal 1, rows.size
    end
  end

  def test_scanner_skips_semantic_when_fast_rules_clean
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, "puts 'ok'\n")
      fast = Class.new do
        def check(_code, path:)
          []
        end
      end.new
      semantic_calls = 0
      semantic_class = Class.new do
        def self.name
          "Master::Judge::Scan::Rules::SemanticRule"
        end

        define_method(:check) do |_code, path:|
          semantic_calls += 1
          []
        end
      end
      scanner = Master::Judge::Scan::Scanner.new(rules: [fast, semantic_class.new])
      scanner.scan(path)
      assert_equal 0, semantic_calls
    end
  end

  def test_scan_dir_stream_progress_format
    Dir.mktmpdir do |dir|
      path = File.join(dir, "bad.rb")
      File.write(path, "var x = 1\n")
      bus = FakeBus.new
      rule = Class.new do
        def check(_code, path:)
          [{ rule: "TEST", line: 1, message: "nope", severity: :warning }]
        end
      end.new
      scanner = Master::Judge::Scan::Scanner.new(rules: [rule], event_bus: bus)
      out, = capture_io { scanner.scan_dir(dir, stream: true) }
      assert_includes out, "scan: bad.rb 1 violation(s)"
      assert bus.events.any? { |name, _| name == "scan:complete" }
    end
  end

  def test_ast_fixer_is_idempotent_on_second_pass
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.js")
      File.write(path, "var answer = 1;\nanswer && answer.value;\n")

      first = Master::Judge::Scan::AstFixer.fix(path, File.read(path))
      second = Master::Judge::Scan::AstFixer.fix(path, File.read(path))

      assert_includes first.transforms, :no_var
      assert_includes first.transforms, :optional_chaining
      assert_empty second.transforms
    end
  end

  def test_genetic_fix_rejects_higher_violation_candidate
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "puts :x\n")
      calls = []
      scanner = Class.new do
        def scan(_path, rules: nil)
          calls << :scan
          count = calls.size == 1 ? 1 : 2
          findings = Array.new(count) { { rule: "TEST", line: 1, message: "x", severity: :warning } }
          Master::Result.ok(findings)
        end

        def should_autofix?(_rule, _conf)
          true
        end
      end.new
      agent = Class.new do
        def ask(_prompt)
          "puts :y\n```ruby\nputs :y\n```"
        end
      end.new
      loop = Master::Loop::RuleLoop.new(
        rule: Struct.new(:id).new("TEST"),
        agent: agent,
        scanner: scanner,
        root: root,
        bus: FakeBus.new
      )
      assert_nil loop.__send__(:best_candidate, ["puts :y\n"], path)
    end
  end

  def test_help_progressive_disclosure
    summary = Master::Now::CommandRegistry::HelpTopics.summary
    assert_includes summary, "/scan"
    detail = Master::Now::CommandRegistry::HelpTopics.detail("scan")
    assert_includes detail, "example:"
  end

  def test_scan_results_silent_on_clean
    pairs = [["/tmp/x.rb", Master::Result.ok([])]]
    report = Master::Now::CommandRegistry.format_scan_results(pairs, nil, nil)
    assert_equal "", report
  end
end
