# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "tmpdir"
require "yaml"
require_relative "../../app/services/shared/outbound_http"
require_relative "../../app/services/shared/link_embed"
require_relative "../../app/services/shared/link_embed/record"

# The oEmbed answers under fixtures/link_embed/ were recorded from the four
# providers' public endpoints on 2026-09-15. Nothing here opens a socket: every
# resolve is handed a fetcher that reads one of those files.
class LinkEmbedTest < Minitest::Test
  FIXTURES = File.expand_path("../fixtures/link_embed", __dir__)

  def recorded(name) = JSON.parse(File.read(File.join(FIXTURES, "#{name}.json")))

  def match(url) = Shared::LinkEmbed.match_url(url)

  def test_each_provider_names_the_media_in_its_own_link_shapes
    {
      "https://www.youtube.com/watch?v=d_HlPboLRL8" => %w[youtube d_HlPboLRL8],
      "https://youtu.be/d_HlPboLRL8" => %w[youtube d_HlPboLRL8],
      "https://m.youtube.com/watch?feature=share&v=d_HlPboLRL8" => %w[youtube d_HlPboLRL8],
      "https://www.youtube.com/shorts/d_HlPboLRL8" => %w[youtube d_HlPboLRL8],
      "https://soundcloud.com/kygo/stars-will-align" => %w[soundcloud kygo/stars-will-align],
      "https://soundcloud.com/kygo/sets/kids-in-love" => %w[soundcloud kygo/sets/kids-in-love],
      "https://vimeo.com/1084537" => %w[vimeo 1084537],
      "https://open.spotify.com/intl-no/track/4cOdK2wGLETKBW3PvgPWqT" => %w[spotify track/4cOdK2wGLETKBW3PvgPWqT],
    }.each do |url, (provider, id)|
      found = match(url)
      refute_nil found, url
      assert_equal [ provider, id ], [ found.provider.key, found.media_id ], url
    end
  end

  # Hosts are compared whole. Each of these carries a provider's name somewhere
  # in the authority and belongs to someone else.
  def test_lookalike_hosts_and_other_links_name_nothing
    [
      "https://youtube.com.evil.test/watch?v=d_HlPboLRL8",
      "https://evilyoutube.com/watch?v=d_HlPboLRL8",
      "https://www.youtube.com.evil.test/watch?v=d_HlPboLRL8",
      "https://youtube.com@evil.test/watch?v=d_HlPboLRL8",
      "https://someone@www.youtube.com/watch?v=d_HlPboLRL8",
      "https://www.youtube.com:8443/watch?v=d_HlPboLRL8",
      "https://soundcloud.com.evil.test/kygo/stars-will-align",
      "https://w.soundcloud.com/player/?url=https://evil.test",
      "https://evil.test/?u=https://www.youtube.com/watch?v=d_HlPboLRL8",
      "https://www.youtube.com/watch?v=short",
      "https://soundcloud.com/discover/sets",
      "https://vimeo.com/channels/staffpicks",
      "https://open.spotify.com/user/someone",
      "javascript:alert(1)//www.youtube.com/watch?v=d_HlPboLRL8",
      "ftp://www.youtube.com/watch?v=d_HlPboLRL8",
    ].each { |url| assert_nil match(url), url }
  end

  def test_the_first_recognised_link_in_prose_or_editor_html_is_found
    prose = "Se denne: https://example.com/artikkel og så https://youtu.be/d_HlPboLRL8."
    assert_equal "https://youtu.be/d_HlPboLRL8", Shared::LinkEmbed.find(prose).source_url

    html = %(<p>Hør <a href="https://www.youtube.com/watch?v=d_HlPboLRL8&amp;t=42">her</a></p>)
    assert_equal "d_HlPboLRL8", Shared::LinkEmbed.find(html).media_id

    assert_nil Shared::LinkEmbed.find("ingen lenke her")
    assert_nil Shared::LinkEmbed.find(nil)
  end

  # The request goes to the provider's endpoint, never to the host the reader
  # pasted, which is what makes a pasted link an identifier rather than a fetch.
  def test_resolving_asks_the_fixed_oembed_endpoint_for_the_canonical_url
    asked = nil
    fetch = lambda do |uri|
      asked = uri
      recorded("youtube")
    end
    Shared::LinkEmbed.resolve(match("https://youtu.be/d_HlPboLRL8"), fetch:)

    assert_equal "www.youtube.com", asked.host
    assert_equal "/oembed", asked.path
    assert_equal "https://www.youtube.com/watch?v=d_HlPboLRL8", URI.decode_www_form(asked.query).to_h["url"]
  end

  def test_a_recorded_answer_becomes_an_ok_record_with_a_privacy_friendly_player
    record = Shared::LinkEmbed.resolve(match("https://youtu.be/d_HlPboLRL8"), fetch: ->(_) { recorded("youtube") },
                                       at: Time.utc(2026, 9, 15, 12))

    assert record.ok?
    assert_equal "AURORA - Runaway", record.title
    assert_equal "iamAURORAVEVO", record.author_name
    assert_equal "https://i.ytimg.com/vi/d_HlPboLRL8/hqdefault.jpg", record.thumbnail_url
    assert_equal "2026-09-15T12:00:00Z", record.fetched_at
    assert_equal "https://www.youtube-nocookie.com/embed/d_HlPboLRL8?autoplay=1", record.player_url
  end

  def test_every_provider_resolves_its_recorded_answer
    {
      "https://soundcloud.com/kygo/stars-will-align" => [
        "soundcloud",
        "https://w.soundcloud.com/player/?url=https%3A%2F%2Fsoundcloud.com%2Fkygo%2Fstars-will-align&auto_play=true&visual=true",
      ],
      "https://vimeo.com/1084537" => [ "vimeo", "https://player.vimeo.com/video/1084537?dnt=1&autoplay=1" ],
      "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT" => [
        "spotify",
        "https://open.spotify.com/embed/track/4cOdK2wGLETKBW3PvgPWqT",
      ],
    }.each do |url, (fixture, player)|
      record = Shared::LinkEmbed.resolve(match(url), fetch: ->(_) { recorded(fixture) })
      assert record.ok?, url
      refute_nil record.thumbnail_url, url
      assert_equal player, record.player_url
    end
  end

  def test_no_answer_is_a_failed_record_that_still_knows_its_link
    record = Shared::LinkEmbed.resolve(match("https://vimeo.com/1084537"), fetch: ->(_) { nil })

    refute record.ok?
    assert_equal "failed", record.status
    assert_equal "https://vimeo.com/1084537", record.match.source_url
    refute_nil record.fetched_at
  end

  def test_an_answer_without_a_title_is_not_ok
    record = Shared::LinkEmbed.resolve(match("https://vimeo.com/1084537"), fetch: ->(_) { { "html" => "<iframe>" } })
    assert_equal "failed", record.status
  end

  # The provider's thumbnail is shown before anyone taps, so a thumbnail from
  # any other host is dropped rather than hotlinked.
  def test_a_thumbnail_off_the_providers_image_host_is_dropped
    answer = recorded("youtube").merge("thumbnail_url" => "https://tracker.evil.test/pixel.gif")
    record = Shared::LinkEmbed.resolve(match("https://youtu.be/d_HlPboLRL8"), fetch: ->(_) { answer })

    assert record.ok?
    assert_nil record.thumbnail_url
    youtube = Shared::LinkEmbed.match_url("https://youtu.be/d_HlPboLRL8").provider
    refute youtube.thumbnail?("https://i.ytimg.com.evil.test/x.jpg")
    refute youtube.thumbnail?("http://i.ytimg.com/vi/d_HlPboLRL8/hqdefault.jpg")
    refute youtube.thumbnail?("https://i.ytimg.com:8443/vi/d_HlPboLRL8/hqdefault.jpg")
  end

  def test_a_stored_record_round_trips
    soundcloud = match("https://soundcloud.com/kygo/stars-will-align")
    record = Shared::LinkEmbed.resolve(soundcloud, fetch: ->(_) { recorded("soundcloud") })
    again = Shared::LinkEmbed::Record.from_stored(JSON.parse(JSON.generate(record.to_h)))

    assert_equal record.to_h, again.to_h
    assert again.ok?
  end

  # The player is rebuilt from the stored link, so editing the row's
  # canonical_url or media_id aims nothing anywhere, and a provider that does
  # not own the link is refused outright.
  def test_a_tampered_stored_row_cannot_move_the_player
    stored = Shared::LinkEmbed.resolve(match("https://youtu.be/d_HlPboLRL8"), fetch: ->(_) { recorded("youtube") }).to_h

    tampered = stored.merge("media_id" => "x", "canonical_url" => "https://evil.test/embed")
    assert_equal "https://www.youtube-nocookie.com/embed/d_HlPboLRL8?autoplay=1",
                 Shared::LinkEmbed::Record.from_stored(tampered).player_url

    assert_nil Shared::LinkEmbed::Record.from_stored(stored.merge("provider" => "vimeo"))
    assert_nil Shared::LinkEmbed::Record.from_stored(stored.merge("source_url" => "https://evil.test/v/1"))
    assert_nil Shared::LinkEmbed::Record.from_stored(stored.merge("status" => "playing"))
    assert_nil Shared::LinkEmbed::Record.from_stored("not a hash")
  end

  def test_provider_text_is_kept_as_text_and_bounded
    answer = recorded("youtube").merge("title" => "<script>alert(1)</script>#{"x" * 300}", "author_name" => " Aurora\n")
    record = Shared::LinkEmbed.resolve(match("https://youtu.be/d_HlPboLRL8"), fetch: ->(_) { answer })

    assert record.title.start_with?("<script>")
    assert_equal Shared::LinkEmbed::Record::TITLE_MAX, record.title.length
    assert_equal "Aurora", record.author_name
  end

  # The fetcher is the only code here that touches the network, so it is driven
  # through a stubbed Shared::OutboundHttp.request rather than left untested.
  def test_fetching_goes_through_the_guard_with_a_body_cap_and_answers_nil_for_anything_but_a_json_object
    json = File.read(File.join(FIXTURES, "vimeo.json"))
    uri = match("https://vimeo.com/1084537").provider.oembed_uri("1084537")

    seen = with_outbound(Reply.new("1.1", "200", "OK").with(json)) { Shared::LinkEmbed.fetch_oembed(uri) }
    assert_equal "Big Buck Bunny", seen[:result]["title"]
    assert_equal Shared::LinkEmbed::OEMBED_MAX_BODY, seen[:max_body]
    assert_equal uri, seen[:uri]

    [
      Reply.new("1.1", "200", "OK").with("<html>"),
      Reply.new("1.1", "200", "OK").with("[1]"),
      Net::HTTPNotFound.new("1.1", "404", "Not Found"),
      Shared::OutboundHttp::BodyTooLarge.new("big"),
    ].each do |answer|
      assert_nil with_outbound(answer) { Shared::LinkEmbed.fetch_oembed(uri) }[:result], answer.inspect
    end
  end

  # The seeders' catalogue, read offline. Every post resolves to an ok embed on
  # a privacy host, and every post's text carries the link it claims.
  def test_the_demo_catalogue_gives_every_seeded_post_an_ok_embed
    %w[brgen amber].each do |app|
      rows = Shared::LinkEmbed.demo_posts(app)
      refute_empty rows, app
      rows.each do |row|
        record = Shared::LinkEmbed::Record.from_stored(row[:link_embed])
        assert record&.ok?, "#{app} #{row[:link]}"
        assert_equal "2026-09-15", record.fetched_at
        refute_nil record.thumbnail_url, row[:link]
        assert_match %r{\Ahttps://(?:www\.youtube-nocookie\.com|w\.soundcloud\.com)/}, record.player_url
      end
    end
  end

  def test_a_demo_post_whose_text_lost_its_link_is_refused
    catalog = YAML.safe_load_file(Shared::LinkEmbed::DEMO)
    catalog["posts"]["amber"] = [ { "link" => "aurora_runaway", "body" => "<p>ingen lenke</p>" } ]

    Dir.mktmpdir do |dir|
      broken = File.join(dir, "demo.yml")
      File.write(broken, catalog.to_yaml)
      assert_raises(KeyError) { Shared::LinkEmbed.demo_posts(:amber, catalog: broken) }
    end
  end

  private

  Reply = Class.new(Net::HTTPOK) do
    def with(body)
      @stubbed_body = body
      self
    end

    def body = @stubbed_body
  end

  def with_outbound(answer)
    seen = {}
    Shared::OutboundHttp.singleton_class.alias_method(:real_request, :request)
    Shared::OutboundHttp.define_singleton_method(:request) do |uri, max_body:, **|
      seen[:uri] = uri
      seen[:max_body] = max_body
      raise answer if answer.is_a?(Exception)

      answer
    end
    seen[:result] = yield
    seen
  ensure
    Shared::OutboundHttp.singleton_class.alias_method(:request, :real_request)
  end
end
