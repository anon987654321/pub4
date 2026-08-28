# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Shared::RescueHandlers
  include Authentication
  include Shared::PunditAuthorization
  include Shared::PagyPagination
  include Shared::VisitCounting
  # Rails' automatic helper inclusion (config.action_controller.include_all_helpers)
  # scans the HOST app's app/helpers/, but pub4-shared is mounted as a separate
  # engine gem -- its helpers aren't in that scan path and need an explicit
  # `helper` call. Other shared helpers (e.g. Shared::SearchHelper's
  # live_search_index) happened to already be reachable via a different
  # inclusion path; Shared::StimulusFormHelper wasn't, breaking
  # password_visibility_field on every sessions/new render.
  helper Shared::StimulusFormHelper
  # Same reason: shared/_ad_slot gates on advertising_consent?, and an ad slot
  # whose gate raises NoMethodError would take the page down instead of
  # rendering nothing.
  helper Shared::ConsentHelper
  helper Shared::AffiliateHelper
  turbo_refreshes_with :morph, scroll: :preserve
  stale_when_importmap_changes

  before_action :set_domain_context

  allow_browser versions: :modern

  private

  # Someone who arrived on a "message me" link and had to sign in first lands in
  # the conversation they were invited to, not on the city feed. Without this the
  # link works only for people who already have an account, which is every person
  # except the one it was sent to.
  def after_authentication_url
    token = session.delete(:invite_token)
    return super if token.blank?

    invite_path(token: token)
  end

  # Registered accounts must confirm their email before posting under their
  # identity. Anonymous guests are unaffected — brgen's anonymous posting stays.
  def require_verified_email
    return if Current.user.nil? || Current.user.try(:guest?) || Current.user.email_verified?

    message = t("verify.needed")
    respond_to do |format|
      format.html { redirect_back fallback_location: main_app.root_path, alert: message }
      format.any  { head :forbidden }
    end
  end

  def set_domain_context
    # City (and full branding/locale) is resolved automatically from the request's TLD/domain.
    # There is no city switcher UI — a visitor on lsangeles.com only ever sees the Los Angeles
    # experience and has no knowledge of brgen.no, oshlo.no or any other city domains.
    result = Brgen::DomainRegistry.resolve(request.host)

    Current.city = result.entry.city
    Current.country = result.entry.country
    Current.currency = result.entry.currency
    Current.domain = result.entry.domain
    Current.locale = result.entry.locale
    Current.subapp = result.subapp
    Current.city_record = result.city_record

    I18n.locale = Brgen::LocaleBridge.resolve(result.entry.locale)

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
