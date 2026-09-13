# frozen_string_literal: true

require "test_helper"

# A shop is public, its payouts are the owner's, and releasing one moves money,
# so each of those lines is pinned from the outside.
class MarketplaceStoresTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    @city = City.find_by!(domain: "brgen.no")
    @owner = create_user("ms_owner")
    @stranger = create_user("ms_stranger")
    @buyer = create_user("ms_buyer")
    ActsAsTenant.current_tenant = @city
    @category = Marketplace::Category.create!(name: "Sko", slug: "sko-#{SecureRandom.hex(4)}")
    @store = Marketplace::Store.create!(owner: @owner, name: "Skobutikken #{SecureRandom.hex(2)}",
                                        slug: "sko-#{SecureRandom.hex(4)}", stripe_connect_id: "acct_test123")
    @listing = Marketplace::Listing.create!(user: @owner, category: @category, store: @store,
                                            title: "Løpesko #{SecureRandom.hex(2)}", price_cents: 120_000, stock: 4)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "markedsplass.brgen.no"
  end

  def payout_for_delivery(delivered_at)
    order = @listing.orders.create!(buyer: @buyer, price_cents: @listing.price_cents, quantity: 1)
    order.update!(payment_status: "paid", status: "paid", fulfilment_status: "delivered", delivered_at: delivered_at)
    Marketplace::Payout.create!(store: @store, order: order, amount_cents: 120_000, currency: "NOK", status: "pending")
  end

  test "a guest sees the shop and its listings, and no payouts" do
    payout_for_delivery(20.days.ago)
    host! "markedsplass.brgen.no"

    get marketplace.shop_path(@store)
    assert_response :success
    assert_includes response.body, @listing.title
    assert_not_includes response.body, I18n.t("marketplace.payout_release")
  end

  test "the owner sees payouts a page at a time" do
    21.times { payout_for_delivery(2.days.ago) }
    sign_in_as(@owner)

    get marketplace.shop_path(@store)
    assert_response :success
    assert_select "turbo-frame#store-payouts article", 20

    get marketplace.shop_path(@store, page: 2)
    assert_select "turbo-frame#store-payouts article", 1
  end

  test "only the owner edits the shop" do
    sign_in_as(@stranger)
    patch marketplace.shop_path(@store), params: { store: { name: "Kapret" } }
    assert_redirected_to marketplace.shop_path(@store.slug)
    assert_equal I18n.t("marketplace.store_not_allowed"), flash[:alert]
    assert_not_equal "Kapret", @store.reload.name

    sign_in_as(@owner)
    patch marketplace.shop_path(@store), params: { store: { name: "Skobutikken Nord" } }
    assert_equal I18n.t("marketplace.store_updated"), flash[:notice]
    assert_equal "Skobutikken Nord", @store.reload.name
  end

  test "a signed-in user opens a shop" do
    sign_in_as(@stranger)

    assert_difference -> { Marketplace::Store.count }, 1 do
      post marketplace.shops_path, params: { store: { name: "Bokhandel #{SecureRandom.hex(2)}", vertical: "books" } }
    end
    assert_equal I18n.t("marketplace.store_created"), flash[:notice]
    assert_equal @stranger.id, Marketplace::Store.order(:id).last.owner_id
  end

  test "a stranger cannot release the owner's payout" do
    payout = payout_for_delivery(20.days.ago)
    sign_in_as(@stranger)

    post marketplace.shop_payouts_path(@store), params: { payout_id: payout.id }
    assert_redirected_to marketplace.shop_path(@store.slug)
    assert_equal I18n.t("marketplace.store_not_allowed"), flash[:alert]
    assert_predicate payout.reload, :pending?
  end

  test "a payout inside the return window stays held" do
    payout = payout_for_delivery(2.days.ago)
    sign_in_as(@owner)

    post marketplace.shop_payouts_path(@store), params: { payout_id: payout.id }
    assert_equal I18n.t("marketplace.payout_held"), flash[:alert]
    assert_predicate payout.reload, :pending?
  end

  # Fail-closed: without Stripe keys the owner is told, and nothing is marked sent.
  test "releasing without Stripe configured leaves the payout pending" do
    payout = payout_for_delivery(20.days.ago)
    sign_in_as(@owner)

    prior = ENV.delete("STRIPE_SECRET_KEY")
    post marketplace.shop_payouts_path(@store), params: { payout_id: payout.id }
    assert_equal I18n.t("marketplace.payout_not_configured"), flash[:alert]
    assert_predicate payout.reload, :pending?
  ensure
    ENV["STRIPE_SECRET_KEY"] = prior if prior
  end
end
