# frozen_string_literal: true

require "test_helper"

# The star on every listing card was write-only, and the index could filter but
# never say how much was behind a filter.
class MarketplaceSavedAndFacetsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @seller = create_user("mf_seller")
    @buyer = create_user("mf_buyer")
    ActsAsTenant.current_tenant = @city
    @bikes = Marketplace::Category.create!(name: "Sykler", slug: "sykler-#{SecureRandom.hex(4)}")
    @sofas = Marketplace::Category.create!(name: "Sofaer", slug: "sofaer-#{SecureRandom.hex(4)}")
    @cheap = listing("Brukt sykkel", category: @bikes, price_cents: 40_000, condition: "fair")
    @dear = listing("Racersykkel", category: @bikes, price_cents: 1_500_000, condition: "like_new")
    @sofa = listing("Sofa", category: @sofas, price_cents: 300_000, condition: "good")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  def listing(title, **attrs)
    Marketplace::Listing.create!({ user: @seller, title: "#{title} #{SecureRandom.hex(2)}" }.merge(attrs))
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "markedsplass.brgen.no"
  end

  def facets(params = {})
    Marketplace::ListingFacets.new(Marketplace::Listing.live, params.with_indifferent_access)
  end

  test "a facet counts what picking it would leave" do
    assert_equal 2, facets.categories[@bikes.id]
    assert_equal 1, facets.categories[@sofas.id]
    assert_equal 1, facets.conditions["good"]
  end

  # Counting with its own filter applied answers "how many of what you already
  # picked", which is the number already on the page.
  test "a facet ignores its own filter and respects the others" do
    # Category picked: the condition counts narrow, the category counts do not.
    narrowed = facets(category_id: @bikes.id)
    assert_equal 2, narrowed.categories[@bikes.id]
    assert_equal 1, narrowed.categories[@sofas.id]
    assert_nil narrowed.conditions["good"]
    assert_equal 1, narrowed.conditions["fair"]
  end

  test "price bands count in kroner" do
    bands = facets.price_bands
    assert_equal 1, bands[[ nil, 500 ]]
    assert_equal 1, bands[[ 2_000, 10_000 ]]
    assert_equal 1, bands[[ 10_000, nil ]]
  end

  test "the saved list shows what the star saved, and drops what left the market" do
    sign_in_as(@buyer)
    post marketplace.listing_favorite_path(@cheap)
    post marketplace.listing_favorite_path(@sofa)

    assert_equal 2, Marketplace::ListingFavorite.where(user_id: @buyer.id).count, "the star did not save"

    get marketplace.saved_listings_path
    assert_response :success
    assert_includes response.body, @cheap.title
    assert_includes response.body, @sofa.title

    @sofa.update!(status: "sold")
    get marketplace.saved_listings_path
    assert_not_includes response.body, @sofa.title
  end

  test "the saved list is the reader's own" do
    sign_in_as(@buyer)
    post marketplace.listing_favorite_path(@cheap)

    sign_in_as(@seller)
    get marketplace.saved_listings_path
    assert_not_includes response.body, @cheap.title
  end
# condition is optional on a listing, so "no condition given" is a real group
# and not a facet anyone can pick.
test "a listing with no condition is no facet option" do
  listing("Uspesifisert", category: @bikes, price_cents: 50_000)

  assert_not_includes facets.conditions.keys, nil
  assert_equal 3, facets.conditions.values.sum
end
end
