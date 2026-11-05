# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# A link typed into the composer previews as the player it will become; anything
# no provider recognises gets nothing back, and the pasted URL is never fetched.
class LinkPreviewsControllerTest < ActionDispatch::IntegrationTest
  YOUTUBE = JSON.parse(File.read(File.expand_path("../../../__shared/test/fixtures/link_embed/youtube.json", __dir__)))

  setup do
    host! "brgen.no"
    Rails.cache.clear
  end

  test "a recognised link answers with the player facade it will become" do
    asked = []
    Shared::LinkEmbed.stub(:fetch_oembed, ->(uri) { asked << uri.host; YOUTUBE }) do
      get link_preview_path(url: "https://youtu.be/d_HlPboLRL8")
    end

    assert_response :success
    assert_select "figure.link-embed button.link-embed-play[data-media-exclusive-src-param]"
    assert_equal %w[www.youtube.com], asked, "only the provider's oEmbed endpoint is asked"
  end

  test "a link no provider recognises gets no answer and no request" do
    Shared::LinkEmbed.stub(:fetch_oembed, ->(*) { flunk "nothing may be fetched for an unknown link" }) do
      get link_preview_path(url: "https://example.com/article")
    end

    assert_response :no_content
  end

  test "the composer carries the preview" do
    get root_path

    assert_select "[data-controller~='link-preview'] output[data-link-preview-target='preview']"
  end
end
