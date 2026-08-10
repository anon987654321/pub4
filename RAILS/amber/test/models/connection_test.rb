# frozen_string_literal: true

require "test_helper"

class ConnectionTest < ActiveSupport::TestCase
  setup do
    @alice = User.strict_loading(false).create!(email_address: "alice@amber.test", password: "password123")
    @bob = User.strict_loading(false).create!(email_address: "bob@amber.test", password: "password123")
  end

  test "rejects self connection" do
    connection = Connection.new(requester: @alice, addressee: @alice, status: "pending")

    assert_not connection.valid?
    # The key, not the sentence. default_locale is nb, so asserting the English
    # string tied this test to whichever language the message happened to be in
    # -- and it was in English on a Norwegian site, which was the bug.
    assert_includes connection.errors.details[:addressee].map { |d| d[:error] }, :self_connection
  end

  test "accept transitions pending to accepted" do
    connection = Connection.create!(requester: @alice, addressee: @bob, status: "pending")

    connection.accept!

    assert_equal "accepted", connection.reload.status
  end
end
