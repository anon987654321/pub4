# frozen_string_literal: true

require "test_helper"

class JobConcurrencyTest < ActiveSupport::TestCase
  PER_ITEM = [ WardrobeMediaJob, FingerprintGarmentJob, CalculateSustainabilityJob ].freeze

  test "per-item media jobs share a key only with the same item" do
    PER_ITEM.each do |job_class|
      assert_equal 1, job_class.concurrency_limit, job_class.name
      assert_equal :discard, job_class.concurrency_on_conflict, job_class.name
      assert_equal job_class.new(5).concurrency_key, job_class.new(5).concurrency_key
      assert_not_equal job_class.new(5).concurrency_key, job_class.new(15).concurrency_key
      assert_not_equal job_class.new(5).concurrency_key, job_class.new(50).concurrency_key
    end
  end

  test "media job keys are distinct across job classes" do
    keys = PER_ITEM.map { |job_class| job_class.new(5).concurrency_key }
    assert_equal keys.uniq, keys
  end

  test "declutter hygiene runs one at a time" do
    assert_equal 1, DeclutterHygieneJob.concurrency_limit
    assert_equal :discard, DeclutterHygieneJob.concurrency_on_conflict
    assert_equal DeclutterHygieneJob.new.concurrency_key, DeclutterHygieneJob.new.concurrency_key
  end
end
