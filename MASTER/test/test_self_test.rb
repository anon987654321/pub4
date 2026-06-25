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

      result = Master::Judge::Scan::SelfTest.new(root:, event_bus: bus).call

      assert result.ok?
      laws = result.value!.checks.map(&:law)
      assert_equal %w[ROBUSTNESS SINGULARITY LINEARITY PROXIMITY ABSTRACTION DENSITY KERNEL_ADHERENCE], laws
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

      result = Master::Judge::Scan::SelfTest.new(root:).call
      singularity = result.value!.checks.find { |check| check.law == "SINGULARITY" }

      assert singularity.findings.any? { |finding| finding[:message].include?("duplicate rule id DUPLICATE_RULE") }
      refute singularity.findings.any? { |finding| finding[:message].include?("duplicate rule id DUPLICATE_PATTERN") }
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
        rescue
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
