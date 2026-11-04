# frozen_string_literal: true

require "test_helper"

class SignInPageTest < ActionDispatch::IntegrationTest
  test "the phone and code fields say what they accept" do
    get new_session_url
    page = Nokogiri::HTML(response.body)
    phone = page.at_css("input[type=tel][name=phone]")
    code = page.at_css("input[name=code]")

    assert phone.key?("required")
    assert code.key?("required")
    assert_equal "4", code["maxlength"]
    assert_equal "[0-9]{4}", code["pattern"]
  end
end
