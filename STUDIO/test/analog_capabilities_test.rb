# frozen_string_literal: true

require "minitest/autorun"
require "json"
require_relative "../postpro/analog_capabilities"

class AnalogCapabilitiesTest < Minitest::Test
  Contract = Studio::AnalogCapabilities

  def test_contract_catalogues_every_direction_without_claiming_unverified_readiness
    assert_equal((1..200).to_a, Contract.all.map { |entry| entry[:id] })
    assert_equal({ postpro: 70, replicate: 60, dilla: 70 }, Contract::GROUPS.transform_values(&:length))
    assert Contract.all.all? { |entry| entry[:catalogued] }
    assert Contract.all.all? { |entry| entry[:stage] }
    assert Contract.all.all? { |entry| entry[:status] == :unverified && entry[:enabled].nil? }
    assert Contract.validate!
  end

  def test_readiness_report_separates_catalogue_coverage_from_verified_support
    report = JSON.parse(Contract.report(:dilla))

    assert_equal 70, report.fetch("count")
    assert_equal true, report.fetch("catalog_complete")
    assert_equal false, report.fetch("complete")
    assert_equal 0, report.fetch("enabled_count")
    assert_equal 70, report.fetch("unverified_count")
    assert_equal "unverified", report.fetch("capabilities").first.fetch("status")
    assert_nil report.fetch("capabilities").first.fetch("enabled")
  end

  def test_profiles_are_deterministic_without_promoting_unverified_directions
    profile = Contract.profile(:dilla, intensity: 0.73, seed: 808)
    assert_equal 808, profile[:seed]
    assert_in_delta 0.73, profile[:intensity]
    assert_nil profile[:capabilities][:hit_microtiming]
    assert_nil profile[:capabilities][:spectral_regression]
    assert_equal :unverified, profile[:capability_status][:hit_microtiming]
    assert_equal :unverified, profile[:capability_status][:spectral_regression]
  end

  def test_lookup_accepts_stable_id_or_key
    assert_equal :exposure_linked_grain, Contract.fetch(1)[:key]
    assert_equal 200, Contract.fetch(:spectral_regression)[:id]
  end
end
