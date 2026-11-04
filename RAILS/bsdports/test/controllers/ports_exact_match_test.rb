# frozen_string_literal: true

require "test_helper"

# A search for "git" listed git-annex and git-crypt above git, and a typed
# pkgpath (devel/git) landed on a list of one instead of the port.
class PortsExactMatchTest < ActionDispatch::IntegrationTest
  setup do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel")
    @git = Port.create!(platform:, category:, name: "git", version: "2", pkgpath: "devel/git")
    %w[git-annex git-crypt].each do |name|
      Port.create!(platform:, category:, name:, version: "1", pkgpath: "devel/#{name}")
    end
  end

  test "an exact pkgpath goes straight to the port page" do
    get ports_path(q: "devel/git")
    assert_redirected_to port_path(@git)
  end

  test "the live search keeps streaming results for a typed pkgpath" do
    get ports_path(q: "devel/git"), headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }
    assert_response :success
    assert_includes response.body, %(<turbo-stream action="update" target="live_search_results">)
  end

  test "an exact name is listed first" do
    Port.find_by(name: "git-annex").update!(name: "agit")
    get ports_path(q: "git")
    assert_response :success
    assert_select "a.port-name", count: 3 do |links|
      assert_equal "git", links.first.text.strip
    end
  end
end
