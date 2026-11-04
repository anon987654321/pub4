# frozen_string_literal: true

require "test_helper"

# The outfits list and page counted each outfit's items with .count, which
# ignores the preloaded association and runs a COUNT per outfit.
class OutfitItemCountsTest < ActionDispatch::IntegrationTest
  setup do
    email = "oc-#{SecureRandom.hex(4)}@example.test"
    @user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }
    shirt = @user.items.create!(title: "Linen shirt", category: "Tops")
    @outfits = Array.new(3) do |index|
      Outfit.strict_loading(false).create!(user: @user, name: "Look #{index}").tap { |outfit| outfit.items << shirt }
    end
  end

  test "the outfits list counts items without a query per outfit" do
    assert_equal 0, item_counts { get outfits_path }
    assert_response :success
  end

  test "an outfit page counts its items from the preload" do
    assert_equal 0, item_counts { get outfit_path(@outfits.first) }
    assert_response :success
  end

  private

  def item_counts(&)
    counts = 0
    counter = lambda do |*, payload|
      sql = payload[:sql]
      counts += 1 if sql.start_with?("SELECT COUNT(*) FROM \"items\"") && sql.include?("outfit_items")
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &)
    counts
  end
end
