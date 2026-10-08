# frozen_string_literal: true

require_relative "test_helper"
require "time"

class ModelQuotaForecastTest < Minitest::Test
  Gate = Master::Io::ModelQuota

  def test_forecast_projects_current_burn_to_the_whole_day
    now = Time.utc(2026, 9, 28, 12, 0, 0)

    Gate.stub(:trackable?, true) do
      Gate.stub(:daily_limit, 200) do
        Gate.stub(:count, 100) do
          forecast = Gate.forecast("demo:free", now:)
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

    Gate.stub(:trackable?, true) do
      Gate.stub(:daily_limit, 200) do
        Gate.stub(:count, 135) do
          assert Gate.burn_risk?("demo:free", now:)
        end
      end
    end
  end

  def test_non_trackable_model_has_no_forecast
    refute Gate.forecast("claude-cli:opus")
    refute Gate.burn_risk?("claude-cli:opus")
  end
end
