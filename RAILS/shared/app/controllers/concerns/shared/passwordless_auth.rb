# frozen_string_literal: true

module Shared
  module PasswordlessAuth
    extend ActiveSupport::Concern

    def sign_in_with_magic_link(user)
      token = user.generate_magic_link_token!
      Shared::PasswordlessMailer.sign_in(user, token).deliver_later
    end
  end
end
