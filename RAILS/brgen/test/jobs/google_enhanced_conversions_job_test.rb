# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# The upload carries a customer's hashed contact details to Google, so the job
# must stay silent until every Ads variable is set, and a failure must end rather
# than queue copies of the payload behind itself.
class GoogleEnhancedConversionsJobTest < ActiveJob::TestCase
  ENV_KEYS = %w[GOOGLE_ENHANCED_CONVERSIONS GOOGLE_ADS_CUSTOMER_ID GOOGLE_ADS_CONVERSION_ACTION_ID
                GOOGLE_ADS_ACCESS_TOKEN].freeze

  PaidOrder = Struct.new(:id, :paid_at, :google_conversion_uploaded_at, keyword_init: true)

  setup { @saved_env = ENV.to_h.slice(*ENV_KEYS) }

  teardown do
    ENV_KEYS.each { |key| ENV.delete(key) }
    @saved_env.each { |key, value| ENV[key] = value }
  end

  def configure!
    ENV["GOOGLE_ENHANCED_CONVERSIONS"] = "1"
    ENV["GOOGLE_ADS_CUSTOMER_ID"] = "1234567890"
    ENV["GOOGLE_ADS_CONVERSION_ACTION_ID"] = "42"
    ENV["GOOGLE_ADS_ACCESS_TOKEN"] = "token"
  end

  def run_with_upload(upload)
    job = GoogleEnhancedConversionsJob.new(1)
    job.stub(:find_order, PaidOrder.new(id: 1, paid_at: Time.current)) do
      GoogleEnhancedConversions.stub(:upload_purchase!, upload) { job.perform_now }
    end
  end

  test "does nothing when the Ads variables are absent" do
    ENV_KEYS.each { |key| ENV.delete(key) }
    uploaded = false

    assert_no_enqueued_jobs do
      run_with_upload(->(*, **) { uploaded = true })
    end
    assert_not uploaded, "the job uploaded a conversion with Google Ads unconfigured"
  end

  test "a configuration lost mid-flight is discarded, not retried" do
    configure!

    assert_no_enqueued_jobs do
      assert_nothing_raised do
        run_with_upload(->(*, **) { raise GoogleEnhancedConversions::NotConfigured, "gone" })
      end
    end
  end

  test "an API failure retries a bounded number of times, then raises" do
    configure!
    failing = ->(*, **) { raise GoogleEnhancedConversions::ApiError, "503" }

    job = GoogleEnhancedConversionsJob.new(1)
    job.stub(:find_order, PaidOrder.new(id: 1, paid_at: Time.current)) do
      GoogleEnhancedConversions.stub(:upload_purchase!, failing) do
        4.times do
          assert_enqueued_with(job: GoogleEnhancedConversionsJob) { job.perform_now }
        end
        assert_no_enqueued_jobs do
          assert_raises(GoogleEnhancedConversions::ApiError) { job.perform_now }
        end
      end
    end
  end
end
