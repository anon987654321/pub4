# frozen_string_literal: true

require_relative "test_helper"

class TestHeartbeat < Minitest::Test
  class FakeBus
    attr_reader :events

    def initialize = @events = []

    def publish(event, payload = {})
      @events << { event:, payload: }
    end
  end

  def test_self_test_job_is_enabled_hourly_from_config
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "data"))
      File.write(File.join(root, "data", "heartbeat.yml"), <<~YAML)
        - name: self_test
          action: self_test
          interval_seconds: 3600
          enabled: true
      YAML

      heartbeat = Master::Loop::Heartbeat.new(root:)

      assert_includes heartbeat.list, "self_test: every 60m"
    end
  end

  def test_self_test_heartbeat_publishes_clean_scan_metrics
    Dir.mktmpdir do |root|
      write_heartbeat_root(root, <<~YAML)
        self_test:
          laws_apply_to_self: {}
      YAML
      bus = FakeBus.new
      heartbeat = Master::Loop::Heartbeat.new(root:, scanner: Object.new, event_bus: bus)

      heartbeat.run_due!

      clean = bus.events.find { |entry| entry[:event] == "heartbeat:scan_clean" }
      assert clean
      assert_equal 0, clean[:payload][:violations]
      assert_operator clean[:payload][:last_fixed], :>, 0
    end
  end

  def test_self_test_heartbeat_publishes_violation_metrics_with_last_fixed
    Dir.mktmpdir do |root|
      write_heartbeat_root(root, <<~YAML)
        self_test:
          laws_apply_to_self: {}
        rules:
          - id: DUPLICATE
            name: one
          - id: DUPLICATE
            name: two
      YAML
      FileUtils.mkdir_p(File.join(root, ".master"))
      File.write(File.join(root, ".master", "heartbeat_state.yml"), { "self_test" => { "last_fixed" => 123 } }.to_yaml)
      bus = FakeBus.new
      heartbeat = Master::Loop::Heartbeat.new(root:, scanner: Object.new, event_bus: bus)

      heartbeat.run_due!

      violations = bus.events.find { |entry| entry[:event] == "heartbeat:violations" }
      assert violations
      assert_operator violations[:payload][:violations], :>, 0
      assert_equal 123, violations[:payload][:last_fixed]
    end
  end

  private

  def write_heartbeat_root(root, rules_yaml)
    FileUtils.mkdir_p(File.join(root, "data"))
    FileUtils.mkdir_p(File.join(root, "lib"))
    File.write(File.join(root, "data", "heartbeat.yml"), <<~YAML)
      - name: self_test
        action: self_test
        interval_seconds: 0
        enabled: true
    YAML
    File.write(File.join(root, "data", "rules.yml"), rules_yaml)
  end
end
