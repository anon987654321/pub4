# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# amber's post body is the HTML the Tiptap editor writes, so a link arrives as
# an href with its ampersands escaped. The provider's answer is the oEmbed
# response recorded under the shared engine's fixtures; nothing opens a socket.
class PostLinkEmbedTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  FIXTURES = Shared::Engine.root.join("test/fixtures/link_embed")

  setup do
    @author = User.strict_loading(false).create!(email_address: "embed-#{SecureRandom.hex(4)}@example.test", password: "password")
  end

  def recorded(name) = JSON.parse(FIXTURES.join("#{name}.json").read)

  test "a link in editor HTML is found, resolved off the request and stored" do
    body = %(<p>Musikk til antrekket: <a href="https://www.youtube.com/watch?v=d_HlPboLRL8&amp;t=12">AURORA</a></p>)
    post = Shared::LinkEmbed.stub(:fetch_oembed, ->(_uri) { flunk "fetched inside the request" }) do
      Post.create!(user: @author, body: body)
    end
    assert post.link_embed_record.pending?
    assert_enqueued_jobs 1, only: Shared::LinkEmbedJob

    Shared::LinkEmbed.stub(:fetch_oembed, ->(_uri) { recorded("youtube") }) do
      perform_enqueued_jobs(only: Shared::LinkEmbedJob)
    end

    record = post.reload.link_embed_record
    assert record.ok?
    assert_equal "d_HlPboLRL8", record.match.media_id
    assert_equal "iamAURORAVEVO", record.author_name
  end

  test "a failed lookup is stored as failed, and a lookalike host is never an embed" do
    post = Post.create!(user: @author, body: "<p>https://soundcloud.com/kygo/stars-will-align</p>")
    Shared::LinkEmbed.stub(:fetch_oembed, ->(_uri) { nil }) do
      perform_enqueued_jobs(only: Shared::LinkEmbedJob)
    end
    assert_equal "failed", post.reload.link_embed["status"]

    assert_nil Post.create!(user: @author, body: "<p>https://soundcloud.com.evil.test/kygo/x</p>").link_embed
  end
end
