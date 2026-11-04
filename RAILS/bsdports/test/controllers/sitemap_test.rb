# frozen_string_literal: true

require "test_helper"

# The sitemap left out maintainer pages, which are public and crawlable, and
# dated every port by updated_at, which each re-import moves for the whole
# tree, rather than by the ports-tree date.
class SitemapTest < ActionDispatch::IntegrationTest
  setup do
    platform = platforms(:openbsd)
    @category = Category.create!(platform:, name: "devel", slug: "devel")
    @maintainer = Maintainer.create!(name: "Jane Porter")
    @port = Port.create!(platform:, category: @category, name: "git", version: "2.45", pkgpath: "devel/git",
                         last_updated: Date.new(2026, 3, 1))
  end

  test "the sitemap lists root, categories, maintainers and ports as well-formed XML" do
    get "/sitemap.xml"
    assert_response :success
    xml = Nokogiri::XML(response.body, &:strict)
    locs = xml.remove_namespaces!.xpath("//url/loc").map(&:text)

    [ root_url, categories_url, category_url(@category), maintainer_url(@maintainer), port_url(@port) ].each do |url|
      assert_includes locs, url
    end
  end

  test "a port is dated by the ports tree, not by the import" do
    get "/sitemap.xml"
    xml = Nokogiri::XML(response.body).remove_namespaces!
    lastmod = xml.at_xpath("//url[loc='#{port_url(@port)}']/lastmod").text
    assert_equal "2026-03-01", lastmod
  end
end
