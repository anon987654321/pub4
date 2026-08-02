# frozen_string_literal: true

require "test_helper"

# passwords/new and passwords/edit were byte-identical in brgen and bsdports, so
# app_duplication_test asked for them to be extracted; they now live only in
# RAILS/shared/app/views/passwords. Neither app had a test that rendered them,
# which meant nothing would have caught the extraction resolving to no template
# at all. This is that test.
class PasswordsControllerTest < ActionDispatch::IntegrationTest
  def test_forgot_password_form_renders_from_the_shared_engine
    get new_password_url
    assert_response :success
    assert_includes response.body, I18n.t("auth.forgot_title")
    assert_includes response.body, "auth-form"
  end
end
