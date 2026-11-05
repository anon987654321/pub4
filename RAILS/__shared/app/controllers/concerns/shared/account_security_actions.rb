# frozen_string_literal: true

module Shared
  # The account page's security rows: change the sign-in email, change the
  # password, and sign out every other device. Each change asks for the current
  # password first, so a session left open on a shared computer cannot take the
  # account over. A password change, like a reset, ends every other session.
  module AccountSecurityActions
    extend ActiveSupport::Concern

    included do
      rate_limit to: 10, within: 10.minutes, only: %i[email password other_sessions],
                 name: "account_security", by: -> { "u#{Current.user&.id}" }
    end

    def email
      user = Current.user
      return refuse_wrong_password unless user.authenticate(params[:current_password].to_s)

      address = params[:email_address].to_s.strip.downcase
      return redirect_to(account_path, alert: t("account_security.email_unchanged")) if address == user.email_address

      if user.update(email_address: address)
        reverify_email(user)
        redirect_to account_path, notice: t("account_security.email_changed")
      else
        refuse_invalid(user)
      end
    end

    def password
      user = Current.user
      return refuse_wrong_password unless user.authenticate(params[:current_password].to_s)
      return redirect_to(account_path, alert: t("account_security.password_blank")) if params[:password].blank?

      if user.update(password: params[:password], password_confirmation: params[:password_confirmation].to_s)
        sign_out_other_sessions(user)
        redirect_to account_path, notice: t("account_security.password_changed")
      else
        refuse_invalid(user)
      end
    end

    def other_sessions
      count = sign_out_other_sessions(Current.user)
      redirect_to account_path, notice: t("account_security.signed_out_others", count:)
    end

    private

    def refuse_invalid(user)
      messages = user.errors.full_messages
      redirect_to account_path, alert: messages.to_sentence
    end

    def refuse_wrong_password
      redirect_to account_path, alert: t("account_security.wrong_password")
    end

    def sign_out_other_sessions(user)
      others = user.sessions
      others = others.where.not(id: Current.session.id) if Current.session
      others.destroy_all.size
    end

    # An app that verifies addresses verifies the new one too; one without the
    # columns or the concern (bsdports) changes the address and stops there.
    def reverify_email(user)
      Shared::VerificationMailer.verify(user, request.host).deliver_later if user.try(:restart_email_verification!)
    end
  end
end
