# frozen_string_literal: true

require_relative "test_helper"

class TestSelfScan < Minitest::Test
  Finding = Data.define(:rule, :message, :line, :severity, :fix, :tags)

  class FakeScanner
    attr_reader :rules

    def initialize(findings, rules: [])
      @findings = findings
      @rules = rules.empty? ? [Object.new, Object.new] : rules
    end

    def scan_dir(path, depth:, stream: false)
      Master::Result.ok([[File.join(path, "example.rb"), Master::Result.ok(@findings)]])
    end
  end

  FakeRule = Struct.new(:id, :auto_fix)

  class FakeBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(event, payload = {})
      @events << [event, payload]
    end
  end

  def test_summarizes_rules_and_violations
    scanner = FakeScanner.new([finding("NO_PUTS"), finding("LONG_LINE")])
    bus = FakeBus.new

    result = Master::Review::Scan::SelfScan.new(scanner:, root: "/tmp/master", event_bus: bus).call

    assert result.ok?
    assert_equal "judge: lib/ 2 rules, 2 violations", result.value!.line
    assert_includes bus.events.map(&:first), "self_scan:complete"
    assert_includes bus.events.map(&:first), "self_violation"
  end

  def test_clean_scan_does_not_publish_self_violation
    bus = FakeBus.new

    result = Master::Review::Scan::SelfScan.new(
      scanner: FakeScanner.new([]),
      root: "/tmp/master",
      event_bus: bus,
    ).call

    assert result.ok?
    assert_equal "judge: lib/ 2 rules, 0 violations", result.value!.line
    refute_includes bus.events.map(&:first), "self_violation"
  end

  def test_autofix_applies_ast_fixer_to_autofixable_findings
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      path = File.join(root, "lib", "example.rb")
      File.write(path, "class Example\nend\n")
      scanner = FakeScanner.new([finding("FROZEN_LITERAL")], rules: [FakeRule.new("FROZEN_LITERAL", true)])
      bus = FakeBus.new

      result = Master::Review::Scan::SelfScan.new(scanner:, root:, event_bus: bus).call(autofix: true)

      assert result.ok?
      # source-assertion: ok — reading back what the fixer wrote is the only way to see it landed
      assert_includes File.read(path), "# frozen_string_literal: true"
      assert_equal "lib/example.rb", result.value!.autofixes.first[:path]
      assert_includes bus.events.map(&:first), "self_autofix:applied"
    end
  end

  def test_self_scan_counts_data_yml_singularity_findings
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "data"))
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "data", "rules.yml"), <<~YAML)
        self_test:
          laws_apply_to_self:
            SINGULARITY: "rules.yml entries unique by id"
        rules:
          - id: DUPLICATE_RULE
          - id: DUPLICATE_RULE
      YAML
      scanner = FakeScanner.new([])

      result = Master::Review::Scan::SelfScan.new(scanner:, root:).call

      assert result.ok?
      assert_equal 1, result.value!.violation_count
      assert_match(/1 violations/, result.value!.line)
    end
  end

  def test_master_lib_self_scan_has_zero_violations
    skip "full lib scan exceeds unit-test budget — run MASTER_SAFE_MODE=1 bin/cli /self" unless ENV["MASTER_INTEGRATION"]

    scanner = Master.bootstrap_container(root: Master::ROOT)[:scanner]
    result = Master::Review::Scan::SelfScan.new(scanner:, root: Master::ROOT).call

    assert result.ok?
    assert_equal 0, result.value!.violation_count, format_self_scan_failures(result.value!.pairs)
  end

  private

  def finding(rule)
    Finding.new(rule:, message: "violation", line: 1, severity: :warning, fix: nil, tags: [])
  end

  def format_self_scan_failures(pairs)
    pairs.flat_map do |path, file_result|
      Master::Result.wrap(file_result).value_or([]).map do |finding|
        "#{path}:#{finding[:line]} #{finding[:rule]} #{finding[:message]}"
      end
    end.first(20).join("\n")
  end
end
