# frozen_string_literal: true

require "test_helper"

# The sidebar and tab bar marked aria-current only on an exact index path, so
# items/123 marked nothing; the sidebar carried the same state twice, as an
# "active" class beside aria-current; and notifications, live sessions,
# declutter and connections were reachable only from the footer.
class SidebarNavCurrentTest < ActionDispatch::IntegrationTest
  setup do
    email = "nav-#{SecureRandom.hex(4)}@example.test"
    @user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: @user.email_address, password: "password" }
  end

  test "a garment page marks Wardrobe as its section in the sidebar and the tab bar" do
    item = Item.strict_loading(false).create!(user: @user, title: "Wool coat", category: "outerwear")

    get item_path(item)
    assert_response :success
    assert_select ".sidebar a.nav-item[href=?][aria-current=true]", items_path
    assert_select ".tab-bar a.tab-item[href=?][aria-current=true]", items_path
    assert_select ".sidebar a.nav-item[href=?][aria-current]", outfits_path, 0
  end

  test "the index itself is the page, and no nav item carries an active class" do
    get items_path
    assert_select ".sidebar a.nav-item[href=?][aria-current=page]", items_path
    assert_select ".sidebar .nav-item.active", 0
  end

  test "the dressing room is its own page, not a place inside Outfits" do
    get dressing_room_outfits_path
    assert_select ".sidebar a.nav-item[href=?][aria-current=page]", dressing_room_outfits_path
    assert_select ".sidebar a.nav-item[href=?][aria-current]", outfits_path, 0
  end

  test "the signed-in sidebar reaches notifications, live sessions, declutter and connections" do
    get items_path
    [ notifications_path, live_streams_path, declutter_index_path, connections_path ].each do |path|
      assert_select ".sidebar a.nav-item[href=?]", path
    end
  end
end
