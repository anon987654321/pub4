# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "display_name prefers the public name or username and never the email local part" do
    user = User.create!(
      email_address: "display-name-#{SecureRandom.hex(4)}@brgen.no",
      password: "password123",
      username: "handle-#{SecureRandom.hex(4)}",
    )

    assert_equal user.username, user.display_name

    user.update_columns(display_name: "Public Name")
    user.reload

    assert_equal "Public Name", user.display_name
    refute_includes user.display_name, user.email_address.split("@").first
  end
end
