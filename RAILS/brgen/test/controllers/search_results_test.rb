# frozen_string_literal: true

require "test_helper"

# The global search page: a query that finds nothing says so, and a section
# that finds something says how much.
class SearchResultsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "a query with no match anywhere renders an empty state naming it" do
    query = "ingentingher#{SecureRandom.hex(3)}"

    get global_search_path(q: query)

    assert_response :success
    assert_select ".empty-state-title", text: I18n.t("search.no_results", query:)
  end

  test "a section heading counts its results" do
    word = "fjellrev#{SecureRandom.hex(3)}"
    author = User.create!(email_address: "sok-#{SecureRandom.hex(4)}@brgen.no", password: "password123",
                          username: "sok_#{SecureRandom.hex(3)}")
    2.times { |i| Post.create!(user: author, city: @city, title: "#{word} #{i}", content: "hei") }

    get global_search_path(q: word)

    assert_response :success
    heading = I18n.t("search.section_heading", vertical: I18n.t("search.sections.posts"), count: 2)
    assert_select "h2", text: heading
  end
end
