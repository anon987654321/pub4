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
      assert_equal %w[ROBUSTNESS SINGULARITY LINEARITY PROXIMITY ABSTRACTION DENSITY KERNEL_ADHERENCE PRINCIPLE_MAP], laws
      assert result.value!.violation_count.positive?
      assert_includes bus.events.map(&:first), "self_test:complete"
      assert_includes bus.events.map(&:first), "self_violation"
    end
  end

  def test_only_rules_yml_ids_are_checked_under_singularity
    Dir.mktmpdir do |root|
      write_fixture_tree(root)
      File.write(File.join(root, "data", "patterns.yml"), <<~YAML)
        patterns:
          - id: DUPLICATE_PATTERN
          - id: DUPLICATE_PATTERN
      YAML

      result = Master::Review::Scan::SelfTest.new(root:).call
      singularity = result.value!.checks.find { |check| check.law == "SINGULARITY" }

      assert singularity.findings.any? { |finding| finding[:message].include?("duplicate rule id DUPLICATE_RULE") }
      refute singularity.findings.any? { |finding| finding[:message].include?("duplicate rule id DUPLICATE_PATTERN") }
    end
  end

  def test_singularity_flags_duplicate_top_level_data_keys
    Dir.mktmpdir do |root|
      write_fixture_tree(root)
      File.write(File.join(root, "data", "one.yml"), "alpha:\n  one: true\n")
      File.write(File.join(root, "data", "two.yml"), "alpha:\n  two: true\n")

      result = Master::Review::Scan::SelfTest.new(root:).call(laws: ["SINGULARITY"])
      singularity = result.value!.checks.fetch(0)

      assert singularity.findings.any? { |finding| finding[:message].include?("top-level key alpha") }
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
    FileUtils.mkdir_p(File.join(root, "lib", "judge", "scan", "rules"))
    FileUtils.mkdir_p(File.join(root, "test"))
    File.write(File.join(root, "data", "rules.yml"), rules_yml)
    File.write(File.join(root, "lib", "example.rb"), <<~RUBY)
      class Example
        def risky
          yield
        rescue => e
          nil
        end
      end
    RUBY
    File.write(File.join(root, "lib", "judge", "scan", "rules", "sample_rule.rb"), <<~RUBY)
      class SampleRule
      end
    RUBY
  end

  def rules_yml
    <<~YAML
      self_test:
        laws_apply_to_self:
          ROBUSTNESS: "scan lib/ for bare_rescue + missing timeouts"
          SINGULARITY: "rules.yml entries unique by id"
          LINEARITY: "no nesting_depth > 4 in lib/"
          PROXIMITY: "test files within 1 directory of source"
          ABSTRACTION: "no class > god_class threshold in lib/"
          DENSITY: "no method > long_method threshold in lib/"
      rules:
        - id: DUPLICATE_RULE
          name: one
        - id: DUPLICATE_RULE
          name: two
    YAML
  end
end
