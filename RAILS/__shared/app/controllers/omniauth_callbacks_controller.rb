# frozen_string_literal: true

# AN204: OAuth callback handler

class OmniauthCallbacksController < ::ApplicationController
  class IdentityEmailConflict < StandardError; end
  class IdentityStorageUnavailable < StandardError; end

  allow_unauthenticated_access
  # create calls User.create! for an unrecognised uid, so a callback that gets
  # this far makes an account. Reaching it needs a real roundtrip through the
  # provider, which is the actual barrier — this is a ceiling on the damage if
  # that assumption is ever wrong, not the thing standing in the way.
  #
  # Deliberately loose. A person signs in once; 30 a minute from one address is
  # already far past that, and a tighter number would lock out an office or a
  # campus behind one NAT for a threat this endpoint does not face.
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
    transfer = transfer_guest_history_from_session(user)
    if transfer == false
      redirect_to new_session_path, alert: t("shared.flash.guest_history_transfer_failed")
      return
    end
    # Was complete_login_for(user, remember: true) -- a method that exists in no
    # app and in no gem here, so every successful OAuth callback raised
    # NoMethodError. start_new_session_for is the one session entry point
    # (Shared::Authentication); it already sets a permanent signed cookie.
    start_new_session_for user

    redirect_to after_authentication_url, notice: t("shared.flash.signed_in_with", provider: auth.provider)
  rescue IdentityStorageUnavailable
    redirect_to new_session_path, alert: t("shared.flash.oauth_storage_unavailable")
  rescue IdentityEmailConflict
    redirect_to new_session_path, alert: t("shared.email_verification.oauth_email_conflict")
  end

  private

  # The non-deliverable placeholder for a provider that sent no email. The
  # provider is hyphenated because a domain label cannot hold "_": as
  # "google_oauth2.oauth" it failed User's email format, so an email-less
  # Google callback could never be saved. bankid's address is unchanged.
  def synthetic_oauth_address(auth)
    "#{auth.uid}@#{auth.provider.to_s.tr('_', '-')}.oauth"
  end

  def find_or_create_user(auth)
    # Never create a user while durable provider-subject storage is unavailable.
    # Otherwise each OAuth return creates a new account and the next login has
    # no stable subject mapping with which to recover the original account.
    ensure_identity_storage!
    record = external_identity_for(auth)
    if record
      # Never lazy-load record.user here: strict loading is enabled in every
      # host. Resolve the persisted FK directly and refuse deleted identities
      # instead of silently creating a second account for the same provider ID.
      user = User.find_by(id: record.user_id)
      raise IdentityEmailConflict unless user && user.try(:deleted_at).blank? && !user.try(:deletion_pending?)

      # Assurance belongs to this verified authentication event, not forever to
      # the first login: upgrade when a fresh BankID token proves high ACR and
      # downgrade when a later token has lower assurance.
      record.update!(
        last_used_at: Time.current,
        assurance_level: assurance_level_for(auth.provider, auth:)
      )
      return user
    end

    email = auth.info.email.to_s.downcase.strip
    verified_email = verified_provider_email?(auth)
    user = User.find_by(email_address: email) if email.present?
    if user && (user.try(:deleted_at).present? || user.try(:deletion_pending?))
      raise IdentityEmailConflict
    end
    legacy_bankid_placeholder = false
    synthetic_placeholder_recovered = false

    # A previous callback can persist the user and fail before it records the
    # provider subject. For email-less non-BankID providers, recover only the
    # exact subject-derived address while it is still unverified and unclaimed.
    # On a concurrent insert, re-query only this exact placeholder after either
    # the model's uniqueness validation or the database index rejects the write.
    if user.nil? && email.blank? && auth.provider.to_s != "bankid"
      placeholder = synthetic_oauth_address(auth)
      user = User.find_by(email_address: placeholder)
      unless user
        candidate = User.new(email_address: placeholder, password: SecureRandom.hex(24))
        candidate.require_email_verification = true
        begin
          candidate.save!
          user = candidate
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
          user = User.find_by(email_address: placeholder)
          raise unless user
        end
      end
      has_unconsumed_synthetic_address = user.respond_to?(:has_attribute?) &&
                                         user.has_attribute?(:email_verification_token) &&
                                         user.email_verification_token.blank?
      eligible = has_unconsumed_synthetic_address && !user.email_verified? &&
                 !user.try(:guest?) && user.try(:deleted_at).blank? &&
                 user.try(:deletion_scheduled_at).blank? && !user.try(:deletion_pending?)
      raise IdentityEmailConflict unless eligible

      synthetic_placeholder_recovered = true
    end

    # Before the shared subject tables existed, BankID accounts were created
    # with a deterministic, non-deliverable "#{sub}@bankid.oauth" placeholder.
    # Reclaim only that exact legacy address when it remains unverified and
    # active; the live, validated BankID subject is the proof for this mapping.
    # This avoids turning a returning user into a duplicate-account failure
    # after the migration, without treating the placeholder as mailbox proof.
    if user.nil? && email.blank? && auth.provider.to_s == "bankid"
      legacy_email = "#{auth.uid}@bankid.oauth"
      legacy_user = User.find_by(email_address: legacy_email)
      if legacy_user
        has_unconsumed_synthetic_address = legacy_user.respond_to?(:has_attribute?) &&
                                           legacy_user.has_attribute?(:email_verification_token) &&
                                           legacy_user.email_verification_token.blank?
        high_assurance_subject = assurance_level_for(auth.provider, auth:) == "verified"
        eligible = high_assurance_subject && has_unconsumed_synthetic_address &&
                   !legacy_user.email_verified? && legacy_user.try(:deleted_at).blank? &&
                   legacy_user.try(:deletion_scheduled_at).blank? && !legacy_user.try(:deletion_pending?)
        raise IdentityEmailConflict unless eligible

        user = legacy_user
        legacy_bankid_placeholder = true
      end
    end

    raise IdentityEmailConflict if user && !verified_email && !legacy_bankid_placeholder && !synthetic_placeholder_recovered

    unless user
      user = User.new(
        email_address: email.presence || synthetic_oauth_address(auth),
        password: SecureRandom.hex(24),
      )
      # A missing provider email still needs a unique placeholder, but that
      # non-deliverable address is not evidence of mailbox ownership.
      user.require_email_verification = true unless verified_email
      user.save!
      if user.require_email_verification && email.present?
        user.generate_email_verification!
        Shared::VerificationMailer.verify(user, request.host).deliver_later
      end
    end
    persist_external_identity(user, auth)
    user
  end

  # Never infer email ownership from a profile field alone. Google and Vipps
  # expose the OIDC email_verified claim; Facebook's email field alone does not
  # prove mailbox control. An unverified new address is allowed to register,
  # but only after the shared confirmation flow does it gain write permissions.
  def verified_provider_email?(auth)
    return false unless %w[google_oauth2 vipps].include?(auth.provider.to_s)
    return false if auth.info&.email.to_s.strip.empty?

    extra = auth.extra
    raw_info = hash_value(extra, :raw_info)
    claim = hash_value(raw_info, :email_verified)
    claim == true || claim.to_s.casecmp("true").zero?
  end

  def hash_value(hash, key)
    return unless hash.respond_to?(:[])

    hash[key] || hash[key.to_s] || hash[key.to_sym]
  end

  def ensure_identity_storage!
    available = defined?(::ExternalIdentity) && defined?(::IdentityProvider) &&
                ::ExternalIdentity.table_exists? && ::IdentityProvider.table_exists?
    raise IdentityStorageUnavailable unless available
  end

  def external_identity_for(auth)
    ensure_identity_storage!

    provider = ::IdentityProvider.find_by(slug: auth.provider.to_s)
    return unless provider

    # Query by the foreign key rather than provider.external_identities; the
    # latter is a lazy association read and raises under the hosts' strict-loading policy.
    ::ExternalIdentity.find_by(identity_provider_id: provider.id, subject: auth.uid.to_s)
  end

  def persist_external_identity(user, auth)
    ensure_identity_storage!

    slug = auth.provider.to_s
    provider = ::IdentityProvider.find_by(slug: slug)
    unless provider
      candidate = ::IdentityProvider.new(
        slug: slug,
        name: slug.tr("_", " ").titleize,
        issuer: hash_value(hash_value(auth.extra, :id_info), :iss),
        client_id: ENV["#{slug.upcase}_CLIENT_ID"]
      )
      begin
        candidate.save!
        provider = candidate
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        provider = ::IdentityProvider.find_by(slug: slug)
        raise unless provider
      end
    end
    identity = ::ExternalIdentity.find_or_initialize_by(identity_provider_id: provider.id, subject: auth.uid.to_s)
    identity.user_id = user.id
    identity.email_address = auth.info&.email.to_s.downcase.presence
    identity.phone_number = auth.info&.phone.to_s.presence
    identity.assurance_level = assurance_level_for(auth.provider, auth:)
    identity.last_used_at = Time.current
    identity.save!
  end

  def assurance_level_for(provider, auth:)
    case provider.to_s
    when "vipps"
      "verified"
    when "bankid"
      # BankID's request parameter is urn:bankid:bid, while its returned ID
      # token normally includes the level: "urn:bankid:bid;LOA=4". Require both
      # the provider and LOA claim; equality with the request value rejects the
      # real high-assurance token and weakens the no-email identity path.
      acr_parts = hash_value(hash_value(auth.extra, :id_info), :acr).to_s.split(";").map(&:strip)
      high_bankid = acr_parts.include?("urn:bankid:bid") &&
                    acr_parts.any? { |part| part.casecmp("LOA=4").zero? }
      high_bankid ? "verified" : "account"
    else
      "account"
    end
  end

end
