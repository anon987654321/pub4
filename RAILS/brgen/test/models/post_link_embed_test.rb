# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# A post's media link is noticed on save and resolved off the request. The
# provider's answer comes from the oEmbed responses recorded under the shared
# engine's test fixtures, so no test here opens a socket.
class PostLinkEmbedTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  FIXTURES = Shared::Engine.root.join("test/fixtures/link_embed")

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @author = User.strict_loading(false).create!(
      email_address: "embed-#{SecureRandom.hex(4)}@brgen.no", password: "password123", city: @city
    )
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def post_with(content)
    Post.create!(user: @author, title: "Kveldsmusikk", content: content)
  end

  def recorded(name) = JSON.parse(FIXTURES.join("#{name}.json").read)

  test "a post with a supported link stores it pending and enqueues one lookup" do
    post = nil
    assert_enqueued_with(job: Shared::LinkEmbedJob) do
      post = post_with("Hør denne: https://youtu.be/d_HlPboLRL8")
    end
    assert_enqueued_jobs 1, only: Shared::LinkEmbedJob

    assert post.link_embed_record.pending?
    assert_equal "youtube", post.link_embed["provider"]
    assert_equal "https://youtu.be/d_HlPboLRL8", post.link_embed["source_url"]
  end

  # Writing the post never waits on the provider: nothing is fetched until the
  # job runs, and the job is the only caller of the fetcher.
  test "creating a post makes no provider request" do
    post = Shared::LinkEmbed.stub(:fetch_oembed, ->(_uri) { flunk "fetched inside the request" }) do
      post_with("https://soundcloud.com/kygo/stars-will-align")
    end

    assert post.link_embed_record.pending?
  end

  test "the job stores the provider's answer and bumps the cache key" do
    post = post_with("https://youtu.be/d_HlPboLRL8")
    before = post.reload.updated_at

    travel 1.minute do
      Shared::LinkEmbed.stub(:fetch_oembed, ->(_uri) { recorded("youtube") }) do
        perform_enqueued_jobs(only: Shared::LinkEmbedJob)
      end
    end

    record = post.reload.link_embed_record
    assert record.ok?
    assert_equal "AURORA - Runaway", record.title
    assert_equal "https://www.youtube-nocookie.com/embed/d_HlPboLRL8?autoplay=1", record.player_url
    assert_operator post.updated_at, :>, before
  end

  test "a provider that will not answer leaves a failed record, which renders as the plain link" do
    post = post_with("https://vimeo.com/1084537")

    Shared::LinkEmbed.stub(:fetch_oembed, ->(_uri) { nil }) do
      perform_enqueued_jobs(only: Shared::LinkEmbedJob)
    end

    assert_equal "failed", post.reload.link_embed["status"]
    refute post.link_embed_record.ok?
  end

  test "unsupported and lookalike links carry no embed and enqueue nothing" do
    assert_no_enqueued_jobs(only: Shared::LinkEmbedJob) do
      assert_nil post_with("https://youtube.com.evil.test/watch?v=d_HlPboLRL8").link_embed
      assert_nil post_with("Se https://example.com/artikkel").link_embed
      assert_nil post_with("ingen lenke").link_embed
    end
  end

  test "an edit that keeps the link keeps the resolved embed, and one that drops it clears it" do
    post = post_with("https://youtu.be/d_HlPboLRL8")
    Shared::LinkEmbed.stub(:fetch_oembed, ->(_uri) { recorded("youtube") }) do
      perform_enqueued_jobs(only: Shared::LinkEmbedJob)
    end

    assert_no_enqueued_jobs(only: Shared::LinkEmbedJob) do
      post.reload.update!(content: "Fortsatt beste låta: https://youtu.be/d_HlPboLRL8")
    end
    assert post.reload.link_embed_record.ok?

    assert_no_enqueued_jobs(only: Shared::LinkEmbedJob) do
      post.update!(content: "Lenka er borte")
    end
    assert_nil post.reload.link_embed
  end

  # The seeders write the resolved embed with the post, so seeding asks no
  # provider and queues no lookup.
  test "a post created with the embed already resolved for its link keeps it and queues nothing" do
    resolved = Shared::LinkEmbed.resolve(Shared::LinkEmbed.find("https://youtu.be/d_HlPboLRL8"), fetch: ->(_uri) { recorded("youtube") })

    post = nil
    assert_no_enqueued_jobs(only: Shared::LinkEmbedJob) do
      post = Post.create!(user: @author, title: "Seedet", content: "https://youtu.be/d_HlPboLRL8", link_embed: resolved.to_h)
    end
    assert post.reload.link_embed_record.ok?
  end

  # Two saves, two jobs. The first to run resolves the link the post carries
  # now, and the other finds nothing pending and asks nobody.
  test "a new link on edit is the one resolved, and it is asked for once" do
    post = post_with("https://youtu.be/d_HlPboLRL8")
    post.reload.update!(content: "https://vimeo.com/1084537")
    asked = []

    Shared::LinkEmbed.stub(:fetch_oembed, ->(uri) { asked << uri.host; recorded("vimeo") }) do
      perform_enqueued_jobs(only: Shared::LinkEmbedJob)
    end

    assert_equal %w[vimeo.com], asked
    assert_equal "vimeo", post.reload.link_embed["provider"]
    assert_equal "Big Buck Bunny", post.link_embed_record.title
  end
end
