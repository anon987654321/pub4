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

    result = Master::Judge::Scan::SelfScan.new(scanner:, root: "/tmp/master", event_bus: bus).call

    assert result.ok?
    assert_equal "judge: lib/ 2 rules, 2 violations", result.value!.line
    assert_includes bus.events.map(&:first), "self_scan:complete"
    assert_includes bus.events.map(&:first), "self_violation"
  end

  def test_clean_scan_does_not_publish_self_violation
    bus = FakeBus.new

    result = Master::Judge::Scan::SelfScan.new(
      scanner: FakeScanner.new([]),
      root: "/tmp/master",
      event_bus: bus
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

      result = Master::Judge::Scan::SelfScan.new(scanner:, root:, event_bus: bus).call(autofix: true)

      assert result.ok?
      assert_includes File.read(path), "# frozen_string_literal: true"
      assert_equal "lib/example.rb", result.value!.autofixes.first[:path]
      assert_includes bus.events.map(&:first), "self_autofix:applied"
    end
  end

  private

  def finding(rule)
    Finding.new(rule:, message: "violation", line: 1, severity: :warning, fix: nil, tags: [])
  end
end
