# frozen_string_literal: true

class IdentityAssuranceService
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

    TrustSignal.create!(
      user: user,
      kind: "#{level}_verified",
      source: source,
      weight: default_weight(level)
    )

    TrustScoreCalculator.new(user: user).call

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
