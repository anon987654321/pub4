# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class HomeControllerTest < ActionDispatch::IntegrationTest
  def test_legal_pages_are_public
    %w[/privacy /terms /cookies].each do |path|
      get path
      assert_response :success, path
      assert_includes response.body, "legal-prose"
    end
    get root_url
    assert_includes response.body, privacy_path
  end

  def test_guest_root_shows_animated_amber_logo
    get root_url
    assert_response :success
    assert_includes response.body, "amber-guest-hero"
    assert_includes response.body, "amber-logo-banner"
    assert_includes response.body, "animated-gradient"
    # Through the key, so it follows the locale amber resolves to (nb by
    # default) rather than pinning the English copy — same fix as b369c6213
    # made for brgen's home and signup pages.
    assert_includes response.body, I18n.t("home.guest_title")
    # The mannequin, not the four stacked carousels it replaced. Operator order
    # 2026-08-17: logo, then this, then the posts. The old assertions pinned
    # shared/_wardrobe_showcase, which rendered from the layout and so appeared
    # above every page in the app.
    assert_includes response.body, "dressing-room"
    assert_includes response.body, 'data-controller="wardrobe-carousel"'
    assert_includes response.body, "mannequin-svg"
    # A garment name reaches the page whether or not a demo wardrobe is seeded.
    assert_includes response.body, "Gold hoop earrings"
    # Saving belongs to an account, so the guest gets the rotation without it.
    assert_not_includes response.body, "dressing-room-save"
    assert_includes response.body, "amber-compose-box"
    assert_includes response.body, I18n.t("empty.guest_post")
    assert_not_includes response.body, 'class="master-embed-frame"'
  end

  def test_guest_root_can_open_master_embed
    get root_url(master: 1)
    assert_response :success
    assert_includes response.body, 'class="master-embed-frame"'
    assert_includes response.body, Rails.application.config.x.master_web_url
  end

  # There was no signed-in test for this page at all, which is how a query
  # against a `price` column that does not exist survived: every authenticated
  # dashboard raised SQLite3::SQLException. Item stores price_cents.
  def test_signed_in_dashboard_renders_with_priced_items
    user = sign_in_as("dashboard@example.com")
    user.items.create!(title: "Gala dress", category: "Dresses", price_cents: 90_000, times_worn: 2)

    stub_weather { get root_url }

    assert_response :success
    assert_select ".cpw-row", text: /Gala dress/
  end

  def test_signed_in_dashboard_offers_a_look_for_today
    user = sign_in_as("dashboard-look@example.com")
    user.items.create!(title: "Linen shirt", category: "Tops", material: "linen")
    user.items.create!(title: "Wide trousers", category: "Bottoms")
    user.items.create!(title: "Loafers", category: "Shoes", material: "leather")
    user.items.create!(title: "Wool coat", category: "Outerwear")

    stub_weather(temp: 3.0, description: "Snowy") { get root_url }

    assert_response :success
    assert_select "#today-look-title"
    # Cold and snowy, so the assistant reaches for the coat.
    assert_select ".today-look-pick", text: /Wool coat/
    # Saving posts to the same endpoint the dressing room uses.
    assert_select "form[action=?]", save_look_outfits_path
  end

  # Utilisation counted `updated_at`, so any background write to an item made
  # the front page claim it had been worn.
  def test_utilisation_counts_wears_not_touches
    user = sign_in_as("dashboard-utilisation@example.com")
    touched = user.items.create!(title: "Never worn but re-tagged", category: "Tops", times_worn: 4)
    worn = user.items.create!(title: "Actually worn", category: "Tops")
    worn.wear!(worn_on: Date.current)
    touched.update!(analysis_status: "complete") # bumps updated_at, not a wear

    stub_weather { get root_url }

    assert_response :success
    # One of two garments, not two of two.
    assert_select ".dash-stats dd", text: "50%"
  end

  def test_signed_in_dashboard_survives_an_empty_wardrobe
    sign_in_as("dashboard-empty@example.com")

    stub_weather { get root_url }

    assert_response :success
    assert_select "#today-look-title", 0
  end

  private

  def sign_in_as(email)
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: user.email_address, password: "password" }
    user
  end

  # Weather.today reaches open-meteo over the network; tests must not.
  def stub_weather(temp: nil, description: nil, &block)
    forecast = temp && { temp: temp, code: 0, wind: 0.0, description: description }
    Weather.stub(:today, forecast, &block)
  end
end
