# frozen_string_literal: true

module Shared
  module SessionsActions
    extend ActiveSupport::Concern

    included do
      allow_unauthenticated_access only: %i[new create]
      rate_limit to: 10, within: 3.minutes, only: :create,
        with: -> { redirect_to new_session_path, alert: "Try again later." }
    end

    def new
    end

    def create
      user = User.authenticate_by(params.permit(:email_address, :password))
      if user && user.try(:deletion_pending?)
        # A scheduled-for-deletion account cannot sign back in and quietly keep
        # itself alive; erasure has teeth (see UserPurgeJob).
        redirect_to new_session_path, alert: "This account is scheduled for deletion."
      elsif user
        start_new_session_for user
        redirect_to after_authentication_url
      else
        redirect_to new_session_path, alert: "Try another email address or password."
      end
    end

    def destroy
      terminate_session
      redirect_to new_session_path, status: :see_other
    end
  end
end
