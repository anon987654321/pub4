# frozen_string_literal: true

require "test_helper"

class ParticipantAccessTest < ActiveSupport::TestCase
  test "direct mode may operate without an intermediary" do
    result = Eritel::ParticipantAccess.check(participant: nil, mode: "direct")

    assert result.allowed
  end

  test "registrar mode requires an active registrar" do
    participant = Participant.create!(
      name: "Example Registrar",
      kind: "registrar",
      status: "active"
    )

    assert Eritel::ParticipantAccess.check(
      participant:,
      mode: "registrar"
    ).allowed

    participant.update!(status: "suspended")

    result = Eritel::ParticipantAccess.check(participant:, mode: "registrar")
    assert_not result.allowed
  end

  test "technical mode rejects a registrar" do
    participant = Participant.create!(
      name: "Example Registrar",
      kind: "registrar",
      status: "active"
    )

    result = Eritel::ParticipantAccess.check(participant:, mode: "technical")

    assert_not result.allowed
    assert_equal "participant role does not permit this mode", result.reason
  end
end
