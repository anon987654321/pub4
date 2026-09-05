# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

class TestScanAutofix < Minitest::Test
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

    def scan_dir(path, depth:, glob: "**/*", stream: false, **)
      @scan_calls += 1
      findings = @findings_by_pass.shift || []
      Master::Result.ok([[File.join(path, "example.rb"), Master::Result.ok(findings)]])
    end
  end

  def finding(rule)
    {
      rule:,
      message: "missing frozen",
      line: 1,
      severity: :info,
      fix: nil,
      tags: [],
      confidence: 0.9,
      why: "frozen header",
      genealogy: %w[STYLE FROZEN],
      dedupe_key: "#{rule}:frozen",
    }
  end

  def test_mechanical_autofix_enabled_by_default
    assert Master::Review::Scan::MechanicalAutofix.enabled?(env: {})
    assert Master::Review::Scan::MechanicalAutofix.enabled?(env: { "MASTER_SCAN_AUTOFIX" => "1" })
    refute Master::Review::Scan::MechanicalAutofix.enabled?(env: { "MASTER_SCAN_AUTOFIX" => "0" })
  end

  def test_dispatch_scan_applies_ast_fixer_then_rescans
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

      assert_includes File.read(path), "# frozen_string_literal: true"
      assert_includes out, "autofixed: 1 file"
      assert_operator scanner.scan_calls, :>=, 2
    end
  end

  def test_dispatch_scan_dry_run_does_not_write
    Dir.mktmpdir do |root|
      path = File.join(root, "example.rb")
      original = "class Example\nend\n"
      File.write(path, original)
      scanner = FakeScanner.new(
        findings_by_pass: [[finding("FROZEN_LITERAL")]],
        rules: [FakeRule.new("FROZEN_LITERAL", true)],
      )

      out = Master::CLI::CommandRegistry.dispatch_scan(
        scanner:,
        root:,
        ctx: { args: "#{path} --dry-run" },
      )

      assert_equal original, File.read(path)
      assert_includes out, "dry-run:"
      refute_includes out, "autofixed:"
    end
  end

  def test_dispatch_scan_no_autofix_flag_skips_writes
    Dir.mktmpdir do |root|
      path = File.join(root, "example.rb")
      original = "class Example\nend\n"
      File.write(path, original)
      scanner = FakeScanner.new(
        findings_by_pass: [[finding("FROZEN_LITERAL")]],
        rules: [FakeRule.new("FROZEN_LITERAL", true)],
      )

      out = Master::CLI::CommandRegistry.dispatch_scan(
        scanner:,
        root:,
        ctx: { args: "#{path} --no-autofix" },
      )

      assert_equal original, File.read(path)
      refute_includes out, "autofixed:"
      assert_match(/violation/i, out)
    end
  end

  def test_help_documents_through_dry_run
    detail = Master::CLI::CommandRegistry.help_text("through")
    assert_includes detail, "--dry-run"
  end

  # The old pass walked the whole tree, then fixed, then walked it again.
  # A finding must be written on the file that just produced it, before the
  # walker moves on — otherwise the operator relocates it hours later.
  def test_scan_dir_writes_the_fix_before_returning_the_file
    Dir.mktmpdir do |root|
      path = File.join(root, "example.rb")
      File.write(path, "class Example\nend\n")
      scanner = Master::Review::Scan::Scanner.new(rules: [FakeRule.new("FROZEN_LITERAL", true)])
      def scanner.scan(_path, depth: :deep)
        @scan_n = (@scan_n || 0) + 1
        if @scan_n.odd?
          Master::Result.ok([{ rule: "FROZEN_LITERAL", message: "missing frozen", line: 1 }])
        else
          Master::Result.ok([])
        end
      end

      result = scanner.scan_dir(root, autofix: true, autofix_root: root)
      assert result.ok?
      assert_includes File.read(path), "# frozen_string_literal: true"
      assert_equal 1, scanner.stream_autofixes.size
    end
  end
end
