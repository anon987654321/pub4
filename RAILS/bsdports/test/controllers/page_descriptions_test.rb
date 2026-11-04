# frozen_string_literal: true

require "test_helper"

# Port, category and maintainer pages all fell back to the site blurb for
# their meta description, so every search snippet and social card read the
# same sentence.
class PageDescriptionsTest < ActionDispatch::IntegrationTest
  setup do
    platform = platforms(:openbsd)
    @category = Category.create!(platform:, name: "devel", slug: "devel", description: "Development tools")
    @maintainer = Maintainer.create!(name: "Jane Porter")
    @port = Port.create!(platform:, category: @category, name: "git", version: "2.45", pkgpath: "devel/git",
                         comment: "distributed version control", maintainer_id: @maintainer.id)
  end

  test "a port page describes the port" do
    get port_path(@port)
    assert_select "meta[name=description][content=?]",
                  I18n.t("ports.meta_description", name: "git", version: "2.45",
                                                   comment: "distributed version control", pkgpath: "devel/git")
  end

  test "a category page uses the category description" do
    get category_path(@category)
    assert_select "meta[name=description][content=?]", "Development tools"
  end

  test "a maintainer page names the maintainer and the port count" do
    get maintainer_path(@maintainer)
    ports = I18n.t("ports.port_count", count: 1)
    expected = I18n.t("maintainers.meta_description", name: "Jane Porter", ports:)
    assert_select "meta[name=description][content=?]", expected
  end
end
