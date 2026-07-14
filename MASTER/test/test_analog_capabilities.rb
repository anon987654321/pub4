# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/reach/analog_capabilities"

class AnalogCapabilitiesTest < Minitest::Test
  Contract = Master::Reach::AnalogCapabilities

  def test_contract_covers_every_original_direction
    assert_equal((1..200).to_a, Contract.all.map { |entry| entry[:id] })
    assert_equal({ postpro: 70, repligen: 60, dilla: 70 }, Contract::GROUPS.transform_values(&:length))
    assert Contract.all.all? { |entry| entry[:enabled] }
    assert Contract.all.all? { |entry| entry[:stage] }
  end

  def test_profiles_are_executable_and_deterministic
    profile = Contract.profile(:dilla, intensity: 0.73, seed: 808)
    assert_equal 808, profile[:seed]
    assert_in_delta 0.73, profile[:intensity]
    assert profile[:capabilities][:hit_microtiming]
    assert profile[:capabilities][:spectral_regression]
  end

  def test_lookup_accepts_stable_id_or_key
    assert_equal :exposure_linked_grain, Contract.fetch(1)[:key]
    assert_equal 200, Contract.fetch(:spectral_regression)[:id]
  end
end
