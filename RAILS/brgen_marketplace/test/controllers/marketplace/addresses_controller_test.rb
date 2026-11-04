# frozen_string_literal: true

require "test_helper"

# The address book a buyer fills before checkout. The page's form posted
# marketplace_address[...] while the controller required :address, so every
# address saved from the page was rejected; and a buyer sent here from the cart
# was returned to the address page rather than to the cart.
class Marketplace::AddressesControllerTest < ActionDispatch::IntegrationTest
  setup do
    host! "markedsplass.brgen.no"
    @buyer = User.create!(email_address: "ad_buyer_#{SecureRandom.hex(3)}@example.com", password: "secret1234")
    post session_path, params: { email_address: @buyer.email_address, password: "secret1234" }
  end

  # The fields as the rendered form names them, so this fails the moment the
  # page and the controller disagree again.
  def rendered_form_params(page)
    form = Nokogiri::HTML(page).at_css("form[action='#{marketplace.addresses_path}']")
    values = { "recipient" => "Kari Nordmann", "line1" => "Bryggen 1", "postcode" => "5003",
               "city_name" => "Bergen", "country_code" => "NO", "phone" => "40000000" }
    fields = form.css("input[name]").to_h { [ _1["name"], _1["value"].to_s ] }
    names = fields.keys
    values.to_h { |field, value| [ names.find { _1.end_with?("[#{field}]") }, value ] }.then { fields.merge(_1) }
  end

  test "an address submitted from the page is saved" do
    get marketplace.addresses_path

    assert_difference -> { Marketplace::Address.where(user_id: @buyer.id).count }, 1 do
      post marketplace.addresses_path, params: rendered_form_params(response.body)
    end
    assert_equal I18n.t("flash.marketplace.address_saved"), flash[:notice]
  end

  test "a buyer sent from the cart goes back to the cart" do
    cart = "http://markedsplass.brgen.no#{marketplace.cart_path}"
    get marketplace.addresses_path, headers: { "HTTP_REFERER" => cart }
    fields = rendered_form_params(response.body)
    assert_equal marketplace.cart_path, fields["return_to"]

    post marketplace.addresses_path, params: fields

    assert_redirected_to marketplace.cart_path
  end

  test "a return_to elsewhere is not followed" do
    get marketplace.addresses_path
    fields = rendered_form_params(response.body).merge("return_to" => "https://example.com/")

    post marketplace.addresses_path, params: fields

    assert_no_match(/example\.com/, response.location)
  end
end
