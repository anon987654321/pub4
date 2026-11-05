# frozen_string_literal: true

require "application_system_test_case"

# sign_in_on_city waits for the server's answer, not for a fixed time: on a
# loaded machine the sign-in takes longer than five seconds and every system
# test that signs in failed at its first step.
class SignInUnderLoadTest < ApplicationSystemTestCase
  include CityHostSystemTest

  # Holds the sign-in answer back, the way a busy machine does.
  module SlowAnswer
    mattr_accessor :seconds, default: 0

    def create
      sleep(SlowAnswer.seconds)
      super
    end
  end
  SessionsController.prepend(SlowAnswer)

  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    city = City.find_by!(domain: "brgen.no")
    @person = User.strict_loading(false).create!(email_address: "slow_sign_in_#{SecureRandom.hex(3)}@brgen.no",
                                                 password: "password123", city: city)
  end

  teardown { SlowAnswer.seconds = 0 }

  test "a sign-in answered after seven seconds still signs in" do
    SlowAnswer.seconds = 7
    sign_in_on_city(@person)

    assert Session.exists?(user_id: @person.id)
  end

  test "a refused sign-in is reported, not waited out" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    error = assert_raises(Minitest::Assertion) { sign_in_on_city(@person, password: "not-the-password") }

    assert_match "did not sign in", error.message
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 30
  end
end
