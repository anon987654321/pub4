# frozen_string_literal: true

require "test_helper"

class Playlist::WhypEmbedResolverTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body)

  def response(html:, type: "rich")
    Response.new("200", JSON.generate("type" => type, "html" => html))
  end

  test "resolves a slug from Whyp oEmbed and retains private share parameters" do
    source = "https://www.whyp.it/tracks/radio-bergen-1?token=secret-token&in=collection-id"
    request = lambda do |endpoint|
      query = URI.decode_www_form(endpoint.query).to_h
      assert_equal "https://api.whyp.it/api/oembed", endpoint.to_s.split("?").first
      assert_equal "json", query.fetch("format")
      assert_equal source, query.fetch("url")
      response(html: %(<iframe src="https://whyp.it/embeds/track/trackSlug?preset=compact"></iframe>))
    end

    embed = Playlist::WhypEmbedResolver.new(request:).call(source)

    uri = URI.parse(embed)
    query = URI.decode_www_form(uri.query).to_h
    assert_equal "/embeds/track/trackSlug", uri.path
    assert_equal "compact", query.fetch("preset")
    assert_equal "secret-token", query.fetch("token")
    assert_equal "collection-id", query.fetch("in")
  end

  test "rejects an iframe outside the Whyp track embed path" do
    resolver = Playlist::WhypEmbedResolver.new(
      request: ->(_endpoint) { response(html: %(<iframe src="https://evil.example/embeds/track/slug"></iframe>)) }
    )

    assert_nil resolver.call("https://whyp.it/tracks/slug")
  end

  test "rejects malformed and non-rich responses" do
    invalid_json = Playlist::WhypEmbedResolver.new(request: ->(_uri) { Response.new("200", "{") })
    non_rich = Playlist::WhypEmbedResolver.new(request: ->(_uri) { response(type: "photo", html: "") })

    assert_nil invalid_json.call("https://whyp.it/tracks/slug")
    assert_nil non_rich.call("https://whyp.it/tracks/slug")
  end

  test "rejects foreign source URLs without making a request" do
    called = false
    resolver = Playlist::WhypEmbedResolver.new(
      request: ->(_uri) { called = true; response(html: "") }
    )

    assert_nil resolver.call("https://whyp.it.evil.example/tracks/slug")
    assert_nil resolver.call("http://whyp.it/tracks/slug")
    assert_not called
  end

  test "rejects non-200, empty and oversized responses" do
    not_found = Playlist::WhypEmbedResolver.new(request: ->(_uri) { Response.new("404", "") })
    empty = Playlist::WhypEmbedResolver.new(request: ->(_uri) { Response.new("200", "") })
    oversized = Playlist::WhypEmbedResolver.new(
      request: ->(_uri) { Response.new("200", " " * (Playlist::WhypEmbedResolver::MAX_RESPONSE_BYTES + 1)) }
    )

    assert_nil not_found.call("https://whyp.it/tracks/slug")
    assert_nil empty.call("https://whyp.it/tracks/slug")
    assert_nil oversized.call("https://whyp.it/tracks/slug")
  end
end
