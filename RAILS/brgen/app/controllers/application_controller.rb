# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Shared::RescueHandlers
  include Authentication
  include Shared::PunditAuthorization
  include Shared::PagyPagination
  # Rails' automatic helper inclusion (config.action_controller.include_all_helpers)
  # scans the HOST app's app/helpers/, but pub4-shared is mounted as a separate
  # engine gem -- its helpers aren't in that scan path and need an explicit
  # `helper` call. Other shared helpers (e.g. Shared::SearchHelper's
  # live_search_index) happened to already be reachable via a different
  # inclusion path; Shared::StimulusFormHelper wasn't, breaking
  # password_visibility_field on every sessions/new render.
  helper Shared::StimulusFormHelper
  turbo_refreshes_with :morph, scroll: :preserve
  stale_when_importmap_changes

  before_action :set_domain_context
  before_action :log_tenant_access

  allow_browser versions: :modern

  private

  def log_tenant_access
    tenant = request.subdomain.presence || "brgen"
    Rails.logger.info(
      "[tenant_access] tenant=#{tenant} ip=#{request.remote_ip} path=#{request.fullpath} at=#{Time.now.to_i}"
    )
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
      city_record = result.city_record || City.find_by(domain: result.entry.domain)
      ActsAsTenant.current_tenant = city_record if city_record
    end
  rescue Brgen::DomainRegistry::UnknownHost, Brgen::DomainRegistry::UnknownSubdomain
    render plain: "Unknown host", status: :not_found
  end
end
