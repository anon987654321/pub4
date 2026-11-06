# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

class TestScanAutofix < Minitest::Test
  FakeRule = Struct.new(:id, :auto_fix)

  class FakeScanner
    attr_reader :laws, :scan_calls

    def initialize(findings_by_pass:, laws: [])
      @findings_by_pass = findings_by_pass
      @laws = laws
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

  # MechanicalAutofix leaves a file alone when git cannot say it is clean, so
  # a write test needs a repository to ask.
  def git_tmpdir(&block)
    Dir.mktmpdir do |root|
      _out, status = Master::Io::Exec.capture2e("git", "-C", root, "init", "-q")
      raise "git init failed" unless status.success?

      block.call(root)
    end
  end

  def finding(rule)
    {
      law: rule,
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
  # trial run the old backlog records made three writes, two of them damage, one of which
  # `node --check` waved through. The candidate is judged before it becomes the
  # file now, by the same guard every constitutional write passes.
  class RefusingGuard
    def verdict(path:, content:)
      Master::Fix::WriteGuard::Verdict.new(
        introduced: [{ law: :NO_GOD_CLASS, line: 1, message: "would introduce #{path}/#{content.size}", severity: :error }],
      )
    end
  end

  def test_a_refused_candidate_never_reaches_the_file
    Dir.mktmpdir do |root|
      path = File.join(root, "example.rb")
      original = "class Example\nend\n"
      File.write(path, original)
      autofix = Master::Fix::Scan::MechanicalAutofix.new(
        scanner: FakeScanner.new(findings_by_pass: [], laws: [FakeRule.new("FROZEN_LITERAL", true)]),
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
    git_tmpdir do |root|
      path = File.join(root, "example.rb")
      File.write(path, "class Example\nend\n")
      autofix = Master::Fix::Scan::MechanicalAutofix.new(
        scanner: FakeScanner.new(findings_by_pass: [], laws: [FakeRule.new("FROZEN_LITERAL", true)]),
        root:,
      )

      applied = autofix.apply([[path, Master::Result.ok([finding("FROZEN_LITERAL")])]])

      assert_equal 1, applied.size
      # source-assertion: ok — reading back what the fixer wrote is the only way to see it landed
      assert_includes File.read(path), "# frozen_string_literal: true"
    end
  end

  # The fix loop's fast stage and /scan share this one writer; a file the
  # dirty predicate names is never touched.
  def test_rewrite_leaves_a_dirty_file_alone
    Dir.mktmpdir do |root|
      path = File.join(root, "example.rb")
      File.write(path, "class Example\nend\n")
      autofix = Master::Fix::Scan::MechanicalAutofix.new(scanner: nil, root:, dirty: ->(candidate) { candidate == path })

      outcome = autofix.rewrite(path, File.read(path))

      assert_equal :dirty, outcome.status
      assert_equal "class Example\nend\n", File.read(path)
    end
  end

  def test_rewrite_writes_a_clean_file_and_reports_the_new_content
    Dir.mktmpdir do |root|
      path = File.join(root, "example.rb")
      File.write(path, "class Example\nend\n")
      autofix = Master::Fix::Scan::MechanicalAutofix.new(scanner: nil, root:, dirty: ->(_) { false })

      outcome = autofix.rewrite(path, File.read(path))

      assert_equal :written, outcome.status
      assert_equal File.read(path), outcome.content
    end
  end

  def test_mechanical_autofix_enabled_by_default
    assert Master::Fix::Scan::MechanicalAutofix.enabled?(env: {})
    assert Master::Fix::Scan::MechanicalAutofix.enabled?(env: { "MASTER_SCAN_AUTOFIX" => "1" })
    refute Master::Fix::Scan::MechanicalAutofix.enabled?(env: { "MASTER_SCAN_AUTOFIX" => "0" })
  end

  def test_observe_applies_ast_fixer_then_rescans
    git_tmpdir do |root|
      path = File.join(root, "example.rb")
      File.write(path, "class Example\nend\n")
      scanner = FakeScanner.new(
        findings_by_pass: [[finding("FROZEN_LITERAL")], []],
        laws: [FakeRule.new("FROZEN_LITERAL", true)],
      )

      out = Master::CLI::CommandRegistry.observe(
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

  def test_observe_dry_run_does_not_write
    Dir.mktmpdir do |root|
      path = File.join(root, "example.rb")
      original = "class Example\nend\n"
      File.write(path, original)
      scanner = FakeScanner.new(
        findings_by_pass: [[finding("FROZEN_LITERAL")]],
        laws: [FakeRule.new("FROZEN_LITERAL", true)],
      )

      snapshot = File.join(root, ".master", "scan_last.txt")
      refute File.exist?(snapshot)

      out = Master::CLI::CommandRegistry.observe(
        scanner:,
        root:,
        ctx: { args: "#{path} --dry-run" },
      )

      assert_equal original, File.read(path)
      refute File.exist?(snapshot), "dry-run created a working-tree snapshot"
      assert_includes out, "dry-run:"
      refute_includes out, "autofixed:"
    end
  end

  def test_observe_no_autofix_flag_skips_writes
    Dir.mktmpdir do |root|
      path = File.join(root, "example.rb")
      original = "class Example\nend\n"
      File.write(path, original)
      scanner = FakeScanner.new(
        findings_by_pass: [[finding("FROZEN_LITERAL")]],
        laws: [FakeRule.new("FROZEN_LITERAL", true)],
      )

      out = Master::CLI::CommandRegistry.observe(
        scanner:,
        root:,
        ctx: { args: "#{path} --no-autofix" },
      )

      assert_equal original, File.read(path)
      refute_includes out, "autofixed:"
      assert_match(/violation/i, out)
    end
  end

  def test_help_documents_the_flag_that_holds_the_repair_back
    assert_includes Master::CLI::CommandRegistry.help_text("fix"), "--dry-run"
  end

  # The old pass walked the whole tree, then fixed, then walked it again.
  # A finding must be written on the file that just produced it, before the
  # walker moves on — otherwise the operator relocates it hours later.
  def test_scan_dir_writes_the_fix_before_returning_the_file
    git_tmpdir do |root|
      path = File.join(root, "example.rb")
      File.write(path, "class Example\nend\n")
      scanner = Master::Fix::Scanner.new(laws: [FakeRule.new("FROZEN_LITERAL", true)])
      def scanner.scan(_path, depth: :deep, **)
        @scan_n = (@scan_n || 0) + 1
        if @scan_n.odd?
          Master::Result.ok([{ law: "FROZEN_LITERAL", message: "missing frozen", line: 1 }])
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
