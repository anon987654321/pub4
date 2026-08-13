# frozen_string_literal: true

require "test_helper"

class HotwireSurfacesTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.strict_loading(false).create!(email_address: "hotwire@example.com", password: "password")
    @other = User.strict_loading(false).create!(email_address: "other@example.com", password: "password")
    sign_in_amber(@user)
  end

  test "messages locale keys exist and inbox lists only connections" do
    get messages_path
    assert_response :success
    assert_includes response.body, I18n.t("messages.title")
    assert_includes response.body, I18n.t("messages.no_recipients")
    refute_includes response.body, @other.email_address
  end

  test "sending a message to a non-connection is rejected" do
    post messages_path, params: { message: { recipient_id: @other.id, body: "hello" } }
    assert_response :unprocessable_entity
    assert_equal 0, Message.count
  end

  test "accepted connection can be messaged over turbo stream" do
    Connection.create!(requester: @user, addressee: @other, status: "accepted")

    assert_difference -> { Message.count }, 1 do
      post messages_path, params: { message: { recipient_id: @other.id, body: "hello" } },
           as: :turbo_stream
    end
    assert_response :success
    assert_includes response.body, "hello"
    assert_includes response.body, I18n.t("messages.to", name: @other.display_name)
  end

  test "accepting a connection updates the list over turbo stream" do
    connection = Connection.create!(requester: @other, addressee: @user, status: "pending")

    patch connection_path(connection), params: { accept: true }, as: :turbo_stream
    assert_response :success
    assert_equal "accepted", connection.reload.status
    assert_includes response.body, I18n.t("connections.status.accepted")
  end

  test "planning an outfit replaces the planner list over turbo stream" do
    outfit = @user.outfits.create!(name: "Office")
    assert_difference -> { @user.planned_outfits.count }, 1 do
      post planned_outfits_path, params: {
        planned_outfit: { outfit_id: outfit.id, planned_date: Date.current, notes: "meet" }
      }, as: :turbo_stream
    end
    assert_response :success
    assert_includes response.body, "Office"
  end

  test "wearing an item updates counts over turbo stream" do
    item = @user.items.create!(title: "Coat", category: "Outerwear", times_worn: 0)
    post wear_item_path(item), as: :turbo_stream
    assert_response :success
    assert_equal 1, item.reload.times_worn
    assert_includes response.body, I18n.t("items.wear_count", count: 1)
  end

  test "user show hides another wardrobe that is not public" do
    coat = @other.items.create!(title: "Secret coat", category: "Outerwear")
    get user_path(@other)
    assert_response :success
    refute_includes response.body, coat.title
    assert_includes response.body, @other.display_name
  end

  test "leftover English is gone from social and planner views" do
    get connections_path
    assert_response :success
    refute_includes response.body, "Follow creators to build your circle."

    get planned_outfits_path
    assert_response :success
    refute_includes response.body, "Pick a date and an outfit above"
    refute_includes response.body, ">Planner<"
  end

  private

  def sign_in_amber(user)
    post session_path, params: { email_address: user.email_address, password: "password" }
  end
end
