# frozen_string_literal: true

module Shared
  class VerificationMailer < ApplicationMailer
    def verify(user, host)
      @user = user
      @token = user.email_verification_token
      @verification_url = Rails.application.routes.url_helpers.verify_email_url(
        @token, host: host, protocol: "https"
      )
      subject = I18n.t("mailer.verify_email_subject", default: I18n.t("shared.email_verification.subject"))
      mail to: user.email_address, subject: subject
    end
  end
end
