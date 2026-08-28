# frozen_string_literal: true

module Shared
  module SessionsActions
    extend ActiveSupport::Concern
    include Shared::PasswordlessAuth

    included do
      allow_unauthenticated_access only: %i[new create magic request_magic]
      rate_limit to: 10, within: 3.minutes, only: :create,
        with: -> { redirect_to new_session_path, alert: t("shared.flash.rate_limited") }
      # Tighter than :create because this one sends mail on an unauthenticated
      # POST, so the cost of abuse is somebody else's inbox rather than a
      # wasted round trip.
      rate_limit to: 3, within: 15.minutes, only: :request_magic,
        with: -> { redirect_to new_session_path, alert: t("shared.flash.rate_limited") }
    end

    def new
    end

    def create
      user = User.authenticate_by(params.permit(:email_address, :password))
      if user&.try(:deletion_pending?)
        # A scheduled-for-deletion account cannot sign back in and quietly keep
        # itself alive; erasure has teeth (see UserPurgeJob).
        redirect_to new_session_path, alert: t("shared.flash.account_scheduled_for_deletion")
      elsif user
        start_new_session_for user
        redirect_to after_authentication_url
      else
        redirect_to new_session_path, alert: t("shared.flash.credentials_invalid")
      end
    end

    # Always the same notice, found or not: a different answer for a known
    # address turns this form into an account-enumeration oracle.
    def request_magic
      user = User.find_by(email_address: params[:email_address].to_s.strip.downcase.presence)
      sign_in_with_magic_link(user) if user && !user.try(:deletion_pending?)
      redirect_to new_session_path, notice: t("shared.flash.magic_link_sent")
    end

    def magic
      user = find_by_magic_token
      return redirect_to(new_session_path, alert: t("shared.flash.magic_link_invalid")) unless user

      # Single use. Cleared before the session starts, so a link replayed from a
      # mail client's link-prefetcher cannot open a second one.
      user.clear_magic_link!
      start_new_session_for user
      redirect_to after_authentication_url
    end

    def destroy
      terminate_session
      redirect_to new_session_path, status: :see_other
    end

    private

    def find_by_magic_token
      token = params[:token].to_s
      return if token.empty?

      user = User.find_by(magic_link_token: token)
      user if user&.magic_link_valid?
    end
  end
end
