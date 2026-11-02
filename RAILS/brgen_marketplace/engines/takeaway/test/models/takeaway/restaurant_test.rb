# frozen_string_literal: true

require "test_helper"

class Takeaway::RestaurantTest < ActiveSupport::TestCase
  PIXEL_PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
  )

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(
      email_address: "restaurant_#{SecureRandom.hex(3)}@brgen.no",
      password: "password123",
      city: @city
    )
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def build_restaurant
    Takeaway::Restaurant.new(
      user: @owner, name: "Cover Kitchen", address: "Marken 4",
      cuisine_type: "Norwegian", city: @city, active: true
    )
  end

  test "a restaurant can carry a supported cover image" do
    restaurant = build_restaurant
    restaurant.cover.attach(
      io: StringIO.new(PIXEL_PNG),
      filename: "cover.png",
      content_type: "image/png",
      identify: false
    )

    assert restaurant.valid?
    assert restaurant.cover.attached?
  end

  test "a restaurant rejects unsupported cover media" do
    restaurant = build_restaurant
    restaurant.cover.attach(
      io: StringIO.new("<script>alert(1)</script>"),
      filename: "cover.html",
      content_type: "text/html",
      identify: false
    )

    assert_not restaurant.valid?
    assert_includes restaurant.errors[:cover], I18n.t("takeaway.cover_image_invalid")
  end

  test "a restaurant rejects cover images over eight megabytes" do
    restaurant = build_restaurant
    restaurant.cover.attach(
      io: StringIO.new(PIXEL_PNG + ("\0" * Takeaway::Restaurant::MAX_COVER_BYTES)),
      filename: "oversized.png",
      content_type: "image/png",
      identify: false
    )

    assert_not restaurant.valid?
    assert_includes restaurant.errors[:cover], I18n.t("takeaway.cover_image_too_large")
  end
end
