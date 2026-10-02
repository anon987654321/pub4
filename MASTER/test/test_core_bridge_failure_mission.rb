# frozen_string_literal: true

require_relative "test_helper"

class TestCoreBridgeFailureMission < Minitest::Test
  def test_exception_fails_the_fold_mission_instead_of_leaving_it_active
    Dir.mktmpdir do |root|
      mission = Master::Fix::Mission.new(root:)
      mission.start_or_resume!(goal: "broken turn", scope: root, origin: "fold", auto_continue: true)

      Master::CLI::CoreBridge.send(
        :defer_mission_on_error,
        mission,
        RuntimeError.new("dilla missing dependency"),
      )

      record = Master::Fix::Mission.current(root:)
      assert_equal "failed", record["state"]
      assert_match(/dilla missing dependency/, record["error"])
    end
  end
end
