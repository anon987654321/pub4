# frozen_string_literal: true

require "test_helper"

class SignInPageTest < ActionDispatch::IntegrationTest
  test "the phone and code fields say what they accept" do
    get new_session_url
    phone = Nokogiri::HTML(response.body).at_css("input[type=tel][name=phone]")
    assert phone.key?("required")

    post session_request_code_url, params: { phone: "90000004" }
    code = Nokogiri::HTML(response.body).at_css("input[name=code]")
    assert code.key?("required")
    assert_equal "4", code["maxlength"]
    assert_equal "[0-9]{4}", code["pattern"]
  end

  test "the code form appears only once a code is on its way" do
    get new_session_url
    page = Nokogiri::HTML(response.body)
    assert_nil page.at_css("input[name=code]"), "no code form before a code is requested"
    assert_equal session_request_code_path, page.at_css("form.auth-form")["action"]

    post session_request_code_url, params: { phone: "900 00 004" }
    page = Nokogiri::HTML(response.body)
    forms = page.css("form.auth-form")

    assert_equal 1, forms.size
    assert_equal session_path, forms.first["action"]
    phone = forms.first.at_css("input[type=tel][name=phone]")
    assert_equal "900 00 004", phone["value"], "the phone stays visible and editable"
    resend = forms.first.at_css("button[formaction]")
    assert_equal session_request_code_path, resend["formaction"]
    assert resend.key?("formnovalidate")
  end

  test "a wrong code keeps the code form and the phone" do
    post session_request_code_url, params: { phone: "90000004" }
    post session_url, params: { phone: "90000004", code: "0000" }

    form = Nokogiri::HTML(response.body).at_css("form.auth-form")
    assert form.at_css("input[name=code]")
    assert_equal "90000004", form.at_css("input[name=phone]")["value"]
  end
end
