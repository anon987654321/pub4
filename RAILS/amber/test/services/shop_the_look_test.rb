# frozen_string_literal: true

require "test_helper"

class ShopTheLookTest < ActiveSupport::TestCase
  test "scores brand overlap" do
    assert ShopTheLook.text_score("Bergans jacket", "Bergans Microlight") > 0.3
    assert_equal 0.0, ShopTheLook.text_score("", "anything")
  end

  test "returns empty remote without token" do
    ENV.delete("TRADEDOUBLER_TOKEN")
    ENV.delete("TRADEDOUBLER_PRODUCTS_TOKEN")
    item = Item.new(title: "Jacket", brand: "Bergans", category: "outerwear")
    assert_equal [], ShopTheLook.remote_suggestions(item, limit: 3)
  end
end
