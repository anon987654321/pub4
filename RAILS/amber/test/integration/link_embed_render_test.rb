# frozen_string_literal: true

require "test_helper"

# amber's front page feed, as a signed-out visitor receives it: a facade for a
# resolved link, no player until it is pressed, and the plain link otherwise.
class LinkEmbedRenderTest < ActionDispatch::IntegrationTest
  FIXTURES = Shared::Engine.root.join("test/fixtures/link_embed")

  def embedded_post(link, answer)
    author = User.strict_loading(false).create!(email_address: "render-#{SecureRandom.hex(4)}@example.test", password: "password")
    resolved = Shared::LinkEmbed.resolve(Shared::LinkEmbed.find(link), fetch: ->(_uri) { answer })
    Post.create!(user: author, body: %(<p>Lyden av høsten: <a href="#{link}">#{link}</a></p>), link_embed: resolved.to_h)
  end

  test "the guest feed shows the facade and loads no player" do
    embedded_post("https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT", JSON.parse(FIXTURES.join("spotify.json").read))

    get root_path
    assert_response :success

    assert_select "body[data-controller~='media-exclusive']"
    assert_select ".amber-guest-feed figure.link_embed button.link_embed_play[data-action='click->media-exclusive#playEmbed']" do |buttons|
      assert_equal "https://open.spotify.com/embed/track/4cOdK2wGLETKBW3PvgPWqT", buttons.first["data-media-exclusive-src-param"]
    end
    assert_select "iframe[src*='spotify']", count: 0
  end

  test "an unresolved link stays a plain link" do
    embedded_post("https://vimeo.com/1084537", nil)

    get root_path
    assert_response :success

    assert_select ".amber-guest-feed p.link_embed a[href='https://vimeo.com/1084537']"
    assert_select ".amber-guest-feed figure.link_embed", count: 0
  end
end
