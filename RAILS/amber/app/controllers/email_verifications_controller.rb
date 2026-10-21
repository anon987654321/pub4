# frozen_string_literal: true

class EmailVerificationsController < ApplicationController
  include Shared::EmailVerificationActions

  allow_unauthenticated_access only: :show
  rate_limit to: 5, within: 5.minutes, only: :create, name: "email_verification",
             by: -> { Current.user&.id ? "u#{Current.user.id}" : request.remote_ip }
end
