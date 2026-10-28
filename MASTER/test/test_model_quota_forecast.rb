# frozen_string_literal: true

require_relative "test_helper"
require "time"

class ModelQuotaForecastTest < Minitest::Test
  Check = Master::Io::ModelQuota

  def test_missing_openrouter_quota_uses_the_conservative_fifty_request_default
    Master.stub(:models_config, {}) do
      assert_equal 50, Check.daily_limit
    end
  end

  def test_openrouter_quota_override_remains_authoritative
    Master.stub(:models_config, { "openrouter" => { "daily_quota_per_model" => 17 } }) do
      assert_equal 17, Check.daily_limit
    end
  end

  def test_forecast_projects_current_burn_to_the_whole_day
    now = Time.utc(2026, 9, 28, 12, 0, 0)

    Check.stub(:trackable?, true) do
      Check.stub(:daily_limit, 200) do
        Check.stub(:count, 100) do
          forecast = Check.forecast("demo:free", now:)
          assert_equal 100, forecast[:used]
          assert_equal 100, forecast[:remaining]
          assert_in_delta 200, forecast[:projected_daily], 0.01
          assert_in_delta 12, forecast[:exhaustion_hours], 0.01
        end
      end
    end
  end

  def test_burn_risk_turns_on_before_hard_exhaustion
    now = Time.utc(2026, 9, 28, 20, 0, 0)

    Check.stub(:trackable?, true) do
      Check.stub(:daily_limit, 200) do
        Check.stub(:count, 135) do
          assert Check.burn_risk?("demo:free", now:)
        end
      end
    end
  end

  # vm23's deploy boot check runs as another user than the daemon that writes this file
  # owner-only; it must start from an empty day there, while corrupt state still stops it.
  def test_a_quota_file_this_process_may_not_read_is_an_empty_day_and_a_corrupt_one_raises
    Dir.mktmpdir do |dir|
      path = File.join(dir, "model_quota.json")
      File.write(path, "{}")

      Check.stub(:path, path) do
        File.stub(:read, ->(*) { raise Errno::EACCES, path }) { assert_equal 0, Check.count("demo:free") }
        File.write(path, "{ not json")
        assert_raises(RuntimeError) { Check.count("demo:free") }
      end
    end
  end

  def test_non_trackable_model_has_no_forecast
    refute Check.forecast("claude-cli:opus")
    refute Check.burn_risk?("claude-cli:opus")
  end
end
