# frozen_string_literal: true

module Shared
  class PasswordlessMailer < ApplicationMailer
    def sign_in(user, token)
      @user = user
      # main_app, because Shared::Engine isolates its namespace: a bare helper
      # here resolves against the engine's route set, where a main-app route is
      # not present and generation falls through to a controller/action lookup
      # that matches nothing.
      #
      # The host comes from Rails.application.routes.default_url_options, which
      # the environments now set alongside action_mailer's. It was unset in every
      # environment, so the previous `Rails.application.routes.url_helpers`
      # call raised "Missing host to link to!", a rescue caught it, and the mail
      # shipped the relative path /session?magic_token=… — which no mail client
      # can follow, and which pointed at a route that did not exist either.
      @url = main_app.magic_session_url(token:)
      mail(to: user.email_address, subject: I18n.t("mailer.sign_in_link_subject"))
    end
  end
end
