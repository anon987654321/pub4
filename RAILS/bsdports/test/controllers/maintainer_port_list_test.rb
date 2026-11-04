# frozen_string_literal: true

require "test_helper"

# The maintainer page's port list was a bare ul#ports: no list role or
# label like the ports index, and the same id the index uses for its
# turbo-frame.
class MaintainerPortListTest < ActionDispatch::IntegrationTest
  test "the maintainer's ports are a labelled list with its own id" do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel")
    maintainer = Maintainer.create!(name: "Jane Porter")
    Port.create!(platform:, category:, name: "git", version: "2.45", pkgpath: "devel/git", maintainer_id: maintainer.id)

    get maintainer_path(maintainer)
    assert_response :success
    assert_select "#ports", 0
    label = I18n.t("maintainers.ports_label", name: "Jane Porter")
    assert_select "ul#maintainer-ports[role=list][aria-label=?] li.port-row", label
  end
end
