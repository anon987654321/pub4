# frozen_string_literal: true

require "test_helper"

# Random pairing: two asks meet, a second ask abandons the first wait, stale
# waits close instead of pairing, blocked strangers never pair, and the match
# is a real direct conversation both sides can find.
class EncounterTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def stranger(handle)
    User.create!(email_address: "#{handle}-#{SecureRandom.hex(4)}@brgen.no",
                 password: "password123", city: ActsAsTenant.current_tenant)
  end

  test "a lone ask waits" do
    mine = Encounter.pair!(stranger("alone"))
    assert_equal Encounter::WAITING, mine.status
  end

  test "two asks pair into a direct conversation" do
    first = stranger("first")
    second = stranger("second")

    wait = Encounter.pair!(first)
    assert_equal Encounter::WAITING, wait.status

    match = Encounter.pair!(second)
    assert_equal Encounter::MATCHED, match.status
    assert_equal first.id, match.partner_id
    assert_equal Encounter::MATCHED, wait.reload.status
    assert_equal second.id, wait.reload.partner_id
    assert Conversation.exists?(match.conversation_id)
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

  test "blocked strangers never pair" do
    blocker = stranger("blocker")
    blocked = stranger("blocked")
    Block.create!(blocker_id: blocker.id, blocked_id: blocked.id)
    blocked.encounters.create!(status: Encounter::WAITING)

    mine = Encounter.pair!(blocker, blocked_ids: [blocked.id])
    assert_equal Encounter::WAITING, mine.status
    assert_equal Encounter::WAITING, blocked.encounters.first.reload.status
  end
end
