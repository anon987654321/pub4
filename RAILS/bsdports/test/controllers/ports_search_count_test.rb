# frozen_string_literal: true

require "test_helper"

class PortsSearchCountTest < ActionDispatch::IntegrationTest
  setup do
    platform = platforms(:openbsd)
    @category = Category.create!(platform:, name: "devel", slug: "devel")
    @maintainer = Maintainer.create!(name: "Jane Porter")
    30.times do |index|
      Port.create!(platform:, category: @category, name: "py-lib#{index}", version: "1",
                   pkgpath: "devel/py-lib#{index}", maintainer_id: @maintainer.id)
    end
  end

  # Categories and maintainers said how many matched a search; the ports
  # list, the one most searched, said nothing.
  test "a ports search says how many ports matched in total" do
    get ports_path(q: "py-lib")
    assert_response :success
    assert_includes response.body, I18n.t("search.results_for", count: 30, query: "py-lib")
  end
end
