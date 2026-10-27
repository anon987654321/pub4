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

  def test_catalogue_rows_and_labels_cannot_be_mutated_after_validation
    entry = Contract.fetch(:hit_microtiming)

    assert_raises(FrozenError) { entry[:enabled] = true }
    assert_raises(FrozenError) { entry[:status] = :verified }
    assert_raises(FrozenError) { entry[:description].replace("ready") }
    refute JSON.parse(Contract.report(:dilla)).fetch("complete"),
           "a consumer must not be able to promote a cached catalogue row"
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

  def test_readiness_promotion_requires_real_source_methods_and_regression_tests
    verified = {
      status: :verified,
      implementation: "STUDIO/postpro/lib/effects_finish.rb#halation".freeze,
      regression_test: "STUDIO/test/test_tools_postpro.rb#test_halation_returns_more_red_than_blue".freeze
    }.freeze
    unavailable = {
      status: :unavailable,
      evidence: "https://provider.example.invalid/schema/timeout-cancellation".freeze,
      regression_test: ("STUDIO/test/test_tools_replicate.rb" \
                        "#test_a_failed_chain_is_recorded_with_its_stage_error_and_kept_frames").freeze,
    }.freeze
    missing_test = {
      status: :verified,
      implementation: "STUDIO/postpro/lib/effects_finish.rb#halation".freeze,
      regression_test: "STUDIO/test/test_tools_postpro.rb#test_method_that_does_not_exist".freeze
    }.freeze
    missing_method = {
      status: :verified,
      implementation: "STUDIO/postpro/lib/effects_finish.rb#made_up_effect".freeze,
      regression_test: "STUDIO/test/test_tools_postpro.rb#test_halation_returns_more_red_than_blue".freeze
    }.freeze
    mutable_reference = {
      status: :verified,
      implementation: "STUDIO/postpro/lib/effects_finish.rb#halation".dup,
      regression_test: "STUDIO/test/test_tools_postpro.rb#test_halation_returns_more_red_than_blue".freeze
    }.freeze

    assert Contract.valid_implementation_record?(:postpro, :red_sensitive_halation, verified)
    assert Contract.valid_implementation_record?(:replicate, :timeout_cancellation, unavailable)
    refute Contract.valid_implementation_record?(:postpro, :red_sensitive_halation, missing_test)
    refute Contract.valid_implementation_record?(:postpro, :red_sensitive_halation, missing_method)
    refute Contract.valid_implementation_record?(:postpro, :red_sensitive_halation, mutable_reference)
    refute Contract.valid_implementation_record?(:postpro, :not_a_catalogued_direction, verified)
    refute Contract.valid_implementation_record?("postpro", :red_sensitive_halation, verified)
    refute Contract.valid_implementation_record?(:postpro, nil, verified)
    refute Contract.evidence_reference?("provider schema has no such field".freeze)
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
