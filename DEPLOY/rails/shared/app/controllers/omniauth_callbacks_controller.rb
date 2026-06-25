# frozen_string_literal: true
# AN204: OAuth callback handler

class OmniauthCallbacksController < ::ApplicationController
  allow_unauthenticated_access

  def passthru
    render plain: "OAuth not configured", status: :not_found unless request.env["omniauth.strategy"]
  end

  def create
    auth = request.env["omniauth.auth"]
    unless auth
      redirect_to new_session_path, alert: "OAuth failed"
      return
    end

    user = find_or_create_user(auth)
    merge_guest_into(user) if session[:guest_user_id].present?
    unless complete_login_for(user, remember: true)
      redirect_to new_session_path, alert: "Sign in failed"
      return
    end

    redirect_to after_authentication_url, notice: "Signed in with #{auth.provider}"
  end

  private

  def find_or_create_user(auth)
    record = Shared::Authentication.find_by(provider: auth.provider, uid: auth.uid)
    return record.user if record

    email = auth.info.email.to_s.downcase.strip
    user = User.find_by(email_address: email) if email.present?
    user ||= User.create!(
      email_address: email.presence || "#{auth.uid}@#{auth.provider}.oauth",
      password: SecureRandom.hex(24)
    )
    Shared::Authentication.create!(
      user: user,
      provider: auth.provider,
      uid: auth.uid,
      info: auth.info.to_h
    )
    user
  end

  def merge_guest_into(user)
    guest = User.find_by(id: session[:guest_user_id], guest: true)
    return unless guest

    AccountMergeService.new(guest_user: guest, user: user).call if defined?(AccountMergeService)
  rescue StandardError => error
    Rails.logger.warn("OAuth guest merge failed: #{error.message}")
  end
end