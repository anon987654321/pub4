# frozen_string_literal: true

require "test_helper"

# What a reader's browser receives for a post that embeds a link: a facade on
# the front page and the post page, no player until it is pressed, the plain
# link when the provider gave no answer, and provider text as text.
class LinkEmbedRenderTest < ActionDispatch::IntegrationTest
  FIXTURES = Shared::Engine.root.join("test/fixtures/link_embed")
  AURORA = "https://youtu.be/d_HlPboLRL8"

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def embedded_post(link, answer)
    ActsAsTenant.with_tenant(@city) do
      author = User.strict_loading(false).create!(
        email_address: "render-#{SecureRandom.hex(4)}@brgen.no", password: "password123", city: @city
      )
      resolved = Shared::LinkEmbed.resolve(Shared::LinkEmbed.find(link), fetch: ->(_uri) { answer })
      Post.create!(user: author, title: "Kveldens låt #{SecureRandom.hex(2)}", content: "Hør: #{link}",
                   link_embed: resolved.to_h)
    end
  end

  def recorded(name) = JSON.parse(FIXTURES.join("#{name}.json").read)

  test "the front page shows the facade and loads no player" do
    embedded_post(AURORA, recorded("youtube"))

    get root_path
    assert_response :success

    assert_select "body[data-controller~='media-exclusive']"
    assert_select "figure.link_embed" do
      assert_select "img[src='https://i.ytimg.com/vi/d_HlPboLRL8/hqdefault.jpg'][loading='lazy'][referrerpolicy='no-referrer']"
      assert_select "button.link_embed_play[data-action='click->media-exclusive#playEmbed']" do |buttons|
        button = buttons.first
        assert_equal "https://www.youtube-nocookie.com/embed/d_HlPboLRL8?autoplay=1", button["data-media-exclusive-src-param"]
        assert_equal I18n.t("link_embed.play", title: "AURORA - Runaway", provider: "YouTube"), button["aria-label"]
      end
      assert_select "figcaption a[href='https://www.youtube.com/watch?v=d_HlPboLRL8']",
                    text: I18n.t("link_embed.open", provider: "YouTube")
    end
    assert_select "iframe[src*='youtube']", count: 0
  end

  test "the post page carries the same facade" do
    post = embedded_post("https://soundcloud.com/kygo/stars-will-align", recorded("soundcloud"))

    get post_path(post)
    assert_response :success

    assert_select "figure.link_embed button.link_embed_play[data-media-exclusive-allow-param='autoplay']"
    assert_select "iframe[src*='soundcloud']", count: 0
  end

  test "a provider that gave no answer leaves the plain link and no facade" do
    embedded_post("https://vimeo.com/1084537", nil)

    get root_path
    assert_response :success

    assert_select "p.link_embed a[href='https://vimeo.com/1084537'][rel='nofollow noopener noreferrer']"
    assert_select "figure.link_embed", count: 0
  end

  # The title reaches three places — an attribute, an aria-label and the
  # caption — and in each it has to arrive escaped.
  test "provider text is escaped wherever it lands" do
    hostile = recorded("youtube").merge("title" => %(<img src=x onerror="alert(1)">"'), "author_name" => "<b>x</b>")
    embedded_post(AURORA, hostile)

    get root_path
    assert_response :success

    refute_includes response.body, %(<img src=x onerror)
    refute_includes response.body, "<b>x</b>"
    assert_select "figcaption strong", text: %(<img src=x onerror="alert(1)">"')
    assert_select "button.link_embed_play[data-media-exclusive-title-param=?]", %(<img src=x onerror="alert(1)">"')
  end
end
