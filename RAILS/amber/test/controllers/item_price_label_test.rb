# frozen_string_literal: true

require "test_helper"

# The item form's price input said "Pris" with no currency, though the
# number is kroner and everything else prints it with number_to_currency.
class ItemPriceLabelTest < ActionDispatch::IntegrationTest
  test "the price label names the currency" do
    email = "ip-#{SecureRandom.hex(4)}@example.test"
    User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }

    get new_item_path(locale: "nb")
    assert_response :success
    assert_select "label[for=item_price]", text: "Pris (kr)"
  end
end
