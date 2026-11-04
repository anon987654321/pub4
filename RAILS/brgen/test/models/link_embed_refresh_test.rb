# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# A link the provider would not describe once used to stay a plain link for
# good: LinkEmbedJob asked only about pending records. A failed answer is now
# asked again after a day and a resolved one after a month, by the daily
# Shared::LinkEmbedRefreshJob.
class LinkEmbedRefreshTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  FIXTURES = Shared::Engine.root.join("test/fixtures/link_embed")

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @author = User.strict_loading(false).create!(
      email_address: "refresh-#{SecureRandom.hex(4)}@brgen.no", password: "password123", city: @city
    )
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def recorded(name) = JSON.parse(FIXTURES.join("#{name}.json").read)

  def resolved_post(link, answer)
    post = Post.create!(user: @author, title: "Kveldsmusikk", content: link)
    Shared::LinkEmbed.stub(:fetch_oembed, ->(_uri) { answer }) { perform_enqueued_jobs(only: Shared::LinkEmbedJob) }
    post.reload
  end

  test "a failed lookup is retried after a day and resolves once the provider answers" do
    post = resolved_post("https://youtu.be/d_HlPboLRL8", nil)
    assert_equal "failed", post.link_embed["status"]

    travel 2.hours do
      Shared::LinkEmbedRefreshJob.perform_now("Post")
      assert_no_enqueued_jobs(only: Shared::LinkEmbedJob)
    end

    travel 25.hours do
      Shared::LinkEmbed.stub(:fetch_oembed, ->(_uri) { recorded("youtube") }) do
        Shared::LinkEmbedRefreshJob.perform_now("Post")
        perform_enqueued_jobs(only: Shared::LinkEmbedJob)
      end
    end

    record = post.reload.link_embed_record
    assert record.ok?
    assert_equal "AURORA - Runaway", record.title
  end

  test "a resolved embed is refreshed after a month and kept when the refresh fails" do
    post = resolved_post("https://youtu.be/d_HlPboLRL8", recorded("youtube"))

    travel 10.days do
      Shared::LinkEmbedRefreshJob.perform_now("Post")
      assert_no_enqueued_jobs(only: Shared::LinkEmbedJob)
    end

    travel 31.days do
      Shared::LinkEmbed.stub(:fetch_oembed, ->(_uri) { nil }) do
        Shared::LinkEmbedRefreshJob.perform_now("Post")
        perform_enqueued_jobs(only: Shared::LinkEmbedJob)
      end
      record = post.reload.link_embed_record

      assert record.ok?, "a failed refresh must not take the player away"
      assert_equal "AURORA - Runaway", record.title
      refute record.stale?, "the retry moves to a month from now"
    end
  end

  test "both apps schedule the refresh" do
    %w[brgen amber].each do |app|
      schedule = YAML.load_file(Rails.root.join("..", app, "config", "recurring.yml")).fetch("production")
      entry = schedule.values.find { |row| row["class"] == "Shared::LinkEmbedRefreshJob" }

      refute_nil entry, "#{app} never refreshes link embeds"
      assert_equal [ "Post" ], entry["args"]
    end
  end
end
