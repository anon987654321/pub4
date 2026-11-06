# frozen_string_literal: true

require "test_helper"

# Each outfit item row labelled itself "Item" with a "Select item…" blank in
# English, and the template plus every existing row ran its own query for
# the user's items.
class OutfitItemFieldsTest < ActionDispatch::IntegrationTest
  setup do
    email = "of-#{SecureRandom.hex(4)}@example.test"
    @user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }
    shirt = @user.items.create!(title: "Linskjorte", category: "Tops")
    trousers = @user.items.create!(title: "Bukse", category: "Bottoms")
    @outfit = Outfit.strict_loading(false).create!(user: @user, name: "Fredag")
    @outfit.items << shirt << trousers
  end

  test "the item picker speaks nb and is loaded once" do
    lookups = 0
    picker = /\ASELECT .*FROM "items" WHERE "items"."user_id" = .* ORDER BY "items"."title"/
    counter = ->(*, payload) { lookups += 1 if payload[:sql].match?(picker) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      get edit_outfit_path(@outfit, locale: "nb")
    end

    assert_response :success
    assert_select "label", text: I18n.t("outfits.item", locale: :nb)
    assert_select "select option[value='']", text: I18n.t("outfits.select_item", locale: :nb)
    assert_equal 1, lookups
  end
end
