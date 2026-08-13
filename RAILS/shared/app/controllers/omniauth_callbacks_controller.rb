# frozen_string_literal: true
# AN204: OAuth callback handler

class OmniauthCallbacksController < ::ApplicationController
  allow_unauthenticated_access
  # create calls User.create! for an unrecognised uid, so a callback that gets
  # this far makes an account. Reaching it needs a real roundtrip through the
  # provider, which is the actual barrier — this is a ceiling on the damage if
  # that assumption is ever wrong, not the thing standing in the way.
  #
  # Deliberately loose. A person signs in once; 30 a minute from one address is
  # already far past that, and a tighter number would lock out an office or a
  # campus behind one NAT for a threat this endpoint does not really face.
  rate_limit to: 30, within: 1.minute, only: :create,
    with: -> { redirect_to new_session_path, alert: t("shared.flash.rate_limited") }

  def passthru
    render plain: "OAuth not configured", status: :not_found unless request.env["omniauth.strategy"]
  end

  def create
    auth = request.env["omniauth.auth"]
    unless auth
      redirect_to new_session_path, alert: t("shared.flash.oauth_failed")
      return
    end

    user = find_or_create_user(auth)
    merge_guest_into(user) if session[:guest_user_id].present?
    # Was complete_login_for(user, remember: true) -- a method that exists in no
    # app and in no gem here, so every successful OAuth callback raised
    # NoMethodError. start_new_session_for is the one session entry point
    # (Shared::Authentication); it already sets a permanent signed cookie.
    start_new_session_for user

    redirect_to after_authentication_url, notice: t("shared.flash.signed_in_with", provider: auth.provider)
  end

  private

  def find_or_create_user(auth)
    record = external_identity_for(auth) || legacy_authentication_for(auth)
    return record.user if record&.user

    email = auth.info.email.to_s.downcase.strip
    user = User.find_by(email_address: email) if email.present?
    user ||= User.create!(
      email_address: email.presence || "#{auth.uid}@#{auth.provider}.oauth",
      password: SecureRandom.hex(24)
    )
    persist_external_identity(user, auth)
    persist_legacy_authentication(user, auth)
    user
  end

  def external_identity_for(auth)
    return unless defined?(::ExternalIdentity) && defined?(::IdentityProvider)
    return unless ::ExternalIdentity.table_exists? && ::IdentityProvider.table_exists?

    provider = ::IdentityProvider.find_by(slug: auth.provider.to_s)
    provider&.external_identities&.find_by(subject: auth.uid.to_s)
  end

  def legacy_authentication_for(auth)
    return unless defined?(Shared::Authentication) && Shared::Authentication.table_exists?

    Shared::Authentication.find_by(provider: auth.provider, uid: auth.uid)
  end

  def persist_external_identity(user, auth)
    return unless defined?(::ExternalIdentity) && defined?(::IdentityProvider)
    return unless ::ExternalIdentity.table_exists? && ::IdentityProvider.table_exists?

    provider = ::IdentityProvider.find_or_create_by!(slug: auth.provider.to_s) do |record|
      record.name = auth.provider.to_s.tr("_", " ").titleize
      record.issuer = auth.extra&.dig(:id_info, :iss) if auth.extra.respond_to?(:dig)
      record.client_id = ENV["#{auth.provider.to_s.upcase}_CLIENT_ID"]
    end
    identity = provider.external_identities.find_or_initialize_by(subject: auth.uid.to_s)
    identity.user = user
    identity.email_address = auth.info&.email.to_s.downcase.presence
    identity.phone_number = auth.info&.phone.to_s.presence
    identity.assurance_level = assurance_level_for(auth.provider)
    identity.last_used_at = Time.current
    identity.save!
  end

  def persist_legacy_authentication(user, auth)
    return unless defined?(Shared::Authentication) && Shared::Authentication.table_exists?

    Shared::Authentication.find_or_create_by!(provider: auth.provider, uid: auth.uid) do |record|
      record.user = user
      record.info = auth.info.to_h if record.respond_to?(:info=)
    end
  end

  def assurance_level_for(provider)
    case provider.to_s
    when "vipps" then "verified"
    else "account"
    end
  end

  def merge_guest_into(user)
    guest = User.find_by(id: session[:guest_user_id], guest: true)
    return unless guest

    AccountMerger.new(guest_user: guest, user: user).call if defined?(AccountMerger)
  rescue StandardError => error
    Rails.logger.warn("OAuth guest merge failed: #{error.message}")
  end
end
