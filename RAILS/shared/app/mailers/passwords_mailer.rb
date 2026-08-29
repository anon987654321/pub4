# frozen_string_literal: true

# The password-reset mail for every app. Shared::PasswordResetJob calls it by
# bare constant, and shared.view_paths puts passwords_mailer/reset.* on
# ActionMailer's view path, so the engine carries both halves.
class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    mail subject: I18n.t("mailer.password_reset_subject"), to: user.email_address
  end
end
