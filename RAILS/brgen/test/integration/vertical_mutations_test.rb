# frozen_string_literal: true

require "test_helper"

# Request-level coverage for state-mutating verticals (marketplace, dating,
# takeaway, playlist import, cart bulk offer). Complements model unit tests
# and the static controller_coverage_contract at RAILS/test/.
class VerticalMutationsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if defined?(Brgen::CitySeed) && City.table_exists?
    @city = City.find_or_initialize_by(domain: "brgen.no")
    @city.name ||= "Bergen"
    @city.slug ||= "bergen-mutations"
    @city.country_code ||= "NO"
    @city.locale ||= "nb"
    @city.currency = "NOK"
    @city.save!
    ActsAsTenant.current_tenant = @city
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def make_user(prefix)
    User.create!(
      email_address: "#{prefix}-#{SecureRandom.hex(4)}@brgen.no",
      password: "password123",
      password_confirmation: "password123",
      username: "#{prefix}_#{SecureRandom.hex(3)}",
      city: @city
    )
  end

  def sign_in_with_session_cookie!(user)
    session = user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
    secret = Rails.application.key_generator.generate_key("signed cookie")
    verifier = ActiveSupport::MessageVerifier.new(
      secret,
      digest: "SHA1",
      serializer: ActiveSupport::MessageEncryptor::NullSerializer
    )
    cookies[:session_id] = verifier.generate(session.id.to_s)
  end

  test "marketplace offer create and seller accept" do
    seller = make_user("seller")
    buyer = make_user("buyer")
    category = Marketplace::Category.find_or_create_by!(name: "Clothes", slug: "clothes-#{SecureRandom.hex(3)}")
    listing = nil
    ActsAsTenant.with_tenant(@city) do
      listing = Marketplace::Listing.create!(
        user: seller,
        category: category,
        title: "Rain jacket",
        price_cents: 15_000,
        currency: "NOK",
        status: "active"
      )
    end

    host! "marketplace.brgen.no"
    sign_in_with_session_cookie!(buyer)

    assert_difference -> { Marketplace::Order.count }, 1 do
      post marketplace.listing_orders_path(listing), params: {
        order: { message: "Still available?" },
        quantity: 1,
      }
    end
    assert_redirected_to marketplace.listing_path(listing)

    order = Marketplace::Order.order(:id).last
    assert_equal "pending", order.status
    assert_equal buyer.id, order.buyer_id

    sign_in_with_session_cookie!(seller)
    patch marketplace.order_path(order), params: { accept: "1" }
    assert_redirected_to marketplace.order_path(order)
    assert_equal "accepted", order.reload.status
  end

  test "marketplace cart send_offers pings sellers for pending orders" do
    seller = make_user("cartseller")
    buyer = make_user("cartbuyer")
    category = Marketplace::Category.find_or_create_by!(name: "Gear", slug: "gear-#{SecureRandom.hex(3)}")
    listing = nil
    ActsAsTenant.with_tenant(@city) do
      listing = Marketplace::Listing.create!(
        user: seller, category: category, title: "Tent", price_cents: 9_000, currency: "NOK", status: "active"
      )
      Marketplace::Order.create!(buyer: buyer, listing: listing, status: "pending", price_cents: 9_000, quantity: 1)
    end

    host! "marketplace.brgen.no"
    sign_in_with_session_cookie!(buyer)

    post marketplace.send_offers_cart_path
    assert_redirected_to marketplace.cart_path
    # Through the key. This asserted /Sent 1/ and passed only while the flash was
    # a hardcoded English string in a controller rendering an nb UI — the test was
    # pinning the bug in place. Second one of these today; the other was
    # maps.checked_in_recently in vertical_forms_test.
    assert_equal I18n.t("flash.marketplace.offers_sent", count: 1), flash[:notice].to_s
  end

  test "dating mutual likes create a match" do
    a = make_user("dater_a")
    b = make_user("dater_b")

    host! "dating.brgen.no"
    sign_in_with_session_cookie!(a)
    assert_difference -> { Dating::Like.count }, 1 do
      post dating.likes_path, params: { user_id: b.id }
    end
    assert_redirected_to dating.root_path

    sign_in_with_session_cookie!(b)
    assert_difference -> { Dating::Match.count }, 1 do
      post dating.likes_path, params: { user_id: a.id }
    end
    assert Dating::Match.active.exists?(initiator_id: a.id, receiver_id: b.id) ||
           Dating::Match.active.exists?(initiator_id: b.id, receiver_id: a.id)
  end

  test "takeaway order create requires delivery address and line items" do
    owner = make_user("rest_owner")
    customer = make_user("diner")
    restaurant = nil
    item = nil
    ActsAsTenant.with_tenant(@city) do
      restaurant = Takeaway::Restaurant.create!(
        user: owner,
        name: "Test Kitchen",
        address: "Strandgaten 1, Bergen",
        cuisine_type: "Norwegian",
        active: true,
        delivery_fee_cents: 500,
        min_order_cents: 0
      )
      item = restaurant.menu_items.create!(name: "Fish soup", price_cents: 1_500, available: true)
    end

    host! "takeaway.brgen.no"
    sign_in_with_session_cookie!(customer)

    assert_difference -> { Takeaway::Order.count }, 1 do
      post takeaway.restaurant_orders_path(restaurant), params: {
        takeaway_order: {
          delivery_address: "Torgallmenningen 1",
          special_instructions: "No onion",
          items: { item.id.to_s => "2" },
        },
      }
    end
    order = Takeaway::Order.order(:id).last
    assert_equal "pending", order.status
    assert_equal customer.id, order.user_id
    assert order.order_items.exists?(menu_item_id: item.id)
    assert_redirected_to takeaway.order_path(order)
  end

  test "playlist import creates tracks from URLs" do
    dj = make_user("dj_import")
    pl = Playlist::Playlist.create!(name: "Import test", user: dj)

    host! "playlist.brgen.no"
    sign_in_with_session_cookie!(dj)

    assert_difference -> { Playlist::Track.count }, 1 do
      post playlist.playlist_imports_path(pl), params: {
        urls: "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC\n",
      }
    end
    assert_redirected_to playlist.playlist_path(pl)
  end

  test "tv live stream go_live requires owner" do
    stream_host = make_user("tv_host")
    other = make_user("tv_viewer")
    channel = Tv::Channel.create!(name: "BRG Live", slug: "brg-live-#{SecureRandom.hex(3)}", user: stream_host)
    stream = Tv::LiveStream.create!(
      user: stream_host,
      channel: channel,
      title: "Evening show",
      status: "scheduled"
    )

    host! "tv.brgen.no"
    sign_in_with_session_cookie!(other)
    patch tv.go_live_live_stream_path(stream)
    assert_equal "scheduled", stream.reload.status

    sign_in_with_session_cookie!(stream_host)
    patch tv.go_live_live_stream_path(stream)
    assert_equal "live", stream.reload.status
  end
end

