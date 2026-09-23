# frozen_string_literal: true

require_relative "test_helper"

class TestLawContract < Minitest::Test
  def test_contract_has_stable_machine_readable_shape
    data = JSON.parse(Law::Contract.render)

    assert_equal 1, data.fetch("contract_version")
    assert_match(/\A[0-9a-f]{64}\z/, data.fetch("law_digest"))
    assert_equal Law::Contract::PROTOCOL, data.fetch("protocol")
    assert_operator data.fetch("laws").length, :>, 100
    assert data.fetch("laws").all? { |law| law.key?("id") && law.key?("severity") }
  end

  def test_full_contract_contains_enforcement_material
    data = JSON.parse(Law::Contract.render(full: true))
    rule = data.fetch("laws").find { |law| law["id"] == "FAIL_VISIBLY" }

    assert rule
    assert rule.key?("question")
    assert rule.key?("fix")
    assert rule.key?("bad")
    assert rule.key?("good")
  end

  def test_digest_changes_with_the_executable_law_set
    first = Law::Contract.digest
    assert_equal first, JSON.parse(Law::Contract.render).fetch("law_digest")
  end
end
