# frozen_string_literal: true

require_relative "test_helper"
require "fix/scanner"
require_relative "../law/detectors/external_linter_laws"
require "json"
require "tmpdir"

class TestExternalLinterLaws < Minitest::Test
  def with_rubocop_report(stdout:, stderr: "", exitstatus: 0)
    status = Struct.new(:exitstatus).new(exitstatus)
    capture = ->(*_args, **_options) { [stdout, stderr, status] }
    rule = Master::Review::Scan::Laws::RubocopLaw.new(root: Master::ROOT)

    rule.stub(:linter_available?, true) do
      Operator::RubyRunner.stub(:bundle_cmd, "bundle") do
        Master::Io::Exec.stub(:capture3, capture) { yield rule }
      end
    end
  end

  def test_every_file_is_judged_by_the_masters_rubocop_config
    seen = nil
    capture = lambda do |*args, **_options|
      seen = args
      ['{"files":[{"offenses":[]}]}', "", Struct.new(:exitstatus).new(0)]
    end
    rule = Master::Review::Scan::Laws::RubocopLaw.new(root: Master::ROOT)

    rule.stub(:linter_available?, true) do
      Operator::RubyRunner.stub(:bundle_cmd, "bundle") do
        Master::Io::Exec.stub(:capture3, capture) { rule.check("x = 1\n", path: "../OPENBSD/test/sample.rb") }
      end
    end

    assert_equal File.join(Master::ROOT, ".rubocop.yml"), seen[seen.index("--config") + 1]
  end

  # Counts the linter spawns for a run of checks over one real file in a scratch root.
  def spawns_for(contents:)
    Dir.mktmpdir do |root|
      calls = 0
      capture = lambda do |*_args, **_options|
        calls += 1

        ['{"files":[{"offenses":[]}]}', "", Struct.new(:exitstatus).new(0)]
      end

      with_linter(root:, capture:) { |rule, path| check_each(rule:, path:, contents:) }
      calls
    end
  end

  def with_linter(root:, capture:)
    rule = Master::Review::Scan::Laws::RubocopLaw.new(root:)

    rule.stub(:linter_available?, true) do
      Operator::RubyRunner.stub(:bundle_cmd, "bundle") do
        Master::Io::Exec.stub(:capture3, capture) { yield rule, File.join(root, "sample.rb") }
      end
    end
  end

  def check_each(rule:, path:, contents:)
    contents.each do |text|
      File.write(path, text)
      rule.check(text, path:)
    end
  end

  def test_an_unchanged_file_is_linted_once
    assert_equal 1, spawns_for(contents: ["x = 1\n", "x = 1\n", "x = 1\n"])
  end

  def test_a_changed_file_is_linted_again
    assert_equal 2, spawns_for(contents: ["x = 1\n", "x = 2\n", "x = 1\n"])
  end

  # A pre-commit lint judges the staged blob, so the linter is handed that text on stdin under the real
  # path, and never reads the working tree's other version of the file.
  def test_an_overridden_source_is_piped_in_under_its_real_path
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "working = :tree\n")

      seen = []
      capture = lambda do |*args, **options|
        seen << [args, options[:stdin_data]]
        ['{"files":[{"offenses":[]}]}', "", Struct.new(:exitstatus).new(0)]
      end

      with_linter(root:, capture:) do |rule|
        Master::Fix::Scan::SourceOverride.with(path => "staged = :blob\n") { rule.check("", path:) }
      end

      args, stdin = seen.fetch(0)
      assert_equal "staged = :blob\n", stdin
      assert_equal ["--stdin", path], args.last(2)
    end
  end

  def test_empty_stdout_is_a_finding_not_a_clean_lint_result
    with_rubocop_report(stdout: "", stderr: "process failed", exitstatus: 1) do |rule|
      findings = rule.check("def sample; end\n", path: "sample.rb")

      assert_equal 1, findings.size
      assert_match(/scan error/, findings.first.message)
      assert_match(/empty JSON stdout/, findings.first.message)
    end
  end

  def test_malformed_json_is_a_finding_not_a_clean_lint_result
    with_rubocop_report(stdout: "{not json") do |rule|
      findings = rule.check("def sample; end\n", path: "sample.rb")

      assert_equal 1, findings.size
      assert_match(/scan error/, findings.first.message)
      assert_match(/invalid JSON stdout/, findings.first.message)
    end
  end

  def test_valid_json_with_the_wrong_rubocop_shape_is_not_clean
    with_rubocop_report(stdout: "null") do |rule|
      findings = rule.check("def sample; end\n", path: "sample.rb")

      assert_equal 1, findings.size
      assert_match(/invalid JSON report shape/, findings.first.message)
    end
  end

  def test_empty_rubocop_file_array_is_not_clean
    with_rubocop_report(stdout: JSON.generate("files" => [])) do |rule|
      findings = rule.check("def sample; end\n", path: "sample.rb")

      assert_equal 1, findings.size
      assert_match(/invalid JSON report shape/, findings.first.message)
    end
  end

  def test_reek_rejects_a_valid_json_value_that_is_not_a_report_array
    status = Struct.new(:exitstatus).new(0)
    rule = Master::Review::Scan::Laws::ReekLaw.new(root: Master::ROOT)
    rule.stub(:linter_available?, true) do
      Operator::RubyRunner.stub(:bundle_cmd, "bundle") do
        Master::Io::Exec.stub(:capture3, ->(*_args, **_options) { ['{"issues":[]}', "", status] }) do
          findings = rule.check("def sample; end\n", path: "sample.rb")

          assert_equal 1, findings.size
          assert_match(/invalid JSON report shape/, findings.first.message)
        end
      end
    end
  end

  def test_reek_rejects_array_entries_missing_the_fields_it_consumes
    status = Struct.new(:exitstatus).new(0)
    rule = Master::Review::Scan::Laws::ReekLaw.new(root: Master::ROOT)
    rule.stub(:linter_available?, true) do
      Operator::RubyRunner.stub(:bundle_cmd, "bundle") do
        Master::Io::Exec.stub(:capture3, ->(*_args, **_options) { ["[{}]", "", status] }) do
          findings = rule.check("def sample; end\n", path: "sample.rb")

          assert_equal 1, findings.size
          assert_match(/scan error/, findings.first.message)
          assert_match(/invalid JSON report shape/, findings.first.message)
        end
      end
    end
  end

  def test_reek_rejects_non_positive_or_non_integer_line_numbers
    status = Struct.new(:exitstatus).new(0)
    rule = Master::Review::Scan::Laws::ReekLaw.new(root: Master::ROOT)
    report = JSON.generate([{ "smell_type" => "Example", "message" => "example", "lines" => [0, "2"] }])
    rule.stub(:linter_available?, true) do
      Operator::RubyRunner.stub(:bundle_cmd, "bundle") do
        Master::Io::Exec.stub(:capture3, ->(*_args, **_options) { [report, "", status] }) do
          findings = rule.check("def sample; end\n", path: "sample.rb")

          assert_equal 1, findings.size
          assert_match(/invalid JSON report shape/, findings.first.message)
        end
      end
    end
  end

  def test_reek_valid_smell_record_preserves_all_reported_lines
    status = Struct.new(:exitstatus).new(2)
    rule = Master::Review::Scan::Laws::ReekLaw.new(root: Master::ROOT)
    report = JSON.generate([{
      "smell_type" => "Example",
      "message" => "example smell",
      "lines" => [2, 4],
    }])
    rule.stub(:linter_available?, true) do
      Operator::RubyRunner.stub(:bundle_cmd, "bundle") do
        Master::Io::Exec.stub(:capture3, ->(*_args, **_options) { [report, "", status] }) do
          findings = rule.check("def sample; end\n", path: "sample.rb")

          assert_equal [2, 4], findings.map(&:line)
          assert findings.all? { |finding| finding.message.include?("Example") && finding.message.include?("example smell") }
        end
      end
    end
  end

  def test_reek_record_with_empty_lines_still_surfaces_the_smell
    status = Struct.new(:exitstatus).new(0)
    rule = Master::Review::Scan::Laws::ReekLaw.new(root: Master::ROOT)
    report = JSON.generate([{ "smell_type" => "Example", "message" => "example", "lines" => [] }])
    rule.stub(:linter_available?, true) do
      Operator::RubyRunner.stub(:bundle_cmd, "bundle") do
        Master::Io::Exec.stub(:capture3, ->(*_args, **_options) { [report, "", status] }) do
          findings = rule.check("def sample; end\n", path: "sample.rb")

          assert_equal 1, findings.size
          assert_equal 1, findings.first.line
          assert_match(/Example/, findings.first.message)
        end
      end
    end
  end

  def test_valid_offense_report_survives_linter_exit_status_one
    report = JSON.generate(
      "files" => [{
        "offenses" => [{
          "location" => { "line" => 2 },
          "cop_name" => "Style/Example",
          "message" => "example offense",
        }],
      }],
    )

    with_rubocop_report(stdout: report, exitstatus: 1) do |rule|
      findings = rule.check("def sample; end\n", path: "sample.rb")

      assert_equal 1, findings.size
      assert_equal 2, findings.first.line
      assert_match(/Style\/Example/, findings.first.message)
    end
  end
  # With the real linters, a batched run caches exactly what each file alone would report.
  def test_real_batched_findings_match_single_file_runs
    laws = Master::Review::Scan::Laws
    skip "rubocop and reek not installed" unless laws::RubocopLaw.new(root: Master::ROOT).linter_available?("reek")

    Dir.mktmpdir do |root|
      files = linter_fixtures(root)
      [laws::RubocopLaw, laws::ReekLaw].each do |klass|
        assert_equal single_runs(klass.new(root:), files), batched_runs(klass.new(root:), files), klass.name
      end
    end
  end

  def linter_fixtures(root)
    FileUtils.cp(File.join(Master::ROOT, ".rubocop.yml"), root)
    { "a.rb" => "def a(x)\n  x.size\nend\n", "b.rb" => "class B\n  def b = 1\nend\n", "c.rb" => "C = 1\n" }
      .map { |name, text| File.join(root, name).tap { |path| File.write(path, text) } }
  end

  def single_runs(law, files)
    files.map { |file| law.check(File.read(file), path: file).map(&:to_h) }
  end

  # Starts from an empty cache, so every answer comes from the batch.
  def batched_runs(law, files)
    FileUtils.rm_rf(File.join(File.dirname(files.first), ".master"))
    law.prefetch(files)
    files.map { |file| law.check(File.read(file), path: file).map(&:to_h) }
  end

  # One reek process answers a whole batch, and each file then reads its own share from the cache.
  def test_a_batch_prefetch_spawns_once_and_answers_each_file_from_the_cache
    Dir.mktmpdir do |root|
      files = %w[a.rb b.rb].map { |name| File.join(root, name).tap { |path| File.write(path, "x = 1\n") } }
      spawns, findings = prefetch_then_check(root, files)

      assert_equal [1, [1, 0]], [spawns, findings]
    end
  end

  # Prefetches files with a fake reek that reports one smell in the first, then checks each file.
  def prefetch_then_check(root, files)
    report = JSON.generate([{ "smell_type" => "UtilityFunction", "message" => "doubts", "lines" => [1],
                              "source" => files.first }])
    spawns = 0
    capture = ->(*, **) { (spawns += 1) && [report, "", Struct.new(:exitstatus).new(2)] }
    law = Master::Review::Scan::Laws::ReekLaw.new(root:)

    with_fake_reek(law, capture) { law.prefetch(files) }
    [spawns, with_fake_reek(law, capture) { files.map { law.check("", path: _1).size } }]
  end

  def with_fake_reek(law, capture, &block)
    law.stub(:linter_available?, true) do
      Operator::RubyRunner.stub(:bundle_cmd, "bundle") { Master::Io::Exec.stub(:capture3, capture, &block) }
    end
  end
end
