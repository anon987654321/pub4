# frozen_string_literal: true

module Shared
  class PasswordlessMailer < ApplicationMailer
    def sign_in(user, token)
      @user = user
      @url = magic_link_url(token)
      mail(to: user.email_address, subject: I18n.t("mailer.sign_in_link_subject"))
    end

    private

    def magic_link_url(token)
      Rails.application.routes.url_helpers.session_url(magic_token: token)
    rescue StandardError
      "/session?magic_token=#{token}"
    end
  end
end
