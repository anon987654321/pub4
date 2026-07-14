require "application_system_test_case"

class PublicNavigationTest < ApplicationSystemTestCase
  test "home remains usable with Turbo and responsive navigation" do
    visit root_path

    assert_selector "a.skip-link[href='#main-content']", text: "Skip to main content"
    assert_selector "main#main-content"
    assert_selector "nav[aria-label='Primary navigation']"
    assert_no_selector "meta[name='turbo-cache-control'][content='no-cache']", visible: :all

    page.current_window.resize_to(390, 844)
    assert_selector "nav.tab-bar[aria-label='Mobile navigation']", visible: :all
    assert_selector "nav.tab-bar a[aria-current='page']", visible: :all
  end

  test "home page has no axe-core accessibility violations" do
    visit root_path
    assert_accessible
  end
end
