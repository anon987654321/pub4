# frozen_string_literal: true

require "test_helper"

# Shops are the commercial half of the two-tier listing model: the directory,
# the storefront page, and the owner's create, update and delete. Every write
# runs require_real_user, so a soft guest is refused at sign-in where the
# listing surfaces would have let them through, and authorize_owner answers a
# non-owner with the shop page and a reason instead of a 404.
class Marketplace::StoresControllerTest < ActionDispatch::IntegrationTest
  setup do
    # A known apex (DomainRegistry) that is also a marketplace subdomain — the
    # controller 404s "Unknown host" otherwise, and .brgen.no scopes the session.
    host! "markedsplass.brgen.no"
    @owner = User.create!(email_address: "st_owner@example.com", password: "secret1234")
    @stranger = User.create!(email_address: "st_stranger@example.com", password: "secret1234")
    @store = Marketplace::Store.create!(owner: @owner, name: "Stasjonen Sport")
    @category = Marketplace::Category.create!(name: "Probe", slug: "st-#{SecureRandom.hex(4)}")
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "secret1234" }
  end

  test "the shop directory shows the city's open shops" do
    get marketplace.shops_path

    assert_response :success
    assert_includes response.body, @store.name
  end

  test "the vertical filter narrows the directory" do
    books = Marketplace::Store.create!(owner: @stranger, name: "Bokkiosken", vertical: "books")

    get marketplace.shops_path, params: { vertical: "books" }

    assert_response :success
    assert_includes response.body, books.name
    assert_not_includes response.body, @store.name
  end

  test "a shop page shows the shop and what it sells" do
    listing = Marketplace::Listing.create!(
      user: @owner, store: @store, category: @category, title: "Freeride ski 180", price_cents: 45_000
    )

    get marketplace.shop_path(@store.slug)

    assert_response :success
    assert_includes response.body, @store.name
    assert_includes response.body, listing.title
  end

  test "the owner sees the seller centre on their own shop page" do
    sign_in(@owner)

    get marketplace.shop_path(@store.slug)

    assert_response :success
    assert_includes response.body, I18n.t("marketplace.seller_center.title")
    assert_includes response.body, I18n.t("marketplace.seller_center.live")
  end

  # publicly_visible reads active, and set_store finds through the same scope,
  # so a closed shop is gone from the directory and its URL answers 404.
  test "a closed shop leaves the directory and its page answers 404" do
    @store.update_columns(active: false)

    get marketplace.shops_path

    assert_response :success
    assert_not_includes response.body, @store.name

    assert_raises(ActiveRecord::RecordNotFound) do
      get marketplace.shop_path(@store.slug)
    end
  end

  test "the owner opens a shop and the slug comes from the name" do
    sign_in(@owner)

    assert_difference -> { Marketplace::Store.count }, 1 do
      post marketplace.shops_path, params: {
        store: { name: "Fjell Sport", vertical: "sports", description: "Utstyr til fjellet" }
      }
    end

    store = Marketplace::Store.order(:id).last
    assert_redirected_to marketplace.shop_path(store.slug)
    assert_equal I18n.t("marketplace.store_created"), flash[:notice]
    assert_equal @owner.id, store.owner_id
    assert_equal "fjell-sport", store.slug
  end

  test "a shop without a name is refused with its form" do
    sign_in(@owner)

    assert_no_difference -> { Marketplace::Store.count } do
      post marketplace.shops_path, params: { store: { name: "", vertical: "sports" } }
    end

    assert_response :unprocessable_entity
    assert_select "form[action*='/shops']"
  end

  # The one place the engine refuses an anonymous mutation at sign-in:
  # require_real_user draws an identity line that the cart and listing paths
  # leave open for guests.
  test "a signed-out visitor is sent to sign in before opening a shop" do
    get marketplace.new_shop_path
    assert_redirected_to new_session_path
    assert_equal I18n.t("shared.flash.sign_in_required"), flash[:alert]

    assert_no_difference -> { Marketplace::Store.count } do
      post marketplace.shops_path, params: { store: { name: "Gjestebutikken" } }
    end
    assert_redirected_to new_session_path
    assert_equal I18n.t("shared.flash.sign_in_required"), flash[:alert]
  end

  test "someone else cannot change or delete a shop that is not theirs" do
    sign_in(@stranger)

    patch marketplace.shop_path(@store.slug), params: { store: { name: "Hijacked" } }
    assert_redirected_to marketplace.shop_path(@store.slug)
    assert_equal I18n.t("marketplace.store_not_allowed"), flash[:alert]
    assert_equal "Stasjonen Sport", @store.reload.name

    delete marketplace.shop_path(@store.slug)
    assert_redirected_to marketplace.shop_path(@store.slug)
    assert Marketplace::Store.exists?(@store.id)
  end

  test "the owner updates the shop" do
    sign_in(@owner)

    patch marketplace.shop_path(@store.slug), params: { store: { description: "Nytt sortiment" } }

    assert_redirected_to marketplace.shop_path(@store.slug)
    assert_equal I18n.t("marketplace.store_updated"), flash[:notice]
    assert_equal "Nytt sortiment", @store.reload.description
  end
end
