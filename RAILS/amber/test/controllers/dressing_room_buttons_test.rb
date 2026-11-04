# frozen_string_literal: true

require "test_helper"

# The dressing room's prev/next carousel buttons had no type, so they were
# submit buttons; inside any form they would submit it on every step.
class DressingRoomButtonsTest < ActionDispatch::IntegrationTest
  test "the carousel step buttons are plain buttons" do
    email = "dr-#{SecureRandom.hex(4)}@example.test"
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: user.email_address, password: "password" }
    user.items.create!(title: "Linen shirt", category: "Tops")

    get dressing_room_outfits_path
    assert_response :success
    assert_select "button.carousel-button"
    assert_select "button.carousel-button:not([type=button])", 0
  end
end
