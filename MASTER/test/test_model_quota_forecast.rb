# frozen_string_literal: true

require_relative "test_helper"
require "time"

class ModelQuotaForecastTest < Minitest::Test
  Check = Master::Io::ModelQuota

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

  def test_non_trackable_model_has_no_forecast
    refute Check.forecast("claude-cli:opus")
    refute Check.burn_risk?("claude-cli:opus")
  end
end
