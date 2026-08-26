# frozen_string_literal: true

class IdentityAssurer
  def initialize(user:)
    @user = user
  end

  def grant!(level:, source:, expires_at: nil)
    assurance = user.identity_assurances.find_or_initialize_by(level: level)

    assurance.update!(
      expires_at: expires_at,
      source: source,
      verified_at: Time.current
    )

    # find_or_create_by, not create!: granting the same assurance twice — a
    # re-verification, a retried job, a second BankID round — used to write a
    # second signal, and TrustScore sums them, so the same proof counted twice.
    # The unique index on [user_id, kind, source] now refuses it outright, so
    # this would raise rather than double-count; making it idempotent is the
    # half that keeps re-verification working.
    signal = TrustSignal.find_or_create_by!(
      user: user,
      kind: "#{level}_verified",
      source: source
    ) { |record| record.weight = default_weight(level) }
    signal.update!(weight: default_weight(level)) if signal.weight != default_weight(level)

    TrustScore.new(user: user).call

    assurance
  end

  private

  attr_reader :user

  def default_weight(level)
    case level
    when "guest"
      1
    when "account"
      5
    when "phone"
      20
    when "bankid"
      100
    when "merchant"
      150
    when "moderator"
      250
    else
      0
    end
  end
end
