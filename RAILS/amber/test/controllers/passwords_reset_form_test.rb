# frozen_string_literal: true

require "test_helper"

# amber's passwords/edit built its form with `form_with model: @user`, so the
# fields posted as user[password]; the shared PasswordsActions#update permits the
# top-level password and password_confirmation. update therefore saw nothing,
# changed nothing, and answered "Password has been reset". The new password never
# took and the old one kept working. Found by the flow gate
# (MASTER/gates/data/flows.yml, amber_password_reset_by_email).
class PasswordsResetFormTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "reset-me@example.com", password: "old-long-password", password_confirmation: "old-long-password")
    @token = @user.password_reset_token
  end

  test "the reset form posts the fields the controller reads" do
    get edit_password_url(@token)

    assert_response :success
    assert_select "input[name='password']"
    assert_select "input[name='password_confirmation']"
    assert_select "input[name='user[password]']", 0
  end

  test "submitting the form's own fields changes the password" do
    put password_url(@token), params: { password: "new-long-password", password_confirmation: "new-long-password" }

    assert_redirected_to new_session_path
    assert User.authenticate_by(email_address: "reset-me@example.com", password: "new-long-password")
    assert_nil User.authenticate_by(email_address: "reset-me@example.com", password: "old-long-password")
  end
end
