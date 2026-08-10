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
end
