# frozen_string_literal: true

class TrustScore
  SIGNAL_WEIGHTS = {
    "account_created" => 5,
    "email_verified" => 10,
    "phone_verified" => 20,
    "bankid_verified" => 100,
    "merchant_verified" => 150,
    "successful_trade" => 15,
    "post_removed" => -20,
    "spam_report" => -40,
    "moderation_ban" => -200
  }.freeze

  def initialize(user:, scope: "global")
    @scope = scope
    @user = user
  end

  def call
    score = user.trust_signals.sum do |signal|
      SIGNAL_WEIGHTS.fetch(signal.kind, signal.weight)
    end

    reputation_score = user.reputation_scores.find_or_initialize_by(scope: scope)
    reputation_score.update!(
      calculated_at: Time.current,
      score: score
    )

    reputation_score
  end

  private

  attr_reader :scope, :user
end
