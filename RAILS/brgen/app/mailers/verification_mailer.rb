# frozen_string_literal: true

class VerificationMailer < ApplicationMailer
  def verify(user)
    @user = user
    @token = user.email_verification_token
    mail subject: "Confirm your email for Brgen", to: user.email_address
  end
end
