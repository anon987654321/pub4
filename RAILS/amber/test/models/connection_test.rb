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
    assert_includes connection.errors[:addressee], "cannot be yourself"
  end

  test "accept transitions pending to accepted" do
    connection = Connection.create!(requester: @alice, addressee: @bob, status: "pending")

    connection.accept!

    assert_equal "accepted", connection.reload.status
  end
end