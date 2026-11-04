# frozen_string_literal: true

require "test_helper"

# The port page printed the whole homepage URL as the link text, so long
# homepages wrapped across the definition list.
class PortHomepageLinkTest < ActionDispatch::IntegrationTest
  test "the homepage link shows its host and keeps the full URL" do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel")
    url = "https://www.git-scm.com/downloads/guis/and/more?with=query"
    port = Port.create!(platform:, category:, name: "git", version: "2.45", pkgpath: "devel/git", homepage: url)

    get port_path(port)
    assert_response :success
    assert_select "dd a[href=?][title=?][rel~=nofollow]", url, url, text: "git-scm.com"
  end
end
