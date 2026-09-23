# frozen_string_literal: true

require_relative "test_helper"

class TestLawHandshake < Minitest::Test
  def setup
    @handshake = Master::Ground::LawHandshake.new
    @contract = JSON.parse(Law::Contract.render)
  end

  def test_current_contract_is_admitted
    verdict = @handshake.verify(**@contract.slice("contract_version", "law_digest", "protocol"))
    assert verdict.accepted?
    assert_equal "admitted", verdict.reason
  end

  def test_stale_digest_is_rejected
    verdict = @handshake.verify(**@contract.merge("law_digest" => "stale"))
    refute verdict.accepted?
    assert_equal "law digest mismatch", verdict.reason
  end

  def test_protocol_tampering_is_rejected
    verdict = @handshake.verify(**@contract.merge("protocol" => ["IDENTIFY"]))
    refute verdict.accepted?
    assert_equal "enforcement protocol mismatch", verdict.reason
  end
end
