# frozen_string_literal: true

require "minitest/autorun"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "master"
require "ground/operator_playbook"

class TestOperatorPlaybook < Minitest::Test
  def test_loads_lessons
    lessons = Master::Ground::OperatorPlaybook.lessons
    assert lessons.size >= 5
    assert lessons.all? { |row| row["id"] && row["signal"] && row["action"] }
  end

  def test_for_area_openbsd
    rows = Master::Ground::OperatorPlaybook.for_area("openbsd")
    assert rows.any? { |row| row["id"] == "relayd_master_health_up" }
  end

  def test_find_by_id
    row = Master::Ground::OperatorPlaybook.find("rails_phantom_foreign_keys")
    assert row
    assert_includes row["proof"], "check_phantom_foreign_keys"
  end
end