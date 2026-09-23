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

  def test_admission_expires_when_laws_change
    original = Law::Contract.method(:digest)
    Law::Contract.define_singleton_method(:digest) { "changed" }
    Master::Ground::LawHandshake::Admission.enable!
    Law::Contract.define_singleton_method(:digest) { "different" }
    refute Master::Ground::LawHandshake::Admission.admitted?
    assert_raises(SecurityError) { Master::Ground::LawHandshake::Admission.require! }
  ensure
    Law::Contract.define_singleton_method(:digest, original)
    Master::Ground::LawHandshake::Admission.disable!
  end
end
