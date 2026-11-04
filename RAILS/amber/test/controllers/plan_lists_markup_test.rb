# frozen_string_literal: true

require "test_helper"

# The demo's outfits rendered as div.plan-list/div.plan-row, a list a screen
# reader could not count; the creator profile form wrapped each single field
# in a fieldset with no legend, a group of one with no name.
class PlanListsMarkupTest < ActionDispatch::IntegrationTest
  test "the demo wardrobe's outfits are a list" do
    demo = User.strict_loading(false).find_by(email_address: Amber::DemoWardrobe::DEMO_EMAIL) ||
           User.strict_loading(false).create!(email_address: Amber::DemoWardrobe::DEMO_EMAIL, password: "password")
    demo.items.create!(title: "Ivory silk slip dress", category: "Dresses")
    demo.outfits.create!(name: "Søndagsbrunsj")

    get demo_wardrobe_path
    assert_response :success
    assert_select "ul.plan-list > li.plan-row strong", text: "Søndagsbrunsj"
  end

  # The dressing room had a read-only mode (savable: false) for exactly this
  # and the demo, the one page a guest can try amber on, never used it.
  test "a guest can try Mix & Match on the demo, without a save form" do
    demo = User.strict_loading(false).find_by(email_address: Amber::DemoWardrobe::DEMO_EMAIL) ||
           User.strict_loading(false).create!(email_address: Amber::DemoWardrobe::DEMO_EMAIL, password: "password")
    shirt = demo.items.create!(title: "Linen shirt", category: "Tops")

    get demo_wardrobe_path
    assert_select "h2#demo-mix-match", text: I18n.t("nav.mix_match")
    zones = JSON.parse(css_select("[data-wardrobe-carousel-zones-value]").first["data-wardrobe-carousel-zones-value"])
    assert_includes zones["top"].map { _1["id"] }, shirt.id
    assert_select "form[action=?]", save_look_outfits_path, 0
  end

  test "the creator profile form has no legendless fieldsets" do
    email = "creator-form-#{SecureRandom.hex(4)}@example.test"
    User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }

    get new_my_creator_profile_path
    assert_response :success
    assert_select "form fieldset", 0
    assert_select "form div.field input[name='creator_profile[handle]']"
  end
end
