# frozen_string_literal: true

require_relative "test_helper"

class TestHeartbeat < Minitest::Test
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
end
