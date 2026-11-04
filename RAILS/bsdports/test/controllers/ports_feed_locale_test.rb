# frozen_string_literal: true

require "test_helper"

# The RSS channel title, description and language were hardcoded English
# and "en-us" while the app ships nb.
class PortsFeedLocaleTest < ActionDispatch::IntegrationTest
  test "the feed channel speaks the reader's language" do
    get ports_url(format: :rss, locale: "nb")
    assert_response :success
    channel = Nokogiri::XML(response.body).at_xpath("/rss/channel")
    assert_equal I18n.t("ports.rss.title", locale: :nb), channel.at_xpath("title").text
    assert_equal I18n.t("ports.rss.description", locale: :nb), channel.at_xpath("description").text
    assert_equal "nb", channel.at_xpath("language").text
  end

  test "the feed holds the last seven days, cached publicly only unscoped" do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel")
    { "fresh" => Date.current - 1, "old" => Date.current - 10 }.each do |name, last_updated|
      Port.create!(platform:, category:, name:, version: "1", pkgpath: "devel/#{name}", last_updated:)
    end

    get ports_url(format: :rss)
    titles = Nokogiri::XML(response.body, &:strict).xpath("//item/title").map(&:text)
    assert_equal [ "fresh-1" ], titles
    assert_match(/public/, response.headers["Cache-Control"])

    get ports_url(format: :rss, category_id: category.id)
    assert_no_match(/public/, response.headers["Cache-Control"].to_s)
  end
end
