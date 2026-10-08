# frozen_string_literal: true

class VerificationMailer < ApplicationMailer
  def verify(user)
    @user = user
    @token = user.email_verification_token
    mail subject: I18n.t("mailer.verify_email_subject"), to: user.email_address
  end
end
