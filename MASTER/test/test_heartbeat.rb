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

  # Heartbeat#load_jobs reads data/patterns.yml#heartbeat. These fixtures used
  # to write data/heartbeat.yml, a file that does not exist in the product, so
  # every test here silently ran Heartbeat's *default* job list instead of the
  # one it had just written — including snapshot and prune_undo. This one
  # passed only because the default self_test interval happens to be hourly.
  def test_self_test_job_is_enabled_hourly_from_config
    Dir.mktmpdir do |root|
      write_heartbeat_jobs(root, <<~YAML)
        - name: self_test
          action: self_test
          interval_seconds: 3600
          enabled: true
      YAML

      heartbeat = Master::Fix::Heartbeat.new(root:)

      assert_includes heartbeat.list, "self_test: every 60m"
      refute_includes heartbeat.list, "snapshot", "default jobs must not leak in when config is present"
    end
  end

  def test_self_test_heartbeat_publishes_clean_scan_metrics
    Dir.mktmpdir do |root|
      write_heartbeat_root(root, <<~YAML)
        self_test:
          laws_apply_to_self: {}
      YAML
      bus = FakeBus.new
      heartbeat = Master::Fix::Heartbeat.new(root:, scanner: Object.new, event_bus: bus)

      heartbeat.run_due!

      clean = bus.events.find { |entry| entry[:event] == "heartbeat:scan_clean" }
      assert clean
      assert_equal 0, clean[:payload][:violations]
      assert_operator clean[:payload][:last_fixed], :>, 0
    end
  end

  def test_personal_pulse_returns_heartbeat_ok_when_nothing_to_say
    Dir.mktmpdir do |root|
      write_heartbeat_jobs(root, <<~YAML)
        - name: personal_pulse
          action: personal_pulse
          interval_seconds: 0
          enabled: true
      YAML

      results = Master::Fix::Heartbeat.new(root:).run_due!
      pulse = results.find { |row| row[:name] == "personal_pulse" }
      assert pulse
      assert_equal "HEARTBEAT_OK", pulse[:result]
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
      heartbeat = Master::Fix::Heartbeat.new(root:, scanner: Object.new, event_bus: bus)

      heartbeat.run_due!

      violations = bus.events.find { |entry| entry[:event] == "heartbeat:violations" }
      assert violations
      assert_operator violations[:payload][:violations], :>, 0
      assert_equal 123, violations[:payload][:last_fixed]
    end
  end

  private

  def write_heartbeat_jobs(root, jobs_yaml)
    FileUtils.mkdir_p(File.join(root, "data"))
    File.write(File.join(root, "data", "patterns.yml"), { "heartbeat" => YAML.safe_load(jobs_yaml) }.to_yaml)
  end

  def write_heartbeat_root(root, rules_yaml)
    FileUtils.mkdir_p(File.join(root, "lib"))
    write_heartbeat_jobs(root, <<~YAML)
      - name: self_test
        action: self_test
        interval_seconds: 0
        enabled: true
    YAML
    File.write(File.join(root, "data", "rules.yml"), rules_yaml)
    # SelfTest's PRINCIPLE_MAP check reports "missing data/principle_map.yml"
    # against a bare fixture root, which made the "clean scan" case impossible
    # to reach — it always published heartbeat:violations instead. An empty map
    # satisfies integrity (nothing to be inconsistent about).
    File.write(File.join(root, "data", "principle_map.yml"),
               { "schema" => 1, "version" => "test-fixture", "principles" => {} }.to_yaml)
  end
end
