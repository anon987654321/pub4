# frozen_string_literal: true

require "test_helper"

# A guest asks without an account, the second ask pairs both, and the
# waiting page walks its reader into the conversation.
class EncountersControllerTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    host! "brgen.no"
    # Encounter.pair! runs outside any request in these tests, so the city
    # tenant that Conversation.find_or_create_direct needs is set here.
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "a guest asks and waits, then walks into the conversation when a stranger asks" do
    post encounters_path
    assert_redirected_to waiting_encounters_path

    stranger = User.create!(email_address: "walk-in-#{SecureRandom.hex(4)}@brgen.no",
                            password: "password123", city: City.find_by!(domain: "brgen.no"))
    match = Encounter.pair!(stranger)
    assert_equal Encounter::MATCHED, match.status

    get waiting_encounters_path
    assert_redirected_to match.conversation
  end

  test "the second ask pairs immediately" do
    first = User.create!(email_address: "first-#{SecureRandom.hex(4)}@brgen.no",
                         password: "password123", city: City.find_by!(domain: "brgen.no"))
    Encounter.pair!(first)

    post encounters_path
    match = Encounter.matched.order(:created_at).last
    assert_redirected_to match.conversation
    assert_equal first.id, match.partner_id
  end

  test "a guest can leave the wait" do
    post encounters_path
    assert_redirected_to waiting_encounters_path

    delete encounters_path
    assert_redirected_to nearby_path
    assert_empty Encounter.waiting
  end
end
