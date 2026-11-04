# frozen_string_literal: true

require "test_helper"

# The item, outfit, message, live stream, declutter and creator profile forms
# label their fields through human_attribute_name, and nb.yml named none of
# those attributes, so an nb reader got "Purchase date", "Recipient", "Due on".
class FormLabelsNbTest < ActionDispatch::IntegrationTest
  ENGLISH = [ "Title", "Color", "Purchase date", "Photos", "Description", "Occasion", "Recipient", "Body",
              "Scheduled at", "Decision", "Reason kept", "Notes", "Due on", "Note", "Handle", "Display name" ].freeze

  setup do
    email = "labels-#{SecureRandom.hex(4)}@example.test"
    @user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: @user.email_address, password: "password" }
  end

  test "the wardrobe forms label their fields in nb" do
    item = Item.strict_loading(false).create!(user: @user, title: "Frakk", category: "outerwear",
                                              lifecycle_state: "declutter_box", times_worn: 0, price_cents: 0)
    [ new_item_path, new_outfit_path, review_declutter_path(item) ].each { |path| assert_no_english_labels(path) }
  end

  test "the social forms label their fields in nb" do
    [ messages_path, live_streams_path, new_my_creator_profile_path ].each { |path| assert_no_english_labels(path) }
  end

  private

  def assert_no_english_labels(path)
    get path, params: { locale: "nb" }
    assert_response :success, path
    labels = css_select("label").map(&:text).map(&:strip)
    assert labels.any?, "#{path} rendered no labels"
    assert_empty labels & ENGLISH, "#{path} has English labels"
  end
end
