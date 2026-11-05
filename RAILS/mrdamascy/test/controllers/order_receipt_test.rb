# frozen_string_literal: true

require "test_helper"

# The order page doubles as a printable receipt: the seller and the payment
# lane on the page, a print button, and the app's chrome left off the print.
class OrderReceiptTest < ActionDispatch::IntegrationTest
  setup do
    @user = customer_sign_in
    @order = seed_order!(user: @user)
  end

  test "the order page names the seller and the payment lane, and offers to print" do
    get order_url(@order)
    page = Nokogiri::HTML(response.body)

    seller = page.at_css(".receipt-seller").text
    assert_includes seller, @order.kitchen.name
    assert_includes seller, @order.kitchen.address
    assert_includes seller, I18n.t("orders.payment_lane", lane: "Vipps")

    button = page.at_css(%(button[data-controller="print"][data-action="print#print"]))
    assert_equal I18n.t("orders.print_receipt"), button.text
    assert button["hidden"], "without the script the button stays hidden"
  end

  test "the print leaves the app's chrome and the page's buttons off" do
    print = Rails.root.join("app/assets/stylesheets/_utilities.scss").read[/@media print \{.*?\n\}/m]

    assert print, "no print rules"
    %w[.brand-bar .tab-bar .app-footer #toasts .page-actions].each { |selector| assert_includes print, selector }
  end
end
