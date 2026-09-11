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

    def scan(_path, depth: :deep, **)
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

  # AstFixer used to transform and write in one call, so the only thing between a
  # misfiring transform and the file was the transform's own judgement — and the
  # trial run TODO.md records made three writes, two of them damage, one of which
  # `node --check` waved through. The candidate is judged before it becomes the
  # file now, by the same guard every constitutional write passes.
  class RefusingGuard
    def verdict(path:, content:)
      Master::Review::Scan::WriteGuard::Verdict.new(
        introduced: [{ rule: :NO_GOD_CLASS, line: 1, message: "would introduce #{path}/#{content.size}", severity: :error }],
      )
    end
  end

  def test_a_refused_candidate_never_reaches_the_file
    Dir.mktmpdir do |root|
      path = File.join(root, "example.rb")
      original = "class Example\nend\n"
      File.write(path, original)
      autofix = Master::Review::Scan::MechanicalAutofix.new(
        scanner: FakeScanner.new(findings_by_pass: [], rules: [FakeRule.new("FROZEN_LITERAL", true)]),
        root:,
        write_guard: RefusingGuard.new,
      )

      applied = autofix.apply([[path, Master::Result.ok([finding("FROZEN_LITERAL")])]])

      assert_empty applied
      assert_equal original, File.read(path), "a blocked candidate was written anyway"
    end
  end

  # And only what a fix introduces can refuse it, or the first repair of a file
  # carrying debt is the one thing the guard stops.
  def test_a_clean_candidate_still_lands
    Dir.mktmpdir do |root|
      path = File.join(root, "example.rb")
      File.write(path, "class Example\nend\n")
      autofix = Master::Review::Scan::MechanicalAutofix.new(
        scanner: FakeScanner.new(findings_by_pass: [], rules: [FakeRule.new("FROZEN_LITERAL", true)]),
        root:,
      )

      applied = autofix.apply([[path, Master::Result.ok([finding("FROZEN_LITERAL")])]])

      assert_equal 1, applied.size
      # source-assertion: ok — reading back what the fixer wrote is the only way to see it landed
      assert_includes File.read(path), "# frozen_string_literal: true"
    end
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

      # source-assertion: ok — reading back what the fixer wrote is the only way to see it landed

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
    detail = Master::CLI::CommandRegistry.help_text("review")
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
      def scanner.scan(_path, depth: :deep, **)
        @scan_n = (@scan_n || 0) + 1
        if @scan_n.odd?
          Master::Result.ok([{ rule: "FROZEN_LITERAL", message: "missing frozen", line: 1 }])
        else
          Master::Result.ok([])
        end
      end

      result = scanner.scan_dir(root, autofix: true, autofix_root: root)
      assert result.ok?
      # source-assertion: ok — reading back what the fixer wrote is the only way to see it landed
      assert_includes File.read(path), "# frozen_string_literal: true"
      assert_equal 1, scanner.stream_autofixes.size
    end
  end
end
