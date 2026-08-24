# frozen_string_literal: true

require "test_helper"

# Asserted through the I18n key, not the English sentence. These apps default
# to nb; the literals only ever matched because rails-i18n was missing, so the
# tests were pinned to the absence of a translation.
class UserTest < ActiveSupport::TestCase
  test "requires email address" do
    user = User.new(password: "password")

    assert_not user.valid?
    assert_includes user.errors[:email_address], I18n.t("errors.messages.blank")
  end

  test "requires unique email address" do
    User.strict_loading(false).create!(email_address: "dup@example.com", password: "password")
    duplicate = User.new(email_address: "dup@example.com", password: "password")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email_address], I18n.t("errors.messages.taken")
  end
end
