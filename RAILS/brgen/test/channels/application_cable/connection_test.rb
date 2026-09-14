# frozen_string_literal: true

require "test_helper"

# A signed-in cable connection reads the user off a Session found by id, and
# strict loading raises on that read unless the finder loads the user with it.
module ApplicationCable
  class ConnectionTest < ActionCable::Connection::TestCase
    setup do
      @city = City.find_or_initialize_by(domain: "brgen.no")
      @city.name ||= "Bergen"
      @city.slug ||= "bergen-cable"
      @city.country_code ||= "NO"
      @city.locale ||= "nb"
      @city.currency = "NOK"
      @city.save!
      ActsAsTenant.current_tenant = @city
    end

    teardown do
      ActsAsTenant.current_tenant = nil
    end

    test "a signed-in session connects as its user" do
      user = User.create!(
        email_address: "cable-#{SecureRandom.hex(4)}@brgen.no",
        password: "password123", password_confirmation: "password123",
        username: "cable_#{SecureRandom.hex(3)}", city: @city,
      )
      session = user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
      cookies.signed[:session_id] = session.id

      connect

      assert_equal user.id, connection.current_user.id
    end

    test "a request with no session or guest is refused" do
      assert_reject_connection { connect }
    end
  end
end
