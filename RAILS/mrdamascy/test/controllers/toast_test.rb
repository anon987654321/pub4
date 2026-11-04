# frozen_string_literal: true

require "test_helper"

class ToastTest < ActionDispatch::IntegrationTest
  setup do
    @item = seed_item!(seed_category!(seed_kitchen!))
  end

  def toast
    Nokogiri::HTML(response.body).at_css(".toast")
  end

  test "a failure is announced at once and stays until closed" do
    @item.update!(available: false)
    post add_item_cart_url, params: { menu_item_id: @item.id }
    follow_redirect!

    assert_equal "alert", toast["role"]
    assert_equal "true", toast["data-toast-persist-value"]
  end

  test "a confirmation is polite and goes by itself" do
    post add_item_cart_url, params: { menu_item_id: @item.id }
    follow_redirect!

    assert_equal "status", toast["role"]
    assert_equal "false", toast["data-toast-persist-value"]
  end
end
