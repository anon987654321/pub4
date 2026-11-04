# frozen_string_literal: true

require "test_helper"

# The phone sign-in's fixed code (1234) used to open any account: POST /session
# with any phone and the code signed in as that customer, with no code ever
# requested, no rate limit, and in production too.
class PhoneSignInTest < ActionDispatch::IntegrationTest
  OWNER = "90000011"
  OTHER = "90000012"

  setup do
    @owner = User.create!(phone: OWNER, name: "Eier", role: ROLES.fetch(:customer))
  end

  def signed_in? = cookies[:session_token].present?

  test "the fixed code without a requested code does not sign in" do
    post session_url, params: { phone: OWNER, code: "1234" }
    assert_response :unprocessable_entity
    refute signed_in?
  end

  test "a code requested for one phone does not sign in another" do
    post session_request_code_url, params: { phone: OTHER }
    post session_url, params: { phone: OWNER, code: "1234" }
    assert_response :unprocessable_entity
    refute signed_in?
  end

  test "the code this session requested signs in its own phone" do
    post session_request_code_url, params: { phone: OWNER }
    post session_url, params: { phone: OWNER, code: "1234" }
    assert_redirected_to root_path
    assert signed_in?
  end

  test "a requested code expires after a few minutes" do
    post session_request_code_url, params: { phone: OWNER }
    travel 6.minutes do
      post session_url, params: { phone: OWNER, code: "1234" }
    end
    assert_response :unprocessable_entity
    refute signed_in?
  end

  test "with real identity live the fixed code opens nothing" do
    original = SessionsController.method(:sms_mocked?)
    SessionsController.define_singleton_method(:sms_mocked?) { false }

    post session_request_code_url, params: { phone: OWNER }
    assert_response :service_unavailable
    post session_url, params: { phone: OWNER, code: "1234" }
    assert_response :unprocessable_entity
    refute signed_in?
  ensure
    SessionsController.singleton_class.send(:remove_method, :sms_mocked?)
    SessionsController.define_singleton_method(:sms_mocked?, original)
  end

  test "repeated guesses are cut off" do
    10.times { post session_url, params: { phone: OWNER, code: "0000" } }
    post session_url, params: { phone: OWNER, code: "0000" }
    assert_redirected_to new_session_path
    assert_equal I18n.t("auth.too_many_attempts"), flash[:alert]
  end
end
