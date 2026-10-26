# frozen_string_literal: true

# One controller for every app that verifies an email; amber and brgen route to it.
class EmailVerificationsController < ::ApplicationController
  include Shared::EmailVerificationActions

  allow_unauthenticated_access only: :show
  rate_limit to: 5, within: 5.minutes, only: :create, name: "email_verification",
             by: -> { Current.user&.id ? "u#{Current.user.id}" : request.remote_ip }
end
