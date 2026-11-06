# frozen_string_literal: true

require "test_helper"

# The coverage-contract debt entry's exact complaint: the trust path had no
# test that calls a method — a body of `raise` would have passed the old
# claim-checks. These call the services against real records.
class TrustAndIdentityTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @user = User.create!(email_address: "trust-#{SecureRandom.hex(4)}@brgen.no",
                         password: SecureRandom.hex(16), username: "tr_#{SecureRandom.hex(3)}", city: @city)
  end
  teardown { ActsAsTenant.current_tenant = nil }

  test "trust score sums the known weights and persists per scope" do
    TrustSignal.create!(user: @user, kind: "email_verified", source: "test", weight: 0)
    TrustSignal.create!(user: @user, kind: "successful_trade", source: "test", weight: 0)
    score = TrustScore.new(user: @user).call
    assert_equal 25, score.score, "email_verified(10) + successful_trade(15) come from SIGNAL_WEIGHTS, not the row"
    assert_equal "global", score.scope
    assert_in_delta Time.current, score.calculated_at, 5
  end

  test "an unknown signal kind falls back to the row's own weight" do
    TrustSignal.create!(user: @user, kind: "community_award", source: "test", weight: 7)
    assert_equal 7, TrustScore.new(user: @user).call.score
  end

  test "a ban outweighs a verified phone — the negative weights are real" do
    TrustSignal.create!(user: @user, kind: "phone_verified", source: "test", weight: 0)
    TrustSignal.create!(user: @user, kind: "moderation_ban", source: "test", weight: 0)
    assert_equal(-180, TrustScore.new(user: @user).call.score)
  end

  test "recalculating updates the same reputation row instead of stacking" do
    2.times { TrustScore.new(user: @user).call }
    assert_equal 1, @user.reputation_scores.where(scope: "global").count
  end

  test "identity grant records the assurance, the signal, and moves the score" do
    assurance = IdentityAssurer.new(user: @user).grant!(level: "phone", source: "vipps")
    assert_in_delta Time.current, assurance.verified_at, 5
    signal = @user.trust_signals.find_by(kind: "phone_verified")
    assert signal, "the grant must leave a trust signal behind"
    assert_equal 20, signal.weight
    assert_equal 20, @user.reputation_scores.find_by(scope: "global").score
  end

  test "granting the same level twice re-verifies rather than duplicating" do
    2.times { IdentityAssurer.new(user: @user).grant!(level: "phone", source: "vipps") }
    assert_equal 1, @user.identity_assurances.where(level: "phone").count
  end
end
