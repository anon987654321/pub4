# frozen_string_literal: true

require "application_system_test_case"

# Behaviour of the shared engine's chrome, measured in Chrome: the theme
# toggle's three states, the button's motion and hover, the bundled faces, the
# consent cookie's reach across a city's hosts and the draft autosave's pause in
# a hidden tab. The page-side probes are in shared_chrome_probes.js.
class SharedChromeBehaviourTest < ApplicationSystemTestCase
  include CityHostSystemTest

  PROBES = File.read(File.expand_path("shared_chrome_probes.js", __dir__))

  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
  end

  def probe(call)
    execute_script(PROBES) unless evaluate_script("Boolean(window.sharedChromeProbes)")
    evaluate_script("window.sharedChromeProbes.#{call}")
  end

  def theme = evaluate_script("document.documentElement.dataset.theme || null")
  def stored_theme = evaluate_script(%(localStorage.getItem("brgen-theme")))
  def label(state) = I18n.t("theme.#{state}", locale: :nb)
  def patches = evaluate_script("window.autosavePatches")

  test "the theme toggle cycles system, light, dark and back to system" do
    visit_city(nil, "/")
    toggle = find("button.theme-toggle")
    assert_nil theme
    assert_equal label(:system), toggle["aria-label"]

    toggle.click
    assert_equal "light", theme
    assert_equal "light", stored_theme
    assert_equal label(:light), toggle["aria-label"]

    toggle.click
    assert_equal "dark", theme
    assert_equal "dark", stored_theme

    toggle.click
    assert_nil theme
    assert_nil stored_theme, "system clears the stored choice"
    assert_equal label(:system), toggle["aria-label"]
  end

  test "a pressed button settles without overshoot and only a hovering pointer dims it" do
    visit_city(nil, "/")

    refute_includes probe("buttonTiming()"), "1.56", "the M3 spring's overshoot is still on .button"
    assert_equal "(hover: hover)", probe("hoverCondition()")
  end

  test "the page declares one bundled mono and no unread faces" do
    visit_city(nil, "/")
    families = probe("fontFamilies()").uniq

    assert_includes families, "JetBrainsMono Nerd Font"
    [ "Source Serif 4", "Source Sans 3", "Source Code Pro" ].each do |family|
      refute_includes families, family, "#{family} is declared on a brgen page"
    end
  end

  test "a cookie choice made on brgen.no holds on its subdomains" do
    visit_city(nil, "/")
    decline_optional_cookies
    assert wait_until { evaluate_script("document.cookie").include?("pub4_consent=") }

    visit_city("markedsplass", "/")
    assert_no_selector "#cookie-consent-banner"
    visit_city("dating", "/")
    assert_no_selector "#cookie-consent-banner"
  end

  test "a hidden tab saves its draft once and then stops the interval" do
    user = User.strict_loading(false).create!(
      email_address: "autosave_#{SecureRandom.hex(3)}@brgen.no", password: "password123",
      username: "autosave#{SecureRandom.hex(3)}", guest: false
    )
    sign_in_on_city(user)
    visit_city(nil, "/posts/new")
    assert_selector "form[data-controller~='autosave']"
    probe("watchAutosave()")

    probe("typeDraft()")
    probe("hideTab(true)")
    assert wait_until(1.5) { patches == 1 }, "hiding the tab did not save the draft at once"

    # Let that save answer first: an answer that lands after the next edit marks
    # the draft clean again.
    sleep 1
    probe("typeDraft()")
    sleep 6
    assert_equal 1, patches, "the interval kept saving in a hidden tab"

    probe("hideTab(false)")
    assert wait_until(7) { patches == 2 }, "the interval did not resume when the tab came back"
  end
end
