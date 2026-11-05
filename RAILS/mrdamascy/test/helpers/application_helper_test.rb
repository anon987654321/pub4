# frozen_string_literal: true

require "test_helper"

# The menu's small marks, written once and used by the card and the sheet.
class ApplicationHelperTest < ActionView::TestCase
  setup do
    @dish = MenuItem.new(name: "Rett", heat: 2, origin: "damaskus", badges: "signature, veg, unknown")
  end

  test "heat dots light as many dots as the level and name it" do
    heat = Nokogiri::HTML.fragment(heat_dots(@dish)).at_css("span.heat.heat-2")

    assert_equal 2, heat.css(".heat-dot.on").size
    assert_equal 3, heat.css(".heat-dot").size
    assert_equal "#{t('menu.heat_label')}:", heat.at_css(".visually-hidden").text
    assert_equal t("menu.heat.2"), heat.at_css(".heat-label").text
    @dish.heat = 0
    assert_nil heat_dots(@dish)
  end

  test "origin, badges and state read as the views wrote them inline" do
    origin = Nokogiri::HTML.fragment(origin_chip(@dish)).at_css("span.badge")
    assert_equal t("menu.origin_chip", origin: "Damaskus"), origin.text

    badges = Nokogiri::HTML.fragment(badge_tags(@dish)).css("span.badge.badge-signature, span.badge.badge-veg")
    assert_equal [ t("menu.badges.signature"), t("menu.badges.veg") ], badges.map(&:text)

    chip = Nokogiri::HTML.fragment(state_chip(Order.new(state: "ready"))).at_css("span.state-chip.state-ready")
    assert_equal t("orders.states.ready"), chip.text
    @dish.origin = nil
    assert_nil origin_chip(@dish)
  end
end
