# frozen_string_literal: true
# AN203: Passwordless magic link authentication

module Shared
  module PasswordlessAuth
    extend ActiveSupport::Concern

    private

    def deliver_magic_link(user)
      token = user.generate_magic_link_token!
      Shared::PasswordlessMailer.sign_in(user, token).deliver_later(queue: :critical)
    end

    def authenticate_by_magic_link(token)
      user = User.find_by(magic_link_token: token)
      return unless user&.magic_link_valid?

      user.clear_magic_link!
      user
    end
  end
end