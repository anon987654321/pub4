# frozen_string_literal: true

module Shared
  class VerificationMailer < ApplicationMailer
    # An app may word its own verification mail; the shared copy covers apps that do not.
    APP_KEYS = {
      subject: "mailer.verify_email_subject",
      welcome: "mailer.verify_welcome",
      body: "mailer.verify_body",
      confirm: "mailer.verify_cta",
      ignore: "mailer.verify_ignore",
    }.freeze

    helper_method :copy

    def verify(user, host)
      @user = user
      @token = user.email_verification_token
      @verification_url = Rails.application.routes.url_helpers.verify_email_url(
        @token, host: host, protocol: "https"
      )
      mail to: user.email_address, subject: copy(:subject)
    end

    private

    def copy(part)
      key = APP_KEYS.fetch(part)
      I18n.t(I18n.exists?(key) ? key : "shared.email_verification.#{part}")
    end
  end
end
