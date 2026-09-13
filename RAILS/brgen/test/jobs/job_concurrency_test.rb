# frozen_string_literal: true

require "test_helper"

# retry_on is not uniqueness. Every recurring or fan-out job here declares a
# Solid Queue concurrency key, and the key has to compute from the job's real
# arguments — a lambda whose arity does not match raises only when the job is
# enqueued in production.
class JobConcurrencyTest < ActiveSupport::TestCase
  CASES = {
    AffiliateImportJob => [],
    NightlySearchIndexRebuildJob => [],
    ExpiredStoriesSweepJob => [],
    ComposeNewsletterEditionJob => [ "weekly_deals", "Bergen" ],
    LinkConverterSyncJob => [],
    UserPurgeJob => [],
    GenerateBlurhashJob => [ 42 ],
    ChannelBotReplyJob => [ 7 ],
    ListingExpiryJob => [],
    SavedSearchAlertJob => []
  }.freeze

  CASES.each do |klass, args|
    test "#{klass.name} computes a concurrency key" do
      job = klass.new(*args)
      assert job.concurrency_limited?, "#{klass.name} declares no limits_concurrency"
      assert_predicate job.concurrency_key, :present?
    end
  end

  test "newsletter composition keys differ by kind and city" do
    daily = ComposeNewsletterEditionJob.new("daily", "Bergen").concurrency_key
    deals = ComposeNewsletterEditionJob.new("weekly_deals", "Bergen").concurrency_key
    oslo = ComposeNewsletterEditionJob.new("daily", "Oslo").concurrency_key

    assert_equal 3, [ daily, deals, oslo ].uniq.size
  end

  test "fediverse delivery keys on inbox and activity, not on the user" do
    one = Fediverse::DeliveryJob.new(inbox_url: "https://a.example/inbox", user_id: 1, payload: '{"id":"x"}')
    same = Fediverse::DeliveryJob.new(inbox_url: "https://a.example/inbox", user_id: 2, payload: '{"id":"x"}')
    other = Fediverse::DeliveryJob.new(inbox_url: "https://b.example/inbox", user_id: 1, payload: '{"id":"x"}')

    assert_equal one.concurrency_key, same.concurrency_key
    refute_equal one.concurrency_key, other.concurrency_key
  end
end
