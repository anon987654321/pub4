# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

class TestScanOutput < Minitest::Test
  FakeRule = Struct.new(:id, :auto_fix)

  class FakeScanner
    attr_reader :rules, :scan_calls

    def initialize(findings_by_pass:, rules: [])
      @findings_by_pass = findings_by_pass
      @rules = rules
      @scan_calls = 0
    end

    def scan(_path, depth: :deep)
      @scan_calls += 1
      findings = @findings_by_pass.shift || []
      Master::Result.ok(findings)
    end

    def scan_dir(path, depth:, glob: "**/*", stream: false)
      @scan_calls += 1
      findings = @findings_by_pass.shift || []
      Master::Result.ok([[File.join(path, "example.rb"), Master::Result.ok(findings)]])
    end
  end

  def finding(rule, line: 1)
    {
      rule:,
      message: "issue #{rule}",
      line:,
      severity: :info,
      fix: nil,
      tags: [],
      confidence: 0.9,
      why: "why",
      genealogy: %w[STYLE X],
      dedupe_key: "#{rule}:issue:#{line}",
    }
  end

  def test_scan_report_brief_and_delta
    pairs = [[
      "/tmp/a.rb",
      # Different lines so ConflictResolver does not collapse them
      Master::Result.ok([finding("LONG_LINE", line: 1), finding("DEAD_CODE", line: 2)]),
    ]]
    r1 = Master::CLI::ScanReport.new(pairs:, profile: "full", rule_filter: nil, phase: "pass1")
    assert_match(/2 violations/, r1.brief)
    assert_match(/LONG_LINE|DEAD_CODE/, r1.brief)

    r2 = Master::CLI::ScanReport.new(
      pairs: [[ "/tmp/a.rb", Master::Result.ok([finding("LONG_LINE", line: 1)]) ]],
      profile: "full",
      rule_filter: nil,
      phase: "pass2",
      prior_total: 2,
      autofixes: [{ path: "a.rb", transforms: [:frozen_string_literal] }],
    )
    text = r2.render
    assert_includes text, "phase: pass2"
    assert_includes text, "delta: 2 → 1"
    assert_includes text, "autofixed: 1 file"
  end

  def test_scan_live_snapshot_written
    Dir.mktmpdir do |root|
      path = Master::CLI::ScanLive.snapshot!("hello findings", root:, note: "test", announce: false)
      assert_equal File.join(root, ".master", "scan_last.txt"), path
      assert_includes File.read(path), "hello findings"
      assert_includes File.read(path), "test"
    end
  end

  def test_dispatch_scan_emits_multiphase_and_snapshot
    Dir.mktmpdir do |root|
      path = File.join(root, "example.rb")
      File.write(path, "class Example\nend\n")
      scanner = FakeScanner.new(
        findings_by_pass: [[finding("FROZEN_LITERAL")], []],
        rules: [FakeRule.new("FROZEN_LITERAL", true)],
      )

      out = Master::CLI::CommandRegistry.dispatch_scan(
        scanner:,
        root:,
        ctx: { args: path },
      )

      snap = File.join(root, ".master", "scan_last.txt")
      assert File.file?(snap), "expected final snapshot"
      assert_includes File.read(snap), "phase:"
      # Final render should mention phase and preferably autofix
      assert_match(/phase:|clean|violation|autofix/i, out)
    end
  end

  def test_help_documents_through_pass
    detail = Master::CLI::CommandRegistry.help_text("through")
    assert_includes detail, "critique"
  end
end
