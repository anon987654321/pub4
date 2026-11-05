# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # The five shared includes, the two shared helper registrations, the browser
  # floor, morph refreshes and the importmap staleness key are one concern that
  # amber and bsdports already use. brgen inlined the same list beside a comment
  # pointing at that concern while the concern's comment pointed back here.
  #
  # Shared::ConsentHelper is not in it and is not needed: shared/_ad_slot is an
  # engine partial, so the engine registers the helper for every app in
  # shared/lib/shared/engine.rb's "shared.consent_helper" initializer.
  include Shared::ApplicationSetup

  before_action :set_domain_context

  private

  # Someone who arrived on a "message me" link and had to sign in first lands in
  # the conversation they were invited to, not on the city feed. Without this the
  # link works only for people who already have an account, which is every person
  # except the one it was sent to.
  #
  # A sign-in asked for by a page (the members-only post) goes back to it.
  def after_authentication_url
    back = local_return_path(params[:return_to])
    return back if back

    token = session.delete(:invite_token)
    return super if token.blank?

    invite_path(token: token)
  end

  # A path on this site only: an absolute or protocol-relative URL here would
  # make the sign-in form an open redirect.
  def local_return_path(path)
    path = path.to_s
    path if path.start_with?("/") && !path.start_with?("//", "/\\") && !path.match?(/[[:cntrl:]]/)
  end
  helper_method :local_return_path

  # Once a session, an account that may not post yet is told so before it
  # writes something, rather than at submit by require_verified_email.
  def verify_email_banner?
    user = Current.user
    return false if user.nil? || user.guest? || session[:verify_email_banner_shown]
    return false if user.email_verified? || verified_bankid_identity?(user)

    session[:verify_email_banner_shown] = true
  end
  helper_method :verify_email_banner?

  # The language of the domain the request came in on (brgen.no is nb).
  def site_locale(result = Brgen::DomainRegistry.resolve(request.host))
    Brgen::LocaleBridge.resolve(result.entry.locale)
  end

  def account_locale
    chosen = Current.user&.try(:locale).presence&.to_sym
    chosen if chosen && I18n.available_locales.include?(chosen)
  end

  def set_domain_context
    # City (and full branding/locale) is resolved automatically from the request's TLD/domain.
    # The city network footer links peer apexes without changing tenant context.
    result = Brgen::DomainRegistry.resolve(request.host)

    Current.city = result.entry.city
    Current.country = result.entry.country
    Current.currency = result.entry.currency
    Current.domain = result.entry.domain
    Current.locale = result.entry.locale
    Current.subapp = result.subapp
    Current.city_record = result.city_record

    # The domain's language, unless the signed-in account chose one on its
    # account page (account_languages#update).
    I18n.locale = account_locale || site_locale(result)
    # The page says which language it is in: the chosen one when there is one.
    Current.locale = account_locale.to_s if account_locale

    # Wire ActsAsTenant if the gem is in use (for row-level city scoping on models)
    if defined?(ActsAsTenant)
      # result.city_record is already `City.find_by(domain: entry.domain)` —
      # DomainRegistry.resolve runs exactly that. The second `City.find_by` that
      # stood here was the same query again, reachable only when the first had
      # just returned nil, so it could never return a record. It only ever cost
      # a round trip per request.
      ActsAsTenant.current_tenant = result.city_record if result.city_record
    end
  rescue Brgen::DomainRegistry::UnknownHost, Brgen::DomainRegistry::UnknownSubdomain
    # The app's styled 404, not two words of text/plain. An unknown host is a
    # typo or a stale link far more often than an attack.
    render_http_error(:not_found, "unknown_host")
  end
end
