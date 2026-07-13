require "application_system_test_case"

class PublicNavigationTest < ApplicationSystemTestCase
  test "ports search and primary navigation render without JavaScript errors" do
    visit root_path

    assert_selector "h1", text: "OpenBSD ports"
    assert_selector "input[placeholder='Search ports…']"
    assert_selector "a.skip-link[href='#main-content']", text: "Skip to main content", visible: :all
    assert_selector "main#main-content"
    assert_selector "a.brand.brand-wordmark[aria-label='BSDports']", text: "BSDports", visible: :all
    assert_selector "nav[aria-label='Primary navigation']"
    assert_selector "nav[aria-label='Primary navigation'] a.nav-item.active", text: "Home", visible: :all
    assert_no_selector "meta[name='turbo-cache-control'][content='no-cache']", visible: :all

    page.current_window.resize_to(390, 844)
    assert_selector "nav.tab-bar[aria-label='Mobile navigation']", visible: :all
    assert_selector "nav.tab-bar a[aria-current='page']", visible: :all
  end
end