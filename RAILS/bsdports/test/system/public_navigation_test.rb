require "application_system_test_case"

class PublicNavigationTest < ApplicationSystemTestCase
  test "ports search and primary navigation render without JavaScript errors" do
    visit root_path

    assert_selector "h1", text: "OpenBSD ports"
    assert_selector "[role='search'][aria-label='Search ports']"
    assert_selector "input[aria-label='Search query']"
    assert_selector "a.skip-link[href='#main-content']", text: "Skip to main content", visible: :all
    assert_selector "main#main-content"
    assert_selector "nav[aria-label='Primary navigation'] a[aria-current='page']", text: "BSDports", visible: :all
    assert_no_selector "meta[name='turbo-cache-control'][content='no-cache']", visible: :all
  end
end
