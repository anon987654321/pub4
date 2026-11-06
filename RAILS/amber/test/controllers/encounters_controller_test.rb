# frozen_string_literal: true

require "test_helper"

# A guest asks without an account, the second ask pairs both, and the
# waiting page walks its reader into the message thread.
class EncountersControllerTest < ActionDispatch::IntegrationTest
  def stranger(handle)
    User.create!(email_address: "#{handle}-#{SecureRandom.hex(4)}@example.no",
                 password: "password123")
  end

  test "a guest asks and waits, then walks into the thread when a stranger asks" do
    post encounters_path
    assert_redirected_to waiting_encounters_path

    walk_in = stranger("walk-in")
    match = Encounter.pair!(walk_in)
    assert_equal Encounter::MATCHED, match.status

    get waiting_encounters_path
    assert_redirected_to messages_path(with: walk_in.id)
  end

  test "the second ask pairs immediately" do
    first = stranger("first")
    Encounter.pair!(first)

    post encounters_path
    match = Encounter.matched.order(:created_at).last
    assert_redirected_to messages_path(with: match.partner_id)
    assert_equal first.id, match.partner_id
  end

  test "a guest can leave the wait" do
    post encounters_path
    assert_redirected_to waiting_encounters_path

    delete encounters_path
    assert_redirected_to root_path
    assert_empty Encounter.waiting
  end
end
