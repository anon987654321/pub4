# frozen_string_literal: true

class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    mail subject: I18n.t("mailer.password_reset_subject"), to: user.email_address
  end
end
