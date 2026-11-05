# frozen_string_literal: true

require "application_system_test_case"

# The shared theme toggle on amber: three states, the dark palette following
# html[data-theme], and the browser's theme-color following the page.
class ThemeToggleTest < ApplicationSystemTestCase
  def theme_color = find("meta[name='theme-color']", visible: :all)[:content]
  def ground
    evaluate_script("getComputedStyle(document.querySelector('.theme-root')).getPropertyValue('--bg').trim()")
  end

  test "the toggle cycles system, light and dark, and the theme colour follows" do
    visit root_path
    toggle = find("button.theme-toggle")
    light_ground = ground
    # System follows the device; headless Chrome may report either scheme.
    device = evaluate_script(%(matchMedia("(prefers-color-scheme: dark)").matches)) ? "#000000" : "#ffffff"
    assert_equal device, theme_color

    toggle.click
    assert_equal "light", evaluate_script("document.documentElement.dataset.theme")
    assert_equal "#ffffff", theme_color

    toggle.click
    assert_equal "dark", evaluate_script("document.documentElement.dataset.theme")
    assert_equal "#000000", theme_color, "theme-color stayed on the light page's colour"
    refute_equal light_ground, ground, "the dark palette did not reach .theme-root"

    toggle.click
    assert_nil evaluate_script("document.documentElement.dataset.theme || null")
    assert_nil evaluate_script(%(localStorage.getItem("amber-theme")))
    assert_equal device, theme_color
  end
end
