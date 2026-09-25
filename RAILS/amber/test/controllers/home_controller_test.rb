# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class HomeControllerTest < ActionDispatch::IntegrationTest
  # Shared::ApplicationSetup declares morph refreshes with the scroll kept, and
  # the page is what has to carry that to Turbo.
  def test_the_page_tells_turbo_to_morph_refreshes_and_keep_the_scroll
    get root_url
    assert_select "head meta[name='turbo-refresh-method'][content='morph']", 1
    assert_select "head meta[name='turbo-refresh-scroll'][content='preserve']", 1
  end

  def test_legal_pages_are_public
    %w[/privacy /terms /cookies].each do |path|
      get path
      assert_response :success, path
      assert_includes response.body, "legal-prose"
    end
    get root_url
    assert_includes response.body, privacy_path
  end

  # The operator's home page, 2026-09-25: two icons in the corner, the mark
  # centred, four looks on the point-cloud figure, the footer. Nothing else.
  def test_guest_root_is_the_mark_four_looks_and_the_footer
    get root_url
    assert_response :success
    assert_select ".amber-masthead--home .amber-logo-home", 1
    assert_select ".amber-corner a[href=?]", new_session_path
    # Through the key, so it follows the locale amber resolves to (nb by default).
    assert_select "h1", text: I18n.t("home.looks.title")
    assert_select ".amber-look", 4
    # Each look is worn by the dressing room's particle mannequin.
    assert_select ".amber-look [data-controller=particle-mannequin][aria-hidden=true]", 4
    # Each look opens on the whole outfit, then one slide per garment.
    assert_select ".amber-look:first-of-type .amber-look-slide:first-child figcaption", I18n.t("home.looks.whole")
    assert_select ".look-zone svg", minimum: 8
    # A garment name reaches the page whether or not a demo wardrobe is seeded.
    assert_includes response.body, "Gold hoop earrings"
    # No hero, no rails, no feed.
    assert_select ".sidebar, .widgets, .amber-compose-box, .btn", 0
    assert_not_includes response.body, 'class="master-embed-frame"'
  end

  def test_the_footer_links_only_to_routes_that_answer
    get root_url
    hrefs = css_select(".amber-footer a[href]").map { |a| a["href"] }.reject { |href| href.start_with?("mailto:") }
    assert_operator hrefs.size, :>=, 25

    hrefs.uniq.each do |href|
      get href
      assert_includes [ 200, 302 ], response.status, "#{href} answered #{response.status}"
    end
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
