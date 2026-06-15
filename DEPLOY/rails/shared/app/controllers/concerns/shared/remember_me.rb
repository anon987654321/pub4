# frozen_string_literal: true
# AN206: Remember me persistent cookie (30 days)

module Shared
  module RememberMe
    extend ActiveSupport::Concern

    REMEMBER_DURATION = 30.days

    private

    def remember_user(user)
      token = user.generate_remember_token!
      cookies.signed[:signed_in_as] = {
        value: token,
        expires: REMEMBER_DURATION.from_now,
        httponly: true,
        same_site: :lax
      }
    end

    def resume_remembered_user
      token = cookies.signed[:signed_in_as]
      return unless token

      user = User.find_by(remember_token: token)
      return unless user&.remember_token_valid?

      start_new_session_for(user)
      Current.user = user if defined?(Current) && Current.respond_to?(:user=)
      user
    end

    def forget_remembered_user(user = Current.user)
      user&.invalidate_remember_token!
      cookies.delete(:signed_in_as)
    end
  end
end