# frozen_string_literal: true

require "application_system_test_case"

class PublicNavigationTest < ApplicationSystemTestCase
  test "guest home exposes its primary actions and responsive navigation" do
    visit root_path

    assert_selector "h1", text: "Amber turns your wardrobe into a working system."
    assert_link "Browse demo wardrobe"
    assert_selector "a.skip-link[href='#main-content']", text: "Skip to main content", visible: :all
    assert_selector "main#main-content"
    assert_no_selector "meta[name='turbo-cache-control'][content='no-cache']", visible: :all

    page.current_window.resize_to(390, 844)
    assert_selector "nav.tab-bar[aria-label='Mobile navigation']"
    assert_selector "nav.tab-bar a[aria-current='page']", visible: :all
  end
end
