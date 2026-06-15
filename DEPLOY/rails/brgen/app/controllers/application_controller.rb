# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication
  include Shared::PunditAuthorization
  include Pagy::Method
  turbo_refreshes_with :morph, scroll: :preserve

  before_action :set_domain_context

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

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

    I18n.locale = result.entry.locale

    # Wire ActsAsTenant if the gem is in use (for row-level city scoping on models)
    if defined?(ActsAsTenant)
      city_record = result.city_record || City.find_by(domain: result.entry.domain)
      ActsAsTenant.current_tenant = city_record if city_record
    end
  rescue Brgen::DomainRegistry::UnknownHost, Brgen::DomainRegistry::UnknownSubdomain
    render plain: "Unknown host", status: :not_found
  end
end
