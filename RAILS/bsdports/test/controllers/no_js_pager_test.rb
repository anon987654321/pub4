# frozen_string_literal: true

require "test_helper"

class NoJsPagerTest < ActionDispatch::IntegrationTest
  setup do
    platform = platforms(:openbsd)
    @category = Category.create!(platform:, name: "devel", slug: "devel")
    @maintainer = Maintainer.create!(name: "Jane Porter")
    30.times do |index|
      Port.create!(platform:, category: @category, name: "py-lib#{index}", version: "1",
                   pkgpath: "devel/py-lib#{index}", maintainer_id: @maintainer.id)
    end
  end

  # The infinite-scroll sentinel needs a reflex; without JavaScript the
  # lists stopped at page one.
  test "the ports, category and maintainer lists carry a no-JS pager" do
    [ ports_path, category_path(@category), maintainer_path(@maintainer) ].each do |path|
      get path
      assert_response :success
      assert_match(%r{<noscript>\s*<nav class="pager"}, response.body, path)
    end
  end
end
