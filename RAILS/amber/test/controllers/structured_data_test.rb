# frozen_string_literal: true

require "test_helper"

# Structured data used to stop at items#show — a page behind authentication,
# so no crawler ever saw it. These cover the pages that are actually public.
class StructuredDataTest < ActionDispatch::IntegrationTest
  def schemas
    css_select("script[type='application/ld+json']").map { |node| JSON.parse(node.text) }
  end

  def schema_of(type)
    schemas.find { |data| data["@type"] == type }
  end

  # The demo wardrobe is the only public catalogue, so it is what the ItemList
  # describes. Seeded here rather than skipped — a skipped test proves nothing.
  def seed_demo_wardrobe
    demo = User.strict_loading(false).find_or_create_by!(email_address: Amber::DemoWardrobe::DEMO_EMAIL) do |user|
      user.password = "password"
    end
    demo.items.create!(title: "Ivory silk slip dress", category: "Dresses", brand: "Reformation",
                       color: "ivory", material: "silk", times_worn: 6)
    demo
  end

  test "the guest home carries the organization and the demo capsule" do
    seed_demo_wardrobe

    get root_url

    assert_response :success
    assert schema_of("Organization"), "the layout's organization schema is missing"
    list = schema_of("ItemList")
    assert list, "the guest home described no demo capsule"
    assert_operator list["numberOfItems"], :>, 0
  end

  test "the demo wardrobe lists garments at URLs a crawler can actually follow" do
    demo = seed_demo_wardrobe

    get demo_wardrobe_url

    assert_response :success
    entry = schema_of("ItemList")["itemListElement"].first["item"]
    # Not /items/:id — that is behind authentication, so a crawler following it
    # would land on the sign-in page.
    assert_equal demo_wardrobe_item_url(demo.items.first), entry["url"]
    assert_equal "Product", entry["@type"]
  end

  test "a demo garment is a Product with no offer, because it is not for sale" do
    demo = seed_demo_wardrobe
    item = demo.items.first

    get demo_wardrobe_item_url(item)

    assert_response :success
    product = schema_of("Product")
    assert_equal item.title, product["name"]
    assert_equal "silk", product["material"]
    assert_nil product["offers"]
  end

  # items#show is behind sign-in, but its markup still states facts. A garment
  # with a purchase price is not on sale, so the price is no Offer, and the
  # label it carries is the only brand it has.
  test "a garment in a signed-in wardrobe carries no offer and its own brand" do
    user = User.strict_loading(false).create!(email_address: "schema-item-#{SecureRandom.hex(4)}@example.test",
                                              password: "password")
    post session_path, params: { email_address: user.email_address, password: "password" }
    item = user.items.create!(title: "Ullkåpe", category: "Outerwear", brand: "Filippa K", price_cents: 250_000)

    get item_path(item)

    assert_response :success
    product = schema_of("Product")
    assert product, "items#show emitted no Product schema"
    assert_nil product["offers"]
    assert_equal "Filippa K", product.dig("brand", "name")
  end

  test "a hex dominant colour is not published as a colour name" do
    demo = seed_demo_wardrobe
    item = demo.items.first
    item.update!(color: "#c9a227")

    get demo_wardrobe_item_url(item)

    assert_response :success
    assert_nil schema_of("Product")["color"]
  end

  test "a public post describes itself as an Article with a followable url" do
    user = User.strict_loading(false).create!(email_address: "schema-post@example.com", password: "password")
    post_record = user.posts.create!(body: "A linen shirt is the whole summer wardrobe.")

    get post_url(post_record)

    assert_response :success
    article = schema_of("Article")
    assert article, "posts#show emitted no Article schema"
    assert_equal post_url(post_record), article["url"]
    assert_equal I18n.locale.to_s, article["inLanguage"]
  end

  test "every JSON-LD block on a public page is valid JSON with a context" do
    get root_url

    assert_response :success
    assert_operator schemas.size, :>=, 1
    schemas.each { |data| assert_equal "https://schema.org", data["@context"] }
  end
  # The outfit page had no description of its own and no structured data, and
  # closed on a "Style intelligence" heading over one static paragraph.
  test "an outfit page describes itself and lists its garments" do
    user = User.strict_loading(false).create!(email_address: "schema-outfit@example.com", password: "password")
    coat = user.items.create!(title: "Wool coat", category: "Outerwear", brand: "Acne")
    outfit = user.outfits.create!(name: "Fredagsantrekk")
    outfit.outfit_items.create!(item: coat, position: 0)
    post session_path, params: { email_address: user.email_address, password: "password" }

    get outfit_url(outfit)

    assert_response :success
    description = I18n.t("outfits.meta_description", name: "Fredagsantrekk", count: 1)
    assert_select "meta[name=description][content=?]", description
    list = schema_of("ItemList")
    assert list, "the outfit page emitted no ItemList"
    assert_equal "Fredagsantrekk", list["name"]
    assert_equal [ "Wool coat" ], list["itemListElement"].map { _1.dig("item", "name") }
    assert_select "h2", count: 0, text: /Hva dette antrekket gjør|What this outfit is doing/
  end

  # posts#show printed its opening twice: an h1 of the first 80 characters,
  # then the body that begins with them.
  test "a post page keeps its heading for screen readers without printing it twice" do
    user = User.strict_loading(false).create!(email_address: "schema-post-h1@example.com", password: "password")
    post_record = user.posts.create!(body: "A linen shirt is the whole summer wardrobe.")

    get post_url(post_record)

    assert_select "h1.visually-hidden", text: "A linen shirt is the whole summer wardrobe."
  end
end
