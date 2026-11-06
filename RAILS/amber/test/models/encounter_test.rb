# frozen_string_literal: true

require "test_helper"

# Random pairing: two asks meet, a second ask abandons the first wait, stale
# waits close instead of pairing, and the pairing arrives as an accepted
# connection so the thread can carry on.
class EncounterTest < ActiveSupport::TestCase
  def stranger(handle)
    User.create!(email_address: "#{handle}-#{SecureRandom.hex(4)}@example.no",
                 password: "password123")
  end

  test "a lone ask waits" do
    mine = Encounter.pair!(stranger("alone"))
    assert_equal Encounter::WAITING, mine.status
  end

  test "two asks pair and accept the connection" do
    first = stranger("first")
    second = stranger("second")

    wait = Encounter.pair!(first)
    assert_equal Encounter::WAITING, wait.status

    match = Encounter.pair!(second)
    assert_equal Encounter::MATCHED, match.status
    assert_equal first.id, match.partner_id
    assert_equal Encounter::MATCHED, wait.reload.status
    assert_equal second.id, wait.reload.partner_id
    assert Connection.accepted.exists?(requester_id: second.id, addressee_id: first.id)
  end

  test "a pending request between the pair upgrades to accepted" do
    first = stranger("first")
    second = stranger("second")
    Connection.create!(requester: second, addressee: first, status: "pending")

    Encounter.pair!(first)
    Encounter.pair!(second)
    assert Connection.accepted.exists?(requester_id: second.id, addressee_id: first.id)
  end

  test "a second ask abandons the first wait" do
    asker = stranger("twice")
    Encounter.pair!(asker)
    mine = Encounter.pair!(asker)

    assert_equal 1, asker.encounters.waiting.count
    assert_equal Encounter::WAITING, mine.status
  end

  test "stale waits close instead of pairing" do
    ghost = stranger("ghost")
    ghost.encounters.create!(status: Encounter::WAITING, created_at: 5.minutes.ago, updated_at: 5.minutes.ago)

    mine = Encounter.pair!(stranger("asker"))
    assert_equal Encounter::WAITING, mine.status
    assert_equal Encounter::CLOSED, ghost.encounters.first.reload.status
  end
end
