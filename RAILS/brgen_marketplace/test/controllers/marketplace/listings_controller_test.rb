# frozen_string_literal: true

require "test_helper"

# The storefront reads and the seller's own write paths: the index with its
# filters, the product page, renew and withdraw. The mutation gate lives in
# ListingPolicy's owner checks and in Shared::TwoFactorAuth, not in a sign-in
# redirect: Shared::Authentication hands every anonymous visitor a soft guest
# Current.user so that no one signs up to list. The guest-listing test pins
# that contract, and the ownership refusals pin where the line is drawn.
class Marketplace::ListingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # A known apex (DomainRegistry) that is also a marketplace subdomain — the
    # controller 404s "Unknown host" otherwise, and .brgen.no scopes the session.
    host! "markedsplass.brgen.no"
    @seller = User.create!(email_address: "li_seller@example.com", password: "secret1234")
    @buyer = User.create!(email_address: "li_buyer@example.com", password: "secret1234")
    @category = Marketplace::Category.create!(name: "Probe", slug: "li-#{SecureRandom.hex(4)}")
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "secret1234" }
  end

  def listing_for(user, title, price_cents:, store: nil)
    Marketplace::Listing.create!(
      user: user, store: store, category: @category, title: title, price_cents: price_cents
    )
  end

  test "the index renders the city's goods with title and price" do
    listing = listing_for(@seller, "Fjellski 180", price_cents: 45_000)

    get marketplace.listings_path

    assert_response :success
    assert_includes response.body, listing.title
    assert_includes response.body, Shared::MoneyDisplay.format(45_000)
  end

  test "a search narrows the grid to what matches" do
    ski = listing_for(@seller, "Freeride ski 180", price_cents: 45_000)
    sofa = listing_for(@seller, "Three-seat sofa", price_cents: 9_000)

    get marketplace.listings_path, params: { q: "ski" }

    assert_response :success
    assert_includes response.body, ski.title
    assert_not_includes response.body, sofa.title
  end

  test "the source filter splits a person's things from a shop's stock" do
    casual = listing_for(@seller, "Upholstered chair", price_cents: 1_200)
    shop = Marketplace::Store.create!(owner: @seller, name: "Stasjonen Sport")
    stocked = listing_for(@seller, "Freeride ski 180", price_cents: 45_000, store: shop)

    get marketplace.listings_path, params: { from: "person", category_id: @category.id }
    assert_response :success
    assert_includes response.body, casual.title
    assert_not_includes response.body, stocked.title

    get marketplace.listings_path, params: { from: "shop", category_id: @category.id }
    assert_response :success
    assert_includes response.body, stocked.title
    assert_not_includes response.body, casual.title
  end

  test "the price floor hides what sits below it" do
    cheap = listing_for(@seller, "Paperback shelf", price_cents: 9_000)
    dear = listing_for(@seller, "Freeride ski 180", price_cents: 45_000)

    get marketplace.listings_path, params: { min_price: "100", category_id: @category.id }

    assert_response :success
    assert_includes response.body, dear.title
    assert_not_includes response.body, cheap.title
  end

  test "the product page shows the thing and counts the visit" do
    listing = listing_for(@seller, "Fjellski 180", price_cents: 45_000)

    get marketplace.listing_path(listing)

    assert_response :success
    assert_includes response.body, listing.title
    assert_equal 1, listing.reload.views_count
    assert Marketplace::ListingEvent.where(listing_id: listing.id, event_type: "click").exists?
  end

  test "a signed-in buyer sees the offer form on the listing page" do
    listing = listing_for(@seller, "Fjellski 180", price_cents: 45_000)
    sign_in(@buyer)

    get marketplace.listing_path(listing)

    assert_response :success
    assert_includes response.body, "order[message]"
  end

  test "an old numeric link answers with a permanent redirect to the slug" do
    listing = listing_for(@seller, "Fjellski 180", price_cents: 45_000)

    get marketplace.listing_path(listing.id)

    assert_response :moved_permanently
    assert_redirected_to marketplace.listing_path(listing)
  end

  # ListingPolicy::Scope reads `live`, so a listing whose window lapsed leaves
  # the index while its row stays active; show? refuses it to everyone but the
  # owner, who keeps the way back in to renew.
  test "a lapsed listing leaves the index and refuses the page" do
    listing = listing_for(@seller, "Gone ski", price_cents: 45_000)
    listing.update_columns(expires_at: 1.hour.ago)

    get marketplace.listings_path

    assert_response :success
    assert_not_includes response.body, listing.title

    get marketplace.listing_path(listing)
    assert_redirected_to marketplace.root_path
    assert_equal I18n.t("shared.flash.not_authorized"), flash[:alert]
  end

  test "the owner renews a lapsed listing and the window restarts" do
    listing = listing_for(@seller, "Gone ski", price_cents: 45_000)
    listing.update_columns(expires_at: 1.hour.ago)
    sign_in(@seller)

    get marketplace.listing_path(listing)
    assert_response :success

    post marketplace.renew_listing_path(listing)
    assert_redirected_to marketplace.listing_path(listing)
    assert_equal I18n.t("flash.marketplace.listing_renewed"), flash[:notice]
    assert_not listing.reload.expired?
    assert listing.reload.expires_at > 44.days.from_now
  end

  test "a non-owner cannot edit or withdraw a listing that is not theirs" do
    listing = listing_for(@seller, "Fjellski 180", price_cents: 45_000)
    sign_in(@buyer)

    patch marketplace.listing_path(listing), params: { listing: { title: "Hijacked" } }
    assert_redirected_to marketplace.root_path
    assert_equal I18n.t("shared.flash.not_authorized"), flash[:alert]
    assert_equal "Fjellski 180", listing.reload.title

    delete marketplace.listing_path(listing)
    assert_redirected_to marketplace.root_path
    assert_equal "active", listing.reload.status
  end

  # Destroy withdraws rather than deletes: the orders against the listing are a
  # financial record, so the row keeps its place with status removed.
  test "the owner withdraws a listing and the public loses it" do
    listing = listing_for(@seller, "Fjellski 180", price_cents: 45_000)
    sign_in(@seller)

    delete marketplace.listing_path(listing)

    assert_redirected_to marketplace.listings_path
    assert_equal "removed", listing.reload.status
  end

  test "a signed-in seller publishes a goods listing" do
    sign_in(@seller)

    assert_difference -> { Marketplace::Listing.count }, 1 do
      post marketplace.listings_path, params: {
        listing: { title: "Sykkelhjelm", kind: "goods", price_cents: 34_900, category_id: @category.id }
      }
    end

    assert_redirected_to %r{/listings/}
    assert_equal I18n.t("flash.marketplace.listing_published"), flash[:notice]
    listing = Marketplace::Listing.order(:id).last
    assert_equal "Sykkelhjelm", listing.title
    assert_equal 34_900, listing.price_cents
    assert_equal @seller.id, listing.user_id
    assert_equal "active", listing.status
    assert_nil listing.store_id
  end

  # The refusal re-renders :new with @kind, @categories and @stores set — the
  # form reads all three, and a create that skipped them 500'd instead of
  # showing the reader what was wrong.
  test "a refused listing answers with its form" do
    sign_in(@seller)

    assert_no_difference -> { Marketplace::Listing.count } do
      post marketplace.listings_path, params: {
        listing: { title: "", kind: "goods", price_cents: 34_900, category_id: @category.id }
      }
    end

    assert_response :unprocessable_entity
    assert_select "form[action*='/listings']"
  end

  # The Craigslist access model: ListingPolicy asks only for a user, and the
  # authentication concern gives every anonymous visitor a soft guest account.
  test "an anonymous visitor lists without signing up" do
    assert_difference -> { Marketplace::Listing.count }, 1 do
      post marketplace.listings_path, params: {
        listing: { title: "Stol fra en gjest", kind: "goods", price_cents: 1_500, category_id: @category.id }
      }
    end

    assert_redirected_to %r{/listings/}
    listing = Marketplace::Listing.order(:id).last
    assert User.exists?(id: listing.user_id, guest: true)
  end
end
