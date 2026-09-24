# frozen_string_literal: true

require "test_helper"

# dating_intro_controller.js has no JavaScript test, so this holds the half a
# request can see: the deck page mounts it, gives it both targets it reads, and
# every action the markup names is a method the controller defines. Delete this
# with the controller if the intro goes.
class DatingLandingTest < ActionDispatch::IntegrationTest
  CONTROLLER = Rails.root.join("engines/dating/app/javascript/controllers/dating_intro_controller.js")

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    host! "dating.brgen.no"
  end

  test "the deck is the landing surface"
    get dating.root_path
    assert_response :success
    assert_select ".dating-page-intro", 1
    assert_select ".dating-discover-panel:not([hidden])", 1
    assert_select "[data-controller~='dating-intro']", 0
    assert_select "[data-controller~='swipe']", 1
  endend
