# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class WeatherTest < ActiveSupport::TestCase
  setup { Rails.cache.delete(Weather::CACHE_KEY) }
  teardown { Rails.cache.delete(Weather::CACHE_KEY) }

  test "the forecast is fetched once and served from cache after that" do
    calls = 0
    forecast = { temp: 7.0, code: 0, wind: 1.0, description: "Clear" }

    Weather.stub(:fetch, -> { calls += 1; forecast }) do
      3.times { assert_equal forecast, Weather.today }
    end

    assert_equal 1, calls, "the dashboard refetched the forecast on every render"
  end

  test "a failed fetch is cached too, so an upstream outage is not one call per page view" do
    calls = 0

    Weather.stub(:fetch, -> { calls += 1; nil }) do
      3.times { assert_nil Weather.today }
    end

    assert_equal 1, calls, "a dead upstream was retried on every render"
  end

  test "a raising cache never takes the dashboard down with it" do
    Rails.cache.stub(:fetch, ->(*) { raise "cache exploded" }) do
      assert_nil Weather.today
    end
  end

  test "weather codes decode to the descriptions StyleAssistant matches on" do
    assert_equal "Rainy", Weather.decode_weather(61)
    assert_equal "Snowy", Weather.decode_weather(73)
    assert_equal "Clear", Weather.decode_weather(0)
  end
end
