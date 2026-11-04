# frozen_string_literal: true

require "test_helper"

# The reset-request email field and both new-password fields were optional
# in the markup, so an empty submit went to the server and came back as a
# generic failure instead of the browser saying which field was empty.
class PasswordFormsRequiredTest < ActionDispatch::IntegrationTest
  test "the reset forms require their fields" do
    get new_password_path
    assert_select "input[type=email][name=email_address][required]", 1

    user = User.create!(email_address: "req-#{SecureRandom.hex(4)}@example.com", password: "old-long-password")
    get edit_password_path(user.password_reset_token)
    assert_select "input[name=password][required]", 1
    assert_select "input[name=password_confirmation][required]", 1
  end
end
