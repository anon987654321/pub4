# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

class TestSelfTest < Minitest::Test
  class FakeBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(event, payload = {})
      @events << [event, payload]
    end
  end

  def test_runs_all_configured_law_checks
    Dir.mktmpdir do |root|
      write_fixture_tree(root)
      bus = FakeBus.new

      result = Master::Review::Scan::SelfTest.new(root:, event_bus: bus).call

      assert result.ok?
      laws = result.value!.checks.map(&:law)
      assert_equal %w[LAW_INTEGRITY ROBUSTNESS SINGULARITY LINEARITY PROXIMITY ABSTRACTION DENSITY KERNEL_ADHERENCE LAW_MAP], laws
      assert result.value!.violation_count.positive?
      assert_includes bus.events.map(&:first), "self_test:complete"
      assert_includes bus.events.map(&:first), "self_violation"
    end
  end

  def test_malformed_data_yaml_is_a_singularity_finding
    Dir.mktmpdir do |root|
      write_fixture_tree(root)
      path = File.join(root, "data", "broken.yml")
      File.write(path, "broken: [\n")

      result = Master::Review::Scan::SelfTest.new(root:).call(laws: ["SINGULARITY"])
      findings = result.value!.checks.fetch(0).findings

      assert findings.any? { |finding| finding[:path] == path && finding[:message].include?("malformed YAML") }
    end
  end

  def test_timeout_audit_read_failure_is_not_reported_as_clean
    Dir.mktmpdir do |root|
      write_fixture_tree(root)
      FileUtils.mkdir_p(File.join(root, "lib", "core"))
      path = File.join(root, "lib", "core", "unreadable.rb")
      File.write(path, "require 'open3'\n")
      audit = Master::Review::Scan::SelfTest.new(root:)
      audit.define_singleton_method(:read_text) do |candidate|
        raise Errno::EACCES, candidate if candidate == path
        File.read(candidate, encoding: "UTF-8")
      end

      findings = audit.send(:timeout_findings)
      assert findings.any? { |finding| finding[:path] == path && finding[:message].include?("unmeasured, not clean") }
    end
  end

  def test_deploy_file_read_and_size_failures_become_findings
    Dir.mktmpdir do |workspace|
      root = File.join(workspace, "MASTER")
      deploy = File.join(workspace, "OPENBSD")
      FileUtils.mkdir_p(root)
      FileUtils.mkdir_p(deploy)
      path = File.join(deploy, "OPERATOR.rb")
      File.write(path, "def example; end\n")
      audit = Master::Review::Scan::SelfTest.new(root:)
      audit.define_singleton_method(:read_text) do |candidate|
        raise Errno::EACCES, candidate if candidate == path
        File.read(candidate, encoding: "UTF-8")
      end

      read_findings = audit.send(:deploy_god_class_findings)
      assert read_findings.any? { |finding| finding[:path] == path && finding[:message].include?("ABSTRACTION unmeasured") }

      original_size = File.method(:size)
      File.stub(:size, lambda { |candidate|
        raise Errno::EACCES, candidate if candidate == path
        original_size.call(candidate)
      }) do
        size_findings = audit.send(:deploy_small_files_findings)
        assert size_findings.any? { |finding| finding[:path] == path && finding[:message].include?("DENSITY unmeasured") }
      end
    end
  end

  def test_only_law_ids_are_checked_under_singularity
    Dir.mktmpdir do |root|
      write_fixture_tree(root)
      File.write(File.join(root, "data", "patterns.yml"), <<~YAML)
        patterns:
          - id: DUPLICATE_PATTERN
          - id: DUPLICATE_PATTERN
      YAML

      result = Master::Review::Scan::SelfTest.new(root:).call
      singularity = result.value!.checks.find { |check| check.law == "SINGULARITY" }

      assert singularity.findings.any? { |finding| finding[:message].include?("duplicate law id DUPLICATE_LAW") }
      refute singularity.findings.any? { |finding| finding[:message].include?("duplicate law id DUPLICATE_PATTERN") }
    end
  end

  def test_singularity_does_not_report_generic_cross_file_keys
    Dir.mktmpdir do |root|
      write_fixture_tree(root)
      File.write(File.join(root, "data", "one.yml"), "law:\n  one: true\n")
      File.write(File.join(root, "data", "two.yml"), "law:\n  two: true\n")

      singularity = Master::Review::Scan::SelfTest.new(root:).call(laws: ["SINGULARITY"]).value!.checks.fetch(0)
      refute singularity.findings.any? { |finding| finding[:message].include?("top-level fact law") }
    end
  end

  def test_data_singularity_flags_duplicate_top_level_data_facts
    Dir.mktmpdir do |root|
      write_fixture_tree(root)
      File.write(File.join(root, "data", "one.yml"), "alpha:\n  one: true\n")
      File.write(File.join(root, "data", "two.yml"), "alpha:\n  one: true\n")

      findings = Master::Review::Scan::SelfTest.new(root:).data_singularity_findings
      assert findings.any? { |finding| finding[:message].include?("top-level fact alpha") }
    end
  end

  def test_singularity_allows_independent_registry_values
    Dir.mktmpdir do |root|
      write_fixture_tree(root)
      File.write(File.join(root, "data", "one.yml"), "law:\n  one: true\n")
      File.write(File.join(root, "data", "two.yml"), "law:\n  two: true\n")

      singularity = Master::Review::Scan::SelfTest.new(root:).call(laws: ["SINGULARITY"]).value!.checks.fetch(0)
      refute singularity.findings.any? { |finding| finding[:message].include?("top-level fact law") }
    end
  end

  def test_data_singularity_ignores_namespaced_data_registers
    Dir.mktmpdir do |root|
      write_fixture_tree(root)
      FileUtils.mkdir_p(File.join(root, "data", "laws"))
      File.write(File.join(root, "data", "laws", "one.yml"), "alpha:\n  one: true\n")
      File.write(File.join(root, "data", "two.yml"), "alpha:\n  two: true\n")

      findings = Master::Review::Scan::SelfTest.new(root:).data_singularity_findings
      refute findings.any? { |finding| finding[:path].include?("/data/laws/") }
    end
  end

  def test_real_rubrics_share_dimension_namespace_without_becoming_singular_runtime_debt
    findings = Master::Review::Scan::SelfTest.new(root: Master::ROOT).data_singularity_findings

    # Parenthesised: unwrapped, the do block bound to refute, and any? with no
    # block asked whether there was any finding at all.
    rubrics = %w[dialogue_rubric.yml visual_rubric.yml].map { |name| File.join(Master::ROOT, "data", name) }
    refute(findings.any? do |finding|
      finding[:message].include?("top-level fact dimensions") && rubrics.include?(finding[:path])
    end)
  end

  def test_shell_nesting_ignores_inline_closers_and_quoted_programs
    Dir.mktmpdir do |workspace|
      root = File.join(workspace, "MASTER")
      openbsd = File.join(workspace, "OPENBSD")
      FileUtils.mkdir_p(root)
      FileUtils.mkdir_p(openbsd)

      File.write(File.join(openbsd, "fixture.sh"), <<~ZSH)
        #!/usr/bin/env zsh
        for item in one two; do echo "$item"; done
        if true; then echo yes; fi
        awk '
          if ($1 == "one") print
          if ($1 == "two") print
        '
        if true; then
          if true; then
            if true; then
              if true; then
                if true; then
                  print yes
                fi
              fi
            fi
          fi
        fi
      ZSH

      findings = Master::Review::Scan::SelfTest.new(root:).send(:deploy_nesting_findings)
      assert_equal 1, findings.size
      assert_equal 12, findings.first[:line]
    end
  end

  def test_openbsd_deploy_corpus_uses_real_paths_and_skips_tests
    Dir.mktmpdir do |workspace|
      root = File.join(workspace, "MASTER")
      openbsd = File.join(workspace, "OPENBSD")
      FileUtils.mkdir_p(File.join(openbsd, "dev"))
      FileUtils.mkdir_p(File.join(openbsd, "test"))

      operator = File.join(openbsd, "OPERATOR.sh")
      stage = File.join(openbsd, "dev", "operator_stage_1.zsh")
      test_file = File.join(openbsd, "test", "fixture.rb")
      File.write(operator, "#!/usr/bin/env zsh\n")
      File.write(stage, "#!/usr/bin/env zsh\n")
      File.write(test_file, "def fixture; end\n")

      paths = Master::Review::Scan::SelfTest.new(root:).send(:build_deploy_paths)

      assert_includes paths, operator
      assert_includes paths, stage
      refute_includes paths, test_file
    end
  end

  private

  def write_fixture_tree(root)
    FileUtils.mkdir_p(File.join(root, "data"))
    FileUtils.mkdir_p(File.join(root, "lib", "review", "scan", "laws"))
    FileUtils.mkdir_p(File.join(root, "test"))
    File.write(File.join(root, "data", "laws.yml"), laws_yml)
    File.write(File.join(root, "lib", "example.rb"), <<~RUBY)
      class Example
        def risky
          yield
        rescue => e
          nil
        end
      end
    RUBY
    File.write(File.join(root, "lib", "review", "scan", "laws", "sample_law.rb"), <<~RUBY)
      class SampleRule
      end
    RUBY
  end

  def laws_yml
    <<~YAML
      self_test:
        laws_apply_to_self:
          LAW_INTEGRITY: "executable law lifecycle and index remain valid"
          ROBUSTNESS: "scan lib/ for bare_rescue + missing timeouts"
          SINGULARITY: "laws.yml entries unique by id"
          LINEARITY: "no nesting_depth > 4 in lib/"
          PROXIMITY: "test files within 1 directory of source"
          ABSTRACTION: "no class > god_class threshold in lib/"
          DENSITY: "no method > long_method threshold in lib/"
      DUPLICATE_LAW:
        id: DUPLICATE_LAW
        name: one
      OTHER:
        id: DUPLICATE_LAW
        name: two
    YAML
  end
end
